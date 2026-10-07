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
    @ObservationIgnored let bump: BumpService = SimulatedBumpService()
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

    /// 演示模式：圈里有示範街坊、右上有演示菜单。设置里可以关；启动参数 -demo 强制开。
    var demoMode = LaunchArgs.has("-demo") || UserDefaults.standard.object(forKey: "demoMode") as? Bool ?? true
    // 出门提醒：总开关 + 只在这个时段接收（F6）。
    var remindAll = UserDefaults.standard.object(forKey: "remindAll") as? Bool ?? true { didSet { UserDefaults.standard.set(remindAll, forKey: "remindAll") } }
    var remindFrom = UserDefaults.standard.object(forKey: "remindFrom") as? Int ?? 7 { didSet { UserDefaults.standard.set(remindFrom, forKey: "remindFrom") } }
    var remindTo = UserDefaults.standard.object(forKey: "remindTo") as? Int ?? 21 { didSet { UserDefaults.standard.set(remindTo, forKey: "remindTo") } }

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
    static let hk: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = SolarPosition.hongKong; return c }()

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

    func showBanner(_ b: BannerItem) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { banner = b }
        Haptics.warning()
        bannerTask?.cancel()
        bannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { self.banner = nil } }
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
        case .none: break
        }
    }

    func toast(_ s: String) {
        withAnimation(.snappy) { toast = s }
        speaker.speak(s)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if self.toast == s { withAnimation(.snappy) { self.toast = nil } }
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
