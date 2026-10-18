import Foundation
import Network
import CryptoKit

/// Discover a nearby phone and establish an encrypted pairing channel, adapted from B's ios/UWBMeetDemo/App/PeerTransport.swift.
/// Change: no manually entered code. Both phones advertise and browse _jiefong._tcp, registered in Info.plist.
/// The smaller ID initiates (BumpTieBreak); use ephemeral Curve25519 key agreement after connecting (BumpChannel).
/// includePeerToPeer permits AWDL peer-to-peer Wi-Fi without a shared access point; Wi-Fi and Bluetooth must remain enabled.
/// All callbacks run on the main thread; Network uses the .main queue.
///
/// 2026-10-17 feedback D-2/D-5: pairing failed on cellular and success was inconsistent.
/// - AWDL between different Wi-Fi networks can initially enter .waiting. Previously this immediately failed and permanently excluded that peer,
///   effectively requiring the same Wi-Fi. Now wait within the handshake deadline and retry after retryDelay rather than blacklisting.
/// - Bonjour discovery over AWDL can be one-sided. The larger ID initiates after fallbackDelay if no inbound connection arrives.
///   Channel roles and one-time-code ownership still follow ID order, independently of TCP initiation.
@MainActor
final class BumpTransport {
    enum Event {
        /// Encrypted channel established. initiator means my ID is smaller and I generate the one-time code.
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
    /// This connection was initiated locally rather than accepted from a peer.
    private var outgoing = false
    private var peerID: String?
    private var channel: BumpChannel?
    private var frames = FrameBuffer()
    private var generation = UUID()
    /// Failed connection/handshake peers: next retry time and attempt count.
    private var retryAt: [String: TimeInterval] = [:]
    private var attempts: [String: Int] = [:]
    /// First observation time per peer; the larger ID waits fallbackDelay before initiating.
    private var firstSeen: [String: TimeInterval] = [:]
    private var endpoints: [String: NWEndpoint] = [:]
    private var recheck: Task<Void, Never>?
    /// kDNSServiceErr_PolicyDenied: Local Network permission has not been granted.
    private static let policyDenied: Int32 = -65570
    /// Handshake timeout in seconds before retrying later. Initial AWDL connection may take several seconds.
    private static let handshakeTimeout: TimeInterval = 8
    /// Delay between attempts for the same peer and maximum attempts per peer.
    private static let retryDelay: TimeInterval = 1.5
    private static let maxAttempts = 8
    /// Seconds the larger ID waits for an inbound connection before initiating itself.
    static let fallbackDelay: TimeInterval = 3

    private static func parameters() -> NWParameters {
        let p = NWParameters.tcp
        p.includePeerToPeer = true
        return p
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

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
                guard let self, self.generation == gen, self.acceptsIncoming else { c.cancel(); return }
                self.detachPending()
                self.attach(c, outgoing: false, peer: nil, gen)
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
        outgoing = false
        endpoints = [:]
        retryAt = [:]
        attempts = [:]
        firstSeen = [:]
        recheck?.cancel(); recheck = nil
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
        let now = Self.now
        for r in results {
            if case .service(let name, _, _, _) = r.endpoint, let id = BumpTieBreak.instanceID(fromServiceName: name), id != myID {
                endpoints[id] = r.endpoint
                if firstSeen[id] == nil { firstSeen[id] = now }
            }
        }
        connectIfNeeded(gen)
    }

    /// Prefer a higher-ID peer (normal direction); otherwise connect to a lower-ID peer after fallbackDelay without an inbound connection.
    /// Wait retryDelay after failure and schedule a recheck if necessary.
    private func connectIfNeeded(_ gen: UUID) {
        guard generation == gen, connection == nil else { return }
        let now = Self.now
        var wake: TimeInterval?
        func usable(_ id: String) -> Bool {
            if (attempts[id] ?? 0) >= Self.maxAttempts { return false }
            if let t = retryAt[id], t > now { wake = min(wake ?? t, t); return false }
            return true
        }
        let visible = endpoints.keys.filter(usable)
        var pick = BumpTieBreak.pick(me: myID, visible: visible)
        if pick == nil {
            for id in visible.filter({ BumpTieBreak.shouldConnect(me: $0, peer: myID) }).sorted() {
                let due = (firstSeen[id] ?? now) + Self.fallbackDelay
                if due <= now { pick = id; break }
                wake = min(wake ?? due, due)
            }
        }
        if let pick, let ep = endpoints[pick] {
            attempts[pick, default: 0] += 1
            attach(NWConnection(to: ep, using: Self.parameters()), outgoing: true, peer: pick, gen)
        } else if let wake {
            recheck?.cancel()
            recheck = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(0, wake - now) + 0.05))
                guard let self, !Task.isCancelled else { return }
                self.connectIfNeeded(gen)
            }
        }
    }

    /// Accept inbound connections when idle. An unhandshaken fallback connection from the larger ID yields to the normal inbound direction.
    /// A smaller ID with an unfinished normal outbound handshake rejects inbound attempts, avoiding mutual rejection during simultaneous connection attempts.
    private var acceptsIncoming: Bool {
        guard connection != nil else { return true }
        guard channel == nil, outgoing, let peerID else { return false }
        return BumpTieBreak.shouldConnect(me: peerID, peer: myID)
    }

    /// Release an unhandshaken fallback connection to yield to inbound traffic; this is not a failure.
    private func detachPending() {
        guard let c = connection, channel == nil else { return }
        c.stateUpdateHandler = nil
        c.cancel()
        if let peerID { attempts[peerID] = max(0, (attempts[peerID] ?? 1) - 1) }
        connection = nil
        peerID = nil
        outgoing = false
        frames = FrameBuffer()
    }

    // MARK: - Connection and handshake

    private func attach(_ c: NWConnection, outgoing: Bool, peer: String?, _ gen: UUID) {
        connection = c
        self.outgoing = outgoing
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
                case .failed:
                    self.dropConnection()
                case .waiting:
                    // Before handshake, Network retries .waiting until the deadline. After handshake, .waiting means the connection is lost.
                    if self.channel != nil { self.dropConnection() }
                case .cancelled:
                    if self.channel != nil { self.dropConnection() }
                default: break
                }
            }
        }
        c.start(queue: .main)
        // Abandon an overdue handshake and retry later.
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
            if outgoing, hello.id != peerID { throw BumpChannel.Failure.badHello }
            // Roles follow ID order, independently of TCP initiation, including fallback connections.
            let initiator = BumpTieBreak.shouldConnect(me: myID, peer: hello.id)
            channel = try BumpChannel(myKey: myKey, myID: myID, peer: hello, initiator: initiator)
            peerID = hello.id
            browser?.cancel(); browser = nil   // Peer found; stop discovery.
            recheck?.cancel(); recheck = nil
            onEvent?(.ready(initiator: initiator))
        } else {
            guard let m = try channel?.open(record) else { return }
            onEvent?(.message(m))
        }
    }

    /// Before handshake, retry a disconnected peer after retryDelay. After handshake, report disconnection to the owner.
    private func dropConnection() {
        let wasReady = channel != nil
        if let peerID, !wasReady { retryAt[peerID] = Self.now + Self.retryDelay }
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        channel = nil
        peerID = nil
        outgoing = false
        frames = FrameBuffer()
        if wasReady { onEvent?(.closed) } else { connectIfNeeded(generation) }
    }
}
