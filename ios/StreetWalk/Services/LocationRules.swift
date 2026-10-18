import Foundation

// Pure departure/return rules: actions after background wake, wait durations, and valid departure distances.
// Also maintains the latest 50 on-device events for Location History.

/// System wake reason passed from LocationMonitor to AppStore.
enum LocationTrigger: Equatable {
    /// Exit from the monitored 100-m home region.
    case leftHome
    /// Entry into the 100-m home region.
    case arrivedHome
    /// System visit departure; fromHome is its distance from home, or nil if unknown.
    case visitDeparture(fromHome: Double?)
    /// System visit arrival.
    case visitArrival(fromHome: Double?)
    /// Significant movement, approximately 500 m or more.
    case significantChange(fromHome: Double?)
}

enum TriggerResponse: Equatable {
    /// Enable location/motion and wait for walking; LiveWalkGate decides when recording begins.
    case watch
    /// Finish recording after returning home.
    case finish
    /// When not recording, backfill background walking from Core Motion history.
    case catchUp
    case none
}

/// Background wake available to backend refresh/outing updates; see LocationMonitor.onWake.
enum LocationWake: String {
    case leftHome, arrivedHome, visit, significantChange, launch
}

extension Notification.Name {
    /// Background location wake notification carries reason: LocationWake.rawValue and background: Bool.
    static let streetWalkLocationWake = Notification.Name("StreetWalkLocationWake")
}

enum TriggerRules {
    /// Home-region radius; approximately 100 m is the recommended minimum for stable monitoring.
    static let homeRadius = 100.0
    /// Treat visits within 150 m of home as home visits.
    static let nearHome = 150.0
    /// After significant movement, wait for walking only within 1.5 km of home; farther travel is often vehicular.
    static let watchRange = 1500.0
    /// After wake, stop waiting after five minutes without walking, or fifteen minutes when walking but recording cannot start.
    static let watchFor: TimeInterval = 5 * 60
    static let watchMax: TimeInterval = 15 * 60
    /// After ending a walk while still outside, retain coarse updates for up to two hours to detect another walk.
    static let awayFor: TimeInterval = 2 * 3600
    /// After home-region departure without vehicle travel, allow a new walk within 2.5 km for three hours, accommodating delayed region events.
    static let relaxedStart = 2500.0
    static let relaxedFor: TimeInterval = 3 * 3600

    /// enabled means real-device tracking is active after onboarding and outside demo mode.
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

    /// Whether to keep waiting for walking; stop waiting once the walk recorder takes over.
    static func keepWatching(since: Date, now: Date, recording: Bool, moving: Bool) -> Bool {
        guard !recording else { return false }
        let t = now.timeIntervalSince(since)
        return t < watchFor || (moving && t < watchMax)
    }

    /// Maximum start distance expands from 400 m to 2.5 km after walking out from home without vehicle travel.
    static func maxStart(leftHomeAt: Date?, now: Date) -> Double {
        guard let l = leftHomeAt, now.timeIntervalSince(l) >= 0, now.timeIntervalSince(l) < relaxedFor else { return LiveWalkGate.maxStart }
        return relaxedStart
    }
}

/// One on-device Location History event.
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
    /// Whether the event occurred while backgrounded/locked.
    var background: Bool

    /// Title for the recent wake entry.
    var title: String {
        switch kind {
        case .leftHome: return L.t("離開屋企", "离开家")
        case .arrivedHome: return L.t("返到屋企", "回到家")
        case .visit: return L.t("到訪", "到访")
        case .significant: return L.t("大範圍移動", "大范围移动")
        case .launch: return L.t("系統喺背景開 App", "系统在后台打开 App")
        case .walkStart: return L.t("開始記錄散步", "开始记录散步")
        case .walkEnd: return L.t("散步記好", "散步已记录")
        case .backfill: return L.t("補記散步", "补记散步")
        case .monitor: return L.t("監察", "监测")
        case .permission: return L.t("權限", "权限")
        case .home: return L.t("屋企位置", "家的位置")
        case .night: return L.t("夜晚位置", "夜间位置")
        case .watch: return L.t("等開始行路", "等待开始走路")
        case .note: return L.t("備註", "备注")
        }
    }

    /// Only these event types appear in the recent wake section.
    var isWake: Bool { [.leftHome, .arrivedHome, .visit, .significant, .launch].contains(kind) }
}

/// Latest 50 events, newest last.
struct LocationLog: Codable, Equatable {
    static let cap = 50
    var events: [LocationEvent] = []

    mutating func add(_ e: LocationEvent) {
        events.append(e)
        if events.count > Self.cap { events.removeFirst(events.count - Self.cap) }
    }

    /// Events for a Hong Kong calendar day.
    func events(on day: Date, calendar: Calendar) -> [LocationEvent] {
        events.filter { calendar.isDate($0.at, inSameDayAs: day) }
    }
}
