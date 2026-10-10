import Foundation

/// 灵动岛嘅状态：散步、找人、约会快到。
/// App 入面岛两侧（IslandCompact）同真·灵动岛 / 锁屏嘅实时活动（StreetWalkWidgets）用同一份：
/// 呢个文件喺 ios/Shared/，两个目标都编译，所以只放纯数据同纯逻辑，唔好引用 App 入面嘅类型。
struct IslandStatus: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case walk, find, meet

        /// 优先次序：找人（跟住箭咀行）> 约会快到（要出发）> 散步（一直喺度）。
        var priority: Int {
            switch self {
            case .find: return 0
            case .meet: return 1
            case .walk: return 2
            }
        }
    }

    var kind: Kind
    /// 散步：行咗几多分钟；约会：仲有几多分钟（0 = 够钟）；找人：大约几耐到。
    var minutes: Int
    /// 找人：相距几多米（已经取整，见 roundMeters）。
    var meters: Int?
    /// 找人：箭咀方向（度，0 = 向上，同找人画面一致）。
    var bearing: Double?
    /// 找人、约会：对方个名。
    var name: String?
    /// 找人、约会：地标名。
    var place: String?
    /// 约会：约定时间（真实时钟），实时活动自己倒数，App 喺背景都唔会停喺旧数字。演示拨过时间就冇。
    var target: Date?
    /// 散步：经过咗几多个地方。
    var places: Int?
    /// 示範数据（示範街坊、演示散步）：锁屏标「示範」。
    var demo = false
    /// 散步完咗：实时活动最后一版（锁屏显示「行咗 N 分鐘」一阵先收）。
    var finished = false
}

extension IslandStatus {
    /// 约会提前几耐开始显示（分钟）。
    static let meetLead = 30
    /// 过咗约定时间几耐仍然显示「夠鐘喇」（之后由迟到询问接手）。
    static let meetGrace = 10

    /// 约会仲有几多分钟（向上取整：14 分 20 秒 = 15 分鐘後）；唔喺显示范围（30 分钟前到过咗 10 分钟）就 nil。
    static func meetMinutes(left: TimeInterval) -> Int? {
        guard left <= Double(meetLead * 60), left > -Double(meetGrace * 60) else { return nil }
        return max(0, Int((left / 60).rounded(.up)))
    }

    /// 距离取整，数字唔会每一步都跳：100 米内按 5 米，1 公里内按 10 米，再远按 100 米。
    static func roundMeters(_ d: Double) -> Int {
        let d = max(0, d)
        if d < 100 { return Int((d / 5).rounded()) * 5 }
        if d < 1000 { return Int((d / 10).rounded()) * 10 }
        return Int((d / 100).rounded()) * 100
    }

    static func metersText(_ m: Int) -> String {
        m >= 1000 ? String(format: "%.1f 公里", Double(m) / 1000) : "\(m) 米"
    }

    /// 同时有几样嘢：按优先次序排，同一类只留第一个。岛同实时活动只显示第一个。
    static func ordered(_ all: [IslandStatus]) -> [IslandStatus] {
        var seen = Set<Kind>()
        return all.enumerated()
            .sorted { $0.element.kind.priority != $1.element.kind.priority ? $0.element.kind.priority < $1.element.kind.priority : $0.offset < $1.offset }
            .map(\.element)
            .filter { seen.insert($0.kind).inserted }
    }

    /// SF Symbol：散步小人、找人箭咀（按 bearing 转）、约会时钟。
    var symbol: String {
        switch kind {
        case .walk: return finished ? "checkmark.circle.fill" : "figure.walk"
        case .find: return "location.north.fill"
        case .meet: return "clock.fill"
        }
    }

    /// 岛右边嘅短字：「12 分」「35 米」「15 分鐘後」。
    var short: String {
        switch kind {
        case .walk: return "\(minutes) 分"
        case .find: return meters.map(Self.metersText) ?? "\(max(1, minutes)) 分"
        case .meet: return minutes > 0 ? "\(minutes) 分鐘後" : "夠鐘喇"
        }
    }

    /// 真·灵动岛右边位好窄：约会只出「15 分」（左边已经有时钟）。
    var compact: String {
        switch kind {
        case .meet: return minutes > 0 ? "\(minutes) 分" : "夠鐘"
        default: return short
        }
    }

    /// 一句讲晒（锁屏大字、展开嘅岛）。
    var title: String {
        switch kind {
        case .walk: return finished ? "散步完成" : "行緊 \(minutes) 分鐘"
        case .find: return "搵緊\(name ?? "街坊")"
        case .meet:
            let who = name ?? "街坊"
            return minutes > 0 ? "\(minutes) 分鐘後約咗\(who)" : "夠鐘見\(who)喇"
        }
    }

    /// 找人：「喺涼亭 · 大約 2 分鐘到」（锁屏、展开嘅岛第二行用；detail 已经有距离）。
    var findLine: String {
        let at = place.map { "喺\($0)" }
        let eta = minutes > 0 ? "大約 \(minutes) 分鐘到" : "就到喇"
        return [at, eta].compactMap { $0 }.joined(separator: " · ")
    }

    /// 第二行。
    var detail: String {
        switch kind {
        case .walk:
            let n = places ?? 0
            if finished { return "今次行咗 \(minutes) 分鐘" + (n > 0 ? "，經過 \(n) 個地方" : "") }
            return n > 0 ? "經過咗 \(n) 個地方" : "出咗門，自動記錄緊"
        case .find:
            let at = place.map { "喺\($0)" } ?? ""
            let far = meters.map { "相距 \(Self.metersText($0))" } ?? ""
            return [at, far].filter { !$0.isEmpty }.joined(separator: " · ")
        case .meet:
            return place.map { "喺\($0)見" } ?? "準備出發"
        }
    }

    /// 读屏：一句讲晒。
    var spoken: String {
        switch kind {
        case .walk: return finished ? "散步完成，行咗 \(minutes) 分鐘" : "行緊 \(minutes) 分鐘"
        case .find: return "搵緊\(name ?? "街坊")，" + (meters.map { "相距 \(Self.metersText($0))" } ?? "")
        case .meet: return title + (place.map { "，喺\($0)" } ?? "")
        }
    }
}
