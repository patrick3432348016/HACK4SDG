import SwiftUI
import UserNotifications

// Connect LocationMonitor, walking flow and UI for background departure detection and home learning.
// Hooks: beginWalk / finishWalk call walkBegan / walkEnded; recordWalk calls noteWalkRecorded.
// populate calls syncHomeLocation; finishOnboarding calls locationOnboarded; appActive calls locationAppActive without stopping background monitoring.
//
// Real-device flow with Always permission and demo mode disabled:
// 1. At home: location is off and iOS may suspend the App.
// 2. Leaving the 100 m home region or a visit-departure event wakes the App and starts watchForWalk.
//    Backfill unrecorded walking, enable Core Motion and coarse location; switch to accurate fixes when motion reports walking.
//    Two valid LiveWalkGate fixes start recording routes, landmarks, stops and outing status; stop waiting after 5–15 minutes.
// 3. During recording, keep accurate location while locked; iOS shows its blue location indicator.
// 4. Returning within 40 m or receiving a home-region entry ends and saves the walk, disables location and permits suspension.
//    After 10 minutes stopped outside, finish this walk and wait up to 2 hours on coarse location for another walk.
// 5. After force-quit or without Always permission, backfill minutes and steps from Core Motion on foreground return, without landmarks.
extension AppStore {
    /// Shared AppStore for App and AppDelegate, ready to receive system background location events immediately.
    private static var instance: AppStore?
    private static var bgTasks: [String: UIBackgroundTaskIdentifier] = [:]
    static let homeFromSampleKey = "homeFromSample"

    static func launch() -> AppStore {
        if let s = instance { return s }
        WalkDetector.rememberSimWalk()
        let s = AppStore()
        instance = s
        s.attachLocation()
        s.attachVoice()     // Announce newly installed enhanced system voices (Voice/VoiceSettingsSection).
        s.startLiveIsland()     // Dynamic Island / Lock Screen activities must reconnect on background launch too.
        return s
    }

    var isInBackground: Bool { UIApplication.shared.applicationState == .background }
    /// Only the App's active store may change LocationMonitor home or records; exclude unit-test stores.
    var isMainStore: Bool { Self.instance === self }

    func attachLocation() {
        let lm = LocationMonitor.shared
        lm.enabled = phase == .main
        lm.onTrigger = { [weak self] t in self?.locationTriggered(t) }
        if LaunchArgs.has("-resetOnboarding") { lm.resetAll() }
        lm.activate()
        if let s = LaunchArgs.value("-simNights"), let g = Self.parseGeo(s) { lm.simulateNights(at: g) }
        if UIPreview.is("alwaysAsk") { lm.showAlwaysAsk = true }
    }

    nonisolated static func parseGeo(_ s: String) -> GeoPoint? {
        let p = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return p.count == 2 ? GeoPoint(lat: p[0], lon: p[1]) : nil
    }

    // MARK: - Lifecycle hooks

    /// Returning to foreground (appActive).
    func locationAppActive() {
        guard isMainStore else { return }
        // Keep monitoring while changing home during the onboarding phase.
        if phase == .main { LocationMonitor.shared.enabled = true }
        LocationMonitor.shared.appBecameActive()
        offerAlwaysIfNeeded()
    }

    /// After initial setup or changing home (finishOnboarding).
    func locationOnboarded() {
        guard isMainStore else { return }
        UserDefaults.standard.set(mapSource == .fallback, forKey: Self.homeFromSampleKey)
        LocationMonitor.shared.enabled = true
        syncHomeLocation()
        offerAlwaysIfNeeded()
    }

    /// After populate, register the home region with LocationMonitor.
    func syncHomeLocation() {
        guard isMainStore, phase == .main, let m = map, let id = scene.homeBuildingID, let b = m.building(id: id) else { return }
        let d = UserDefaults.standard
        let picked = d.object(forKey: "homeBuilding") != nil && !d.bool(forKey: Self.homeFromSampleKey)
        LocationMonitor.shared.setHome(m.geoPoint(b.centroid), picked: picked)
    }

    /// After the first recorded real walk ends, show the Always Allow explanation once; request permission when needed (UX finding 24).
    /// Suppress the prompt in demo and scripted flows; later reminders appear in Today and Settings.
    func offerAlwaysIfNeeded() {
        let lm = LocationMonitor.shared
        guard phase == .main, !demoMode, !skipsPermissionPrompt, !changingHome, lm.auth != .authorizedAlways, !lm.alwaysOffered else { return }
        guard walk == nil, walkLog.values.contains(where: { !$0.demo && $0.walks > 0 }) else { return }
        lm.markAlwaysOffered()
        lm.showAlwaysAsk = true
    }

    // MARK: - System wake events

    func locationTriggered(_ t: LocationTrigger) {
        let lm = LocationMonitor.shared
        let d = walkDetector
        let enabled = WalkDetector.isAvailable && !demoMode && phase == .main
        let r = TriggerRules.response(to: t, recording: d.recording, enabled: enabled)
        if !enabled, t == .leftHome {
            lm.record(.note, demoMode ? L.t("演示模式開住：唔記錄真散步", "演示模式开着：不记录真实散步") : WalkDetector.isAvailable ? L.t("未完成首次使用", "未完成首次使用") : L.t("呢部機冇動作感應", "这台手机没有动作感应"))
        }
        switch r {
        case .watch:
            let fromHome: Bool
            switch t {
            case .leftHome, .visitDeparture: fromHome = true
            default: fromHome = false
            }
            watchForWalk(fromHome: fromHome)
        case .finish:
            arriveHomeWhileRecording()
        case .catchUp:
            catchUpAtHome()
        case .none:
            break
        }
    }

    /// Leaving home enables motion and location while waiting for LiveWalkGate in handleWalkEvent to start a walk.
    func watchForWalk(fromHome: Bool) {
        let d = walkDetector
        holdBackgroundTime("watch")
        if fromHome { d.leftHomeAt = Date() }
        let since = Date()
        d.keepAlive = true                 // Stay awake in background; enable accurate location only after Core Motion detects walking.
        startWalkDetection()               // Backfill unrecorded walking and start motion sensing, as on foreground return.
        if !d.catchingUp, d.running { d.setLocating(d.moving || d.recording) }
        LocationMonitor.shared.record(.watch, L.t("開定位等你開始行路（最多 15 分鐘）", "开定位等你开始走路（最多 15 分钟）"))
        d.watchTask?.cancel()
        d.watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                if !TriggerRules.keepWatching(since: since, now: Date(), recording: d.recording, moving: d.moving) { break }
            }
            guard !Task.isCancelled else { return }
            self?.endWatch(since: since)
        }
    }

    private func endWatch(since: Date) {
        let d = walkDetector
        d.watchTask = nil
        guard !d.recording else { return }      // Walking has already taken over.
        d.keepAlive = false
        LocationMonitor.shared.record(.watch, L.t("冇開始行路，熄返定位", "没开始走路，关掉定位"))
        guard isInBackground else { return }    // Foreground behavior: enable location only while walking.
        // In background stop everything until the next system wake; backfill unhandled walking from since on foreground return.
        UserDefaults.standard.set(min(since, d.pendingWalk?.start ?? since), forKey: Self.backgroundKey)
        d.pendingWalk = nil
        d.leftHomeAt = nil
        saveNow()
        d.stop()
    }

    /// Home-region entry during recording finishes the walk; walkEnded saves and disables location.
    /// If still walking outside 40 m, defer to LiveWalkGate and the five-minute stop near home, allowing routes that pass nearby.
    func arriveHomeWhileRecording() {
        let d = walkDetector
        guard d.recording, walk != nil else { return }
        if d.moving, let fix = d.lastFix, let m = map,
           m.scenePoint(fix.0).distance(to: scene.homeTarget) - fix.accuracy > LiveWalkGate.homeRadius {
            LocationMonitor.shared.record(.note, L.t("經過屋企附近，仲行緊：繼續記錄", "经过家附近，还在走：继续记录"))
            return
        }
        holdBackgroundTime("arrive")
        finishLiveWalk(endAt: Date(), reason: .home)
    }

    /// Returning home without recording: in background backfill the final walking segment with Core Motion, then stop.
    func catchUpAtHome() {
        let d = walkDetector
        d.watchTask?.cancel()
        d.watchTask = nil
        d.keepAlive = false
        d.leftHomeAt = nil
        guard isInBackground else { return }    // Foreground walk detection is already active.
        holdBackgroundTime("catchUp")
        startWalkDetection()
        Task { [weak self] in
            for _ in 0..<40 where d.catchingUp { try? await Task.sleep(for: .milliseconds(250)) }
            guard let self, !d.recording, self.isInBackground else { return }
            // Backfill the just-completed return segment immediately.
            self.settlePendingWalk(stoppedAt: Date())
            try? await Task.sleep(for: .seconds(2))
            guard !d.recording, self.isInBackground else { return }
            UserDefaults.standard.set(Date(), forKey: Self.backgroundKey)
            self.saveNow()
            d.stop()
        }
    }

    // MARK: - Walking hooks

    /// After beginWalk.
    func walkBegan(live: Bool) {
        guard live, isMainStore, let w = walk else { return }
        let d = walkDetector
        d.watchTask?.cancel()
        d.watchTask = nil
        d.keepAlive = false      // Keep accurate location throughout recording, including stops; coarse mode is unnecessary.
        let bg = isInBackground
        LocationMonitor.shared.record(.walkStart, L.t("\(bg ? "鎖咗機 / 背景" : "App 開住")，由 \(Self.clock(w.start)) 計", "\(bg ? "锁屏 / 后台" : "App 开着")，从 \(Self.clock(w.start)) 算起"))
        guard bg else { return }
        // If terminated while recording, backfill from this walk's start on next launch.
        UserDefaults.standard.set(w.start, forKey: Self.backgroundKey)
        notifyWalk(L.t("偵測到你出咗門，開始記錄散步。", "检测到你出门了，开始记录散步。"))
    }

    /// After finishWalk.
    func walkEnded(live: Bool, minutes: Int, places: Int, reason: WalkEnd, recorded: Bool) {
        guard live, isMainStore else { return }
        let why: String
        switch reason {
        case .home: why = L.t("返到屋企", "回到家")
        case .stopped: why = L.t("喺外面停低咗", "在外面停下了")
        case .riding: why = L.t("上咗車", "上车了")
        }
        LocationMonitor.shared.record(.walkEnd, recorded ? L.t("\(why)：行咗 \(minutes) 分鐘，經過 \(places) 個地方", "\(why)：走了 \(minutes) 分钟，经过 \(places) 个地方") : L.t("\(why)：太短，唔記錄", "\(why)：太短，不记录"))
        if recorded, !isInBackground {
            // After the first recorded walk, request Always permission once, following the return-home announcement.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.offerAlwaysIfNeeded()
            }
        }
        guard isInBackground else { return }
        let d = walkDetector
        UserDefaults.standard.set(Date(), forKey: Self.backgroundKey)
        if recorded { notifyWalk(reason == .home ? L.t("返到屋企喇，今次行咗 \(minutes) 分鐘。", "到家了，这次走了 \(minutes) 分钟。") : L.t("今次散步記好咗：行咗 \(minutes) 分鐘。", "这次散步记好了：走了 \(minutes) 分钟。")) }
        holdBackgroundTime("walkEnd")
        Task { [weak self] in
            // Wait for finishLiveWalk to finish adjusting location according to motion.
            await Task.yield()
            guard let self, !d.recording else { return }
            self.saveNow()
            guard self.isInBackground else { return }
            if reason == .stopped {
                // Stopped outside: keep coarse location for up to 2 hours and record again when walking resumes.
                d.keepAlive = true
                d.watchTask?.cancel()
                d.watchTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(TriggerRules.awayFor))
                    guard !Task.isCancelled, let self, !d.recording else { return }
                    d.watchTask = nil
                    d.keepAlive = false
                    guard self.isInBackground else { return }
                    LocationMonitor.shared.record(.watch, L.t("喺外面停低咗兩個鐘，熄返定位", "在外面停了两个小时，关掉定位"))
                    d.stop()
                }
            } else {
                d.leftHomeAt = nil
                d.pendingWalk = nil
                d.stop()
            }
        }
    }

    /// After recordWalk, save background backfills to location records; walkEnded saves live walks.
    func noteWalkRecorded(minutes: Int, simulated: Bool, backfilled: Bool, steps: Int?) {
        guard !simulated, backfilled, isMainStore else { return }
        LocationMonitor.shared.record(.backfill, L.t("用手機步行紀錄補記：\(minutes) 分鐘\(steps.map { "、\($0) 步" } ?? "")（冇地標）", "用手机步行记录补记：\(minutes) 分钟\(steps.map { "、\($0) 步" } ?? "")（没有地标）"))
        if !isInBackground { offerAlwaysIfNeeded() }    // Request Always permission after backfilling the first walk on foreground return.
    }

    /// Silent notifications for background walk start / completion; suppress while the App is open.
    func notifyWalk(_ body: String) {
        let c = UNMutableNotificationContent()
        c.title = "街坊行"
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "walk-\(UUID().uuidString)", content: c, trigger: nil))
    }

    // MARK: - Moving home

    /// Confirming a move restarts building selection around the overnight location, as in Settings.
    func acceptHomePrompt() {
        let lm = LocationMonitor.shared
        guard let p = lm.homePrompt else { return }
        lm.snooze(days: 1)
        lm.record(.home, L.t("你揀咗「搬過嚟」：喺過夜嘅地方重新揀樓", "你选了「搬过来」：在过夜的地方重新选楼"))
        mapService.pinnedLocation = p.target
        showSettings = false
        beginChangeHome()
    }

    /// Declining suppresses the question for 7 days.
    func declineHomePrompt() {
        let lm = LocationMonitor.shared
        lm.snooze(days: 7)
        lm.record(.home, L.t("你揀咗「唔係」：7 日內唔再問", "你选了「不是」：7 天内不再问"))
    }

    // MARK: - Utilities

    /// Request extra background time beyond the roughly 10-second wake window; release automatically after seconds.
    func holdBackgroundTime(_ name: String, seconds: Double = 25) {
        Self.releaseBackgroundTime(name)
        let id = UIApplication.shared.beginBackgroundTask(withName: name) { AppStore.releaseBackgroundTime(name) }
        Self.bgTasks[name] = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if Self.bgTasks[name] == id { Self.releaseBackgroundTime(name) }
        }
    }

    static func releaseBackgroundTime(_ name: String) {
        guard let id = bgTasks.removeValue(forKey: name), id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
    }

    /// Format HH:mm in Hong Kong time.
    static func clock(_ d: Date) -> String {
        let c = hk.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

extension MapModel {
    /// Convert scene coordinates to latitude/longitude, the inverse of scenePoint.
    func geoPoint(_ p: Vec2) -> GeoPoint {
        let cs = cos(rotation), sn = sin(rotation)
        let v = Vec2(x: p.x * cs + p.y * sn, y: -p.x * sn + p.y * cs)
        return LocalProjection(origin: center).toGeo(v)
    }
}
