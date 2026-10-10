import Foundation
import Network
import CryptoKit

/// 碰一碰：喺身边搵另一部手机，连上，开加密通道。参考组员 B 嘅 PeerTransport（ios/UWBMeetDemo/App/PeerTransport.swift），
/// 改咗：唔使输入配对码——两部手机同时广播同搜索 `_jiefong._tcp`（Info.plist 已登记），
/// id 细嘅一方主动连（BumpTieBreak），连上后用一次性 Curve25519 密钥协商（BumpChannel）。
/// includePeerToPeer：唔使连同一个 Wi-Fi，Wi-Fi 同蓝牙开住就得（AWDL）。
/// 全部回调都喺主线程（Network 用 .main 队列）。
@MainActor
final class BumpTransport {
    enum Event {
        /// 加密通道通咗。initiator = 我係主动连嗰方（负责定一次性码）。
        case ready(initiator: Bool)
        case message(BumpMessage)
        /// 「本地網絡」权限：true = 被挡住（未允许 / 拒绝咗），false = 通咗。
        case localNetwork(blocked: Bool)
        /// 通道通咗之后断线（对方走咗 / 出错）。
        case closed
        /// Bonjour 本身用唔到（广播 / 搜索失败）。
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
    /// 连唔上 / 握手失败嘅对方：今次唔再试。
    private var tried: Set<String> = []
    private var endpoints: [String: NWEndpoint] = [:]
    /// kDNSServiceErr_PolicyDenied：本地网络权限未允许。
    private static let policyDenied: Int32 = -65570
    /// 一条连接几耐未握手完就放弃，试下一部（秒）。
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

    /// 话俾对方知停咗（尽力），之后收线。
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

    // MARK: - 搵对方

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

    // MARK: - 连接与握手

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
        // 握手太耐：放弃呢部，试下一部。
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
            browser?.cancel(); browser = nil   // 已经搵到，唔使再搵
            onEvent?(.ready(initiator: initiator))
        } else {
            guard let m = try channel?.open(record) else { return }
            onEvent?(.message(m))
        }
    }

    /// 连接断咗：握手前 = 呢部唔得，试下一部；握手后 = 话俾上面知。
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
