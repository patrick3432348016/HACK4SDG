import Foundation

// 出门 / 返屋企检测嘅纯逻辑（唔掂传感器，可单测）：系统喺背景叫醒 App 之后做乜、等几耐、几远都算出门；
// 同埋手机上嘅定位纪录（最近 50 件事，俾「定位紀錄」页睇）。

/// 系统叫醒 App 嘅原因（LocationMonitor → AppStore）。
enum LocationTrigger: Equatable {
    /// 离开屋企 100 m 范围（区域监察）。
    case leftHome
    /// 返到屋企 100 m 范围。
    case arrivedHome
    /// 系统「到访」：离开咗一个地方（fromHome：嗰个地方离屋企几远，唔知就 nil）。
    case visitDeparture(fromHome: Double?)
    /// 系统「到访」：到咗一个地方。
    case visitArrival(fromHome: Double?)
    /// 大范围移动（约 500 m 以上）。
    case significantChange(fromHome: Double?)
}

enum TriggerResponse: Equatable {
    /// 开定位同动作感应，等开始行路（LiveWalkGate 决定几时开始）。
    case watch
    /// 收尾：返到屋企。
    case finish
    /// 冇记录紧：用 Core Motion 步行纪录补记背景期间行过嘅路。
    case catchUp
    case none
}

/// 「其他功能」（后端刷新、出门状态）可以跟住做嘢嘅背景唤醒。见 LocationMonitor.onWake。
enum LocationWake: String {
    case leftHome, arrivedHome, visit, significantChange, launch
}

extension Notification.Name {
    /// 系统喺背景叫醒 App（定位事件）。userInfo: ["reason": LocationWake.rawValue, "background": Bool]
    static let streetWalkLocationWake = Notification.Name("StreetWalkLocationWake")
}

enum TriggerRules {
    /// 屋企区域半径（系统建议最少约 100 m 先稳定）。
    static let homeRadius = 100.0
    /// 到访喺屋企 150 m 内当係屋企。
    static let nearHome = 150.0
    /// 大范围移动：离屋企 1.5 km 内先开定位等吓（再远多数係坐车）。
    static let watchRange = 1500.0
    /// 叫醒之后等开始行路：冇行路 5 分钟收工；行紧路但未开始（定位差、喺屋企附近行），最多等 15 分钟。
    static let watchFor: TimeInterval = 5 * 60
    static let watchMax: TimeInterval = 15 * 60
    /// 喺外面停低咗（散步收咗尾但未返屋企）：保持粗略定位最多 2 个钟，再行路就再记一次。
    static let awayFor: TimeInterval = 2 * 3600
    /// 由屋企行出去（区域监察报离开、之后冇坐车）：3 个钟内 2.5 km 内都算出门（区域离开可能迟报几分钟）。
    static let relaxedStart = 2500.0
    static let relaxedFor: TimeInterval = 3 * 3600

    /// enabled：真机散步检测开咗（唔係演示模式、完成咗首次使用）。
    static func response(to t: LocationTrigger, recording: Bool, enabled: Bool) -> TriggerResponse {
        guard enabled else { return .none }
        switch t {
        case .leftHome:
            return recording ? .none : .watch
        case .visitDeparture(let d):
            return !recording && (d ?? .infinity) <= nearHome ? .watch : .none
        case .arrivedHome:
            return recording ? .finish : .catchUp
        case .visitArrival(let d):
            guard (d ?? .infinity) <= nearHome else { return .none }
            return recording ? .finish : .catchUp
        case .significantChange(let d):
            guard !recording, let d else { return .none }
            return d > nearHome && d <= watchRange ? .watch : .none
        }
    }

    /// 继续等开始行路？开始咗（交俾散步）就唔使等。
    static func keepWatching(since: Date, now: Date, recording: Bool, moving: Bool) -> Bool {
        guard !recording else { return false }
        let t = now.timeIntervalSince(since)
        return t < watchFor || (moving && t < watchMax)
    }

    /// 几远以内开始行路都算「出门散步」：由屋企行出去（未坐过车）放宽到 2.5 km，否则照旧 400 m。
    static func maxStart(leftHomeAt: Date?, now: Date) -> Double {
        guard let l = leftHomeAt, now.timeIntervalSince(l) >= 0, now.timeIntervalSince(l) < relaxedFor else { return LiveWalkGate.maxStart }
        return relaxedStart
    }
}

/// 「定位紀錄」页嘅一件事（只存喺手机）。
struct LocationEvent: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case leftHome, arrivedHome, visit, significant, launch
        case walkStart, walkEnd, backfill
        case monitor, permission, home, night, watch, note
    }

    var id = UUID()
    var at: Date
    var kind: Kind
    var detail: String
    /// 发生时 App 喺背景（锁咗机 / 冇打开）。
    var background: Bool

    /// 「最近喚醒」用嘅标题。
    var title: String {
        switch kind {
        case .leftHome: return "離開屋企"
        case .arrivedHome: return "返到屋企"
        case .visit: return "到訪"
        case .significant: return "大範圍移動"
        case .launch: return "系統喺背景開 App"
        case .walkStart: return "開始記錄散步"
        case .walkEnd: return "散步記好"
        case .backfill: return "補記散步"
        case .monitor: return "監察"
        case .permission: return "權限"
        case .home: return "屋企位置"
        case .night: return "夜晚位置"
        case .watch: return "等開始行路"
        case .note: return "備註"
        }
    }

    /// 系统叫醒 App 嘅事（「最近喚醒」一栏只列呢几种）。
    var isWake: Bool { [.leftHome, .arrivedHome, .visit, .significant, .launch].contains(kind) }
}

/// 最近 50 件事，新嘅排最后。
struct LocationLog: Codable, Equatable {
    static let cap = 50
    var events: [LocationEvent] = []

    mutating func add(_ e: LocationEvent) {
        events.append(e)
        if events.count > Self.cap { events.removeFirst(events.count - Self.cap) }
    }

    /// 某日（香港日历）嘅事。
    func events(on day: Date, calendar: Calendar) -> [LocationEvent] {
        events.filter { calendar.isDate($0.at, inSameDayAs: day) }
    }
}
