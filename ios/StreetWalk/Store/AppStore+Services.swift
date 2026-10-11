import UIKit

// 真实服务的接线：天文台天气、真机散步检测、本地通知、打电话
extension AppStore {
    /// 回到前台 / 退到后台（StreetWalkApp 按 scenePhase 调用，启动时也会来一次；.inactive 不调）。
    func appActive(_ active: Bool) {
        backendAppActive(active)   // 真后端：前台开 Realtime、补拉；后台断线、排后台刷新（AppStore+Backend）
        liveFind?.setForeground(active)   // 找人分享位置：只喺前台传（AppStore+LiveFind）
        if active {
            ensureMeBeforeMap()
            refreshLiveWeather()
            hko.keepFresh(true) { [weak self] in self?.refreshLiveWeather() }
            startWalkDetection()
            // 隔咗一阵返嚟：太阳、今日状态、约会提醒跟返而家（A34）
            updateSun(animated: false)
            refreshMe()
            if map != nil { checkAppointments() }   // 启动时地图未装好，等 populate 再查（唔好出冇名嘅提醒）
            startDayClock()
            locationAppActive()     // 权限、屋企范围、夜晚位置、「始终允许」解释页（AppStore+Location）
        } else {
            // 退后台即刻写盘（唔等 0.5 秒），之后被系统收咗都唔会冇咗最后一次改动（A76）
            saveTask?.cancel()
            saveNow()
            syncNotifications()
            dayClock?.cancel()
            hko.keepFresh(false) {}
            markBackground()
            // 记录紧散步 / 等紧开始行路：锁机放袋都继续（背景定位）；否则停，等系统喺离开屋企时叫醒（AppStore+Location）
            if !walkDetector.staysAwakeInBackground { walkDetector.stop() }
        }
    }

    /// 前台时每分钟：用真实时间时每 5 分钟郁一次太阳；过咗午夜刷新连续天数、请假、今日一句。
    func startDayClock() {
        dayClock?.cancel()
        dayClock = Task { [weak self] in
            var day = LocalStore.dayKey(Date())
            var sunAt = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                if self.demoHour == nil, Date().timeIntervalSince(sunAt) >= 5 * 60 {
                    self.updateSun(animated: true)
                    sunAt = Date()
                }
                let k = LocalStore.dayKey(self.now)
                if k != day {
                    day = k
                    self.refreshMe()
                    self.refreshWeatherTip()
                }
            }
        }
    }

    // MARK: - 本地通知（A58）

    /// 自动演示、录视频、开发用嘅 -skipOnboarding 唔弹通知权限框（免得挡住画面）。
    var skipsPermissionPrompt: Bool {
        ["-script", "-script2", "-script3", "-scriptOnboarding", "-captions", "-skipOnboarding"].contains(where: LaunchArgs.has)
    }

    /// 完成首次使用之后先问通知权限（之后每次开 App 都唔会再问，由系统设定管）。
    func requestNotificationsIfReady() {
        guard phase == .main, UserDefaults.standard.bool(forKey: "onboarded"), !skipsPermissionPrompt else { return }
        notifier.requestIfNeeded()
    }

    /// 约会有改动（存盘时）同退后台时重排。演示拉咗时间滑杆（假钟点）就唔排。
    func syncNotifications() {
        guard demoHour == nil else { notifier.sync([]); return }
        notifier.sync(NotificationPlan.items(appointments, now: Date(),
                                             partner: { resident($0)?.name ?? L.t("街坊", "邻居") },
                                             place: { landmark($0)?.name ?? L.t("約好嘅地方", "约好的地方") }))
    }

    // MARK: - 打电话（找人超时卡片）

    func call(_ id: String) {
        guard let p = resident(id) else { return }
        guard let number = PhoneBook.number(for: id), let url = URL(string: "tel:\(number)") else {
            toast(demoMode ? L.t("示範街坊冇電話號碼，真機會直接打俾佢。", "示范邻居没有电话号码，真机会直接打给他。") : L.t("未有\(p.name)嘅電話號碼。", "还没有\(p.name)的电话号码。"))
            return
        }
        // 不用 canOpenURL（要在 Info.plist 声明 tel），直接 open，打不到（模拟器、iPad）再讲。
        UIApplication.shared.open(url) { [weak self] ok in
            if !ok { self?.toast(L.t("呢部機打唔到電話，用手機會直接打俾\(p.name)。", "这台设备打不了电话，用手机会直接打给\(p.name)。")) }
        }
    }
}
