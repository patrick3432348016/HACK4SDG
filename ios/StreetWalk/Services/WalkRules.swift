import Foundation

// Pure walking logic without UI/sensors: stopping points, start/end gates, backfill, cadence drops, and leave dates.

/// F1 stop: stay at least two minutes within a 30-m radius; emit once per stay.
/// Demo movement is only 9 m per simulated minute, so use a smaller stop radius.
struct StopDetector {
    var minDwell: TimeInterval
    var radius: Double
    private var center: Vec2?
    private var sum = Vec2.zero
    private var count = 0
    private var since: Date?
    private var reported = false

    init(minDwell: TimeInterval = 120, radius: Double = 30) {
        self.minDwell = minDwell
        self.radius = radius
    }

    /// For a new fix, return the stop centre when minDwell is first reached, once per stay.
    mutating func add(_ p: Vec2, at t: Date) -> Vec2? {
        if let c = center, c.distance(to: p) <= radius {
            sum = sum + p
            count += 1
            center = sum * (1 / Double(count))
            return check(t)
        }
        center = p; sum = p; count = 1; since = t; reported = false
        return nil
    }

    /// No new fix, but Core Motion confirms the user remains stationary; GPS may stop emitting points while still.
    mutating func hold(at t: Date) -> Vec2? { center == nil ? nil : check(t) }

    private mutating func check(_ t: Date) -> Vec2? {
        guard !reported, let s = since, let c = center, t.timeIntervalSince(s) >= minDwell else { return nil }
        reported = true
        return c
    }
}

/// F1 device start/end decisions from location fixes.
/// C-1 feedback: the old <=30-m accuracy and error-adjusted 55-m departure rules missed departures in dense buildings with 30–45-m accuracy.
struct LiveWalkGate {
    static let homeRadius = 40.0     // Within 40 m of home counts as returned.
    static let leaveRadius = 50.0    // Require at least 50 m after accounting for error, giving 10-m hysteresis above the return threshold.
    static let maxStart = 400.0      // Do not start beyond 400 m under the ordinary gate; walking after a distant vehicle trip is not home departure.
    static let goodAcc = 45.0        // Start requires <=45-m accuracy; the former 30-m limit was too strict around dense buildings.
    static let trailAcc = 40.0       // Draw routes only with <=40-m accuracy; otherwise count time only.
    static let homeAcc = 50.0        // Relaxed return-home detection requires <=50-m accuracy.
    static let confirmGap: TimeInterval = 5   // Require two valid fixes at least five seconds apart to reject a single GPS jump.
    /// Suppress automatic restart for 90 seconds after ending, avoiding repeated start/end announcements near home.
    static let restartGap: TimeInterval = 90
    /// After manual end while outside, suppress restart until home, capped at three hours.
    static let userEndQuiet: TimeInterval = 3 * 3600

    /// 10-18: during the first two recording minutes, require actual entry within 40 m to finish, avoiding immediate GPS-jitter cancellation.
    static let settleTime: TimeInterval = 2 * 60

    enum Action: Equatable { case none, start, step, minutesOnly, finish }

    private(set) var pendingSince: Date?
    /// Time of the first recorded location fix, used by the new-walk grace period.
    private(set) var recordingSince: Date?
    /// A manual start at home must not end for being at home until the user has first left.
    var awaitingLeave = false
    /// Suppress automatic start until this time; untilHome allows earlier release on return.
    private(set) var quietUntil: Date?
    private(set) var quietUntilHome = false

    /// Relax return detection for poor indoor fixes: error-adjusted distance within 40 m, accuracy <=50 m, and raw distance <=100 m.
    static func isHome(fromHome d: Double, acc: Double) -> Bool {
        d < homeRadius || (acc <= homeAcc && d - acc < homeRadius && d < 100)
    }

    /// Error-adjusted distance from home is at least 50 m.
    static func isAway(fromHome d: Double, acc: Double) -> Bool { d - acc > leaveRadius }

    /// Suppress automatic start for an interval.
    mutating func quiet(until t: Date, untilHome: Bool = false) {
        quietUntil = t
        quietUntilHome = untilHome
        pendingSince = nil
    }

    /// moving comes from motion/speed; wheelchair mode treats non-stationary activity as movement.
    /// maxStart expands after delayed home-region departure; see TriggerRules.maxStart.
    mutating func decide(fromHome d: Double, acc: Double, at t: Date, recording: Bool, moving: Bool,
                         maxStart: Double = LiveWalkGate.maxStart) -> Action {
        if recording {
            pendingSince = nil
            if recordingSince == nil { recordingSince = t }
            let step: Action = acc <= Self.trailAcc ? .step : .minutesOnly
            if awaitingLeave {
                if Self.isAway(fromHome: d, acc: acc) { awaitingLeave = false }
                return step
            }
            if Self.isHome(fromHome: d, acc: acc) {
                if let s = recordingSince, t.timeIntervalSince(s) < Self.settleTime, d >= Self.homeRadius { return step }
                return .finish
            }
            return step
        }
        if let q = quietUntil {
            if t >= q || (quietUntilHome && Self.isHome(fromHome: d, acc: acc)) {
                quietUntil = nil
                quietUntilHome = false
            } else {
                pendingSince = nil
                return .none
            }
        }
        guard moving, acc <= Self.goodAcc, Self.isAway(fromHome: d, acc: acc), d < maxStart else { pendingSince = nil; return .none }
        guard let s = pendingSince else { pendingSince = t; return .none }
        guard t.timeIntervalSince(s) >= Self.confirmGap else { return .none }
        pendingSince = nil
        return .start
    }
}

/// 10-18 device feedback: derive walk minutes and stillness from actual movement evidence.
/// Previously automatic walks used the latest GPS timestamp, including stationary drift, while manual walks used wall-clock time.
/// Stillness required uninterrupted stationary motion; intermittent unknown classifications reset the timer and prevented ending after sitting.
/// Movement evidence: walking motion, a meaningful step increase, or displacement over 40 m from the GPS anchor rather than small drift.
struct WalkMotionClock {
    static let driftRadius = 40.0
    /// Movement within 90 seconds keeps elapsed minutes advancing.
    static let activeGrace: TimeInterval = 90
    /// Finish after five stationary minutes near home or ten outside.
    static let stillNearHome: TimeInterval = 5 * 60
    static let stillAway: TimeInterval = 10 * 60
    /// Require this step increase for movement evidence, excluding small phone shakes.
    static let stepNudge = 8
    /// Lower bound of one minute per 120 steps, conservatively below older residents' typical 90–110 steps/minute estimate.
    static let stepsPerMinute = 120

    let start: Date
    private(set) var lastMoveAt: Date
    /// Track whether any sensor signal arrived. Manual starts without permission/data use wall-clock time and do not auto-end.
    private(set) var signal = false
    private var anchor: Vec2?
    private var stepsAtMove = 0

    /// now is recording activation; start may be earlier from locked-screen walking. Treat activation as initial movement.
    init(start: Date, now: Date) {
        self.start = start
        lastMoveAt = max(start, now)
    }

    mutating func moved(at t: Date) {
        signal = true
        if t > lastMoveAt { lastMoveAt = t }
    }

    /// Cumulative steps for this walk.
    mutating func steps(_ n: Int, at t: Date) {
        signal = true
        if n - stepsAtMove >= Self.stepNudge { stepsAtMove = n; moved(at: t) }
    }

    /// Use fixes with <=40-m accuracy; count movement only beyond 40 m from the anchor to reject stationary drift.
    mutating func fix(_ p: Vec2, acc: Double, at t: Date) {
        signal = true
        guard acc <= LiveWalkGate.trailAcc else { return }
        guard let a = anchor else { anchor = p; return }
        if a.distance(to: p) > Self.driftRadius { anchor = p; moved(at: t) }
    }

    func stillFor(_ now: Date) -> TimeInterval { max(0, now.timeIntervalSince(lastMoveAt)) }
    func isActive(_ now: Date) -> Bool { stillFor(now) < Self.activeGrace }
    /// Walk end time is now while moving, otherwise the last movement time; exclude seated time.
    func endTime(_ now: Date) -> Date { isActive(now) ? now : lastMoveAt }
    func shouldFinish(_ now: Date, nearHome: Bool) -> Bool { stillFor(now) >= (nearHome ? Self.stillNearHome : Self.stillAway) }

    /// Minutes from start to end, with a step-derived lower bound capped by wall-clock duration.
    static func minutes(start: Date, end: Date, steps: Int?, now: Date) -> Int {
        var m = Int(max(0, end.timeIntervalSince(start)) / 60)
        if let s = steps, s > 0 { m = max(m, min(s / stepsPerMinute, Int(max(0, now.timeIntervalSince(start)) / 60))) }
        return m
    }
}

/// A05 background backfill uses motion history for walking intervals, minutes, and steps, without inventing landmarks.
enum WalkBackfill {
    struct Sample: Equatable {
        var start: Date
        var moving: Bool
    }
    static let minLength: TimeInterval = 5 * 60   // Ignore intervals shorter than five minutes, such as movement inside home.
    static let mergeGap: TimeInterval = 2 * 60    // Merge stops under two minutes, such as waiting at crossings.

    /// Continuous walking intervals; cap an unfinished final interval at end.
    static func segments(_ samples: [Sample], until end: Date, minLength: TimeInterval = minLength) -> [DateInterval] {
        var raw: [DateInterval] = []
        var open: Date?
        for s in samples.sorted(by: { $0.start < $1.start }) {
            if s.moving { if open == nil { open = s.start } }
            else if let o = open { raw.append(DateInterval(start: o, end: max(o, s.start))); open = nil }
        }
        if let o = open, o < end { raw.append(DateInterval(start: o, end: end)) }
        var merged: [DateInterval] = []
        for r in raw {
            if let last = merged.last, r.start.timeIntervalSince(last.end) < mergeGap {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, r.end))
            } else {
                merged.append(r)
            }
        }
        return merged.filter { $0.duration >= minLength }
    }

    /// Separate completed intervals for immediate backfill from a final ongoing/recently stopped interval within two minutes.
    /// Let live location take over the final interval using its original start; otherwise backfill after it stops (PendingWalk.interval).
    static func split(_ samples: [Sample], until end: Date) -> (done: [DateInterval], tail: PendingWalk?) {
        var segs = segments(samples, until: end, minLength: 0)
        let open = samples.max { $0.start < $1.start }?.moving == true
        var tail: PendingWalk?
        if let last = segs.last, last.end >= end.addingTimeInterval(-mergeGap) {
            tail = PendingWalk(start: last.start, end: open ? nil : last.end)
            segs.removeLast()
        }
        return (segs.filter { $0.duration >= minLength }, tail)
    }

    /// Wheelchair backfill requires medium/high confidence and excludes explicit stationary/vehicle/cycling/unknown states.
    static func isMoving(walking: Bool, running: Bool, stationary: Bool, automotive: Bool, cycling: Bool, unknown: Bool, seated: Bool) -> Bool {
        seated ? !stationary && !automotive && !cycling && !unknown : walking || running
    }
}

/// A pending final interval has end=nil while still walking at foreground entry.
struct PendingWalk: Equatable {
    var start: Date
    var end: Date?

    /// Without live takeover, backfill to the stop time; ignore intervals below five minutes.
    func interval(stoppedAt: Date) -> DateInterval? {
        let d = DateInterval(start: start, end: max(start, end ?? stoppedAt))
        return d.duration >= WalkBackfill.minLength ? d : nil
    }
}

/// F9: after ten walking minutes, cadence below 70% of the walk median for two minutes triggers one rest suggestion per walk.
struct CadenceWatch {
    static let warmUp: TimeInterval = 10 * 60
    static let sustain: TimeInterval = 2 * 60
    static let ratio = 0.7
    private var samples: [Double] = []
    private var lowSince: Date?
    private(set) var fired = false

    /// cadence is steps/second from CMPedometerData.currentCadence; true means suggest a rest now.
    mutating func add(_ cadence: Double, at t: Date, walkStart: Date) -> Bool {
        guard !fired, cadence > 0 else { return false }
        guard t.timeIntervalSince(walkStart) >= Self.warmUp, samples.count >= 5 else {
            samples.append(cadence)
            return false
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        guard cadence < median * Self.ratio else {
            lowSince = nil
            samples.append(cadence)   // Exclude the slowdown from the baseline.
            return false
        }
        let since = lowSince ?? t
        lowSince = since
        guard t.timeIntervalSince(since) >= Self.sustain else { return false }
        fired = true
        return true
    }
}

/// F4 leave parser supports tomorrow, durations, and next-week requests; default is one day today.
struct LeaveRequest: Hashable {
    var startOffset = 0     // Day offsets 0/1/2/3 mean today/tomorrow/two/three days ahead; next week starts next Monday.
    var days = 1

    static let maxDays = 14

    /// Use today's Hong Kong calendar date to resolve next week.
    static func parse(_ raw: String, today: Date = Date()) -> LeaveRequest {
        let t = raw.replacingOccurrences(of: " ", with: "")
        var r = LeaveRequest()
        if t.contains("大後日") || t.contains("大后天") { r.startOffset = 3 }
        else if t.contains("後日") || t.contains("后天") { r.startOffset = 2 }
        else if t.contains("聽日") || t.contains("明日") || t.contains("明天") { r.startOffset = 1 }
        else if ["下星期", "下個星期", "下禮拜", "下個禮拜", "下周", "下週", "下个星期", "下礼拜", "下个礼拜"].contains(where: t.contains) {
            let wd = AppStore.hk.component(.weekday, from: today)   // Calendar weekday values: Sunday=1, Monday=2.
            let k = (9 - wd) % 7
            r.startOffset = k == 0 ? 7 : k
        }
        // Prefer an explicit day count, then a week duration; next week alone specifies the start, not duration.
        if let m = t.range(of: "[0-9一二兩两三四五六七八九十]+[日天]", options: .regularExpression), let n = number(String(t[m].dropLast())) {
            r.days = n
        } else if ["兩個禮拜", "兩個星期", "兩星期", "两个礼拜", "两个星期", "两星期", "两周", "兩周", "兩週"].contains(where: t.contains) {
            r.days = 14
        } else if ["一個禮拜", "一個星期", "成個禮拜", "成個星期", "一星期", "一周", "一週", "一个礼拜", "一个星期", "整个星期", "整個星期", "整個禮拜"].contains(where: t.contains) {
            r.days = 7
        }
        r.days = max(1, min(maxDays, r.days))
        return r
    }

    /// Convert Arabic and Chinese number forms to integers.
    static func number(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let d: [Character: Int] = ["一": 1, "二": 2, "兩": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if s == "十" { return 10 }
        if s.hasPrefix("十"), let last = s.last { return 10 + (d[last] ?? 0) }
        if s.count == 2, s.last == "十", let first = s.first { return (d[first] ?? 0) * 10 }
        return s.count == 1 ? s.first.flatMap { d[$0] } : nil
    }
}
