import Foundation
import Network
import CryptoKit

/// Discover a nearby phone and establish an encrypted pairing channel, adapted from B's ios/UWBMeetDemo/App/PeerTransport.swift.
/// Change: no manually entered code. Both phones advertise and browse _jiefong._tcp, registered in Info.plist.
/// The smaller ID initiates (BumpTieBreak); use ephemeral Curve25519 key agreement after connecting (BumpChannel).
/// includePeerToPeer enables AWDL without a shared Wi-Fi network; Wi-Fi and Bluetooth must be enabled.
/// All callbacks run on the main thread; Network uses the .main queue.
@MainActor
final class BumpTransport {
    enum Event {
        /// The encrypted channel is connected. The initiator creates the one-time pairing code.
        case ready(initiator: Bool)
        case message(BumpMessage)
        /// Local Network permission: true means blocked/not granted; false means available.
        case localNetwork(blocked: Bool)
        /// An established channel disconnected because the peer left or an error occurred.
        case closed
        /// Bonjour advertising/browsing is unavailable.
        case unavailable
    }

    var onEvent: ((Event) -> Void)?
    let myID = BumpTieBreak.newInstanceID()
    private let myKey = Curve25519.KeyAgreement.PrivateKey()
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var initiator = false
    private var peerID: String?
    private var channel: BumpChannel?
    private var frames = FrameBuffer()
    private var generation = UUID()
    /// Do not retry a peer whose connection or handshake failed during this attempt.
    private var tried: Set<String> = []
    private var endpoints: [String: NWEndpoint] = [:]
    /// kDNSServiceErr_PolicyDenied: Local Network permission has not been granted.
    private static let policyDenied: Int32 = -65570
    /// Handshake timeout in seconds before abandoning this connection and trying another phone.
    private static let handshakeTimeout: TimeInterval = 8

    private static func parameters() -> NWParameters {
        let p = NWParameters.tcp
        p.includePeerToPeer = true
        return p
    }

    func start() throws {
        stop()
        let gen = generation
        let listener = try NWListener(using: Self.parameters())
        listener.service = NWListener.Service(name: BumpTieBreak.serviceName(myID), type: BumpTieBreak.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerState(state, gen) }
        }
        listener.newConnectionHandler = { [weak self] c in
            MainActor.assumeIsolated {
                guard let self, self.generation == gen, self.connection == nil else { c.cancel(); return }
                self.attach(c, initiator: false, peer: nil, gen)
            }
        }
        self.listener = listener
        listener.start(queue: .main)

        let browser = NWBrowser(for: .bonjour(type: BumpTieBreak.serviceType, domain: nil), using: Self.parameters())
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.browserState(state, gen) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.browsed(results, gen) }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func send(_ kind: BumpMessage.Kind, token: Data? = nil, code: String? = nil) {
        guard let connection, channel != nil else { return }
        guard let frame = try? channel?.seal(kind, token: token, code: code) else { return }
        connection.send(content: frame, completion: .idempotent)
    }

    /// Best-effort stop message before closing the connection.
    func sendCancelAndStop() {
        if let connection, channel != nil, let frame = try? channel?.seal(.cancel) {
            connection.send(content: frame, completion: .contentProcessed { _ in connection.cancel() })
            self.connection = nil
        }
        stop()
    }

    func stop() {
        generation = UUID()
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        channel = nil
        frames = FrameBuffer()
        peerID = nil
        endpoints = [:]
        tried = []
    }

    // MARK: - Peer discovery

    private func listenerState(_ state: NWListener.State, _ gen: UUID) {
        guard generation == gen else { return }
        switch state {
        case .waiting(let e): if Self.isPolicyDenied(e) { onEvent?(.localNetwork(blocked: true)) }
        case .failed: if channel == nil { onEvent?(.unavailable) }
        default: break
        }
    }

    private func browserState(_ state: NWBrowser.State, _ gen: UUID) {
        guard generation == gen else { return }
        switch state {
        case .waiting(let e): if Self.isPolicyDenied(e) { onEvent?(.localNetwork(blocked: true)) }
        case .ready: onEvent?(.localNetwork(blocked: false))
        case .failed: if channel == nil { onEvent?(.unavailable) }
        default: break
        }
    }

    private static func isPolicyDenied(_ e: NWError) -> Bool {
        if case .dns(let code) = e { return code == policyDenied }
        return false
    }

    private func browsed(_ results: Set<NWBrowser.Result>, _ gen: UUID) {
        guard generation == gen else { return }
        endpoints = [:]
        for r in results {
            if case .service(let name, _, _, _) = r.endpoint, let id = BumpTieBreak.instanceID(fromServiceName: name), id != myID {
                endpoints[id] = r.endpoint
            }
        }
        connectIfNeeded(gen)
    }

    private func connectIfNeeded(_ gen: UUID) {
        guard connection == nil else { return }
        let visible = endpoints.keys.filter { !tried.contains($0) }
        guard let pick = BumpTieBreak.pick(me: myID, visible: Array(visible)), let ep = endpoints[pick] else { return }
        attach(NWConnection(to: ep, using: Self.parameters()), initiator: true, peer: pick, gen)
    }

    // MARK: - Connection and handshake

    private func attach(_ c: NWConnection, initiator: Bool, peer: String?, _ gen: UUID) {
        connection = c
        self.initiator = initiator
        peerID = peer
        channel = nil
        frames = FrameBuffer()
        c.stateUpdateHandler = { [weak self, weak c] state in
            MainActor.assumeIsolated {
                guard let self, let c, self.generation == gen, self.connection === c else { return }
                switch state {
                case .ready:
                    self.sendHello(c)
                    self.receive(c, gen)
                case .failed, .waiting:
                    self.dropConnection()
                case .cancelled:
                    if self.channel != nil { self.dropConnection() }
                default: break
                }
            }
        }
        c.start(queue: .main)
        // Handshake timed out: abandon this phone and try another.
        Task { @MainActor [weak self, weak c] in
            try? await Task.sleep(for: .seconds(Self.handshakeTimeout))
            guard let self, let c, self.generation == gen, self.connection === c, self.channel == nil else { return }
            self.dropConnection()
        }
    }

    private func sendHello(_ c: NWConnection) {
        let hello = BumpHello(id: myID, key: myKey.publicKey.rawRepresentation)
        guard let data = try? JSONEncoder().encode(hello), let frame = try? FrameBuffer.frame(data) else { dropConnection(); return }
        c.send(content: frame, completion: .idempotent)
    }

    private func receive(_ c: NWConnection, _ gen: UUID) {
        c.receive(minimumIncompleteLength: 1, maximumLength: FrameBuffer.maximum) { [weak self, weak c] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self, let c, self.generation == gen, self.connection === c else { return }
                do {
                    if let data, !data.isEmpty {
                        for record in try self.frames.append(data) {
                            try self.handle(record)
                            guard self.generation == gen, self.connection === c else { return }
                        }
                    }
                    if done || error != nil { self.dropConnection() } else { self.receive(c, gen) }
                } catch {
                    self.dropConnection()
                }
            }
        }
    }

    private func handle(_ record: Data) throws {
        if channel == nil {
            let hello = try JSONDecoder().decode(BumpHello.self, from: record)
            if initiator, hello.id != peerID { throw BumpChannel.Failure.badHello }
            channel = try BumpChannel(myKey: myKey, myID: myID, peer: hello, initiator: initiator)
            peerID = hello.id
            browser?.cancel(); browser = nil   // Peer found; stop discovery.
            onEvent?(.ready(initiator: initiator))
        } else {
            guard let m = try channel?.open(record) else { return }
            onEvent?(.message(m))
        }
    }

    /// Before handshake completion, try another phone after disconnection; afterward, notify the caller.
    private func dropConnection() {
        let wasReady = channel != nil
        if let peerID { tried.insert(peerID) }
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        channel = nil
        peerID = nil
        frames = FrameBuffer()
        if wasReady { onEvent?(.closed) } else { connectIfNeeded(generation) }
    }
}
