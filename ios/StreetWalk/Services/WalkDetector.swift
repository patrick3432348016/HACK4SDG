import CoreLocation
import CoreMotion
import Foundation

/// Real walking detection uses Core Motion; accurate location is enabled while walking/recording.
/// Continue an active walk through lock/background using allowsBackgroundLocationUpdates. With Always permission,
/// LocationMonitor can wake the app after departure and restart detection through AppStore+Location.
/// Backfill other background periods, including force-quit gaps, from motion/pedometer history on foreground.
/// This walk-recording path converts precise fixes to scene coordinates without upload or disk persistence. Simulator/demo modes normally use simulated walks.
/// -simWalk enables simulator speed-based detection without Core Motion, for development only.
@MainActor
final class WalkDetector: NSObject, CLLocationManagerDelegate {
    enum Event {
        case walking(Bool)          // Core Motion walking start/stop.
        case riding                 // Vehicle/cycling activity does not count as walking.
        case location(GeoPoint, accuracy: Double)   // Accept fixes within 100-m accuracy and ten seconds; accuracy worse than 30 m is only for detecting return home.
        case still(since: Date)     // Report stationary thresholds at two, five, and ten minutes.
        case steps(Int, cadence: Double?)           // Pedometer: current walk steps and cadence in steps per second.

        var isSteps: Bool { if case .steps = self { return true } else { return false } }
    }

    /// Still thresholds: two minutes for a stop, five to finish near home, ten to finish while outside.
    static let stillMarks: [TimeInterval] = [2 * 60, 5 * 60, 10 * 60]

    var onEvent: ((Event) -> Void)?
    /// Whether the current walk is real-device recording rather than demo.
    var recording = false
    /// Real-device route in scene coordinates.
    var trail: [Vec2] = []
    /// Wheelchair mode treats non-definite stationary activity as movement; classify vehicle travel only above 4 m/s.
    /// Estimate by minutes instead of using an unfair near-zero pedometer count for wheelchair users.
    var seated = false { didSet { if seated && countingSteps { pedometer.stopUpdates(); countingSteps = false } } }
    /// Start/finish gate requires two valid fixes before declaring departure.
    var gate = LiveWalkGate()
    /// Latest active/recently stopped backfill segment waits for live location takeover; otherwise backfill after stopping.
    var pendingWalk: PendingWalk?
    /// During foreground history reconciliation, do not start location or start/finish a walk.
    var catchUps = 0
    var catchingUp: Bool { catchUps > 0 }
    /// Current Core Motion walking state and interval start; use motion start rather than the first GPS fix as walk start.
    private(set) var moving = false
    private(set) var movingSince: Date?
    private(set) var stillSince: Date?
    /// Last fix time/position drives elapsed minutes and cleanup after backgrounding.
    private(set) var lastFixAt: Date?
    private(set) var lastFix: (GeoPoint, accuracy: Double)?
    private var lastSpeed = -1.0

    /// Create motion hardware lazily after consent on a real device because construction may trigger the fitness permission prompt.
    private lazy var motion = CMMotionActivityManager()
    private lazy var pedometer = CMPedometer()
    private var countingSteps = false
    private let location = CLLocationManager()
    private(set) var running = false
    private var stillTask: Task<Void, Never>?

    // Background departure detection through AppStore+Location.
    /// Location levels: off, coarse keep-alive while waiting, and accurate walking/recording.
    private enum Mode { case off, coarse, fine }
    private var mode = Mode.off
    private var wantFine = false
    private var locating: Bool { mode == .fine }
    /// Coarse background keep-alive waits for walking after departure or an outdoor stop with little GPS use.
    /// Without background location, iOS suspends the app and motion callbacks stop too.
    var keepAlive = false { didSet { if keepAlive != oldValue { applyMode() } } }
    /// Home-region departure time without subsequent vehicle travel expands the allowed start distance (TriggerRules.maxStart).
    var leftHomeAt: Date?
    /// Background wake/wait and outdoor-stop timing from AppStore+Location.
    var watchTask: Task<Void, Never>?
    /// Keep location active in background while recording, waiting for walking, or waiting to resume after an outdoor stop.
    var staysAwakeInBackground: Bool { recording || watchTask != nil }
    /// Maximum starting distance, expanded after walking out from home.
    var maxStart: Double { TriggerRules.maxStart(leftHomeAt: leftHomeAt, now: Date()) }
    /// Previous simulator -simWalk fix for speed calculation.
    private var simLast: (GeoPoint, Date)?

    /// Hardware availability: real motion-capable device, or simulator with -simWalk. AppStore.startWalkDetection controls demo mode.
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return locationOnly
        #else
        return CMMotionActivityManager.isActivityAvailable()
        #endif
    }

    /// Simulator-only speed-based detection under -simWalk, without motion/pedometer; development testing only.
    /// Background relaunch has no launch arguments; reuse the configuration saved by the last explicit launch.
    static var locationOnly: Bool {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-simWalk") || (args.count == 1 && UserDefaults.standard.bool(forKey: "simWalk"))
        #else
        return false
        #endif
    }

    /// Persist simulator -simWalk presence for subsequent argument-free background relaunches.
    static func rememberSimWalk() {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if args.count > 1 { UserDefaults.standard.set(args.contains("-simWalk"), forKey: "simWalk") }
        #endif
    }

    /// Default demo mode on simulators, except -simWalk, and off on devices; preserve an explicit Settings choice.
    static var demoByDefault: Bool {
        #if targetEnvironment(simulator)
        return !locationOnly
        #else
        return false
        #endif
    }

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 3
        location.activityType = .fitness
    }

    /// After backgrounding an active walk, wait for AppStore history reconciliation before resuming location or finishing.
    func start() {
        guard Self.isAvailable, !running else { return }
        running = true
        if recording && !catchingUp { setLocating(true) }
        // -simWalk has no Core Motion; keep location active to measure speed.
        if Self.locationOnly { setLocating(true); return }
        motion.startActivityUpdates(to: .main) { [weak self] a in
            guard let self, let a, a.confidence != .low || self.seated else { return }
            let stepping = a.walking || a.running
            let riding = (a.automotive || a.cycling) && !(self.seated && self.lastSpeed <= 4)
            let moving = self.seated ? !a.stationary && !riding : stepping
            let still = a.stationary && !stepping && !riding
            self.watchStill(still)
            if riding {
                self.moving = false
                self.leftHomeAt = nil      // Vehicle travel ends the assumption that the user walked directly out from home.
                self.onEvent?(.riding)
            } else if moving {
                if !self.moving { self.movingSince = a.startDate }
                self.moving = true
                self.onEvent?(.walking(true))
            } else if still {
                self.moving = false
                self.onEvent?(.walking(false))
            }
        }
    }

    /// Emit still after enough time even without new GPS points due to distanceFilter.
    private func watchStill(_ still: Bool) {
        guard still else { stillTask?.cancel(); stillTask = nil; stillSince = nil; return }
        guard stillTask == nil else { return }
        let since = Date()
        stillSince = since
        stillTask = Task { @MainActor [weak self] in
            var waited: TimeInterval = 0
            for mark in Self.stillMarks {
                try? await Task.sleep(for: .seconds(mark - waited))
                waited = mark
                guard let self, !Task.isCancelled else { return }
                self.onEvent?(.still(since: since))
            }
        }
    }

    /// Walk cleanup clears route/last fix and stops pedometer updates.
    func reset() {
        recording = false
        trail = []
        lastFixAt = nil
        lastFix = nil
        gate = LiveWalkGate()
        if countingSteps { pedometer.stopUpdates(); countingSteps = false }
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
        keepAlive = false
        guard running else { return }
        running = false
        moving = false
        if !Self.locationOnly { motion.stopActivityUpdates() }
        stillTask?.cancel()
        stillTask = nil
        stillSince = nil
        simLast = nil
        wantFine = false
        applyMode()
    }

    /// Enable precise location only when needed to save power, except throughout a -simWalk run.
    func setLocating(_ on: Bool) {
        wantFine = on || (Self.locationOnly && running)
        applyMode()
    }

    /// Accurate while walking/recording, coarse for keepAlive, otherwise off.
    /// Both levels support background continuation; Always permission allows starting in background.
    private func applyMode() {
        let m: Mode = wantFine ? .fine : keepAlive ? .coarse : .off
        guard m != mode else { return }
        mode = m
        guard m != .off else { location.stopUpdatingLocation(); return }
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        location.desiredAccuracy = m == .fine ? kCLLocationAccuracyBest : kCLLocationAccuracyThreeKilometers
        location.distanceFilter = m == .fine ? 3 : 500
        location.pausesLocationUpdatesAutomatically = false
        location.allowsBackgroundLocationUpdates = true
        // Show the blue location indicator while recording; omit it for coarse keep-alive.
        location.showsBackgroundLocationIndicator = m == .fine
        location.startUpdatingLocation()
    }

    // MARK: - Pedometer: real steps (A85) and cadence (F9)

    func startSteps(from start: Date) {
        guard Self.isAvailable, !seated, CMPedometer.isStepCountingAvailable() else { return }
        countingSteps = true
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            guard let data else { return }
            let n = data.numberOfSteps.intValue, cadence = data.currentCadence?.doubleValue
            Task { @MainActor in self?.onEvent?(.steps(n, cadence: cadence)) }
        }
    }

    func steps(from: Date, to: Date) async -> Int? {
        guard Self.isAvailable, !seated, CMPedometer.isStepCountingAvailable() else { return nil }
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: from, to: to) { data, _ in cont.resume(returning: data?.numberOfSteps.intValue) }
        }
    }

    /// Read up to seven days of system motion history; return nil without permission/history.
    func activities(from: Date, to: Date) async -> [WalkBackfill.Sample]? {
        guard Self.isAvailable, !Self.locationOnly else { return nil }
        let seated = seated
        return await withCheckedContinuation { cont in
            motion.queryActivityStarting(from: from, to: to, to: .main) { list, _ in
                // Backfill lacks location validation, so reject low-confidence motion, including wheelchair mode.
                let s = list?.filter { $0.confidence != .low }.map {
                    WalkBackfill.Sample(start: $0.startDate, moving: WalkBackfill.isMoving(
                        walking: $0.walking, running: $0.running, stationary: $0.stationary, automotive: $0.automotive,
                        cycling: $0.cycling, unknown: $0.unknown, seated: seated))
                }
                cont.resume(returning: s)
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Reject accuracy worse than 100 m. Use 30–100-m fixes only for return-home detection, never route drawing.
        // Reject cached fixes older than ten seconds when location starts.
        let ok = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 100 && abs($0.timestamp.timeIntervalSinceNow) < 10 }
        guard let l = ok.last else { return }
        let p = GeoPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude), acc = l.horizontalAccuracy, at = l.timestamp, speed = l.speed
        Task { @MainActor in
            // Coarse keepAlive fixes maintain execution only; do not process them as route points.
            guard self.mode == .fine else { return }
            if Self.locationOnly { self.simMotion(p, speed: speed, at: at) }
            self.lastFixAt = at
            self.lastFix = (p, acc)
            self.lastSpeed = speed
            self.onEvent?(.location(p, accuracy: acc))
        }
    }

    /// -simWalk treats speed >= 0.5 m/s as walking, deriving speed from two fixes if absent; retain two/five/ten-minute stationary thresholds.
    private func simMotion(_ p: GeoPoint, speed: Double, at: Date) {
        var v = speed
        if v < 0, let (q, t) = simLast, at.timeIntervalSince(t) > 0.5 {
            v = LocalProjection(origin: q).toLocal(p).length / at.timeIntervalSince(t)
        }
        simLast = (p, at)
        let walking = v >= 0.5
        watchStill(!walking)
        if walking {
            if !moving { movingSince = at }
            moving = true
            onEvent?(.walking(true))
        } else if moving {
            moving = false
            onEvent?(.walking(false))
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
