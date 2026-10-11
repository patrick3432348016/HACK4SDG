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
struct LiveWalkGate {
    static let homeRadius = 40.0     // 我屋企 40 m 内算返到屋企
    static let leaveRadius = 55.0    // 扣埋误差都离开 55 m 先算出门（大过返屋企阈值，唔会一开一收）
    static let maxStart = 400.0      // 400 m 外先开始唔算（喺别区落车行路唔係「出門」）
    static let goodAcc = 30.0        // 开始、画轨迹要精度 ≤30 m
    static let homeAcc = 50.0        // 放宽嘅返屋企判断只接受精度 ≤50 m
    static let confirmGap: TimeInterval = 5   // 要两个相隔 ≥5 秒嘅好点先开始（防定位跳一下）

    enum Action: Equatable { case none, start, step, minutesOnly, finish }

    private(set) var pendingSince: Date?

    /// 精度差（屋企楼里）时放宽：扣掉误差仍在 40 m 内、精度唔差过 50 m、唔超过 100 m。
    static func isHome(fromHome d: Double, acc: Double) -> Bool {
        d < homeRadius || (acc <= homeAcc && d - acc < homeRadius && d < 100)
    }

    /// moving：Core Motion 而家判断喺行路（轮椅：唔係停低）。
    /// maxStart：几远以内开始都算出门（由屋企行出去、区域监察迟报时放宽，见 TriggerRules.maxStart）。
    mutating func decide(fromHome d: Double, acc: Double, at t: Date, recording: Bool, moving: Bool,
                         maxStart: Double = LiveWalkGate.maxStart) -> Action {
        if recording {
            pendingSince = nil
            if Self.isHome(fromHome: d, acc: acc) { return .finish }
            return acc <= Self.goodAcc ? .step : .minutesOnly
        }
        guard moving, acc <= Self.goodAcc, d - acc > Self.leaveRadius, d < maxStart else { pendingSince = nil; return .none }
        guard let s = pendingSince else { pendingSince = t; return .none }
        guard t.timeIntervalSince(s) >= Self.confirmGap else { return .none }
        pendingSince = nil
        return .start
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
        } else if ["兩個禮拜", "兩個星期", "兩星期", "两个礼拜", "两个星期", "两星期", "两周"].contains(where: t.contains) {
            r.days = 14
        } else if ["一個禮拜", "一個星期", "成個禮拜", "成個星期", "一星期", "一周", "一週", "一个礼拜", "一个星期", "整个星期"].contains(where: t.contains) {
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
