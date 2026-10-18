import SwiftUI
import UIKit

/// Member A owns App state and flows; AI, speech and bump capabilities use Domain/Contracts protocols.
@MainActor
@Observable
final class AppStore: NeighborRegistry {
    enum Phase: Equatable { case onboarding(Step), main }
    /// Five onboarding steps: welcome, privacy, location/building, floor/nickname, microphone trial. Home changes use only building and floor.
    enum Step: Int { case welcome, consent, locate, pickHome, floor, tryMic }
    enum Tab: Hashable { case today, board, neighbors }
    enum BumpStage: Equatable { case idle, searching, found(String) }
    /// home opens the home card from the building or label, showing building, floor and home-change controls.
    enum Selection: Equatable { case landmark(String), person(String), home }

    // Services.
    @ObservationIgnored let ai: AIService = TemplateAI()
    /// Bump uses simulated neighbors in demo mode and real UWB otherwise; selection lives in AppStore+Bump.
    @ObservationIgnored let simulatedBump = SimulatedBumpService()
    @ObservationIgnored let nearbyBump = NearbyBumpService()
    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored let listener = Listener()
    @ObservationIgnored let mapService = MapService()
    @ObservationIgnored let scene = DioramaController()
    /// Demo uses LocalCommunityService; normal mode uses SupabaseCommunityService. See installCommunity.
    @ObservationIgnored var community: CommunityService
    @ObservationIgnored let hko = HKOWeatherService()
    @ObservationIgnored let walkDetector = WalkDetector()
    @ObservationIgnored var shade: ShadeService?
    @ObservationIgnored var ticker: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    // Internal flow state that does not publish UI updates.
    /// Full tile for home selection; the selected-home scene uses a smaller base. See current map sizing constants.
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
    /// Canonical landmark names for restoring after data deletion.
    @ObservationIgnored var originalLandmarkNames: [String: String] = [:]
    @ObservationIgnored var clockTask: Task<Void, Never>?

    // Published state.
    // Stop prior-screen speech immediately on navigation or Settings changes (2026-10-12 user feedback).
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
    /// Continuous Doubao conversation keeps listening true without requiring a tap for each utterance.
    var conversing = false
    /// Current unprocessed continuous-conversation transcript.
    var heardPartial = ""
    @ObservationIgnored let ear = VoiceEar()
    @ObservationIgnored var earPending: [String] = []
    @ObservationIgnored var earFlush: Task<Void, Never>?
    @ObservationIgnored var earIdle: Task<Void, Never>?
    @ObservationIgnored var earFeed: Task<Void, Never>?
    @ObservationIgnored var lastEarActivity = Date()
    /// Recent output sentences for the continuous-conversation echo guard.
    @ObservationIgnored var recentSpoken: [(text: String, at: Date)] = []
    var phrasePicker = false
    var bumpStage: BumpStage = .idle
    var remindPromptFor: String?
    var selection: Selection?
    var renaming: String?
    var reports: [Report] = [] { didSet { scheduleSave() } }
    /// Daily walking records keyed by Hong Kong date; derive today's minutes and streak from these.
    var walkLog: [String: DayLog] = [:] { didSet { scheduleSave() } }
    var leaveDays: Set<String> = [] { didSet { scheduleSave() } }
    /// Renamed landmarks, ID to name, reapplied after map reload.
    var landmarkNames: [String: String] = [:] { didSet { scheduleSave() } }
    var showSettings = false { didSet { if showSettings != oldValue { hush() } } }
    /// -captions provides recording subtitles when simulator screen capture cannot record audio.
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
    /// My skin tone and age group, selectable in onboarding / Settings and saved immediately.
    var skinChoice = UserDefaults.standard.object(forKey: "skin") as? Int ?? 1 { didSet { UserDefaults.standard.set(skinChoice, forKey: "skin") } }
    var ageChoice = AgeGroup(rawValue: UserDefaults.standard.string(forKey: "age") ?? "") ?? .elder { didSet { UserDefaults.standard.set(ageChoice.rawValue, forKey: "age") } }

    /// Demo mode adds sample neighbors and the demo menu; Settings disables it and -demo forces it on.
    var demoMode = LaunchArgs.has("-demo") || UserDefaults.standard.object(forKey: "demoMode") as? Bool ?? true
    // F6: master outing-alert switch and receiving time window.
    /// 10-18 privacy feedback: building sharing defaults on, including legacy users; disabling uploads empty building / floor values.
    var shareHome = UserDefaults.standard.object(forKey: "shareHome") as? Bool ?? true { didSet { UserDefaults.standard.set(shareHome, forKey: "shareHome"); uploadProfile() } }
    var remindAll = UserDefaults.standard.object(forKey: "remindAll") as? Bool ?? true { didSet { UserDefaults.standard.set(remindAll, forKey: "remindAll") } }
    var remindFrom = UserDefaults.standard.object(forKey: "remindFrom") as? Int ?? 7 { didSet { UserDefaults.standard.set(remindFrom, forKey: "remindFrom") } }
    var remindTo = UserDefaults.standard.object(forKey: "remindTo") as? Int ?? 21 { didSet { UserDefaults.standard.set(remindTo, forKey: "remindTo") } }
    // Walking, data and services added by A.
    /// Per-walk demo clock, stopping places and step state.
    @ObservationIgnored var track = WalkTrack()
    /// Local departure and expiry notifications for meetings.
    @ObservationIgnored let notifier = Notifier()
    /// Foreground minute checks update sunlight and refresh Today after midnight.
    @ObservationIgnored var dayClock: Task<Void, Never>?
    /// Home-change onboarding entered from Settings supports cancellation.
    var changingHome = false

    // Voice and social flows added by A.
    /// Speech queuing, VoiceOver compatibility and listening deferral through AppStore+Voice.say().
    @ObservationIgnored let announcer = Announcer()
    /// Prevent a second microphone start while permission dialogs are pending.
    @ObservationIgnored var micStarting = false

    // Map, scene and performance additions by A.
    /// Map notice for sample estates, placeholder buildings or unavailable location; shown during home selection.
    var mapNotice: String?
    /// Map-load generation rejects stale results after sample selection or restarting home selection.
    @ObservationIgnored var mapLoadGen = 0
    /// Fixed scene meeting point during bump pairing.
    @ObservationIgnored var bumpSpot: Vec2?

    // Integration additions.
    /// Snapshot skin tone and age before home changes so cancellation can restore immediately saved edits.
    @ObservationIgnored var lookBeforeChange: (skin: Int, age: AgeGroup)?

    // Real-device bump and QR additions (2026-10-10); see AppStore+Bump.
    /// Full-screen bump progress: distance, proximity, pairing and failure reason.
    var bumpProgress: BumpUpdate = .searching
    /// QR state; nil shows the bump screen.
    var bumpQR: BumpQRState?
    /// QR pairing and post-success handoff tasks cancelled together.
    @ObservationIgnored var bumpTask: Task<Void, Never>?

    // Real-backend additions (AppStore+Backend).
    /// Nickname, 1–20 characters, visible on the local leaderboard and saved immediately.
    var nickname = UserDefaults.standard.string(forKey: "nickname") ?? "" { didSet { UserDefaults.standard.set(nickname, forKey: "nickname") } }
    /// B's voice assistant conversation and unresolved operations through the Mac server.
    @ObservationIgnored let assistant = AssistantSession()
    /// Current assistant request ID; discard replies to superseded requests.
    @ObservationIgnored var assistantGen = UUID()
    /// Confirmed action with unknown result, retained for adding the meeting after successful reconciliation.
    @ObservationIgnored var pendingAssistantAction: AssistantCard.Action?
    /// F8 incoming request to find me awaits acceptance or refusal.
    var incomingFind: IncomingFindAsk?

    // Live finding (AppStore+LiveFind).
    /// Temporarily share live coordinates with a real neighbor during finding; stop when it ends.
    @ObservationIgnored var liveFind: LiveFindSession?
    /// Last peer location rendered; redraw only when it changes.
    @ObservationIgnored var liveSceneStamp: Date?
    /// On the first peer fix, center the camera between both people once.
    @ObservationIgnored var liveCameraDone = false
    /// After meeting, Today's hero names the walking companion instead of prompting finding again; clear on walk end or new finding.
    var walkingWith: String?

    // After onboarding (AppStore+FirstDay).
    /// Persist first-day task progress; nil means no card, including legacy users.
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

    /// Use the same Hong Kong calendar for meetings, reminders and daily records.
    nonisolated static let hk: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = SolarPosition.hongKong; return c }()

    // MARK: - Startup

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
            phase = .onboarding(.welcome)     // Start onboarding with purpose on the welcome screen, followed by privacy.
        }
        runOnboardingScriptIfNeeded()
    }

    // MARK: - Banners and toasts

    // Assign banner / toast values without withAnimation; IslandBanner and ToastView animate their own values.
    // With other pending updates, withAnimation can synchronously redraw during willSet and read the old value,
    // then coalesce away the new notification; integration logs reproduced a missing banner in two of three trials.
    /// reply banners remain 30 seconds, or 60 with VoiceOver, to allow response.
    /// UX 5 / 11: persistent reply cards remain atop Today and Neighbors afterward; informational banners last 8 seconds.
    func showBanner(_ b: BannerItem, haptic: Bool = true, reply: Bool = false) {
        banner = b
        if haptic { Haptics.warning() }
        bannerTask?.cancel()
        let seconds: Double = UIAccessibility.isVoiceOverRunning ? (reply ? 60 : 30) : (reply ? 30 : 8)   // A43: allow VoiceOver users time to find buttons.
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

    // MARK: - Geometry helpers

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
