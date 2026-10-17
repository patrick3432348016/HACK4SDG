import SwiftUI
import UIKit

/// 成员 A：应用状态和全部流程。B 侧能力（AI、语音、碰一碰）通过 Contracts 里的协议调用。
@MainActor
@Observable
final class AppStore: NeighborRegistry {
    enum Phase: Equatable { case onboarding(Step), main }
    /// 首次使用 5 步：欢迎、私隐、屋企（定位 + 揀樓）、樓層同網名、試一次撳咪。改楼（设定）只行屋企同樓層。
    enum Step: Int { case welcome, consent, locate, pickHome, floor, tryMic }
    enum Tab: Hashable { case today, board, neighbors }
    enum BumpStage: Equatable { case idle, searching, found(String) }
    /// home：撳「你屋企」名牌 / 屋企嗰座楼，出「你屋企」卡（住边座、几楼、改我住嘅楼）。
    enum Selection: Equatable { case landmark(String), person(String), home }

    // 服务
    @ObservationIgnored let ai: AIService = TemplateAI()
    /// 碰一碰：演示模式用模拟（碰到示範街坊），关咗演示模式用真机超宽带。选边个见 AppStore+Bump 嘅 bump。
    @ObservationIgnored let simulatedBump = SimulatedBumpService()
    @ObservationIgnored let nearbyBump = NearbyBumpService()
    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored let listener = Listener()
    @ObservationIgnored let mapService = MapService()
    @ObservationIgnored let scene = DioramaController()
    /// 演示模式：LocalCommunityService（示範街坊）；关咗：SupabaseCommunityService（真后端）。见 AppStore+Backend.installCommunity。
    @ObservationIgnored var community: CommunityService
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
    // 换页 / 换标签 / 开关设定：上一个画面讲紧嘅嘢即刻停（2026-10-12 用户：「切到画面上一个画面声音没有停一直播」）
    var phase: Phase = .onboarding(.consent) { didSet { if phase != oldValue { hush() } } }
    var tab: Tab = .today { didSet { if tab != oldValue { hush() } } }
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
    /// 连续对话中（B 嘅豆包识别，见 AppStore+Conversation）：listening 都系 true，但唔使每句撳。
    var conversing = false
    /// 连续对话：而家听到（未处理）嘅字。
    var heardPartial = ""
    @ObservationIgnored let ear = VoiceEar()
    @ObservationIgnored var earPending: [String] = []
    @ObservationIgnored var earFlush: Task<Void, Never>?
    @ObservationIgnored var earIdle: Task<Void, Never>?
    @ObservationIgnored var earFeed: Task<Void, Never>?
    @ObservationIgnored var lastEarActivity = Date()
    /// 最近讲过嘅句子（连续对话嘅回声保险）。
    @ObservationIgnored var recentSpoken: [(text: String, at: Date)] = []
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
    var showSettings = false { didSet { if showSettings != oldValue { hush() } } }
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
    /// 让邻居看到我住哪栋（10-18 测试：怕泄露私隐）。默认开，旧用户冇呢个键都当开；关咗上传嘅座数楼层留空。
    var shareHome = UserDefaults.standard.object(forKey: "shareHome") as? Bool ?? true { didSet { UserDefaults.standard.set(shareHome, forKey: "shareHome"); uploadProfile() } }
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

    // 真后端追加（AppStore+Backend）
    /// 网名（排行榜上同区嘅人见到；1–20 字）。即时存盘。
    var nickname = UserDefaults.standard.string(forKey: "nickname") ?? "" { didSet { UserDefaults.standard.set(nickname, forKey: "nickname") } }
    /// 组员 B 嘅语音助手（Mac 语音服务器，见 AppStore+Assistant）：对话、待查操作。
    @ObservationIgnored let assistant = AssistantSession()
    /// 而家等紧边一次助手请求（旧嘅答覆返嚟就唔理）。
    @ObservationIgnored var assistantGen = UUID()
    /// 撳咗「好」但未知结果嗰个动作（查到做好咗之后加约会用）。
    @ObservationIgnored var pendingAssistantAction: AssistantCard.Action?
    /// F8：街坊问「想過嚟搵你，方唔方便？」，等我撳「好 / 唔方便」。
    var incomingFind: IncomingFindAsk?

    // 「查找」式找人（AppStore+LiveFind）
    /// 同真街坊临时共享即时位置（找人期间先有；结束即刻停）。
    @ObservationIgnored var liveFind: LiveFindSession?
    /// 场景上次按边个对方定位画人（新定位先重画）。
    @ObservationIgnored var liveSceneStamp: Date?
    /// 第一次见到对方位置：镜头移去两人之间（只做一次）。
    @ObservationIgnored var liveCameraDone = false
    /// 找人见到咗面：而家同边个一齐行（「今日」页主角卡改讲「同XX一齊行緊」，唔再叫你過去搵佢）。行完 / 再找人就清。
    var walkingWith: String?

    // 首次使用之后（AppStore+FirstDay）
    /// 「今日三件事」任务卡嘅进度（nil = 冇任务卡，例如旧用户）。存档。
    var firstDay: FirstDayProgress? { didSet { scheduleSave() } }

    var me: Resident { residents.first { $0.isMe } ?? Resident(id: "me", name: L.t("你", "你", "You"), floor: floorChoice, colorIndex: colorChoice, mobility: mobilityChoice, streakDays: 9, todayLine: "", isMe: true, nickname: nickname) }
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
        installCommunity()
        community.resume(appointments)
        startClock()
        if LaunchArgs.has("-resetOnboarding") { ["onboarded", "homeBuilding", "homeTile", "floor", "mobility", "color"].forEach { d.removeObject(forKey: $0) } }
        if d.bool(forKey: "onboarded") || LaunchArgs.has("-skipOnboarding") {
            floorChoice = d.object(forKey: "floor") as? Int ?? 12
            mobilityChoice = Mobility(rawValue: d.string(forKey: "mobility") ?? "") ?? .walk
            colorChoice = d.object(forKey: "color") as? Int ?? Palette.meIndex
            phase = .main
            Task { await loadMap(home: (d.object(forKey: "homeBuilding") as? NSNumber)?.int64Value, animated: true) }
        } else {
            phase = .onboarding(.welcome)     // 首次使用由欢迎页开始（讲用途），再到私隐
        }
        runOnboardingScriptIfNeeded()
    }

    // MARK: - 横幅与提示

    // 横幅、提示直接改值，唔好包 withAnimation（动画由 IslandBanner / ToastView 自己按值做）：
    // 同一刻仲有其他改动未刷新时，withAnimation 会令 SwiftUI 喺 willSet 嗰刻同步重画，读到旧值，
    // 之后呢次改动就冇再通知（合并时用日志实测：横幅已经设好但画面冇出，三次有两次）。
    /// reply：要你回应嘅横幅（别人约你、改约）留 30 秒（读屏 60 秒），长者来得及按；
    /// 收咗之后「今日」页最上面同「街坊」页最上面都有张可以直接回覆嘅卡（UX 评审 5 / 11）。只係话你知嘅照 8 秒收。
    func showBanner(_ b: BannerItem, haptic: Bool = true, reply: Bool = false) {
        banner = b
        if haptic { Haptics.warning() }
        bannerTask?.cancel()
        let seconds: Double = UIAccessibility.isVoiceOverRunning ? (reply ? 60 : 30) : (reply ? 30 : 8)   // 读屏开着：留时间找按钮（A43）
        bannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
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
