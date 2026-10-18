import Foundation
import NearbyInteraction
import UIKit

/// Physical-device F5: discover a phone over Bonjour, exchange UWB tokens over encryption, and measure distance.
/// After sustained proximity on both phones, the initiator sends a one-time code; both submit it to NeighborLinker and receive the peer.
/// Adapted from B's UWBMeetDemo MeetCoordinator: NISession, token archiving, foreground restrictions, and timeouts.
/// Changes: no manual code, confirmation card, or contact-field exchange; the backend determines the paired identity.
///
/// Requires supported UWB hardware on both phones and foreground apps. Report unsupported and offer QR when unavailable.
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
    private var backgroundObserver: NSObjectProtocol?

    /// ranging: actual UWB implementation on devices, fake implementation in unit tests.
    init(ranging: @escaping @MainActor () -> BumpRanging = { NIRanging() }, searchTimeout: TimeInterval = BumpTuning.searchTimeout) {
        makeRanging = ranging
        self.searchTimeout = searchTimeout
    }

    /// Check hardware support; simulators and unsupported phone models lack UWB.
    static var deviceSupported: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }

    // MARK: - BumpService

    func startSearching(candidates: [Resident], onUpdate: @escaping (BumpUpdate) -> Void, onFound: @escaping (BumpMatch) -> Void) {
        cancel()
        let r = makeRanging()
        guard r.isSupported else { onUpdate(.failed(.unsupported)); return }
        self.onUpdate = onUpdate
        self.onFound = onFound
        r.onDistance = { [weak self] d in self?.measured(d) }
        r.onFailure = { [weak self] f in self?.fail(f) }
        ranging = r
        phase = .searching
        do { myToken = try r.prepare() } catch { fail(.other); return }
        let t = BumpTransport()
        t.onEvent = { [weak self] e in self?.transportEvent(e) }
        transport = t
        do { try t.start() } catch { fail(.other); return }
        onUpdate(.searching)
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wentToBackground() }
        }
        let limit = searchTimeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
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
            guard let myToken else { fail(.other); return }
            transport?.send(.hello, token: myToken)
        case .message(let m):
            received(m)
        case .closed:
            // The code is already submitted; only the server result remains, so peer disconnection is harmless here.
            if agreement.code == nil { fail(.peerLeft) }
        case .unavailable:
            fail(.other)
        }
    }

    private func received(_ m: BumpMessage) {
        switch m.kind {
        case .hello:
            guard phase == .searching, let token = m.token else { fail(.other); return }
            do { try ranging?.start(peerToken: token) } catch { fail(.other); return }
            phase = .ranging
            onUpdate?(.ranging(nil))
            startGapWatch()
        case .near:
            guard phase == .ranging || phase == .linking else { fail(.other); return }
            agreement.markPeerNear()
            checkBothNear()
        case .code:
            // Accept only the initiator's code, and only after local proximity is measured; the peer's claim cannot replace local evidence.
            guard !initiator, phase == .linking, let code = m.code, agreement.accept(code: code) else { fail(.other); return }
            startLinking(code)
        case .cancel:
            if agreement.code == nil { fail(.peerLeft) }
        }
    }

    // MARK: - Distance

    private func measured(_ d: Float?) {
        guard phase == .ranging else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if d != nil { lastSample = now }
        guard !agreement.localNear else { return }
        onUpdate?(.ranging(d))
        if gate.update(distance: d, at: now) {
            agreement.markLocalNear()
            transport?.send(.near)
            onUpdate?(.nearMe)
            checkBothNear()
        }
    }

    /// Restart timing when readings stop; after more than one second without readings, show that distance is being measured.
    private func startGapWatch() {
        gapTask?.cancel()
        gapTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                guard self.phase == .ranging, !self.agreement.localNear, let last = self.lastSample else { continue }
                let gap = ProcessInfo.processInfo.systemUptime - last
                if gap > BumpTuning.maxGap { _ = self.gate.update(distance: nil, at: ProcessInfo.processInfo.systemUptime) }
                if gap > 1 { self.onUpdate?(.ranging(nil)) }
            }
        }
    }

    private func checkBothNear() {
        guard agreement.bothNear, phase == .ranging else { return }
        phase = .linking
        gapTask?.cancel()
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

    // MARK: - Failure and cleanup

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
        ranging?.onDistance = nil
        ranging?.onFailure = nil
        ranging?.stop(); ranging = nil
        if notifyPeer { transport?.sendCancelAndStop() } else { transport?.stop() }
        transport = nil
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
            onFailure?(.background)
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
