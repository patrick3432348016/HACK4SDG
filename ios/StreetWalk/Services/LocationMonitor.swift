import CoreLocation
import CoreMotion
import os
import UIKit

/// F1 background departure detection uses a dedicated CLLocationManager for three low-power monitors, requiring Always location permission:
/// 100-m home-region entry/exit, system visits, and significant location changes.
/// iOS can wake/relaunch a system-terminated app for these events. AppStore+Location decides whether to start accurate walk tracking.
/// After a user force-quit, iOS does not wake the app; Core Motion backfills on foreground.
/// Also collect nighttime home-inference samples and the latest 50 diagnostic events, stored only on this phone.
@MainActor
@Observable
final class LocationMonitor: NSObject, CLLocationManagerDelegate {
    static let shared = LocationMonitor()
    nonisolated static let regionID = "home"

    // MARK: UI state

    private(set) var auth: CLAuthorizationStatus = .notDetermined
    /// Whether Precise Location is enabled; reduced accuracy limits route and region detection.
    private(set) var precise = true
    private(set) var motionAuth: CMAuthorizationStatus = .notDetermined
    /// Whether region, visit, and significant-change monitoring are active.
    private(set) var monitoring = false
    /// Background App Refresh and Low Power Mode state; disabled refresh can prevent relaunch after system termination.
    private(set) var backgroundRefreshOK = true
    private(set) var lowPower = false
    /// System-reported home-region membership; nil means unknown.
    private(set) var insideHome: Bool?
    private(set) var log = LocationLog()
    private(set) var learner = HomeLearner()
    private(set) var verdict: HomeVerdict = .learning(nights: 0)
    /// Home-building centre and whether the user selected it.
    private(set) var home: GeoPoint?
    private(set) var homePicked = false
    private(set) var snoozeUntil: Date?
    /// Whether Always permission has been requested; subsequent changes require Settings.
    private(set) var askedAlways = UserDefaults.standard.bool(forKey: Keys.askedAlways)
    /// Whether the automatic explanation was shown; later guidance appears on Today/Settings.
    private(set) var alwaysOffered = UserDefaults.standard.bool(forKey: Keys.alwaysOffered)
    /// When the incomplete-permissions card may reappear after choosing later.
    private(set) var cardHiddenUntil = UserDefaults.standard.object(forKey: Keys.cardHidden) as? Date
    /// Post-onboarding Always-permission explanation sheet.
    var showAlwaysAsk = false
    /// Remember the spoken move-home prompt so each wording is read only once.
    @ObservationIgnored var spokenPrompt: String?

    /// Start monitoring only after consented onboarding.
    var enabled = false { didSet { if enabled != oldValue { refreshMonitoring() } } }

    // MARK: Internal state

    /// Queue wake events until AppStore's handler is attached.
    @ObservationIgnored var onTrigger: ((LocationTrigger) -> Void)? { didSet { flush() } }
    @ObservationIgnored private var pending: [LocationTrigger] = []
    @ObservationIgnored private var wakeHandlers: [(LocationWake) -> Void] = []
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var servicesOn = false
    @ObservationIgnored private var servicesSince = Date.distantPast
    @ObservationIgnored private var wantsAlways = false
    @ObservationIgnored private var oneShot = false
    private let logger = Logger(subsystem: "hk.hack4sdg.streetwalk", category: "location")

    private enum Keys {
        static let log = "loc.log.v1"
        static let learner = "loc.learner.v1"
        static let home = "loc.home.v1"
        static let snooze = "loc.snoozeUntil"
        static let askedAlways = "loc.askedAlways"
        static let alwaysOffered = "loc.alwaysOffered"
        static let cardHidden = "loc.cardHiddenUntil"
        static let lastSignificant = "loc.lastSignificant"
        static let monitoring = "loc.monitoring"
    }

    private struct SavedHome: Codable {
        var lat: Double
        var lon: Double
        var picked: Bool
    }

    var isBackground: Bool { UIApplication.shared.applicationState == .background }
    static var calendar: Calendar { AppStore.hk }

    // MARK: - Startup

    /// Initialize manager/delegate immediately on every launch, including background launch, so iOS can deliver location events.
    func activate() {
        guard manager == nil else { return }
        restore()
        let m = CLLocationManager()
        m.delegate = self
        manager = m
        auth = m.authorizationStatus
        precise = m.accuracyAuthorization == .fullAccuracy
        motionAuth = CMMotionActivityManager.authorizationStatus()
        refreshSystemSwitches()
        reevaluate()
        refreshMonitoring()
    }

    private func refreshSystemSwitches() {
        backgroundRefreshOK = UIApplication.shared.backgroundRefreshStatus == .available
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// AppDelegate background relaunch when the process was not running, usually for location events.
    func noteLocationLaunch() {
        record(.launch, L.t("App 冇開住，iOS 喺背景重新開咗街坊行", "App 没开着，iOS 在后台重新打开了街坊行"))
        wake(.launch)
    }

    /// On foreground, refresh permissions changed in Settings and request one nighttime home-learning sample if applicable.
    func appBecameActive() {
        guard let m = manager else { return }
        authChanged(m.authorizationStatus, precise: m.accuracyAuthorization == .fullAccuracy)
        motionAuth = CMMotionActivityManager.authorizationStatus()
        refreshSystemSwitches()
        if monitoring, let r = m.monitoredRegions.first(where: { $0.identifier == Self.regionID }) { m.requestState(for: r) }
        sampleNightIfNeeded()
        reevaluate()
    }

    /// Run other wake-dependent work, such as backend refresh/outing upload, through handler on the main thread.
    /// Also post streetWalkLocationWake. A wake usually offers about ten seconds unless a walk is being recorded.
    func onWake(_ handler: @escaping (LocationWake) -> Void) { wakeHandlers.append(handler) }

    // MARK: - Monitoring

    func refreshMonitoring() {
        guard let m = manager else { return }
        if enabled && auth == .authorizedAlways {
            if !servicesOn {
                servicesOn = true
                servicesSince = Date()
                m.startMonitoringSignificantLocationChanges()
                m.startMonitoringVisits()
            }
            registerHome()
            if !monitoring {
                monitoring = true
                // Do not duplicate the monitoring-start log if already active, including across process restarts.
                if !UserDefaults.standard.bool(forKey: Keys.monitoring) { record(.monitor, L.t("開始監察：離開 / 返到屋企、到訪、大範圍移動", "开始监测：离开 / 回到家、到访、大范围移动")) }
                UserDefaults.standard.set(true, forKey: Keys.monitoring)
            }
        } else if servicesOn || monitoring || !m.monitoredRegions.isEmpty {
            servicesOn = false
            m.stopMonitoringSignificantLocationChanges()
            m.stopMonitoringVisits()
            for r in m.monitoredRegions { m.stopMonitoring(for: r) }
            if monitoring || UserDefaults.standard.bool(forKey: Keys.monitoring) {
                monitoring = false
                UserDefaults.standard.set(false, forKey: Keys.monitoring)
                record(.monitor, enabled ? L.t("停咗監察：定位唔係「始終允許」", "已停止监测：定位不是「始终允许」") : L.t("停咗監察", "已停止监测"))
            }
        }
    }

    /// Register a 100-m home region; changing home replaces the previous same-name region.
    private func registerHome() {
        guard let m = manager, let h = home, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let radius = min(TriggerRules.homeRadius, m.maximumRegionMonitoringDistance)
        if let old = m.monitoredRegions.first(where: { $0.identifier == Self.regionID }) as? CLCircularRegion,
           HomeLearner.distance(GeoPoint(lat: old.center.latitude, lon: old.center.longitude), h) < 5, abs(old.radius - radius) < 1 {
            m.requestState(for: old)
            return
        }
        let r = CLCircularRegion(center: CLLocationCoordinate2D(latitude: h.lat, longitude: h.lon), radius: radius, identifier: Self.regionID)
        r.notifyOnEntry = true
        r.notifyOnExit = true
        m.startMonitoring(for: r)
        m.requestState(for: r)
        record(.home, L.t("登記咗屋企範圍：你揀嗰座樓周圍 \(Int(radius)) 米", "已登记家的范围：你选的那栋楼周围 \(Int(radius)) 米"))
    }

    // MARK: - Home

    /// AppStore supplies the model home after map installation; picked excludes example/developer defaults.
    func setHome(_ g: GeoPoint, picked: Bool) {
        let moved = home.map { HomeLearner.distance($0, g) > 5 } ?? true
        guard moved || picked != homePicked else { return }
        home = g
        homePicked = picked
        if let data = try? JSONEncoder().encode(SavedHome(lat: g.lat, lon: g.lon, picked: picked)) {
            UserDefaults.standard.set(data, forKey: Keys.home)
        }
        if moved {
            setSnooze(nil)
            record(.home, picked ? L.t("屋企定咗喺你揀嘅樓", "家已定在你选的楼") : L.t("屋企暫時用模型預設嘅樓（未揀）", "家暂时用模型默认的楼（未选）"))
        }
        if monitoring { registerHome() }
        reevaluate()
    }

    func reevaluate() {
        verdict = learner.verdict(home: home, picked: homePicked, now: Date(), calendar: Self.calendar)
    }

    /// Whether to ask about moving or suggest the inferred overnight location.
    enum HomePrompt: Equatable {
        case moved(GeoPoint, distance: Double, nights: Int)
        case suggest(GeoPoint, distance: Double?, nights: Int)

        var target: GeoPoint {
            switch self {
            case .moved(let p, _, _), .suggest(let p, _, _): return p
            }
        }
    }

    var homePrompt: HomePrompt? {
        if let s = snoozeUntil, s > Date() { return nil }
        switch verdict {
        case .moved(let p, let n, let d): return .moved(p, distance: d, nights: n)
        case .suggest(let p, let n, let d): return .suggest(p, distance: d, nights: n)
        default: return nil
        }
    }

    /// After no, suppress for seven days; after yes, suppress for one day while repicking home.
    func snooze(days: Double) { setSnooze(Date().addingTimeInterval(days * 86400)) }

    private func setSnooze(_ d: Date?) {
        snoozeUntil = d
        UserDefaults.standard.set(d, forKey: Keys.snooze)
    }

    // MARK: - Permissions

    /// Request When In Use before Always. After the one-time Always upgrade prompt, open Settings instead.
    func requestAlways() {
        guard let m = manager else { return }
        askedAlways = true
        UserDefaults.standard.set(true, forKey: Keys.askedAlways)
        switch m.authorizationStatus {
        case .notDetermined:
            wantsAlways = true
            m.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            m.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        default:
            openSettings()
        }
        record(.permission, L.t("問咗「始終允許」定位", "已请求「始终允许」定位"))
    }

    func markAlwaysOffered() {
        alwaysOffered = true
        UserDefaults.standard.set(true, forKey: Keys.alwaysOffered)
    }

    func hideCard(days: Double) {
        cardHiddenUntil = Date().addingTimeInterval(days * 86400)
        UserDefaults.standard.set(cardHiddenUntil, forKey: Keys.cardHidden)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Automatic tracking lacks permission when not Always or when Precise Location is disabled.
    var needsAlways: Bool { auth != .authorizedAlways || !precise }
    /// Today/Settings should explain missing location permissions or disabled Background App Refresh.
    var needsAttention: Bool { needsAlways || !backgroundRefreshOK }

    private func authChanged(_ s: CLAuthorizationStatus, precise full: Bool) {
        let changed = s != auth || full != precise
        auth = s
        precise = full
        if changed { record(.permission, L.t("定位：\(Self.authLabel(s))\(full ? "" : "，精確位置關咗")", "定位：\(Self.authLabel(s))\(full ? "" : "，精确位置已关闭")")) }
        if wantsAlways, s == .authorizedWhenInUse {
            wantsAlways = false
            manager?.requestAlwaysAuthorization()
        } else if s != .notDetermined {
            wantsAlways = false
        }
        refreshMonitoring()
    }

    static func authLabel(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .authorizedAlways: return L.t("始終允許", "始终允许")
        case .authorizedWhenInUse: return L.t("只係用緊 App 時", "仅使用 App 时")
        case .denied: return L.t("已拒絕", "已拒绝")
        case .restricted: return L.t("受限制", "受限制")
        case .notDetermined: return L.t("未問", "未询问")
        @unknown default: return L.t("未知", "未知")
        }
    }

    static func motionLabel(_ s: CMAuthorizationStatus) -> String {
        switch s {
        case .authorized: return L.t("已允許", "已允许")
        case .denied: return L.t("已拒絕", "已拒绝")
        case .restricted: return L.t("受限制", "受限制")
        case .notDetermined: return L.t("未問", "未询问")
        @unknown default: return L.t("未知", "未知")
        }
    }

    // MARK: - Nighttime location

    /// On an app launch between 22:00 and 06:00, request one home-learning location sample.
    private func sampleNightIfNeeded() {
        guard let m = manager, !oneShot, HomeLearner.isNight(Date(), calendar: Self.calendar), precise,
              auth == .authorizedAlways || auth == .authorizedWhenInUse else { return }
        oneShot = true
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        m.requestLocation()
    }

    private func addSample(_ s: NightSample) {
        learner.add(s, now: Date(), calendar: Self.calendar)
        save()
        reevaluate()
    }

    private func closeRegionStay(at t: Date) {
        if learner.close(.region, at: t) {
            save()
            reevaluate()
        }
    }

    /// Simulator -simNights lat,lon adds overnight samples for the last two nights, 22:30–06:30.
    func simulateNights(at p: GeoPoint, count: Int = 2) {
        let cal = Self.calendar
        let now = Date()
        // Most recent completed night is last night after 06:00, otherwise the night before.
        let tonight = cal.startOfDay(for: now.addingTimeInterval(-Double(HomeLearner.nightEnd) * 3600))
        for i in 1...max(1, count) {
            guard let day = cal.date(byAdding: .day, value: -i, to: tonight),
                  let start = cal.date(bySettingHour: 22, minute: 30, second: 0, of: day) else { continue }
            learner.add(NightSample(lat: p.lat, lon: p.lon, start: start, end: start.addingTimeInterval(8 * 3600), source: .simulated),
                        now: now, calendar: cal)
        }
        save()
        reevaluate()
        record(.night, L.t("模擬：加咗 \(count) 晚過夜位置（\(Self.describe(home.map { HomeLearner.distance($0, p) }))）", "模拟：加了 \(count) 晚过夜位置（\(Self.describe(home.map { HomeLearner.distance($0, p) }))）"))
    }

    /// Development -resetOnboarding also clears home and Always-request history to simulate a fresh install.
    func resetAll() {
        [Keys.log, Keys.learner, Keys.home, Keys.snooze, Keys.askedAlways, Keys.alwaysOffered, Keys.cardHidden, Keys.lastSignificant, Keys.monitoring]
            .forEach(UserDefaults.standard.removeObject(forKey:))
        log = LocationLog()
        learner = HomeLearner()
        home = nil
        homePicked = false
        snoozeUntil = nil
        askedAlways = false
        alwaysOffered = false
        cardHiddenUntil = nil
        reevaluate()
    }

    /// Location History clear action removes diagnostic events and nighttime samples.
    func clearRecords() {
        log = LocationLog()
        learner = HomeLearner()
        save()
        reevaluate()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus, full = m.accuracyAuthorization == .fullAccuracy
        Task { @MainActor in self.authChanged(s, precise: full) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.regionID else { return }
        Task { @MainActor in self.crossed(inside: true) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.regionID else { return }
        Task { @MainActor in self.crossed(inside: false) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == Self.regionID else { return }
        let inside: Bool? = state == .inside ? true : state == .outside ? false : nil
        Task { @MainActor in self.stateKnown(inside) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in self.record(.note, L.t("屋企範圍監察出錯：\(msg)", "家范围监测出错：\(msg)")) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didVisit visit: CLVisit) {
        let c = visit.coordinate, acc = visit.horizontalAccuracy, a = visit.arrivalDate, d = visit.departureDate
        Task { @MainActor in self.visited(GeoPoint(lat: c.latitude, lon: c.longitude), accuracy: acc, arrival: a, departure: d) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let p = GeoPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude), acc = l.horizontalAccuracy, at = l.timestamp
        Task { @MainActor in self.gotFix(p, accuracy: acc, at: at) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.oneShot = false }
    }

    // MARK: - Events

    private func crossed(inside: Bool) {
        let now = Date()
        insideHome = inside
        if inside {
            if let h = home, !learner.hasOpen(.region) {
                addSample(NightSample(lat: h.lat, lon: h.lon, start: now, end: nil, source: .region))
            }
            record(.arrivedHome, L.t("入咗屋企 \(Int(TriggerRules.homeRadius)) 米範圍", "进入了家 \(Int(TriggerRules.homeRadius)) 米范围"))
            deliver(.arrivedHome)
            wake(.arrivedHome)
        } else {
            closeRegionStay(at: now)
            record(.leftHome, L.t("出咗屋企 \(Int(TriggerRules.homeRadius)) 米範圍", "离开了家 \(Int(TriggerRules.homeRadius)) 米范围"))
            deliver(.leftHome)
            wake(.leftHome)
        }
    }

    /// Initial/foreground region state updates membership and overnight records, but does not count as entry/exit.
    private func stateKnown(_ inside: Bool?) {
        guard let inside else { return }
        insideHome = inside
        if inside {
            if let h = home, !learner.hasOpen(.region) {
                addSample(NightSample(lat: h.lat, lon: h.lon, start: Date(), end: nil, source: .region))
            }
        } else {
            closeRegionStay(at: Date())
        }
    }

    private func visited(_ p: GeoPoint, accuracy: Double, arrival: Date, departure: Date) {
        let start = arrival == .distantPast ? departure : arrival
        let end: Date? = departure == .distantFuture ? nil : departure
        if accuracy >= 0, accuracy <= 200 {
            addSample(NightSample(lat: p.lat, lon: p.lon, start: start, end: end, source: .visit))
        }
        let d = home.map { HomeLearner.distance($0, p) }
        let leaving = end != nil
        record(.visit, L.t("\(leaving ? "離開" : "到咗")一個地方（\(Self.describe(d))）", "\(leaving ? "离开" : "到了")一个地方（\(Self.describe(d))）"))
        deliver(leaving ? .visitDeparture(fromHome: d) : .visitArrival(fromHome: d))
        wake(.visit)
    }

    private func gotFix(_ p: GeoPoint, accuracy: Double, at: Date) {
        let d = home.map { HomeLearner.distance($0, p) }
        let mine = oneShot
        oneShot = false
        if accuracy >= 0, accuracy <= 200, HomeLearner.isNight(at, calendar: Self.calendar) {
            addSample(NightSample(lat: p.lat, lon: p.lon, start: at, end: at, source: mine ? .fix : .significant))
            if mine { record(.night, L.t("夜晚位置（\(Self.describe(d))）", "夜间位置（\(Self.describe(d))）")) }
        }
        guard !mine else { return }
        // Monitoring immediately returns a position; do not treat a point near the previous significant-change fix as movement.
        let prev = UserDefaults.standard.data(forKey: Keys.lastSignificant).flatMap { try? JSONDecoder().decode(GeoPoint.self, from: $0) }
        if let data = try? JSONEncoder().encode(GeoPoint(lat: HomeLearner.round(p.lat), lon: HomeLearner.round(p.lon))) {
            UserDefaults.standard.set(data, forKey: Keys.lastSignificant)
        }
        if let prev, HomeLearner.distance(prev, p) < 300 { return }
        if prev == nil, Date().timeIntervalSince(servicesSince) < 20 { return }
        record(.significant, L.t("大範圍移動（\(Self.describe(d))）", "大范围移动（\(Self.describe(d))）"))
        deliver(.significantChange(fromHome: d))
        wake(.significantChange)
    }

    private func deliver(_ t: LocationTrigger) {
        if let h = onTrigger { h(t) } else { pending.append(t) }
    }

    private func flush() {
        guard let h = onTrigger, !pending.isEmpty else { return }
        let list = pending
        pending = []
        list.forEach(h)
    }

    private func wake(_ r: LocationWake) {
        wakeHandlers.forEach { $0(r) }
        NotificationCenter.default.post(name: .streetWalkLocationWake, object: nil, userInfo: ["reason": r.rawValue, "background": isBackground])
    }

    // MARK: - History

    func record(_ kind: LocationEvent.Kind, _ detail: String) {
        let bg = isBackground
        log.add(LocationEvent(at: Date(), kind: kind, detail: detail, background: bg))
        logger.info("[loc] \(kind.rawValue, privacy: .public) \(detail, privacy: .public)\(bg ? " (bg)" : "", privacy: .public)")
        if let data = try? JSONEncoder().encode(log) { UserDefaults.standard.set(data, forKey: Keys.log) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(learner) { UserDefaults.standard.set(data, forKey: Keys.learner) }
        if let data = try? JSONEncoder().encode(log) { UserDefaults.standard.set(data, forKey: Keys.log) }
    }

    private func restore() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Keys.log), let l = try? JSONDecoder().decode(LocationLog.self, from: data) { log = l }
        if let data = d.data(forKey: Keys.learner), let l = try? JSONDecoder().decode(HomeLearner.self, from: data) { learner = l }
        if let data = d.data(forKey: Keys.home), let h = try? JSONDecoder().decode(SavedHome.self, from: data) {
            home = GeoPoint(lat: h.lat, lon: h.lon)
            homePicked = h.picked
        }
        snoozeUntil = d.object(forKey: Keys.snooze) as? Date
        learner.prune(now: Date())
    }

    /// Distance-from-home wording in metres or kilometres.
    static func describe(_ d: Double?) -> String {
        guard let d else { return L.t("未知離屋企幾遠", "不知离家多远") }
        return d < 1000 ? L.t("離屋企 \(Int(d.rounded())) 米", "离家 \(Int(d.rounded())) 米") : String(format: L.t("離屋企 %.1f 公里", "离家 %.1f 公里"), d / 1000)
    }
}
