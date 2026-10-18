import SwiftUI

/// A resident in the circle. Non-neighbors appear only on the board with nickname/avatar/streak, never in the scene.
struct Resident: Identifiable, Equatable {
    let id: String
    var name: String            // Nickname: profiles.nickname from the real backend or a clearly simulated demo name.
    var floor: Int
    var blockName: String?
    var colorIndex: Int
    var mobility: Mobility
    var streakDays: Int
    var todayLine: String
    var isMe = false
    var isNeighbor = false
    var isOut = false
    var atLandmarkID: String?
    var homeLandmarkID: String?   // Frequently visited places.
    var sendRemind = true
    var receiveRemind = true
    var onLeave = false
    var neighborSince: Date?
    /// A resident simulated by LocalCommunityService in demo mode; label it in the UI.
    var isDemo = false
    /// Appearance covers skin tone and age (specification §4). AppStore.applyLooks assigns demo appearances and the user's selected appearance.
    var skinTone = 1
    var ageGroup: AgeGroup = .adult
    /// Previous month's winning circle receives an avatar medal (F4).
    var hasMedal = false
    /// Current user's nickname for the self row; other residents use name.
    var nickname: String? = nil

    /// Floor 0 means unknown; non-neighbors cannot see the floor.
    var floorLabel: String { floor > 0 ? L.t("\(floor) 樓", "\(floor) 楼") : "" }
    /// Retain only the Chinese portion of a bilingual block name; omit an absent name.
    var blockShort: String? {
        guard let b = blockName?.split(separator: " ").first.map(String.init), !b.isEmpty else { return nil }
        return b
    }
    /// Block and floor label, or empty when unavailable.
    var placeLabel: String { [blockShort, floor > 0 ? floorLabel : nil].compactMap { $0 }.joined(separator: " ") }
    /// Board decision (2026-10-10): show nicknames for everyone; add block/floor only for neighbors.
    var listName: String {
        if isMe {
            let nick = nickname.flatMap { $0.isEmpty ? nil : $0 }
            return nick.map { "\($0) · 你" } ?? "你"
        }
        let place = placeLabel
        return isNeighbor && !place.isEmpty ? "\(name) · \(place)" : name
    }
    var color: Color { Palette.person(colorIndex) }
    var uiColor: UIColor { Palette.personUI(colorIndex) }
}

/// Avatar age group: white hair for older residents, smaller body for younger residents.
enum AgeGroup: String, Codable, CaseIterable {
    case elder, adult, young
    var label: String {
        switch self {
        case .elder: return L.t("長者", "长者")
        case .adult: return L.t("中年", "中年")
        case .young: return L.t("後生", "年轻人")
        }
    }
}

/// Avatar palette: pairwise Delta E 2000 >= 12 under simulated red/green/blue color-vision deficiencies.
/// Contrast >= 2.2 against light/dark ground, checked by ios/tools/cvd_check.py. Self always uses orange.
enum Palette {
    static let people: [UIColor] = [
        UIColor(red: 0.322, green: 0.678, blue: 0.639, alpha: 1),  // Teal #52ADA3.
        UIColor(red: 0.624, green: 0.518, blue: 0.976, alpha: 1),  // Light purple #9F84F9.
        UIColor(red: 0.243, green: 0.467, blue: 0.678, alpha: 1),  // Blue #3E77AD.
        UIColor(red: 0.698, green: 0.173, blue: 0.494, alpha: 1),  // Magenta #B22C7E.
        UIColor(red: 0.894, green: 0.596, blue: 0.000, alpha: 1),  // Yellow #E49800.
        UIColor(red: 0.522, green: 0.478, blue: 0.451, alpha: 1),  // Gray #857A73.
        UIColor(red: 0.847, green: 0.353, blue: 0.188, alpha: 1),  // Orange for self #D85A30.
    ]
    static let meIndex = 6
    private static var names: [String] { L.isCmn ? ["青绿色", "浅紫色", "蓝色", "紫红色", "黄色", "灰色", "橙色"] : ["青綠色", "淺紫色", "藍色", "紫紅色", "黃色", "灰色", "橙色"] }
    static func personUI(_ i: Int) -> UIColor { people[wrap(i)] }
    static func person(_ i: Int) -> Color { Color(personUI(i)) }
    /// Accessible color names shared by Settings and onboarding.
    static func name(_ i: Int) -> String { names[wrap(i)] }
    private static func wrap(_ i: Int) -> Int { ((i % people.count) + people.count) % people.count }

    /// Four muted, stylized skin tones from light to dark, matching the paper-art style.
    static let skins: [UIColor] = [
        UIColor(red: 0.980, green: 0.851, blue: 0.788, alpha: 1),  // #FAD9C9
        UIColor(red: 0.929, green: 0.741, blue: 0.620, alpha: 1),  // #EDBD9E
        UIColor(red: 0.776, green: 0.557, blue: 0.408, alpha: 1),  // #C68E68
        UIColor(red: 0.494, green: 0.329, blue: 0.231, alpha: 1),  // #7E543B
    ]
    private static var skinNames: [String] { L.isCmn ? ["浅肤色", "中浅肤色", "中深肤色", "深肤色"] : ["淺膚色", "中淺膚色", "中深膚色", "深膚色"] }
    static func skinName(_ i: Int) -> String { skinNames[min(max(i, 0), skinNames.count - 1)] }
    static func skinUI(_ i: Int) -> UIColor { skins[min(max(i, 0), skins.count - 1)] }
    static func skin(_ i: Int) -> Color { Color(skinUI(i)) }
    /// White hair for older residents; dark brown otherwise.
    static func hairUI(_ age: AgeGroup) -> UIColor {
        age == .elder ? UIColor(white: 0.93, alpha: 1) : UIColor(red: 0.20, green: 0.15, blue: 0.13, alpha: 1)
    }
}

struct Appointment: Identifiable, Equatable, Codable {
    /// Specification §7 states plus expired: no meeting within one hour of the agreed time.
    enum Status: String, Equatable, Codable { case waiting, accepted, done, cancelled, expired }
    var id = UUID()
    var partnerID: String
    var date: Date
    var landmarkID: String
    var reason: String
    var status: Status
    var fromPartner = false
    /// Whether the thirty-minute departure reminder has already been sent.
    var reminded = false
    /// F8: whether the ten-minute-late phone-call prompt was shown. Optional for compatibility with older saves.
    var lateAsked: Bool?

    /// Still active: neither completed, cancelled, nor expired.
    var isOpen: Bool { status == .waiting || status == .accepted }
}

/// Invitation choices contain time/place/reason; non-nil editing means modifying an existing meetup.
struct Proposal: Equatable {
    var partnerID: String
    var options: [MeetProposal]
    var index: Int
    var editing: UUID? = nil
}

/// Meetup proposal: suggested time, place, and reason.
struct MeetProposal: Equatable {
    var date: Date
    var landmarkID: String
    var reason: String
}

/// Finding for a scheduled meetup or an impromptu request during a walk.
struct FindSession: Equatable {
    enum Stage: Equatable { case asking, going, near, met, declined }
    var partnerID: String
    var landmarkID: String
    var spontaneous: Bool
    var stage: Stage
    var distance: Double = 0
    var etaMinutes: Int = 0
    var bearing: Double = 0          // Angle in degrees relative to the top of the screen.
    var latePrompt = false
    var broadcast: String?
    /// Unique finding-session marker prevents delayed replies from affecting a newer session (A22).
    var token = UUID()
    /// For scheduled finding, departure must come from CommunityService. For an impromptu request, the peer is already waiting at a landmark.
    var partnerOut = true
    /// Primary-action stage: 0 not announced; 1 departed/waiting; 2 nearly there. See AppStore.findStep.
    var told = 0

    // Real-neighbor finding (2026-10-11): phones temporarily share live location through a private channel; see AppStore+LiveFind.
    /// Real neighbors use live location rather than a simulated route.
    var live = false
    /// Whether I am the person who accepted an incoming finding request.
    var incoming = false
    /// Far GPS/compass, near UWB, or waiting for peer location.
    var liveMode: LiveFindMath.Mode = .waiting
    /// Arrow currently uses precise UWB direction.
    var precise = false
    /// Unreliable compass: ask the user to hold the phone flat.
    var headingPoor = false
    /// Arrow approximately straight ahead; show green.
    var facing = false
    /// Camera-assisted convergence incomplete: ask for gentle side-to-side phone movement.
    var sweep = false
    /// Peer location temporarily unavailable or older than 30 seconds.
    var partnerStale = false
}

struct WalkSession: Equatable {
    var start: Date
    var minutes = 0
    var passed: [String] = []
    var route: [Vec2] = []
    var travelled = 0.0
}

enum ReportKind: String, CaseIterable, Identifiable, Codable {
    case sunny = "好曬", noSeat = "冇櫈", rough = "難行"
    var id: String { rawValue }
    /// Display labels only; do not change rawValue used by persistence/backend.
    var label: String {
        switch self {
        case .sunny: return L.t("好曬", "太晒")
        case .noSeat: return L.t("冇櫈", "没凳子")
        case .rough: return L.t("難行", "难走")
        }
    }
    var symbol: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .noSeat: return "chair.lounge"
        case .rough: return "figure.walk.motion.trianglebadge.exclamationmark"
        }
    }
}

struct Report: Identifiable, Equatable, Codable {
    var id = UUID()
    var kind: ReportKind
    var pos: Vec2
    var landmarkID: String?
    var date: Date
    /// F10: estate-management/social-worker follow-up relayed to the reporting resident.
    var followUp: String?
    /// Whether the reply is simulated; optional for compatibility with older saves.
    var followUpDemo: Bool?
    /// Specification §7: original spoken report text, used for classification before aggregation and not public. Absent for button reports.
    var rawText: String?
}

struct BannerItem: Identifiable, Equatable {
    enum Action: Equatable { case invite(String), goFind(String), openNeighbors, depart(UUID), call(String), none }
    let id = UUID()
    var symbol: String
    var text: String
    var action: Action = .none
    var actionTitle: String?
}

/// Read-back card after an utterance.
struct VoiceCard: Identifiable, Equatable {
    let id = UUID()
    var heard: String
    var title: String
    var detail: String?
    var needsConfirm: Bool
    var intent: VoiceIntent
    /// Remember the exact meetup selected for rescheduling/cancellation; do not choose again on confirmation.
    var appointmentID: UUID? = nil
    /// Remember the report ID so Undo retracts the correct report.
    var reportID: UUID? = nil
    /// B's server-assistant step: person/place choice, clarification, confirmation, or result. nil means a local-template card; see AppStore+Assistant.swift.
    var assistant: AssistantCard? = nil
    /// Emergency card requires manual dismissal so it remains readable under stress or VoiceOver.
    var sticky = false
}

enum Weather: Equatable {
    case normal, hot, rain
}

struct MonthlyReport: Equatable {
    struct Item: Equatable, Identifiable {
        var id: String { place + kind.rawValue }
        var place: String
        var kind: ReportKind
        var count: Int
        var suggestion: String
    }
    var title: String
    var summary: String
    var items: [Item]
    var walkers: Int
    var meetups: Int
}

/// Anonymous monthly aggregates: backend estate-wide data, or explicitly simulated data in demo mode.
struct MonthlyStats: Equatable {
    var walks: Int          // Number of walks.
    var walkers: Int        // Number of people who walked.
    var meetups: Int        // Number of shared neighbor walks.
    var isDemo: Bool
}
