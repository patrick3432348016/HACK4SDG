import Foundation

// 移植自组员 B 嘅 UWB 原型（ios/UWBMeetDemo/Core/ProximityGate.swift，原檔唔郁）。
// 改动：门限、持续时间由 BumpTuning 统一定义；加 progress / hint 俾画面用。

/// 碰一碰嘅参数。全部【待真机实测】，改呢度就得。
enum BumpTuning {
    /// 几近先算「碰」（米）。规格 F5 写 ≤ 10 厘米【待定】；组员 B 原型用 0.30 米（未实测）。
    /// 超宽带喺 10 厘米左右误差大（几厘米到十几厘米，仲受手机方向、手掌遮挡影响），
    /// 定 10 厘米会令贴埋都成日判唔到，所以起步用 20 厘米，真机试完再收紧。
    static let nearDistance: Float = 0.20
    /// 要连续够近几耐（秒）：防止擦身而过就加咗街坊。B 原型 0.5 秒，改短少少等长者唔使拎太耐。
    static let dwell: TimeInterval = 0.4
    /// 两次读数相隔超过呢个（秒）就重新计时（B 原型嘅数）。
    static let maxGap: TimeInterval = 0.35
    /// 画面：远过呢个讲「靠近啲」，近过就讲「再近啲」。
    static let closerHint: Float = 0.5
    /// 进度环由几远开始填（米）。
    static let ringFrom: Float = 1.0
    /// 搵手机 + 靠近嘅总时限（秒）。
    static let searchTimeout: TimeInterval = 60
    /// 向后端配对：每 1.5 秒问一次，最多 20 秒（NeighborLinking.swift 嘅约定：每 1–2 秒）。
    static let linkInterval: TimeInterval = 1.5
    static let linkTimeout: TimeInterval = 20
    /// 二维码：后端嘅码 2 分钟内有效，出示方每 100 秒换一个新码。
    static let qrRotate: TimeInterval = 100

    /// 进度环 0–1：ringFrom 米 = 0，nearDistance 或者更近 = 1。
    static func progress(_ distance: Float?) -> Double {
        guard let d = distance, d.isFinite else { return 0 }
        let p = (ringFrom - d) / (ringFrom - nearDistance)
        return Double(min(max(p, 0), 1))
    }

    /// 大字提示。
    static func hint(_ distance: Float?) -> String {
        guard let d = distance, d.isFinite else { return L.t("量緊距離…", "正在测距离…") }
        if d <= nearDistance { return L.t("好！拎穩唔好郁", "好！拿稳别动") }
        if d <= closerHint { return L.t("再近啲", "再近一点") }
        return L.t("靠近啲", "靠近一点")
    }
}

/// 只有真实的超宽带读数会喂进来：连续 dwell 秒都 ≤ threshold 先触发，触发一次之后唔再触发。
/// 读数中断（nil、NaN、负数、相隔超过 maxGap）或者远咗都会重新计时。
struct ProximityGate {
    var threshold: Float
    var dwell: TimeInterval
    var maxGap: TimeInterval
    private(set) var triggered = false
    private var began: TimeInterval?
    private var previous: TimeInterval?

    init(threshold: Float = BumpTuning.nearDistance, dwell: TimeInterval = BumpTuning.dwell, maxGap: TimeInterval = BumpTuning.maxGap) {
        self.threshold = threshold
        self.dwell = dwell
        self.maxGap = maxGap
    }

    mutating func update(distance: Float?, at now: TimeInterval) -> Bool {
        guard !triggered else { return false }
        guard let distance, distance.isFinite, distance >= 0, distance <= threshold else {
            began = nil
            previous = nil
            return false
        }
        if let previous, now < previous || now - previous > maxGap { began = nil }
        if began == nil { began = now }
        previous = now
        if let began, now - began >= dwell {
            triggered = true
            return true
        }
        return false
    }

    mutating func reset() { self = ProximityGate(threshold: threshold, dwell: dwell, maxGap: maxGap) }
}

/// 两边都够近先可以交一次性码（改编自组员 B 嘅 ExchangeState：对方话够近唔可以代替本机自己量到）。
/// 产品定咗：撳「碰一碰」+ 贴埋就係同意，冇确认卡、冇交换联络方式，所以只留「两边够近」同「取消」。
struct BumpAgreement {
    private(set) var localNear = false
    private(set) var peerNear = false
    private(set) var code: String?
    private(set) var cancelled = false

    var bothNear: Bool { localNear && peerNear && !cancelled }
    mutating func markLocalNear() { if !cancelled { localNear = true } }
    mutating func markPeerNear() { if !cancelled { peerNear = true } }
    /// 收 / 定一次性码：两边都够近、未有码先得。
    mutating func accept(code: String) -> Bool {
        guard bothNear, self.code == nil, PairCode.isValid(code) else { return false }
        self.code = code
        return true
    }
    mutating func cancel() { cancelled = true }
}
