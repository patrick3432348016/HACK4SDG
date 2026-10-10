import CoreLocation
import CoreMotion
import os
import UIKit

/// F1 真机：后台出门检测。用一个专用 CLLocationManager 做三样低耗电嘅监察（都要「始终允许」定位）：
/// ① 屋企 100 m 区域（离开 / 返到）② 系统「到访」③ 大范围移动。
/// 有事时 iOS 会喺背景叫醒 App（App 俾系统收咗都会重新开），由 AppStore+Location 决定开唔开准确定位记录散步。
/// 用户喺多工画面将 App 扫走之后 iOS 唔会再叫醒（返前台时由 Core Motion 补记）。
/// 另外：收集夜晚位置估计屋企（HomeLearner），同埋记低最近 50 件事俾「定位紀錄」页睇。全部只喺呢部手机，唔上传。
@MainActor
@Observable
final class LocationMonitor: NSObject, CLLocationManagerDelegate {
    static let shared = LocationMonitor()
    nonisolated static let regionID = "home"

    // MARK: 界面状态

    private(set) var auth: CLAuthorizationStatus = .notDetermined
    /// 「精確位置」开咗（关咗认唔到行过边，区域监察都唔准）。
    private(set) var precise = true
    private(set) var motionAuth: CMAuthorizationStatus = .notDetermined
    /// 区域、到访、大范围移动监察开紧。
    private(set) var monitoring = false
    /// 系统话而家喺唔喺屋企范围内（未知 = nil）。
    private(set) var insideHome: Bool?
    private(set) var log = LocationLog()
    private(set) var learner = HomeLearner()
    private(set) var verdict: HomeVerdict = .learning(nights: 0)
    /// 屋企（揀咗嘅楼嘅中心）同埋係唔係用户自己揀嘅。
    private(set) var home: GeoPoint?
    private(set) var homePicked = false
    private(set) var snoozeUntil: Date?
    /// 问过「始终允许」（系统只会弹一次，之后要去设定改）。
    private(set) var askedAlways = UserDefaults.standard.bool(forKey: Keys.askedAlways)
    /// 自动弹过解释页（之后只喺今日页同设定显示）。
    private(set) var alwaysOffered = UserDefaults.standard.bool(forKey: Keys.alwaysOffered)
    /// 今日页嘅「未開齊」卡：按「遲啲先」之后几时先再出。
    private(set) var cardHiddenUntil = UserDefaults.standard.object(forKey: Keys.cardHidden) as? Date
    /// 完成首次使用后嘅「始终允许」解释页。
    var showAlwaysAsk = false
    /// 今日页「係咪搬咗屋」卡读过边句（每句只读一次）。
    @ObservationIgnored var spokenPrompt: String?

    /// 完成咗首次使用（同意咗）先开监察。
    var enabled = false { didSet { if enabled != oldValue { refreshMonitoring() } } }

    // MARK: 内部

    /// 叫醒 App 嘅事交俾 AppStore；未接上之前先排住。
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
    }

    private struct SavedHome: Codable {
        var lat: Double
        var lon: Double
        var picked: Bool
    }

    var isBackground: Bool { UIApplication.shared.applicationState == .background }
    static var calendar: Calendar { AppStore.hk }

    // MARK: - 启动

    /// App 一启动就要叫（包括系统喺背景开 App）：建好 manager、设好 delegate，系统先会将定位事件交过嚟。
    func activate() {
        guard manager == nil else { return }
        restore()
        let m = CLLocationManager()
        m.delegate = self
        manager = m
        auth = m.authorizationStatus
        precise = m.accuracyAuthorization == .fullAccuracy
        motionAuth = CMMotionActivityManager.authorizationStatus()
        if isBackground {
            record(.launch, "iOS 喺背景開咗街坊行")
            wake(.launch)
        }
        reevaluate()
        refreshMonitoring()
    }

    /// 返到前台：权限可能喺设定改咗；夜晚就攞一个定位做夜晚位置。
    func appBecameActive() {
        guard let m = manager else { return }
        authChanged(m.authorizationStatus, precise: m.accuracyAuthorization == .fullAccuracy)
        motionAuth = CMMotionActivityManager.authorizationStatus()
        if monitoring, let r = m.monitoredRegions.first(where: { $0.identifier == Self.regionID }) { m.requestState(for: r) }
        sampleNightIfNeeded()
        reevaluate()
    }

    /// 其他功能（后端刷新、出门状态上传）跟住背景唤醒做嘢：系统叫醒 App 时喺主线程叫 handler，
    /// 同时发 Notification.Name.streetWalkLocationWake。叫醒后大约得 10 秒（记录紧散步就一直有）。
    func onWake(_ handler: @escaping (LocationWake) -> Void) { wakeHandlers.append(handler) }

    // MARK: - 监察

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
                record(.monitor, "開始監察：離開 / 返到屋企、到訪、大範圍移動")
            }
        } else if servicesOn || monitoring || !m.monitoredRegions.isEmpty {
            servicesOn = false
            m.stopMonitoringSignificantLocationChanges()
            m.stopMonitoringVisits()
            for r in m.monitoredRegions { m.stopMonitoring(for: r) }
            if monitoring {
                monitoring = false
                record(.monitor, enabled ? "停咗監察：定位唔係「始終允許」" : "停咗監察")
            }
        }
    }

    /// 以屋企为中心登记 100 m 区域（屋企改咗就重新登记；同一个名会取代旧嘅）。
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
        record(.home, "登記咗屋企範圍：你揀嗰座樓周圍 \(Int(radius)) 米")
    }

    // MARK: - 屋企

    /// 模型用紧嘅屋企（AppStore 装好地图时叫）。picked：用户自己揀嘅（唔係示例屋邨、唔係默认楼）。
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
            record(.home, picked ? "屋企定咗喺你揀嘅樓" : "屋企暫時用模型預設嘅樓（未揀）")
        }
        if monitoring { registerHome() }
        reevaluate()
    }

    func reevaluate() {
        verdict = learner.verdict(home: home, picked: homePicked, now: Date(), calendar: Self.calendar)
    }

    /// 要问「係咪搬咗屋」/ 建议用过夜嘅地方。
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

    /// 「唔係」：7 日内唔再问；「係」：重新揀楼期间 1 日内唔再问。
    func snooze(days: Double) { setSnooze(Date().addingTimeInterval(days * 86400)) }

    private func setSnooze(_ d: Date?) {
        snoozeUntil = d
        UserDefaults.standard.set(d, forKey: Keys.snooze)
    }

    // MARK: - 权限

    /// 先要「使用 App 期间」，再要「始终」（系统只会弹一次「改为始终允许」；问过就打开设定）。
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
        record(.permission, "問咗「始終允許」定位")
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

    /// 自动记录要嘅权限未齐（唔係「始终」、或者精确位置关咗）。
    var needsAlways: Bool { auth != .authorizedAlways || !precise }

    private func authChanged(_ s: CLAuthorizationStatus, precise full: Bool) {
        let changed = s != auth || full != precise
        auth = s
        precise = full
        if changed { record(.permission, "定位：\(Self.authLabel(s))\(full ? "" : "，精確位置關咗")") }
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
        case .authorizedAlways: return "始終允許"
        case .authorizedWhenInUse: return "只係用緊 App 時"
        case .denied: return "已拒絕"
        case .restricted: return "受限制"
        case .notDetermined: return "未問"
        @unknown default: return "未知"
        }
    }

    static func motionLabel(_ s: CMAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "已允許"
        case .denied: return "已拒絕"
        case .restricted: return "受限制"
        case .notDetermined: return "未問"
        @unknown default: return "未知"
        }
    }

    // MARK: - 夜晚位置

    /// 夜晚（22:00–06:00）打开 App：攞一个定位做夜晚位置样本。
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

    /// 模拟器测试（-simNights lat,lon）：喺呢个位置加最近两晚（22:30–06:30）嘅过夜样本。
    func simulateNights(at p: GeoPoint, count: Int = 2) {
        let cal = Self.calendar
        let now = Date()
        // 最近一晚已经完咗嘅：而家过咗 06:00 就係琴晚，否则係前晚
        let tonight = cal.startOfDay(for: now.addingTimeInterval(-Double(HomeLearner.nightEnd) * 3600))
        for i in 1...max(1, count) {
            guard let day = cal.date(byAdding: .day, value: -i, to: tonight),
                  let start = cal.date(bySettingHour: 22, minute: 30, second: 0, of: day) else { continue }
            learner.add(NightSample(lat: p.lat, lon: p.lon, start: start, end: start.addingTimeInterval(8 * 3600), source: .simulated),
                        now: now, calendar: cal)
        }
        save()
        reevaluate()
        record(.night, "模擬：加咗 \(count) 晚過夜位置（\(Self.describe(home.map { HomeLearner.distance($0, p) }))）")
    }

    /// 「定位紀錄」页：清走事件同夜晚位置。
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
        Task { @MainActor in self.record(.note, "屋企範圍監察出錯：\(msg)") }
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

    // MARK: - 事件

    private func crossed(inside: Bool) {
        let now = Date()
        insideHome = inside
        if inside {
            if let h = home, !learner.hasOpen(.region) {
                addSample(NightSample(lat: h.lat, lon: h.lon, start: now, end: nil, source: .region))
            }
            record(.arrivedHome, "入咗屋企 \(Int(TriggerRules.homeRadius)) 米範圍")
            deliver(.arrivedHome)
            wake(.arrivedHome)
        } else {
            closeRegionStay(at: now)
            record(.leftHome, "出咗屋企 \(Int(TriggerRules.homeRadius)) 米範圍")
            deliver(.leftHome)
            wake(.leftHome)
        }
    }

    /// 启动 / 返前台时系统话我哋喺唔喺屋企范围（唔当出入，只更新状态同过夜纪录）。
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
        record(.visit, "\(leaving ? "離開" : "到咗")一個地方（\(Self.describe(d))）")
        deliver(leaving ? .visitDeparture(fromHome: d) : .visitArrival(fromHome: d))
        wake(.visit)
    }

    private func gotFix(_ p: GeoPoint, accuracy: Double, at: Date) {
        let d = home.map { HomeLearner.distance($0, p) }
        let mine = oneShot
        oneShot = false
        if accuracy >= 0, accuracy <= 200, HomeLearner.isNight(at, calendar: Self.calendar) {
            addSample(NightSample(lat: p.lat, lon: p.lon, start: at, end: at, source: mine ? .fix : .significant))
            if mine { record(.night, "夜晚位置（\(Self.describe(d))）") }
        }
        guard !mine else { return }
        // 啱啱开始监察时系统会即刻俾一个位置：前台嗰个唔当移动
        if !isBackground, Date().timeIntervalSince(servicesSince) < 20 { return }
        record(.significant, "大範圍移動（\(Self.describe(d))）")
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

    // MARK: - 纪录

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

    /// 「離屋企 35 米」「離屋企 2.3 公里」。
    static func describe(_ d: Double?) -> String {
        guard let d else { return "未知離屋企幾遠" }
        return d < 1000 ? "離屋企 \(Int(d.rounded())) 米" : String(format: "離屋企 %.1f 公里", d / 1000)
    }
}
