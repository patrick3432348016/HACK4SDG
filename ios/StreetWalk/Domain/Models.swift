import SwiftUI

/// 圈里的一个居民。非街坊只在排行榜出现（只显示网名、小人、连续日数），永远不进场景。
struct Resident: Identifiable, Equatable {
    let id: String
    var name: String            // 网名，例如"陳太"（真后端：profiles.nickname；示範街坊：示範名）
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
    var neighborSince: Date?
    /// 示範街坊：单机演示时由 LocalCommunityService 模拟的居民（界面要标明）。
    var isDemo = false
    /// 外形（规格 §4：不同肤色、年龄）。由 AppStore.applyLooks 填：示範街坊各一套，我用自己选的。
    var skinTone = 1
    var ageGroup: AgeGroup = .adult
    /// 上个月圈对圈赢了：头像加小奖牌（F4）。
    var hasMedal = false
    /// 我的网名（只用喺「我」嗰行；其他人嘅网名就系 name）。
    var nickname: String? = nil

    /// 楼层：0 = 唔知（非街坊睇唔到楼层）。
    var floorLabel: String { floor > 0 ? L.t("\(floor) 樓", "\(floor) 楼") : "" }
    /// 座名只留中文部分（"皇滙樓 Wong Wui House" → "皇滙樓"）；没有名就不显示。
    var blockShort: String? {
        guard let b = blockName?.split(separator: " ").first.map(String.init), !b.isEmpty else { return nil }
        return b
    }
    /// 座数 + 楼层（例如「皇滙樓 8 樓」）；冇就空。
    var placeLabel: String { [blockShort, floor > 0 ? floorLabel : nil].compactMap { $0 }.joined(separator: " ") }
    /// 排行榜（2026-10-10 定）：人人都系网名；街坊先加座数楼层（地址私隐：非街坊永远唔出座数楼层）。
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

/// 年龄段（卡通形象用）：長者白头发，後生身形小一点。
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

/// 人物配色：色弱（红 / 绿 / 蓝色盲模拟）下两两色差 ΔE2000 ≥ 12，
/// 对浅色、深色地面对比度都 ≥ 2.2（ios/tools/cvd_check.py 计算）。「我」固定橙色。
enum Palette {
    static let people: [UIColor] = [
        UIColor(red: 0.322, green: 0.678, blue: 0.639, alpha: 1),  // 青绿 #52ADA3
        UIColor(red: 0.624, green: 0.518, blue: 0.976, alpha: 1),  // 浅紫 #9F84F9
        UIColor(red: 0.243, green: 0.467, blue: 0.678, alpha: 1),  // 蓝 #3E77AD
        UIColor(red: 0.698, green: 0.173, blue: 0.494, alpha: 1),  // 紫红 #B22C7E
        UIColor(red: 0.894, green: 0.596, blue: 0.000, alpha: 1),  // 黄 #E49800
        UIColor(red: 0.522, green: 0.478, blue: 0.451, alpha: 1),  // 灰 #857A73
        UIColor(red: 0.847, green: 0.353, blue: 0.188, alpha: 1),  // 橙（我）#D85A30
    ]
    static let meIndex = 6
    private static var names: [String] { L.isCmn ? ["青绿色", "浅紫色", "蓝色", "紫红色", "黄色", "灰色", "橙色"] : ["青綠色", "淺紫色", "藍色", "紫紅色", "黃色", "灰色", "橙色"] }
    static func personUI(_ i: Int) -> UIColor { people[wrap(i)] }
    static func person(_ i: Int) -> Color { Color(personUI(i)) }
    /// 读屏用的颜色名（设置页、首次使用同一套）。
    static func name(_ i: Int) -> String { names[wrap(i)] }
    private static func wrap(_ i: Int) -> Int { ((i % people.count) + people.count) % people.count }

    /// 肤色四档（浅 → 深），卡通化、低饱和，配纸雕画风。
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
    /// 头发：長者白、其他深啡。
    static func hairUI(_ age: AgeGroup) -> UIColor {
        age == .elder ? UIColor(white: 0.93, alpha: 1) : UIColor(red: 0.20, green: 0.15, blue: 0.13, alpha: 1)
    }
}

struct Appointment: Identifiable, Equatable, Codable {
    /// 规格 §7：待确认 / 已接受 / 已完成 / 已取消；另加「過咗期」（约定时间过了一个钟都冇碰头）。
    enum Status: String, Equatable, Codable { case waiting, accepted, done, cancelled, expired }
    var id = UUID()
    var partnerID: String
    var date: Date
    var landmarkID: String
    var reason: String
    var status: Status
    var fromPartner = false
    /// 已经提醒过"半個鐘後出發"。
    var reminded = false
    /// F8：已经问过"過咗 10 分鐘，要唔要打電話"（可选值：旧存档没有这个字段也读得回）。
    var lateAsked: Bool?

    /// 仲有效（未完成、未取消、未過期）。
    var isOpen: Bool { status == .waiting || status == .accepted }
}

/// 约人卡：几个候选（时间 + 地点 + 理由），editing 有值时是在改已有的约会。
struct Proposal: Equatable {
    var partnerID: String
    var options: [MeetProposal]
    var index: Int
    var editing: UUID? = nil
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
    /// 每次找人一个记号：延时回覆认返係边一次，旧回覆唔会落到新一次（A22）。
    var token = UUID()
    /// 约会找人：对方出咗门未（收到 CommunityService 通知先算）。临时找人对方已经喺地标等。
    var partnerOut = true
    /// 底栏主按钮讲到边一步：0 未讲、1 讲咗「出發喇」（被搵嗰边：「我喺度等你」）、2 讲咗「我就到」。见 AppStore.findStep。
    var told = 0

    // 「查找」式找人（真街坊，2026-10-11）：两部手机经私有频道临时共享即时位置，见 AppStore+LiveFind。
    /// 真街坊：用即时位置（唔係模拟路线）。
    var live = false
    /// 我係被搵嗰个（对方问「過嚟搵你」我答咗好）。
    var incoming = false
    /// 远（GPS + 指南针）/ 近（超宽带）/ 等紧对方位置。
    var liveMode: LiveFindMath.Mode = .waiting
    /// 箭咀用紧超宽带方向（精确）。
    var precise = false
    /// 指南针唔准：叫用户将手机放平。
    var headingPoor = false
    /// 箭咀差唔多向前（转绿）。
    var facing = false
    /// 镜头辅助未收敛：叫用户慢慢左右移动手机。
    var sweep = false
    /// 对方位置暂时收唔到（旧过 30 秒）。
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
    /// 显示用（rawValue 係存档 / 后端用，唔好改）。
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
    /// F10：屋邨管理 / 社工落实后的回覆，会告诉反映的居民。
    var followUp: String?
    /// 回覆是演示模拟的（可选值：旧存档没有这个字段也读得回）。
    var followUpDemo: Bool?
    /// 规格 §7：语音反映的原话（只在汇总前给 AI 分类，不对外）；撳掣反映没有。
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

/// 听完一句话后的复述卡。
struct VoiceCard: Identifiable, Equatable {
    let id = UUID()
    var heard: String
    var title: String
    var detail: String?
    var needsConfirm: Bool
    var intent: VoiceIntent
    /// 改约 / 取消约时复述的是边一个约会（按「好」就改呢个，唔再重新揀）。
    var appointmentID: UUID? = nil
    /// 语音反映记低咗边一条（「撤回」就撤呢条，唔会撤错）。
    var reportID: UUID? = nil
    /// 组员 B 语音助手（Mac 服务器）嘅一步：揀人 / 揀地点 / 补资料 / 复述确认 / 结果。nil = 手机模板嘅卡。见 Store/AppStore+Assistant.swift。
    var assistant: AssistantCard? = nil
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

/// 月报用的匿名汇总（后端按全邨数据算；单机演示时由示範数据推算）。
struct MonthlyStats: Equatable {
    var walks: Int          // 散步人次
    var walkers: Int        // 有散步嘅人数
    var meetups: Int        // 街坊一齊行嘅次数
    var isDemo: Bool
}
