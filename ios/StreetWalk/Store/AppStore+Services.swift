import UIKit

// Wire real weather, device walk detection, local notifications and telephone calls.
extension AppStore {
    /// StreetWalkApp calls on scenePhase foreground/background transitions and startup, excluding inactive.
    func appActive(_ active: Bool) {
        backendAppActive(active)   // Real backend: reconnect Realtime and refresh in foreground; disconnect and schedule refresh in background.
        liveFind?.setForeground(active)   // Send live finding coordinates only in foreground (AppStore+LiveFind).
        if active {
            ensureMeBeforeMap()
            refreshLiveWeather()
            hko.keepFresh(true) { [weak self] in self?.refreshLiveWeather() }
            startWalkDetection()
            // A34: refresh sun, daily status and meeting reminders after returning from an absence.
            updateSun(animated: false)
            refreshMe()
            if map != nil { checkAppointments() }   // Wait for populate if the map has not loaded, avoiding nameless reminders.
            startDayClock()
            locationAppActive()     // Permissions, home region, overnight location and Always-permission explanation (AppStore+Location).
        } else {
            endConversation()   // Continuous conversation stops local microphone capture immediately on backgrounding.
            hush()              // Stop speech in background; walking alerts use system notifications.
            // A76: save immediately on backgrounding instead of waiting 0.5 seconds, preserving the last change before termination.
            saveTask?.cancel()
            saveNow()
            syncNotifications()
            dayClock?.cancel()
            hko.keepFresh(false) {}
            markBackground()
            // Continue background location while recording or awaiting a walk; otherwise stop until a home-departure wake event.
            if !walkDetector.staysAwakeInBackground { walkDetector.stop() }
        }
    }

    /// Foreground minute tick: update actual sunlight every 5 minutes; refresh streaks, leave and daily greetings after midnight.
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

    // MARK: - Local notifications (A58)

    /// Suppress permission prompts for automatic demos, recordings and developer -skipOnboarding flows.
    var skipsPermissionPrompt: Bool {
        ["-script", "-script2", "-script3", "-scriptOnboarding", "-captions", "-skipOnboarding"].contains(where: LaunchArgs.has)
    }

    /// UX issue 24: ask for notification permission only when a neighbor enables outing alerts or a meeting exists.
    /// Ask once; later changes use system Settings.
    func requestNotificationsIfReady() {
        guard phase == .main, UserDefaults.standard.bool(forKey: "onboarded"), !skipsPermissionPrompt else { return }
        guard neighbors.contains(where: \.receiveRemind) || appointments.contains(where: \.isOpen) else { return }
        notifier.requestIfNeeded()
    }

    /// Reschedule after meeting changes and backgrounding; suppress scheduling under the demo time slider.
    func syncNotifications() {
        guard demoHour == nil else { notifier.sync([]); return }
        notifier.sync(NotificationPlan.items(appointments, now: Date(),
                                             partner: { resident($0)?.name ?? L.t("街坊", "邻居", "Neighbour") },
                                             place: { landmark($0)?.name ?? L.t("約好嘅地方", "约好的地方", "the meeting spot") }))
    }

    // MARK: - Telephone calls from finding-timeout cards

    func call(_ id: String) {
        guard let p = resident(id) else { return }
        guard let number = PhoneBook.number(for: id), let url = URL(string: "tel:\(number)") else {
            toast(demoMode ? L.t("示範街坊冇電話號碼，真機會直接打俾佢。", "示范邻居没有电话号码，真机会直接打给他。", "Demo neighbours have no phone number. On a real phone this calls them.") : L.t("未有\(p.name)嘅電話號碼。", "还没有\(p.name)的电话号码。", "No phone number for \(p.name) yet."))
            return
        }
        // Open tel directly without canOpenURL's Info.plist requirement; explain failure on simulator or unsupported devices.
        UIApplication.shared.open(url) { [weak self] ok in
            if !ok { self?.toast(L.t("呢部機打唔到電話，用手機會直接打俾\(p.name)。", "这台设备打不了电话，用手机会直接打给\(p.name)。", "This device can’t make calls. On a phone it calls \(p.name).")) }
        }
    }
}
