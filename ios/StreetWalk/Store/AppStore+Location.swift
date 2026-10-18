import SwiftUI
import UserNotifications

// 后台出门检测、屋企学习嘅接线（LocationMonitor ↔ 散步流程 ↔ 界面）。
// 原有文件只加咗几个 hook：beginWalk / finishWalk（walkBegan / walkEnded）、recordWalk（noteWalkRecorded）、
// populate（syncHomeLocation）、finishOnboarding（locationOnboarded）、appActive（locationAppActive、背景唔停）。
//
// 流程（真机、「始终允许」、关咗演示模式）：
// 1. 喺屋企：App 可以俾系统暂停，冇开定位。
// 2. 出咗屋企 100 m（或者系统「到访」话离开咗屋企）→ iOS 喺背景叫醒 App → watchForWalk：
//    补记之前未记嘅行路、开 Core Motion、粗略定位保持醒住；Core Motion 话行紧路就开准确定位，
//    LiveWalkGate 两个好点就开始记录（同前台一样记路线、地标、落脚点，发出门状态）。5–15 分钟都冇开始就熄返。
// 3. 记录中锁机放袋：一直用准确定位（状态栏有蓝色标记）。
// 4. 返到屋企（40 m 内、或者系统报入咗屋企范围）→ 收尾、存盘、熄定位、App 再俾系统暂停。
//    喺外面停低 10 分钟 → 今次收尾，粗略定位等多 2 个钟，再行路就再记一次。
// 5. App 被扫走、冇「始终允许」：同以前一样，返前台时用 Core Motion 补记分钟同步数（冇地标）。
extension AppStore {
    /// 唯一嘅 AppStore：App 同 AppDelegate 都用佢（系统喺背景开 App 时要即刻有人接定位事件）。
    private static var instance: AppStore?
    private static var bgTasks: [String: UIBackgroundTaskIdentifier] = [:]
    static let homeFromSampleKey = "homeFromSample"

    static func launch() -> AppStore {
        if let s = instance { return s }
        WalkDetector.rememberSimWalk()
        let s = AppStore()
        instance = s
        s.attachLocation()
        s.attachVoice()     // 装咗更好嘅系统声音就讲一声（Voice/VoiceSettingsSection）
        s.startLiveIsland()     // 灵动岛 / 锁屏实时活动（AppStore+Island）：背景开 App 都要接手
        return s
    }

    var isInBackground: Bool { UIApplication.shared.applicationState == .background }
    /// App 用紧嘅嗰个 store（单元测试自己 new 嘅唔好改 LocationMonitor 嘅屋企同纪录）。
    var isMainStore: Bool { Self.instance === self }

    func attachLocation() {
        let lm = LocationMonitor.shared
        lm.enabled = phase == .main
        lm.onTrigger = { [weak self] t in self?.locationTriggered(t) }
        if LaunchArgs.has("-resetOnboarding") { lm.resetAll() }
        lm.activate()
        if let s = LaunchArgs.value("-simNights"), let g = Self.parseGeo(s) { lm.simulateNights(at: g) }
        if UIPreview.is("alwaysAsk") { lm.showAlwaysAsk = true }
        previewFirstDayIfNeeded()       // 截图自检：-uiPreview firstDay（AppStore+FirstDay）
    }

    nonisolated static func parseGeo(_ s: String) -> GeoPoint? {
        let p = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return p.count == 2 ? GeoPoint(lat: p[0], lon: p[1]) : nil
    }

    // MARK: - 生命周期 hook

    /// 返到前台（appActive）。
    func locationAppActive() {
        guard isMainStore else { return }
        // 改楼途中（phase 係首次使用）唔好停监察
        if phase == .main { LocationMonitor.shared.enabled = true }
        LocationMonitor.shared.appBecameActive()
        offerAlwaysIfNeeded()
    }

    /// 完成首次使用 / 改完楼（finishOnboarding）。
    func locationOnboarded() {
        guard isMainStore else { return }
        UserDefaults.standard.set(mapSource == .fallback, forKey: Self.homeFromSampleKey)
        LocationMonitor.shared.enabled = true
        syncHomeLocation()
        // 首次设定完就问「始终允许」（C-1：唔好等到行出街先弹框）；等「搞掂！…」讲完先出解释页
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.offerAlwaysIfNeeded()
        }
    }

    /// 装好地图（populate）：屋企位置交俾 LocationMonitor 登记屋企范围。
    func syncHomeLocation() {
        guard isMainStore, phase == .main, let m = map, let id = scene.homeBuildingID, let b = m.building(id: id) else { return }
        let d = UserDefaults.standard
        let picked = d.object(forKey: "homeBuilding") != nil && !d.bool(forKey: Self.homeFromSampleKey)
        LocationMonitor.shared.setHome(m.geoPoint(b.centroid), picked: picked)
    }

    /// 「始终允许」解释页（测试反馈 C-1）：完成首次设定就弹一次，喺屋企一次问清楚（以前等第一次散步之后先问，
    /// 结果行出街先弹系统框）。之后只喺今日页卡同设定提；但定位变返「未问」（例如以前揀咗「允许一次」），
    /// 每次打开 App 都再问一次，唔好留到喺街上先问。散步中、演示、自动脚本唔弹。
    func offerAlwaysIfNeeded() {
        let lm = LocationMonitor.shared
        guard phase == .main, !demoMode, !skipsPermissionPrompt, !changingHome, lm.auth != .authorizedAlways, walk == nil, !lm.showAlwaysAsk else { return }
        guard !lm.alwaysOffered || (lm.auth == .notDetermined && !lm.offeredThisLaunch) else { return }
        lm.markAlwaysOffered()
        lm.showAlwaysAsk = true
    }

    // MARK: - 系统叫醒

    func locationTriggered(_ t: LocationTrigger) {
        let lm = LocationMonitor.shared
        let d = walkDetector
        let enabled = WalkDetector.isAvailable && !demoMode && phase == .main
        let r = TriggerRules.response(to: t, recording: d.recording, enabled: enabled)
        if !enabled, t == .leftHome {
            lm.record(.note, demoMode ? L.t("演示模式開住：唔記錄真散步", "演示模式开着：不记录真实散步", "Demo mode on: real walks not recorded") : WalkDetector.isAvailable ? L.t("未完成首次使用", "未完成首次使用", "Setup not finished") : L.t("呢部機冇動作感應", "这台手机没有动作感应", "This phone has no motion sensor"))
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

    /// 离开屋企：开动作感应同定位，等开始行路（开始由 handleWalkEvent 嘅 LiveWalkGate 决定）。
    func watchForWalk(fromHome: Bool) {
        let d = walkDetector
        holdBackgroundTime("watch")
        if fromHome { d.leftHomeAt = Date() }
        let since = Date()
        d.keepAlive = true                 // 背景醒住：等 Core Motion 话行紧路先开准确定位
        startWalkDetection()               // 补记之前未记嘅行路、开动作感应（同返前台一样）
        if !d.catchingUp, d.running { d.setLocating(d.moving || d.recording) }
        LocationMonitor.shared.record(.watch, L.t("開定位等你開始行路（最多 15 分鐘）", "开定位等你开始走路（最多 15 分钟）", "Location on, waiting for you to walk (up to 15 min)"))
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
        guard !d.recording else { return }      // 已经交咗俾散步
        d.keepAlive = false
        LocationMonitor.shared.record(.watch, L.t("冇開始行路，熄返定位", "没开始走路，关掉定位", "No walk started, location off"))
        guard isInBackground else { return }    // 前台照旧（行路先开定位）
        // 背景：停晒，等系统再叫醒。由 since 起（未接手嘅行路由佢开始）返前台时补记
        UserDefaults.standard.set(min(since, d.pendingWalk?.start ?? since), forKey: Self.backgroundKey)
        d.pendingWalk = nil
        d.leftHomeAt = nil
        saveNow()
        d.stop()
    }

    /// 记录中返到屋企范围：收尾（walkEnded 负责存盘、熄定位）。
    /// 仲行紧路又未入 40 m（例如绕圈经过屋企附近）就唔收，交返 LiveWalkGate（40 m）同「停低 5 分钟喺屋企附近」判断。
    func arriveHomeWhileRecording() {
        let d = walkDetector
        guard d.recording, walk != nil else { return }
        if d.moving, let fix = d.lastFix, let m = map,
           m.scenePoint(fix.0).distance(to: scene.homeTarget) - fix.accuracy > LiveWalkGate.homeRadius {
            LocationMonitor.shared.record(.note, L.t("經過屋企附近，仲行緊：繼續記錄", "经过家附近，还在走：继续记录", "Passed near home, still walking: still recording"))
            return
        }
        holdBackgroundTime("arrive")
        finishLiveWalk(endAt: Date(), reason: .home)
    }

    /// 冇记录紧但返到屋企：背景就用 Core Motion 补记之前行过嘅路（例如喺外面停低后行返屋企嗰段），再停。
    func catchUpAtHome() {
        let d = walkDetector
        d.watchTask?.cancel()
        d.watchTask = nil
        d.keepAlive = false
        d.leftHomeAt = nil
        guard isInBackground else { return }    // 前台：散步检测本身开住
        holdBackgroundTime("catchUp")
        startWalkDetection()
        Task { [weak self] in
            for _ in 0..<40 where d.catchingUp { try? await Task.sleep(for: .milliseconds(250)) }
            guard let self, !d.recording, self.isInBackground else { return }
            // 最后一段（啱啱行返嚟）即刻按而家补记
            self.settlePendingWalk(stoppedAt: Date())
            try? await Task.sleep(for: .seconds(2))
            guard !d.recording, self.isInBackground else { return }
            UserDefaults.standard.set(Date(), forKey: Self.backgroundKey)
            self.saveNow()
            d.stop()
        }
    }

    // MARK: - 散步 hook

    /// beginWalk 之后。
    func walkBegan(live: Bool) {
        guard live, isMainStore, let w = walk else { return }
        let d = walkDetector
        d.watchTask?.cancel()
        d.watchTask = nil
        d.keepAlive = false      // 记录中一直用准确定位（停低都唔熄），唔使粗略档
        let bg = isInBackground
        LocationMonitor.shared.record(.walkStart, L.t("\(bg ? "鎖咗機 / 背景" : "App 開住")，由 \(Self.clock(w.start)) 計", "\(bg ? "锁屏 / 后台" : "App 开着")，从 \(Self.clock(w.start)) 算起", "\(bg ? "Locked / background" : "App open"), counting from \(Self.clock(w.start))"))
        guard bg else { return }
        // 记录中俾系统收咗：下次开 App 由今次开始补记
        UserDefaults.standard.set(w.start, forKey: Self.backgroundKey)
        notifyWalk(L.t("偵測到你出咗門，開始記錄散步。", "检测到你出门了，开始记录散步。", "You’ve gone out. Recording your walk."))
    }

    /// finishWalk 之后。
    func walkEnded(live: Bool, minutes: Int, places: Int, reason: WalkEnd, recorded: Bool) {
        guard live, isMainStore else { return }
        let why: String
        switch reason {
        case .home: why = L.t("返到屋企", "回到家", "Back home")
        case .stopped: why = L.t("喺外面停低咗", "在外面停下了", "Stopped while out")
        case .riding: why = L.t("上咗車", "上车了", "Got on a vehicle")
        case .user: why = L.t("你撳咗結束散步", "你点了结束散步", "You ended the walk")
        }
        LocationMonitor.shared.record(.walkEnd, recorded ? L.t("\(why)：行咗 \(minutes) 分鐘，經過 \(places) 個地方", "\(why)：走了 \(minutes) 分钟，经过 \(places) 个地方", "\(why): walked \(minutes) min, passed \(places) places") : L.t("\(why)：太短，唔記錄", "\(why)：太短，不记录", "\(why): too short, not saved"))
        if recorded, !isInBackground {
            // 第一次散步记好：等「返到屋企喇…」讲完先问「始终允许」（只问一次）
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.offerAlwaysIfNeeded()
            }
        }
        guard isInBackground else { return }
        let d = walkDetector
        UserDefaults.standard.set(Date(), forKey: Self.backgroundKey)
        if recorded { notifyWalk(reason == .home ? L.t("返到屋企喇，今次行咗 \(minutes) 分鐘。", "到家了，这次走了 \(minutes) 分钟。", "Home now. You walked \(minutes) min.") : L.t("今次散步記好咗：行咗 \(minutes) 分鐘。", "这次散步记好了：走了 \(minutes) 分钟。", "Walk saved: \(minutes) min.")) }
        holdBackgroundTime("walkEnd")
        Task { [weak self] in
            // 等 finishLiveWalk 做埋（佢之后会按行唔行路开关定位）
            await Task.yield()
            guard let self, !d.recording else { return }
            self.saveNow()
            guard self.isInBackground else { return }
            if reason == .stopped {
                // 喺外面停低：粗略定位醒住最多 2 个钟，再行路就再记一次
                d.keepAlive = true
                d.watchTask?.cancel()
                d.watchTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(TriggerRules.awayFor))
                    guard !Task.isCancelled, let self, !d.recording else { return }
                    d.watchTask = nil
                    d.keepAlive = false
                    guard self.isInBackground else { return }
                    LocationMonitor.shared.record(.watch, L.t("喺外面停低咗兩個鐘，熄返定位", "在外面停了两个小时，关掉定位", "Stopped out for 2 hours, location off"))
                    d.stop()
                }
            } else {
                d.leftHomeAt = nil
                d.pendingWalk = nil
                d.stop()
            }
        }
    }

    /// recordWalk 之后：补记嘅（背景期间行嘅）写入定位纪录；实时散步由 walkEnded 写。
    func noteWalkRecorded(minutes: Int, simulated: Bool, backfilled: Bool, steps: Int?) {
        guard !simulated, backfilled, isMainStore else { return }
        LocationMonitor.shared.record(.backfill, L.t("用手機步行紀錄補記：\(minutes) 分鐘\(steps.map { "、\($0) 步" } ?? "")（冇地標）", "用手机步行记录补记：\(minutes) 分钟\(steps.map { "、\($0) 步" } ?? "")（没有地标）", "Added from phone step log: \(minutes) min\(steps.map { ", \($0) steps" } ?? "") (no landmarks)"))
        if !isInBackground { offerAlwaysIfNeeded() }    // 补记咗第一次散步（返前台）：问「始终允许」
    }

    /// 背景开始 / 记好散步：静音通知（App 打开时唔弹）。
    func notifyWalk(_ body: String) {
        let c = UNMutableNotificationContent()
        c.title = L.t("街坊行", "街坊行", "StreetWalk")
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "walk-\(UUID().uuidString)", content: c, trigger: nil))
    }

    // MARK: - 搬屋

    /// 「係，搬過嚟」：用过夜嘅地方重新揀楼（同设定「改我住嘅樓」一样嘅流程，地图按新位置重新生成）。
    func acceptHomePrompt() {
        let lm = LocationMonitor.shared
        guard let p = lm.homePrompt else { return }
        lm.snooze(days: 1)
        lm.record(.home, L.t("你揀咗「搬過嚟」：喺過夜嘅地方重新揀樓", "你选了「搬过来」：在过夜的地方重新选楼", "You picked “Moved here”: pick your block again"))
        mapService.pinnedLocation = p.target
        showSettings = false
        beginChangeHome()
    }

    /// 「唔係」：7 日内唔再问。
    func declineHomePrompt() {
        let lm = LocationMonitor.shared
        lm.snooze(days: 7)
        lm.record(.home, L.t("你揀咗「唔係」：7 日內唔再問", "你选了「不是」：7 天内不再问", "You picked “No”: won’t ask again for 7 days"))
    }

    // MARK: - 小工具

    /// 背景多攞少少时间（系统叫醒后大约得 10 秒）；seconds 之后自动交还。
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

    /// 「08:05」（香港时间）。
    static func clock(_ d: Date) -> String {
        let c = hk.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

extension MapModel {
    /// 场景坐标 → 经纬度（scenePoint 嘅反向）。
    func geoPoint(_ p: Vec2) -> GeoPoint {
        let cs = cos(rotation), sn = sin(rotation)
        let v = Vec2(x: p.x * cs + p.y * sn, y: -p.x * sn + p.y * cs)
        return LocalProjection(origin: center).toGeo(v)
    }
}
