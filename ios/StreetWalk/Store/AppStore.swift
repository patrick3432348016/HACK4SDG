import SwiftUI
import UIKit

/// 成员 A：应用状态和全部流程。B 侧能力（AI、语音、碰一碰）通过 Contracts 里的协议调用。
@MainActor
@Observable
final class AppStore: NeighborRegistry {
    enum Phase: Equatable { case onboarding(Step), main }
    enum Step: Int { case consent, locate, pickHome, floor, avatar }
    enum Tab: Hashable { case today, board, neighbors }
    enum BumpStage: Equatable { case idle, searching, found(String) }
    enum Selection: Equatable { case landmark(String), person(String) }

    // 服务
    @ObservationIgnored let ai: AIService = TemplateAI()
    /// 碰一碰：演示模式用模拟（碰到示範街坊），关咗演示模式用真机超宽带。选边个见 AppStore+Bump 嘅 bump。
    @ObservationIgnored let simulatedBump = SimulatedBumpService()
    @ObservationIgnored let nearbyBump = NearbyBumpService()
    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored let listener = Listener()
    @ObservationIgnored let mapService = MapService()
    @ObservationIgnored let scene = DioramaController()
    @ObservationIgnored let community: CommunityService
    @ObservationIgnored let hko = HKOWeatherService()
    @ObservationIgnored let walkDetector = WalkDetector()
    @ObservationIgnored var shade: ShadeService?
    @ObservationIgnored var ticker: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    // 流程内部状态（不触发界面刷新）
    /// 完整格子（560 m，首次使用选楼时用）。选好楼后场景只用以我屋企为中心的 300 m。
    @ObservationIgnored var fullMap: MapModel?
    @ObservationIgnored var findRoute: [Vec2]?
    @ObservationIgnored var partnerRoute: [Vec2]?
    @ObservationIgnored var findTravelled = 0.0
    @ObservationIgnored var partnerTravelled = 0.0
    @ObservationIgnored var findAppointment: UUID?
    @ObservationIgnored var askedSpeechAuth = false
    @ObservationIgnored var restoring = false
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var savedMapKey: String?
    @ObservationIgnored var savedNeighbors: [String: NeighborLink] = [:]
    /// 地标的原名（清除纪录时改回去）。
    @ObservationIgnored var originalLandmarkNames: [String: String] = [:]
    @ObservationIgnored var clockTask: Task<Void, Never>?

    // 状态
    var phase: Phase = .onboarding(.consent)
    var tab: Tab = .today
    var map: MapModel?
    var mapSource: MapService.Source = .fallback
    var loadingMap = false
    var landmarks: [Landmark] = []
    var residents: [Resident] = []
    var walk: WalkSession?
    var partnerAgreed = false
    var appointments: [Appointment] = [] { didSet { scheduleSave() } }
    var proposal: Proposal?
    var find: FindSession?
    var findFullScreen = false
    var banner: BannerItem?
    var voiceCard: VoiceCard?
    var listening = false
    var phrasePicker = false
    var bumpStage: BumpStage = .idle
    var remindPromptFor: String?
    var selection: Selection?
    var renaming: String?
    var reports: [Report] = [] { didSet { scheduleSave() } }
    /// 每日散步记录（键是香港日期）。今日分钟、连续天数都由它推算。
    var walkLog: [String: DayLog] = [:] { didSet { scheduleSave() } }
    var leaveDays: Set<String> = [] { didSet { scheduleSave() } }
    /// 改过的地标名（地标 id → 名），重新装载地图后要套回去。
    var landmarkNames: [String: String] = [:] { didSet { scheduleSave() } }
    var showSettings = false
    /// 录演示视频用的字幕（启动参数 -captions）：模拟器录屏录唔到声，用字幕讲清楚每一步。
    var caption: (zh: String, en: String)?
    var weather: Weather = .normal
    var weatherTip: String?
    var paceTip: String?
    var demoHour: Double?
    var showReport = false
    var showTimeSlider = false
    var toast: String?
    var pendingHome: Int64?
    var floorChoice = 12
    var mobilityChoice: Mobility = .walk
    var colorChoice = Palette.meIndex
    /// 我的外形：肤色档、年龄段（首次使用 / 设置里选；即时存盘）。
    var skinChoice = UserDefaults.standard.object(forKey: "skin") as? Int ?? 1 { didSet { UserDefaults.standard.set(skinChoice, forKey: "skin") } }
    var ageChoice = AgeGroup(rawValue: UserDefaults.standard.string(forKey: "age") ?? "") ?? .elder { didSet { UserDefaults.standard.set(ageChoice.rawValue, forKey: "age") } }

    /// 演示模式：圈里有示範街坊、右上有演示菜单。设置里可以关；启动参数 -demo 强制开。
    var demoMode = LaunchArgs.has("-demo") || UserDefaults.standard.object(forKey: "demoMode") as? Bool ?? true
    // 出门提醒：总开关 + 只在这个时段接收（F6）。
    var remindAll = UserDefaults.standard.object(forKey: "remindAll") as? Bool ?? true { didSet { UserDefaults.standard.set(remindAll, forKey: "remindAll") } }
    var remindFrom = UserDefaults.standard.object(forKey: "remindFrom") as? Int ?? 7 { didSet { UserDefaults.standard.set(remindFrom, forKey: "remindFrom") } }
    var remindTo = UserDefaults.standard.object(forKey: "remindTo") as? Int ?? 21 { didSet { UserDefaults.standard.set(remindTo, forKey: "remindTo") } }
    // 散步、数据与服务（A 线追加）
    /// 今次散步嘅附加状态：演示时钟、落脚点、步数。
    @ObservationIgnored var track = WalkTrack()
    /// 约会嘅本地通知（出发前提醒、过期）。
    @ObservationIgnored let notifier = Notifier()
    /// 前台时每分钟检查：太阳跟真实时间、过咗午夜刷新「今日」。
    @ObservationIgnored var dayClock: Task<Void, Never>?
    /// 喺设置「改我住嘅樓」入嚟嘅首次使用流程（可以「唔改」退返出去）。
    var changingHome = false

    // 语音与社交流程（A 线追加）
    /// 播报排队、读屏兼容、聆听时先收起（AppStore+Voice 的 say()）。
    @ObservationIgnored let announcer = Announcer()
    /// 按咪后等紧权限框：再撳唔会开两次。
    @ObservationIgnored var micStarting = false

    // 地图、场景与性能（A 线追加）
    /// 地图有状况时的一句说明（示例屋邨、示意楼、拿不到位置），选楼画面可以显示；见 AppStore+Map。
    var mapNotice: String?
    /// 第几次装地图：等网络时改用示例屋邨或重新选楼，旧的结果就不要。
    @ObservationIgnored var mapLoadGen = 0
    /// 碰一碰时两个人见面的位置（碰面期间固定）。
    @ObservationIgnored var bumpSpot: Vec2?

    // 合并时追加
    /// 改楼前嘅肤色、年纪（佢哋一改就存，「唔改」要还原）。
    @ObservationIgnored var lookBeforeChange: (skin: Int, age: AgeGroup)?

    // 真机碰一碰、二维码（2026-10-10 追加，流程见 AppStore+Bump）
    /// 碰一碰全屏画面显示嘅进度（距离、够近、配对中、失败原因）。
    var bumpProgress: BumpUpdate = .searching
    /// 改用二维码时嘅状态；nil = 碰一碰画面。
    var bumpQR: BumpQRState?
    /// 二维码配对 / 成功后交接嘅任务（取消时一齐停）。
    @ObservationIgnored var bumpTask: Task<Void, Never>?

    var me: Resident { residents.first { $0.isMe } ?? Resident(id: "me", name: "你", floor: floorChoice, colorIndex: colorChoice, mobility: mobilityChoice, streakDays: 9, todayLine: "", isMe: true) }
    var neighbors: [Resident] { residents.filter { $0.isNeighbor && !$0.isMe } }
    var outNeighbors: [Resident] { neighbors.filter(\.isOut) }
    var todayMinutes: Int { log(for: now).minutes }
    var ranking: [Resident] { residents.sorted { $0.streakDays != $1.streakDays ? $0.streakDays > $1.streakDays : $0.floor < $1.floor } }
    func resident(_ id: String) -> Resident? { residents.first { $0.id == id } }
    func landmark(_ id: String?) -> Landmark? { landmarks.first { $0.id == id } }

    var now: Date {
        guard let h = demoHour else { return Date() }
        return Self.today(at: h)
    }

    static func today(at hour: Double, dayOffset: Int = 0) -> Date {
        hk.startOfDay(for: Date()).addingTimeInterval(Double(dayOffset) * 86400 + hour * 3600)
    }

    /// 全部日期、钟点都按香港时间（约会、提醒、每日记录用同一个日历）。
    nonisolated static let hk: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = SolarPosition.hongKong; return c }()

    // MARK: - 启动

    init() {
        demoHour = LaunchArgs.hour
        let d = UserDefaults.standard
        community = LocalCommunityService(demoEnabled: LaunchArgs.has("-demo") || d.object(forKey: "demoMode") as? Bool ?? true)
        restoreSaved()
        community.onEvent = { [weak self] e in self?.receive(e) }
        community.resume(appointments)
        startClock()
        if LaunchArgs.has("-resetOnboarding") { ["onboarded", "homeBuilding", "homeTile", "floor", "mobility", "color"].forEach { d.removeObject(forKey: $0) } }
        if d.bool(forKey: "onboarded") || LaunchArgs.has("-skipOnboarding") {
            floorChoice = d.object(forKey: "floor") as? Int ?? 12
            mobilityChoice = Mobility(rawValue: d.string(forKey: "mobility") ?? "") ?? .walk
            colorChoice = d.object(forKey: "color") as? Int ?? Palette.meIndex
            phase = .main
            Task { await loadMap(home: (d.object(forKey: "homeBuilding") as? NSNumber)?.int64Value, animated: true) }
        }
        runOnboardingScriptIfNeeded()
    }

    // MARK: - 横幅与提示

    // 横幅、提示直接改值，唔好包 withAnimation（动画由 BannerView / ToastView 自己按值做）：
    // 同一刻仲有其他改动未刷新时，withAnimation 会令 SwiftUI 喺 willSet 嗰刻同步重画，读到旧值，
    // 之后呢次改动就冇再通知（合并时用日志实测：横幅已经设好但画面冇出，三次有两次）。
    func showBanner(_ b: BannerItem) {
        banner = b
        Haptics.warning()
        bannerTask?.cancel()
        bannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 30 : 8))   // 读屏开着：30 秒，留时间找按钮（A43）
            if !Task.isCancelled { self.banner = nil }
        }
    }

    func bannerAction() {
        guard let b = banner else { return }
        banner = nil
        switch b.action {
        case .invite(let id): proposeMeetup(with: id)
        case .goFind(let id): goFind(id)
        case .openNeighbors: tab = .neighbors
        case .depart(let id): if let a = appointments.first(where: { $0.id == id }), a.status == .accepted { departForAppointment(a) }
        case .call(let id): call(id)
        case .none: break
        }
    }

    func toast(_ s: String) {
        toast = s
        say(s)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if self.toast == s { self.toast = nil }
        }
    }

    // MARK: - 几何辅助

    func pathLength(_ p: [Vec2]) -> Double { zip(p, p.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }

    func point(along path: [Vec2], at dist: Double) -> (Vec2, Int) {
        guard path.count > 1 else { return (path.first ?? .zero, 0) }
        var rest = max(0, dist)
        for i in 0..<(path.count - 1) {
            let seg = path[i].distance(to: path[i + 1])
            if rest <= seg { return (path[i] + (path[i + 1] - path[i]) * (seg > 0 ? rest / seg : 0), i) }
            rest -= seg
        }
        return (path.last!, path.count - 2)
    }

    func prefix(of path: [Vec2], upTo dist: Double) -> [Vec2] {
        guard path.count > 1 else { return path }
        var out = [path[0]]
        var rest = dist
        for i in 0..<(path.count - 1) {
            let seg = path[i].distance(to: path[i + 1])
            if rest <= seg { out.append(path[i] + (path[i + 1] - path[i]) * (seg > 0 ? rest / seg : 0)); return out }
            out.append(path[i + 1])
            rest -= seg
        }
        return out
    }
}

extension TileCache {
    static func clear() { try? FileManager.default.removeItem(at: dir) }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}
