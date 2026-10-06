import SwiftUI

/// 圈里的一个居民。非街坊只在排行榜出现（只显示楼层），永远不进场景。
struct Resident: Identifiable, Equatable {
    let id: String
    var name: String            // 例如"陳太"；只有成为街坊后才显示
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
    var homeLandmarkID: String?   // 常去的地方
    var sendRemind = true
    var receiveRemind = true
    var onLeave = false

    var floorLabel: String { "\(floor) 樓" }
    var listName: String { isMe ? "\(floor) 樓 · 你" : (isNeighbor ? "\(floor) 樓 \(name)" : "\(floor) 樓") }
    var color: Color { Palette.person(colorIndex) }
    var uiColor: UIColor { Palette.personUI(colorIndex) }
}

enum Palette {
    static let people: [UIColor] = [
        UIColor(red: 0.114, green: 0.620, blue: 0.459, alpha: 1),  // 绿
        UIColor(red: 0.498, green: 0.467, blue: 0.867, alpha: 1),  // 紫
        UIColor(red: 0.216, green: 0.541, blue: 0.867, alpha: 1),  // 蓝
        UIColor(red: 0.831, green: 0.325, blue: 0.494, alpha: 1),  // 粉
        UIColor(red: 0.729, green: 0.459, blue: 0.090, alpha: 1),  // 琥珀
        UIColor(red: 0.373, green: 0.369, blue: 0.353, alpha: 1),  // 灰
        UIColor(red: 0.847, green: 0.353, blue: 0.188, alpha: 1),  // 橙（我）
    ]
    static let meIndex = 6
    static func personUI(_ i: Int) -> UIColor { people[((i % people.count) + people.count) % people.count] }
    static func person(_ i: Int) -> Color { Color(personUI(i)) }
}

struct Appointment: Identifiable, Equatable {
    enum Status: Equatable { case waiting, accepted, done }
    let id = UUID()
    var partnerID: String
    var date: Date
    var landmarkID: String
    var reason: String
    var status: Status
    var fromPartner = false
}

/// 约会提议（AI 给的时间 + 地点 + 理由）。
struct MeetProposal: Equatable {
    var date: Date
    var landmarkID: String
    var reason: String
}

/// 找人：约好的当天，或散步中临时"過去搵佢"。
struct FindSession: Equatable {
    enum Stage: Equatable { case asking, going, near, met, declined }
    var partnerID: String
    var landmarkID: String
    var spontaneous: Bool
    var stage: Stage
    var distance: Double = 0
    var etaMinutes: Int = 0
    var bearing: Double = 0          // 相对屏幕上方的角度（度）
    var latePrompt = false
    var broadcast: String?
}

struct WalkSession: Equatable {
    var start: Date
    var minutes = 0
    var passed: [String] = []
    var route: [Vec2] = []
    var travelled = 0.0
}

enum ReportKind: String, CaseIterable, Identifiable {
    case sunny = "好曬", noSeat = "冇櫈", rough = "難行"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .noSeat: return "chair.lounge"
        case .rough: return "figure.walk.motion.trianglebadge.exclamationmark"
        }
    }
}

struct Report: Identifiable, Equatable {
    let id = UUID()
    var kind: ReportKind
    var pos: Vec2
    var landmarkID: String?
    var date: Date
}

struct BannerItem: Identifiable, Equatable {
    enum Action: Equatable { case invite(String), goFind(String), openNeighbors, none }
    let id = UUID()
    var symbol: String
    var text: String
    var action: Action = .none
    var actionTitle: String?
}

/// 听完一句话后的复述卡。
struct VoiceCard: Identifiable, Equatable {
    let id = UUID()
    var heard: String
    var title: String
    var detail: String?
    var needsConfirm: Bool
    var intent: VoiceIntent
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
