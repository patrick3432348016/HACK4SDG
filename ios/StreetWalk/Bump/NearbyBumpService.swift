import Foundation
import NearbyInteraction
import UIKit

/// 真机碰一碰（F5）：Bonjour 搵身边部手机 → 加密通道交换超宽带令牌 → 量距离 →
/// 两部都连续够近 → 主动连嗰方定一个一次性码、经通道交俾对方 → 两部各自交俾后端（NeighborLinker）→ 返回对方。
/// 移植自组员 B 嘅 UWBMeetDemo（MeetCoordinator：NISession、令牌归档、前台限制、时限），
/// 改咗：唔使输入配对码、冇确认卡、唔交换联络方式；配对结果由后端决定。
///
/// 限制（苹果）：两部都要 iPhone 11 或之后（有 U1/U2 芯片，SE 冇），App 要喺前台。唔支援就报 .unsupported，界面提供二维码。
///
/// 2026-10-17（测试员 D-2 / D-6）：
/// - 中途断线（唔係对方撳取消）、超宽带出错：时限内静静重新搵（最多 maxRestarts 次），唔使两个人都撳「再試」。
///   对方撳取消（收到 .cancel）先即刻讲「對方停咗」。
/// - 总时限 60 → 30 秒；连上咗至少再俾 rangingGrace 秒慢慢靠近。量到过距离之后 peerSilence 秒冇读数 = 对方走咗，重新搵。
/// - 弹「隔空投送」之类令超宽带暂停：唔当失败，返嚟继续量。
@MainActor
final class NearbyBumpService: BumpService {
    enum Phase: Equatable { case idle, searching, ranging, linking }

    /// 后端。AppStore 每次开始前设（见 AppStore+Bump 嘅 linker）。
    var linker: NeighborLinker?
    private(set) var phase: Phase = .idle

    private let makeRanging: @MainActor () -> BumpRanging
    private let searchTimeout: TimeInterval
    private var ranging: BumpRanging?
    private var transport: BumpTransport?
    private var myToken: Data?
    private var gate = ProximityGate()
    private var agreement = BumpAgreement()
    private var initiator = false
    private var localNetworkBlocked = false
    private var lastSample: TimeInterval?
    private var onUpdate: ((BumpUpdate) -> Void)?
    private var onFound: ((BumpMatch) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var gapTask: Task<Void, Never>?
    private var linkTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var peerEndedTask: Task<Void, Never>?
    private var backgroundObserver: NSObjectProtocol?
    /// 今次碰一碰几时到钟（systemUptime）；静静重新搵唔会重新计。
    private var deadline: TimeInterval = 0
    private var restarts = 0

    /// - ranging: 量距离嘅实现（真机 = 超宽带；单元测试用假嘅）。
    init(ranging: @escaping @MainActor () -> BumpRanging = { NIRanging() }, searchTimeout: TimeInterval = BumpTuning.searchTimeout) {
        makeRanging = ranging
        self.searchTimeout = searchTimeout
    }

    /// 呢部手机有冇超宽带（模拟器、iPhone 11 之前、SE 都冇）。
    static var deviceSupported: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - BumpService

    func startSearching(candidates: [Resident], onUpdate: @escaping (BumpUpdate) -> Void, onFound: @escaping (BumpMatch) -> Void) {
        cancel()
        self.onUpdate = onUpdate
        self.onFound = onFound
        restarts = 0
        deadline = Self.now + searchTimeout
        begin()
    }

    /// 开一轮：超宽带会话 + Bonjour 通道。第一次同静静重新搵都用。
    private func begin() {
        let r = makeRanging()
        guard r.isSupported else {
            let u = onUpdate
            onUpdate = nil
            onFound = nil
            u?(.failed(.unsupported))
            return
        }
        r.onDistance = { [weak self] d in self?.measured(d) }
        r.onFailure = { [weak self] f in self?.rangingFailed(f) }
        ranging = r
        phase = .searching
        do { myToken = try r.prepare() } catch { fail(.other); return }
        let t = BumpTransport()
        t.onEvent = { [weak self] e in self?.transportEvent(e) }
        transport = t
        do { try t.start() } catch { recover(.other); return }
        onUpdate?(.searching)
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wentToBackground() }
        }
        scheduleTimeout()
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        let wait = max(0, deadline - Self.now)
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled, self.phase == .searching || self.phase == .ranging || (self.phase == .linking && self.agreement.code == nil) else { return }
            self.fail(self.phase == .searching && self.localNetworkBlocked ? .localNetworkDenied : .timeout)
        }
    }

    func cancel() {
        teardown(notifyPeer: phase != .idle)
        onUpdate = nil
        onFound = nil
    }

    // MARK: - 通道

    private func transportEvent(_ e: BumpTransport.Event) {
        guard phase != .idle else { return }
        switch e {
        case .localNetwork(let blocked):
            localNetworkBlocked = blocked
            if phase == .searching { onUpdate?(blocked ? .needsLocalNetwork : .searching) }
        case .ready(let initiator):
            self.initiator = initiator
            guard let myToken else { recover(.other); return }
            transport?.send(.hello, token: myToken)
        case .message(let m):
            received(m)
        case .closed:
            // 已经交咗码：之后只係等伺服器，对方收线唔紧要。未交码：断线唔等于对方唔要，静静重新搵。
            if agreement.code == nil { recover(.peerLeft) }
        case .unavailable:
            recover(.other)
        }
    }

    private func received(_ m: BumpMessage) {
        switch m.kind {
        case .hello:
            guard phase == .searching, let token = m.token else { recover(.other); return }
            do { try ranging?.start(peerToken: token) } catch { recover(.other); return }
            phase = .ranging
            // 连上咗：至少再俾 rangingGrace 秒慢慢靠近（唔好啱啱搵到就够钟）。
            let grace = Self.now + BumpTuning.rangingGrace
            if deadline < grace { deadline = grace; scheduleTimeout() }
            onUpdate?(.ranging(nil))
            startGapWatch()
        case .near:
            guard phase == .ranging || phase == .linking else { recover(.other); return }
            agreement.markPeerNear()
            checkBothNear()
        case .code:
            // 只收主动连嗰方嘅码，而且自己都要量到够近（对方话够近唔算数，B 原型嘅原则）。
            guard !initiator, phase == .linking, let code = m.code, agreement.accept(code: code) else { recover(.other); return }
            startLinking(code)
        case .cancel:
            // 对方撳咗取消 / 佢嗰边真係失败：即刻讲，唔好等到够钟（D-6）。
            if agreement.code == nil { fail(.peerLeft) }
        }
    }

    // MARK: - 距离

    private func measured(_ d: Float?) {
        guard phase == .ranging else { return }
        let now = Self.now
        if d != nil { lastSample = now; peerEndedTask?.cancel(); peerEndedTask = nil }
        guard !agreement.localNear else { return }
        onUpdate?(.ranging(d))
        if gate.update(distance: d, at: now) {
            agreement.markLocalNear()
            transport?.send(.near)
            onUpdate?(.nearMe)
            checkBothNear()
        }
    }

    /// 读数断咗：计时重来；超过 1 秒冇读数，画面改讲「量緊距離」；量到过之后好耐冇读数 = 对方走咗，重新搵。
    private func startGapWatch() {
        gapTask?.cancel()
        gapTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                guard self.phase == .ranging, let last = self.lastSample else { continue }
                let now = Self.now
                let gap = now - last
                if gap > BumpTuning.peerSilence { self.recover(.peerLeft); return }
                guard !self.agreement.localNear else { continue }
                if gap > BumpTuning.maxGap { _ = self.gate.update(distance: nil, at: now) }
                if gap > 1 { self.onUpdate?(.ranging(nil)) }
            }
        }
    }

    private func checkBothNear() {
        guard agreement.bothNear, phase == .ranging else { return }
        phase = .linking
        gapTask?.cancel()
        peerEndedTask?.cancel(); peerEndedTask = nil
        ranging?.stop()   // 够近咗，唔使再量
        onUpdate?(.linking)
        if initiator {
            let code = PairCode.random()
            _ = agreement.accept(code: code)
            transport?.send(.code, code: code)
            startLinking(code)
        }
    }

    // MARK: - 后端

    private func startLinking(_ code: String) {
        guard let linker else { fail(.noServer); return }
        timeoutTask?.cancel()
        linkTask = Task { [weak self] in
            do {
                let peer = try await LinkPolling.poll(linker, code: code)
                guard let self, self.phase == .linking else { return }
                if let peer { self.succeed(peer) } else { self.fail(.linkFailed) }
            } catch is CancellationError {
            } catch {
                self?.fail(.network)
            }
        }
    }

    private func succeed(_ peer: LinkedPeer) {
        let found = onFound
        teardown(notifyPeer: false)
        onUpdate = nil
        onFound = nil
        found?(.linked(peer))
    }

    // MARK: - 失败、重新搵与收尾

    private func rangingFailed(_ f: BumpFailure) {
        guard phase != .idle else { return }
        switch f {
        case .nearbyDenied:
            fail(f)
        case .peerLeft:
            // 对方超宽带停咗：可能撳咗取消（.cancel 好快会到），亦可能佢静静重新搵紧。等一阵先决定。
            guard peerEndedTask == nil else { return }
            peerEndedTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled else { return }
                self.peerEndedTask = nil
                // 呢段时间已经两边够近（对方停超宽带係因为够近咗）就唔理，等码。
                guard self.phase == .ranging else { return }
                self.recover(.peerLeft)
            }
        default:
            recover(f)
        }
    }

    /// 中途出咗意外（断线、超宽带出错、对方静静重新搵）：时限内静静由头搵过，唔使用户撳「再試」；
    /// 次数用完 / 就快够钟就当失败。已经交咗码就唔理（等伺服器）。
    private func recover(_ f: BumpFailure) {
        guard phase != .idle, agreement.code == nil else { return }
        guard restarts < BumpTuning.maxRestarts, deadline - Self.now > 5 else { fail(f); return }
        restarts += 1
        teardown(notifyPeer: false)   // 唔发「取消」：对方见到断线都会静静重新搵
        phase = .searching
        onUpdate?(.searching)
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(BumpTuning.restartPause))
            guard let self, !Task.isCancelled, self.onUpdate != nil else { return }
            self.restartTask = nil
            self.phase = .idle
            self.begin()
        }
    }

    private func wentToBackground() {
        // 已经交咗码就继续等伺服器（返嚟前台会接住问）；否则超宽带一定停，讲清楚。
        guard phase != .idle, agreement.code == nil else { return }
        fail(.background)
    }

    private func fail(_ f: BumpFailure) {
        guard phase != .idle else { return }
        let update = onUpdate
        teardown(notifyPeer: true)
        update?(.failed(f))
    }

    private func teardown(notifyPeer: Bool) {
        phase = .idle
        timeoutTask?.cancel(); timeoutTask = nil
        gapTask?.cancel(); gapTask = nil
        linkTask?.cancel(); linkTask = nil
        restartTask?.cancel(); restartTask = nil
        peerEndedTask?.cancel(); peerEndedTask = nil
        // 先话俾对方知（.cancel），再停超宽带：对方先收到「取消」，唔会误当成断线重新搵。
        if notifyPeer { transport?.sendCancelAndStop() } else { transport?.stop() }
        transport = nil
        ranging?.onDistance = nil
        ranging?.onFailure = nil
        ranging?.stop(); ranging = nil
        if let o = backgroundObserver { NotificationCenter.default.removeObserver(o) }
        backgroundObserver = nil
        myToken = nil
        gate.reset()
        agreement = BumpAgreement()
        initiator = false
        localNetworkBlocked = false
        lastSample = nil
    }
}

// MARK: - 量距离

/// 量距离嘅抽象：真机用超宽带（NIRanging），单元测试用假嘅（唔使硬件都试得到成个流程）。
@MainActor
protocol BumpRanging: AnyObject {
    var isSupported: Bool { get }
    /// 开会话，返回我嘅令牌（经加密通道交俾对方）。
    func prepare() throws -> Data
    /// 用对方令牌开始量。
    func start(peerToken: Data) throws
    func stop()
    /// 每次量到（米）；nil = 暂时冇读数。
    var onDistance: ((Float?) -> Void)? { get set }
    var onFailure: ((BumpFailure) -> Void)? { get set }
}

/// 超宽带（Nearby Interaction）。令牌用 NSKeyedArchiver 归档（同 B 原型一样）。
@MainActor
final class NIRanging: NSObject, BumpRanging, NISessionDelegate {
    enum Failure: Error { case noToken, badToken }
    var onDistance: ((Float?) -> Void)?
    var onFailure: ((BumpFailure) -> Void)?
    private var session: NISession?
    private var peerToken: NIDiscoveryToken?
    private var config: NINearbyPeerConfiguration?

    var isSupported: Bool { NearbyBumpService.deviceSupported }

    func prepare() throws -> Data {
        let s = NISession()
        s.delegate = self
        s.delegateQueue = .main
        session = s
        guard let token = s.discoveryToken else { throw Failure.noToken }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    func start(peerToken data: Data) throws {
        guard let s = session,
              let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else { throw Failure.badToken }
        peerToken = token
        let c = NINearbyPeerConfiguration(peerToken: token)
        config = c
        s.run(c)   // 第一次会弹「附近互動」权限框
    }

    func stop() {
        session?.delegate = nil
        session?.invalidate()
        session = nil
        config = nil
        peerToken = nil
    }

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        MainActor.assumeIsolated {
            guard session === self.session, let o = nearbyObjects.first(where: { $0.discoveryToken == self.peerToken }) else { return }
            onDistance?(o.distance)
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        MainActor.assumeIsolated {
            guard session === self.session else { return }
            if reason == .peerEnded { onFailure?(.peerLeft); return }
            // 超时（行远咗 / 遮住）：苹果建议用返同一个配置再开。
            onDistance?(nil)
            if let config { session.run(config) }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        MainActor.assumeIsolated {
            guard session === self.session else { return }
            // 例如弹咗「隔空投送」/ 系统框：暂停，唔当失败，sessionSuspensionEnded 再开（D-4）。真係去咗背景由 NearbyBumpService 处理。
            onDistance?(nil)
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        MainActor.assumeIsolated {
            guard session === self.session, let config else { return }
            session.run(config)
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        MainActor.assumeIsolated {
            guard session === self.session else { return }
            let denied = (error as? NIError)?.code == .userDidNotAllow
            onFailure?(denied ? .nearbyDenied : .other)
        }
    }
}
