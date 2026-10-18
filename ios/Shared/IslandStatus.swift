import Foundation

/// Dynamic Island state: walking, finding someone, or an upcoming meetup.
/// Shared by the in-app IslandCompact and the real Dynamic Island / Lock Screen Live Activity (StreetWalkWidgets).
/// Compiled into both targets from ios/Shared/. Keep data and logic independent of app-specific types.
struct IslandStatus: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case walk, find, meet

        /// Priority: finding (follow the arrow) > upcoming meetup (time to leave) > walking (ongoing status).
        var priority: Int {
            switch self {
            case .find: return 0
            case .meet: return 1
            case .walk: return 2
            }
        }
    }

    var kind: Kind
    /// Walking: elapsed minutes; meetup: minutes remaining (0 means due); finding: estimated arrival time.
    var minutes: Int
    /// Finding: rounded distance in metres; see roundMeters.
    var meters: Int?
    /// Finding: arrow bearing in degrees; 0 points up, matching the finding screen.
    var bearing: Double?
    /// Finding/meetup: the other person's name.
    var name: String?
    /// Finding/meetup: landmark name.
    var place: String?
    /// Meetup: actual scheduled time, allowing Live Activity to count down while the app is backgrounded. Absent when demo time is shifted.
    var target: Date?
    /// Walking: number of places visited.
    var places: Int?
    /// Demo neighbors/walks: label the Lock Screen activity as a demo.
    var demo = false
    /// Completed walk: final Live Activity state, briefly showing the total minutes before dismissal.
    var finished = false
    /// Language is supplied when exporting to Live Activity: the widget runs separately and cannot read app settings. In-app nil follows L.lang.
    var lang: AppLang?

    /// Choose text using this state's language.
    func t(_ yue: String, _ cmn: String) -> String { (lang ?? L.lang) == .cmn ? cmn : yue }
}

extension IslandStatus {
    /// Minutes before a meetup when its status becomes visible.
    static let meetLead = 30
    /// How long to show the due status after the scheduled time, before the late-arrival prompt takes over.
    static let meetGrace = 10

    /// Minutes remaining, rounded up (14:20 becomes 15). Return nil outside the window from 30 minutes before to 10 minutes after.
    static func meetMinutes(left: TimeInterval) -> Int? {
        guard left <= Double(meetLead * 60), left > -Double(meetGrace * 60) else { return nil }
        return max(0, Int((left / 60).rounded(.up)))
    }

    /// Round distance to avoid changes at every step: 5 m below 100 m, 10 m below 1 km, then 100 m.
    static func roundMeters(_ d: Double) -> Int {
        let d = max(0, d)
        if d < 100 { return Int((d / 5).rounded()) * 5 }
        if d < 1000 { return Int((d / 10).rounded()) * 10 }
        return Int((d / 100).rounded()) * 100
    }

    static func metersText(_ m: Int) -> String {
        m >= 1000 ? String(format: "%.1f 公里", Double(m) / 1000) : "\(m) 米"   // Same text in Cantonese and Mandarin.
    }

    /// Sort simultaneous states by priority and keep only the first of each kind. Both islands display the highest-priority state.
    static func ordered(_ all: [IslandStatus]) -> [IslandStatus] {
        var seen = Set<Kind>()
        return all.enumerated()
            .sorted { $0.element.kind.priority != $1.element.kind.priority ? $0.element.kind.priority < $1.element.kind.priority : $0.offset < $1.offset }
            .map(\.element)
            .filter { seen.insert($0.kind).inserted }
    }

    /// SF Symbols: walking figure, finding arrow rotated by bearing, and meetup clock.
    var symbol: String {
        switch kind {
        case .walk: return finished ? "checkmark.circle.fill" : "figure.walk"
        case .find: return "location.north.fill"
        case .meet: return "clock.fill"
        }
    }

    /// Short trailing text: 12 minutes, 35 metres, or in 15 minutes.
    var short: String {
        switch kind {
        case .walk: return t("\(minutes) 分", "\(minutes) 分")
        case .find: return meters.map(Self.metersText) ?? "\(max(1, minutes)) 分"
        case .meet: return minutes > 0 ? t("\(minutes) 分鐘後", "\(minutes) 分钟后") : t("夠鐘喇", "到点了")
        }
    }

    /// The real Dynamic Island has little trailing space: show only 15 minutes; the clock icon is already on the left.
    var compact: String {
        switch kind {
        case .meet: return minutes > 0 ? "\(minutes) 分" : t("夠鐘", "到点")
        default: return short
        }
    }

    /// Single-sentence summary for large Lock Screen text and the expanded island.
    var title: String {
        switch kind {
        case .walk: return finished ? t("散步完成", "散步完成") : t("行緊 \(minutes) 分鐘", "已走 \(minutes) 分钟")
        case .find: return t("搵緊\(name ?? "街坊")", "正在找\(name ?? "邻居")")
        case .meet:
            let who = name ?? t("街坊", "邻居")
            return minutes > 0 ? t("\(minutes) 分鐘後約咗\(who)", "\(minutes) 分钟后约了\(who)") : t("夠鐘見\(who)喇", "该去见\(who)了")
        }
    }

    /// Finding subtitle: at the pavilion, about two minutes away. Used on the Lock Screen/expanded island; detail already contains distance.
    var findLine: String {
        let at = place.map { t("喺\($0)", "在\($0)") }
        let eta = minutes > 0 ? t("大約 \(minutes) 分鐘到", "大约 \(minutes) 分钟到") : t("就到喇", "马上到")
        return [at, eta].compactMap { $0 }.joined(separator: " · ")
    }

    /// Second line.
    var detail: String {
        switch kind {
        case .walk:
            let n = places ?? 0
            if finished { return t("今次行咗 \(minutes) 分鐘", "这次走了 \(minutes) 分钟") + (n > 0 ? t("，經過 \(n) 個地方", "，经过 \(n) 个地方") : "") }
            return n > 0 ? t("經過咗 \(n) 個地方", "经过了 \(n) 个地方") : t("出咗門，自動記錄緊", "已出门，正在自动记录")
        case .find:
            let at = place.map { t("喺\($0)", "在\($0)") } ?? ""
            let far = meters.map { t("相距 \(Self.metersText($0))", "相距 \(Self.metersText($0))") } ?? ""
            return [at, far].filter { !$0.isEmpty }.joined(separator: " · ")
        case .meet:
            return place.map { t("喺\($0)見", "在\($0)见") } ?? t("準備出發", "准备出发")
        }
    }

    /// VoiceOver: one complete sentence.
    var spoken: String {
        switch kind {
        case .walk: return finished ? t("散步完成，行咗 \(minutes) 分鐘", "散步完成，走了 \(minutes) 分钟") : t("行緊 \(minutes) 分鐘", "已走 \(minutes) 分钟")
        case .find: return t("搵緊\(name ?? "街坊")，", "正在找\(name ?? "邻居")，") + (meters.map { "相距 \(Self.metersText($0))" } ?? "")
        case .meet: return title + (place.map { t("，喺\($0)", "，在\($0)") } ?? "")
        }
    }
}
