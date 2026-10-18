import Foundation
import NearbyInteraction
import UIKit

/// Physical-device F5: discover a phone over Bonjour, exchange UWB tokens over encryption, and measure distance.
/// After sustained proximity on both phones, the initiator sends a one-time code; both submit it to NeighborLinker and receive the peer.
/// Adapted from B's UWBMeetDemo MeetCoordinator: NISession, token archiving, foreground restrictions, and timeouts.
/// Changes: no manual code, confirmation card, or contact-field exchange; the backend determines the paired identity.
///
/// Requires supported UWB hardware on both phones and foreground apps. Report unsupported and offer QR when unavailable.
///
/// 2026-10-17 feedback D-2/D-6:
/// - On unexpected disconnect/UWB error, rediscover silently within the deadline, up to maxRestarts, without requiring both users to retry.
///   Only an explicit .cancel immediately reports that the other person stopped.
/// - Overall timeout changes from 60 to 30 seconds, with at least rangingGrace after connection. After initial readings, peerSilence without readings triggers rediscovery.
/// - System overlays such as AirDrop may suspend UWB; resume ranging when they close rather than failing.
@MainActor
final class NearbyBumpService: BumpService {
    enum Phase: Equatable { case idle, searching, ranging, linking }

    /// Backend set by AppStore before each attempt; see AppStore+Bump.linker.
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
    /// Attempt deadline in systemUptime; silent rediscovery does not reset it.
    private var deadline: TimeInterval = 0
    private var restarts = 0

    /// ranging: actual UWB implementation on devices, fake implementation in unit tests.
    init(ranging: @escaping @MainActor () -> BumpRanging = { NIRanging() }, searchTimeout: TimeInterval = BumpTuning.searchTimeout) {
        makeRanging = ranging
        self.searchTimeout = searchTimeout
    }

    /// Check hardware support; simulators and unsupported phone models lack UWB.
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

    /// Start one UWB/Bonjour round, both initially and after silent rediscovery.
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

    // MARK: - Channel

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
            // After code submission, only the server result matters. Before submission, a disconnect triggers rediscovery rather than assuming rejection.
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
            // Allow at least rangingGrace after connection so finding a peer near the deadline still leaves time to approach.
            let grace = Self.now + BumpTuning.rangingGrace
            if deadline < grace { deadline = grace; scheduleTimeout() }
            onUpdate?(.ranging(nil))
            startGapWatch()
        case .near:
            guard phase == .ranging || phase == .linking else { recover(.other); return }
            agreement.markPeerNear()
            checkBothNear()
        case .code:
            // Accept only the initiator's code, and only after local proximity is measured; the peer's claim cannot replace local evidence.
            guard !initiator, phase == .linking, let code = m.code, agreement.accept(code: code) else { recover(.other); return }
            startLinking(code)
        case .cancel:
            // Report explicit peer cancellation/failure immediately instead of waiting for timeout (D-6).
            if agreement.code == nil { fail(.peerLeft) }
        }
    }

    // MARK: - Distance

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

    /// Reset interrupted proximity timing; after one second without readings show ranging. Prolonged silence after prior readings triggers rediscovery.
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
        ranging?.stop()   // Proximity confirmed; stop ranging.
        onUpdate?(.linking)
        if initiator {
            let code = PairCode.random()
            _ = agreement.accept(code: code)
            transport?.send(.code, code: code)
            startLinking(code)
        }
    }

    // MARK: - Backend

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

    // MARK: - Failure, rediscovery, and cleanup

    private func rangingFailed(_ f: BumpFailure) {
        guard phase != .idle else { return }
        switch f {
        case .nearbyDenied:
            fail(f)
        case .peerLeft:
            // A peer stopping UWB may precede .cancel or silent rediscovery; wait briefly before deciding.
            guard peerEndedTask == nil else { return }
            peerEndedTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled else { return }
                self.peerEndedTask = nil
                // If both sides became close during the delay, the peer may have stopped ranging normally; continue waiting for the code.
                guard self.phase == .ranging else { return }
                self.recover(.peerLeft)
            }
        default:
            recover(f)
        }
    }

    /// Unexpected disconnect/UWB failure/peer restart triggers silent rediscovery within the deadline.
    /// Fail when attempts or time are exhausted. Ignore such errors after code submission while waiting for the server.
    private func recover(_ f: BumpFailure) {
        guard phase != .idle, agreement.code == nil else { return }
        guard restarts < BumpTuning.maxRestarts, deadline - Self.now > 5 else { fail(f); return }
        restarts += 1
        teardown(notifyPeer: false)   // Do not send cancellation during rediscovery; the peer can rediscover after disconnecting too.
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
        // After code submission, keep waiting for the server and resume polling on foreground. Otherwise stop UWB and explain the interruption.
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
        // Send .cancel before stopping UWB so the peer does not mistake cancellation for a recoverable disconnect.
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

// MARK: - Ranging

/// Ranging abstraction: NIRanging on hardware, fakes for end-to-end unit tests without hardware.
@MainActor
protocol BumpRanging: AnyObject {
    var isSupported: Bool { get }
    /// Start a session and return the local token for encrypted exchange.
    func prepare() throws -> Data
    /// Begin ranging with the peer's token.
    func start(peerToken: Data) throws
    func stop()
    /// Distance readings in metres; nil means temporarily unavailable.
    var onDistance: ((Float?) -> Void)? { get set }
    var onFailure: ((BumpFailure) -> Void)? { get set }
}

/// Nearby Interaction ranging with NSKeyedArchiver token serialization, matching B's prototype.
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
        s.run(c)   // The first use prompts for Nearby Interaction permission.
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
            // After timeout/out-of-range/occlusion, Apple recommends restarting with the same configuration.
            onDistance?(nil)
            if let config { session.run(config) }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        MainActor.assumeIsolated {
            guard session === self.session else { return }
            // System overlays suspend rather than fail ranging; restart at sessionSuspensionEnded (D-4). NearbyBumpService handles actual backgrounding.
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
