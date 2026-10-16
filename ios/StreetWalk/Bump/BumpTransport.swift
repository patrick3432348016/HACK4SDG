import Foundation
import Network
import CryptoKit

/// 碰一碰：喺身边搵另一部手机，连上，开加密通道。参考组员 B 嘅 PeerTransport（ios/UWBMeetDemo/App/PeerTransport.swift），
/// 改咗：唔使输入配对码——两部手机同时广播同搜索 `_jiefong._tcp`（Info.plist 已登记），
/// id 细嘅一方主动连（BumpTieBreak），连上后用一次性 Curve25519 密钥协商（BumpChannel）。
/// includePeerToPeer：唔使连同一个 Wi-Fi，Wi-Fi 同蓝牙开住就得（AWDL，点对点 Wi-Fi）。
/// 全部回调都喺主线程（Network 用 .main 队列）。
///
/// 2026-10-17（测试员 D-2 / D-5：用流量时碰唔到、成功率唔稳）：
/// - 唔同 Wi-Fi 时要行 AWDL，连线会先「等緊」（.waiting）一阵；以前一见 .waiting 就当失败，仲永远唔再试嗰部
///   → 实际上只有同一个 Wi-Fi 先得。而家 .waiting 照等（握手时限内），失败咗隔 retryDelay 秒再试同一部，唔会拉黑。
/// - AWDL 下 Bonjour 可能得一边见到另一边：id 大嗰部见到对方 fallbackDelay 秒都未有人连过嚟，就由佢主动连。
///   通道角色（边个定一次性码）仍然按 id 大细定（BumpTieBreak），同边个开 TCP 无关。
@MainActor
final class BumpTransport {
    enum Event {
        /// 加密通道通咗。initiator = 我 id 细（负责定一次性码）。
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
    /// 呢条连接係我主动开嘅（唔係对方连入嚟）。
    private var outgoing = false
    private var peerID: String?
    private var channel: BumpChannel?
    private var frames = FrameBuffer()
    private var generation = UUID()
    /// 连唔上 / 握手失败嘅对方：几时之后先再试、试咗几多次。
    private var retryAt: [String: TimeInterval] = [:]
    private var attempts: [String: Int] = [:]
    /// 每部对方第一次见到嘅时间（id 大嗰部要等 fallbackDelay 秒先主动连）。
    private var firstSeen: [String: TimeInterval] = [:]
    private var endpoints: [String: NWEndpoint] = [:]
    private var recheck: Task<Void, Never>?
    /// kDNSServiceErr_PolicyDenied：本地网络权限未允许。
    private static let policyDenied: Int32 = -65570
    /// 一条连接几耐未握手完就放弃，迟啲再试（秒）。AWDL 第一次连可能要几秒。
    private static let handshakeTimeout: TimeInterval = 8
    /// 连唔上之后隔几耐再试同一部；每部最多试几次。
    private static let retryDelay: TimeInterval = 1.5
    private static let maxAttempts = 8
    /// id 大嗰部见到对方几耐都未有人连过嚟，就自己连（秒）。
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
        outgoing = false
        endpoints = [:]
        retryAt = [:]
        attempts = [:]
        firstSeen = [:]
        recheck?.cancel(); recheck = nil
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
        let now = Self.now
        for r in results {
            if case .service(let name, _, _, _) = r.endpoint, let id = BumpTieBreak.instanceID(fromServiceName: name), id != myID {
                endpoints[id] = r.endpoint
                if firstSeen[id] == nil { firstSeen[id] = now }
            }
        }
        connectIfNeeded(gen)
    }

    /// 揀一部去连：先揀 id 比我大嘅（正常方向）；冇就揀 id 比我细、见咗 fallbackDelay 秒都未连过嚟嘅（AWDL 一边见唔到另一边）。
    /// 啱啱失败嘅等 retryDelay 秒先再试；未到钟就排一个复查。
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

    /// 有人连入嚟时收唔收：未有连接就收；手上只有一条「后备」（我 id 大、主动连 id 细嗰部）而且未握手，就让路俾对方嗰条。
    /// 我 id 细、自己嗰条（正常方向）未握手完：唔收，等对方收我嗰条（两边同时连都唔会互相拒绝）。
    private var acceptsIncoming: Bool {
        guard connection != nil else { return true }
        guard channel == nil, outgoing, let peerID else { return false }
        return BumpTieBreak.shouldConnect(me: peerID, peer: myID)
    }

    /// 放低手上未握手嘅后备连接（让路俾连入嚟嗰条），唔当失败。
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

    // MARK: - 连接与握手

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
                    // AWDL / 网络未准备好：Network 会自己再试，握手时限到先放弃。握手之后先「等」就当断线。
                    if self.channel != nil { self.dropConnection() }
                case .cancelled:
                    if self.channel != nil { self.dropConnection() }
                default: break
                }
            }
        }
        c.start(queue: .main)
        // 握手太耐：放弃呢条，迟啲再试。
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
            // 角色按 id 定（id 细 = 定码嗰方），同边个开 TCP 无关（后备连线都一样）。
            let initiator = BumpTieBreak.shouldConnect(me: myID, peer: hello.id)
            channel = try BumpChannel(myKey: myKey, myID: myID, peer: hello, initiator: initiator)
            peerID = hello.id
            browser?.cancel(); browser = nil   // 已经搵到，唔使再搵
            recheck?.cancel(); recheck = nil
            onEvent?(.ready(initiator: initiator))
        } else {
            guard let m = try channel?.open(record) else { return }
            onEvent?(.message(m))
        }
    }

    /// 连接断咗：握手前 = 隔 retryDelay 秒再试（同一部都会再试）；握手后 = 话俾上面知。
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
