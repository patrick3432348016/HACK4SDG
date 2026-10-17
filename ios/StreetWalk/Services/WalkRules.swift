import Foundation

// 散步嘅纯逻辑（唔掂界面、唔掂传感器），方便单测：落脚点、真机开始 / 收尾、背景补记、步频下降、请假日子。

/// F1 落脚点：同一位置附近停留 ≥ 2 分钟、半径 ≤ 30 m。每段停留只报一次。
/// 演示散步每秒只行 9 m（= 每分钟 9 m，比真人慢好多），所以演示用细啲嘅半径。
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

    /// 新位置。啱啱停够 minDwell 时返回落脚点中心（每段一次）。
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

    /// 冇新定位点，但知道仲喺原地（Core Motion 话停低咗；企定唔郁时定位唔会再出新点）。
    mutating func hold(at t: Date) -> Vec2? { center == nil ? nil : check(t) }

    private mutating func check(_ t: Date) -> Vec2? {
        guard !reported, let s = since, let c = center, t.timeIntervalSince(s) >= minDwell else { return nil }
        reported = true
        return c
    }
}

/// F1 真机：按定位点判断几时开始、几时收尾。
/// 测试反馈 C-1：以前要精度 ≤30 m、扣埋误差离家 55 m 先开始，香港楼密精度成日 30–45 m，行到 100 m 都唔开始。
struct LiveWalkGate {
    static let homeRadius = 40.0     // 我屋企 40 m 内算返到屋企
    static let leaveRadius = 50.0    // 扣埋误差都离开 50 m 先算出门（大过返屋企阈值 10 m，唔会一开一收）
    static let maxStart = 400.0      // 400 m 外先开始唔算（喺别区落车行路唔係「出門」）
    static let goodAcc = 45.0        // 开始要精度 ≤45 m（以前 30 m：楼密嘅地方成日开唔到）
    static let trailAcc = 40.0       // 画轨迹要精度 ≤40 m（再差就只计时间）
    static let homeAcc = 50.0        // 放宽嘅返屋企判断只接受精度 ≤50 m
    static let confirmGap: TimeInterval = 5   // 要两个相隔 ≥5 秒嘅好点先开始（防定位跳一下）
    /// 收尾之后 90 秒内唔自动再开始（喺门口附近定位跳嚟跳去时唔会一开一收、讲过不停）。
    static let restartGap: TimeInterval = 90
    /// 自己撳「结束散步」而仲喺外面：返到屋企之前唔自动再开始（最多 3 个钟）。
    static let userEndQuiet: TimeInterval = 3 * 3600

    /// 10-18：啱啱开始记录 2 分钟内，只认真系入咗 40 m 先收尾（门口定位跳一跳唔会一开就收、讲「太短唔记录」）。
    static let settleTime: TimeInterval = 2 * 60

    enum Action: Equatable { case none, start, step, minutesOnly, finish }

    private(set) var pendingSince: Date?
    /// 今次记录第一个定位嘅时间（用嚟判断啱啱开始）。
    private(set) var recordingSince: Date?
    /// 自己撳「现在出去走走」时仲喺屋企：未行出屋企之前唔会因为「喺屋企」收尾。
    var awaitingLeave = false
    /// 呢个时间之前唔自动开始（untilHome：返到屋企就提早解除）。
    private(set) var quietUntil: Date?
    private(set) var quietUntilHome = false

    /// 精度差（屋企楼里）时放宽：扣掉误差仍在 40 m 内、精度唔差过 50 m、唔超过 100 m。
    static func isHome(fromHome d: Double, acc: Double) -> Bool {
        d < homeRadius || (acc <= homeAcc && d - acc < homeRadius && d < 100)
    }

    /// 扣埋误差都离开屋企 50 m（出门）。
    static func isAway(fromHome d: Double, acc: Double) -> Bool { d - acc > leaveRadius }

    /// 一段时间内唔自动开始。
    mutating func quiet(until t: Date, untilHome: Bool = false) {
        quietUntil = t
        quietUntilHome = untilHome
        pendingSince = nil
    }

    /// moving：而家行紧路（Core Motion，或者定位速度似行路；轮椅：唔係停低）。
    /// maxStart：几远以内开始都算出门（由屋企行出去、区域监察迟报时放宽，见 TriggerRules.maxStart）。
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

/// 10-18 真机测试：散步分钟同「停低咗」按真系郁过嘅时间计。
/// 以前自动开始嘅按最后一个定位计（坐低时 GPS 漂移照出新点，分钟一路加）、手动开始嘅按墙钟计；
/// 停低又靠 Core Motion 连续报「静止」2/5/10 分钟（坐低时佢成日夹住报「唔知」，计时一直被打断，坐 10 分钟都唔收尾）。
/// 郁过 = Core Motion 话行紧路、计步器步数加咗、或者定位离开上一个锚点超过 40 m（GPS 漂移唔算）。
struct WalkMotionClock {
    static let driftRadius = 40.0
    /// 90 秒内郁过：当仲行紧，分钟跟住钟走。
    static let activeGrace: TimeInterval = 90
    /// 停低几耐收尾：喺屋企附近 5 分钟、喺外面 10 分钟。
    static let stillNearHome: TimeInterval = 5 * 60
    static let stillAway: TimeInterval = 10 * 60
    /// 计步器每加咁多步当郁过一次（企定摇吓手机唔算）。
    static let stepNudge = 8
    /// 分钟下限：每 120 步当 1 分钟（长者慢行约 90–110 步 / 分钟，宁愿少计）。
    static let stepsPerMinute = 120

    let start: Date
    private(set) var lastMoveAt: Date
    /// 收过任何传感器讯号（定位、计步、Core Motion）。手动开始又乜都收唔到（冇权限）就按钟计、唔自动收尾。
    private(set) var signal = false
    private var anchor: Vec2?
    private var stepsAtMove = 0

    /// now：开始记录嗰刻（开始时间可能早过佢：锁屏时已经行紧）。开始嗰刻一定当郁紧。
    init(start: Date, now: Date) {
        self.start = start
        lastMoveAt = max(start, now)
    }

    mutating func moved(at t: Date) {
        signal = true
        if t > lastMoveAt { lastMoveAt = t }
    }

    /// 计步器：今次散步累计步数。
    mutating func steps(_ n: Int, at t: Date) {
        signal = true
        if n - stepsAtMove >= Self.stepNudge { stepsAtMove = n; moved(at: t) }
    }

    /// 新定位：精度 ≤40 m 先用；离开锚点 >40 m 先当郁过（坐低时定位喺几十米内跳嚟跳去唔算）。
    mutating func fix(_ p: Vec2, acc: Double, at t: Date) {
        signal = true
        guard acc <= LiveWalkGate.trailAcc else { return }
        guard let a = anchor else { anchor = p; return }
        if a.distance(to: p) > Self.driftRadius { anchor = p; moved(at: t) }
    }

    func stillFor(_ now: Date) -> TimeInterval { max(0, now.timeIntervalSince(lastMoveAt)) }
    func isActive(_ now: Date) -> Bool { stillFor(now) < Self.activeGrace }
    /// 今次散步计到几时：行紧就到而家，停低咗就到最后郁嗰刻（坐低嘅时间唔计）。
    func endTime(_ now: Date) -> Date { isActive(now) ? now : lastMoveAt }
    func shouldFinish(_ now: Date, nearHome: Bool) -> Bool { stillFor(now) >= (nearHome ? Self.stillNearHome : Self.stillAway) }

    /// 分钟：开始到 end；步数多过呢个时间嘅就用步数做下限（唔超过墙钟）。
    static func minutes(start: Date, end: Date, steps: Int?, now: Date) -> Int {
        var m = Int(max(0, end.timeIntervalSince(start)) / 60)
        if let s = steps, s > 0 { m = max(m, min(s / stepsPerMinute, Int(max(0, now.timeIntervalSince(start)) / 60))) }
        return m
    }
}

/// A05：App 喺背景 / 锁屏时冇定位，返前台用 Core Motion 嘅活动纪录补记行路时段（只有分钟、步数，冇地标）。
enum WalkBackfill {
    struct Sample: Equatable {
        var start: Date
        var moving: Bool
    }
    static let minLength: TimeInterval = 5 * 60   // 少过 5 分钟唔算（屋企入面行来行去）
    static let mergeGap: TimeInterval = 2 * 60    // 停低少过 2 分钟（等过马路）当同一次

    /// 连续「行路」嘅时段。最后一段如果仲未停，就到 end 为止。
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

    /// 分开：已经完咗嘅段（即刻补记）同最后一段（返前台时仲行紧、或者 2 分钟内啱啱停）。
    /// 最后一段交俾定位接手做真机散步（开始时间用佢嘅）；接唔到就等停低再补记（PendingWalk.interval）。
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

    /// 轮椅：iPhone 认唔到推轮椅，只信中高可信度、而且明确唔係停低 / 坐车 / 踩单车 / 唔知（手机拎喺手、放袋都可能报 unknown）。
    static func isMoving(walking: Bool, running: Bool, stationary: Bool, automotive: Bool, cycling: Bool, unknown: Bool, seated: Bool) -> Bool {
        seated ? !stationary && !automotive && !cycling && !unknown : walking || running
    }
}

/// 背景补记嘅最后一段：end = nil 即係返前台时仲行紧。
struct PendingWalk: Equatable {
    var start: Date
    var end: Date?

    /// 冇接到真机散步，按停低嘅时间补记；少过 5 分钟唔记。
    func interval(stoppedAt: Date) -> DateInterval? {
        let d = DateInterval(start: start, end: max(start, end ?? stoppedAt))
        return d.duration >= WalkBackfill.minLength ? d : nil
    }
}

/// F9 真机步频：行咗 10 分钟后，步频持续 2 分钟低过本次散步中位数七成，就提示休息（每次散步一次）。
struct CadenceWatch {
    static let warmUp: TimeInterval = 10 * 60
    static let sustain: TimeInterval = 2 * 60
    static let ratio = 0.7
    private var samples: [Double] = []
    private var lowSince: Date?
    private(set) var fired = false

    /// cadence：每秒步数（CMPedometerData.currentCadence）。返回 true = 而家要提示。
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
            samples.append(cadence)   // 慢落嚟嘅唔计入基线
            return false
        }
        let since = lowSince ?? t
        lowSince = since
        guard t.timeIntervalSince(since) >= Self.sustain else { return false }
        fired = true
        return true
    }
}

/// F4 请假日子：「聽日請假」「請三日假」「聽日起請一個禮拜」。冇讲就係今日一日。
struct LeaveRequest: Hashable {
    var startOffset = 0     // 0 今日、1 聽日、2 後日、3 大後日；「下星期」= 下個禮拜一
    var days = 1

    static let maxDays = 14

    /// today：按佢计「下星期」由边日开始（香港日历）。
    static func parse(_ raw: String, today: Date = Date()) -> LeaveRequest {
        let t = raw.replacingOccurrences(of: " ", with: "")
        var r = LeaveRequest()
        if t.contains("大後日") || t.contains("大后天") { r.startOffset = 3 }
        else if t.contains("後日") || t.contains("后天") { r.startOffset = 2 }
        else if t.contains("聽日") || t.contains("明日") || t.contains("明天") { r.startOffset = 1 }
        else if ["下星期", "下個星期", "下禮拜", "下個禮拜", "下周", "下週", "下个星期", "下礼拜", "下个礼拜"].contains(where: t.contains) {
            let wd = AppStore.hk.component(.weekday, from: today)   // 1 = 星期日、2 = 星期一
            let k = (9 - wd) % 7
            r.startOffset = k == 0 ? 7 : k
        }
        // 先睇明讲嘅「N 日」，再睇「一個禮拜」（「下星期」只係讲由几时开始）
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

    /// 「3」「三」「十四」「兩」→ 数字。
    static func number(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let d: [Character: Int] = ["一": 1, "二": 2, "兩": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if s == "十" { return 10 }
        if s.hasPrefix("十"), let last = s.last { return 10 + (d[last] ?? 0) }
        if s.count == 2, s.last == "十", let first = s.first { return (d[first] ?? 0) * 10 }
        return s.count == 1 ? s.first.flatMap { d[$0] } : nil
    }
}
