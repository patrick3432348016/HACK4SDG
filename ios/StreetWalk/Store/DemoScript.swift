import SwiftUI

/// -script runs the main flows in sequence for checking and recording.
/// Log [script] timestamps and steps for screenshot alignment.
extension AppStore {
    private static var scriptStarted = false

    func runScriptIfNeeded() {
        guard !Self.scriptStarted else { return }
        if LaunchArgs.has("-videoShot") { Self.scriptStarted = true; runVideoShotIfNeeded(); return }   // DemoScript+Video
        if LaunchArgs.has("-script2") { Self.scriptStarted = true; runScript2(); return }
        if LaunchArgs.has("-script3") { Self.scriptStarted = true; runScript3(); return }
        if LaunchArgs.has("-autoWalk") { Self.scriptStarted = true; runAutoWalk(); return }
        if LaunchArgs.has("-scriptWalk") { Self.scriptStarted = true; runScriptWalk(); return }
        #if DEBUG
        if LaunchArgs.has("-scriptBump") { Self.scriptStarted = true; runScriptBump(); return }   // DemoScript+Bump
        if LaunchArgs.has("-scriptIsland") { Self.scriptStarted = true; runScriptIsland(); return }   // DemoScript+Island
        #endif
        guard LaunchArgs.has("-script") else { return }
        Self.scriptStarted = true
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            let t0 = Date()
            // Require @MainActor so execution after sleep cannot mutate store / scene on a background thread and cause races or missing UI updates.
            @MainActor func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[script] t=\(Int(at)) \(name)")
                action()
            }
            // -captions shows Chinese and English recording subtitles.
            @MainActor func cap(_ zh: String, _ en: String) { if LaunchArgs.has("-captions") { caption = L.isEn ? (en, "") : (zh, en) } }   // Avoid withAnimation; see showBanner.
            await step(1, "Opening") { cap(L.t("北都新屋邨：每日行嘅路，就係認識街坊嘅地方", "北部都会区新屋苑：每天走的路，就是认识邻居的地方", "New estates in the Northern Metropolis: your daily walk is where neighbours meet"), "New estates in the Northern Metropolis: your daily walk is where neighbours meet") }
            await step(4, "Rankings") { tab = .board; cap(L.t("排行榜：同區常行嘅人；未係街坊只見網名同小人", "排行榜：同区常走的人；还不是邻居只看到网名和小人", "Leaderboard: regular walkers nearby. Non-neighbours show only a nickname and avatar"), "Circle board: regular walkers nearby — strangers show only a nickname and avatar") }
            await step(9, "Neighbors: pairing") { tab = .neighbors; startBump(); cap(L.t("碰一碰：兩部手機貼近，就成為街坊", "碰一碰：两部手机靠近，就成为邻居", "Tap phones to become neighbours"), "Bump phones to become neighbours — the only way to connect") }
            await step(19, "Enable outing alerts") { createNeighbor("chan", remind: true); cap(L.t("成為街坊時問一次：開唔開出門提醒", "成为邻居时问一次：开不开出门提醒", "Asked once: turn on out-and-about alerts?"), "Opt in to going-out alerts, once") }
            await step(22, "Today: Mrs Chan goes out") { tab = .today; neighborGoesOut("chan"); cap(L.t("街坊出門：只講地標，唔顯示地圖坐標", "邻居出门：只说地标，不显示地图坐标", "A neighbour heads out: shown by landmark, never coordinates"), "A neighbour heads out — shown by landmark, never coordinates") }
            await step(28, "Start walk") { banner = nil; startWalk(); cap(L.t("出門自動記錄散步，唔使撳任何掣", "出门自动记录散步，不用按任何按钮", "Walks are recorded automatically, no buttons"), "Walks are recorded automatically — no buttons") }
            await step(36, "Find Mrs Chan") { goFind("chan"); cap(L.t("散步中一撳：先問對方方唔方便", "散步中一按：先问对方方不方便", "One tap on a walk: the app asks your neighbour first"), "Drop by: the app asks your neighbour first") }
            await step(41, "Go") { startGoing(); cap(L.t("50 米內震動，大箭咀指住對方，唔用地圖", "50 米内震动，大箭头指着对方，不用地图", "Within 50 m: buzz and a big arrow, no map"), "Within 50 m: haptics and a big arrow, no map") }
            await step(62, "Invite Mrs Chan by voice") { cap(L.t("講一句就約好：AI 揀有樓遮、有櫈、兩個都近嘅地方", "说一句就约好：AI 选有楼遮阴、有凳子、离两人都近的地方", "Say one sentence: AI picks a shady spot with seats, near you both"), "Say one sentence — AI picks a shaded spot with seats, near you both") ; handle(L.t("約陳太聽日下晝三點一齊行", "约陈太明天下午三点一起走", "Invite 陳太 for a walk tomorrow 3 pm")) }
            await step(68, "Confirm") { confirmVoice() }
            await step(73, "Accept") { cap(L.t("影響別人嘅動作，一定先複述再按「好」", "影响别人的操作，一定先复述再按「好的」", "Anything that affects others is read back first"), "Anything that affects others is read back for confirmation first") }
            await step(79, "Weather and shade") { banner = nil; setDemoHour(15); setWeather(.hot); cap(L.t("天文台天氣 + 樓影遮蔭：建議幾點出門", "天文台天气 + 楼影遮阴：建议几点出门", "Observatory weather + building shade: when to head out"), "HK Observatory weather + building shade: when to head out") }
            await step(87, "Report: too sunny here") { banner = nil; report(.sunny); cap(L.t("講一句「呢度好曬」，記低喺最近嘅地標", "说一句「这里太晒」，记在最近的地标", "Say “too sunny here”: it is pinned to the nearest landmark"), "Say \"too sunny here\" — it's pinned to the nearest landmark") }
            await step(92, "Month-end report") { showReport = true; cap(L.t("月報：只出多位街坊嘅匿名匯總，交社工同屋邨管理", "月报：只出多位邻居的匿名汇总，交社工和屋苑管理", "Monthly report: anonymous, several residents only, for social workers and estate management"), "Monthly report: anonymous, several residents only, for social workers & estate management") }
            await step(101, "End") { showReport = false; caption = nil }
        }
    }
}

extension AppStore {
    /// -autoWalk runs a demo walk without finding and logs stopping places / records to check F1.
    func runAutoWalk() {
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
            startWalk()
            var seen = 0
            while walk != nil {
                try? await Task.sleep(for: .milliseconds(250))
                for id in track.stopIDs.dropFirst(seen) { print("[autoWalk] Stop: \(landmark(id)?.name ?? id) t=\(walk?.minutes ?? 0)") }
                seen = max(seen, track.stopIDs.count)
            }
            let l = log(for: now)
            print("[autoWalk] Finished: \(l.minutes) minutes; stops: \(l.stops.compactMap { landmark($0)?.name }); summary: \(me.todayLine)")
        }
    }
}

extension AppStore {
    /// -scriptWalk checks leave intervals, alert windows, disabling demo and cancelling / stepping back through home changes.
    /// Restore the alert window and demo mode afterward because they persist in UserDefaults.
    func runScriptWalk() {
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            let t0 = Date()
            @MainActor func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[scriptWalk] t=\(Int(at)) \(name)")
                action()
            }
            let (from, to) = (remindFrom, remindTo)
            await step(1, "Three days off") { tab = .today; requestLeave(days: 3) }
            await step(4, "Day off tomorrow") { withdrawLeave(); _ = requestLeave(fromVoice: L.t("聽日請假", "明天请假", "Day off tomorrow")) }
            await step(7, "Demo time and very hot weather") { withdrawLeave(); setDemoHour(15); setWeather(.hot) }
            await step(10, "Settings: same start and end time") { banner = nil; remindFrom = 21; remindTo = 21; showSettings = true }
            await step(14, "Disable demo mode") { setDemoMode(false) }
            await step(17, "Return to main screen") { showSettings = false }
            await step(21, "Change building") { remindFrom = from; remindTo = to; setDemoMode(true); beginChangeHome() }
            while phase != .onboarding(.pickHome) { try? await Task.sleep(for: .milliseconds(200)) }
            await step(27, "Select building") { if let b = residentialBuildings().first(where: { $0.name != nil }) { pickHome(b.id) } }
            await step(30, "Confirm") { confirmHome() }
            await step(34, "Go back one step") { backToPickHome() }
            await step(38, "Cancel change") { cancelChangeHome() }
            // Cancel during location loading; a late remote map result must not replace the saved home tile and building.
            await step(44, "Change building again") { beginChangeHome() }
            await step(44.3, "Cancel during location lookup") { print("[scriptWalk] phase=\(phase) loadingMap=\(loadingMap)"); cancelChangeHome() }
            await step(56, "Check diorama base") {
                let saved = (UserDefaults.standard.object(forKey: "homeBuilding") as? NSNumber)?.int64Value
                let tile = UserDefaults.standard.string(forKey: "homeTile") ?? "-"
                print("[scriptWalk] Base \(map.map { "\($0.tile.ix),\($0.tile.iy)" } ?? "-") (home tile \(tile)) building \(scene.homeBuildingID.map(String.init) ?? "-") (saved \(saved.map(String.init) ?? "-")) \(phase)")
            }
            await step(58, "End") {}
        }
    }
}

extension AppStore {
    /// Second script: Neighbors, landmark card, examples, voice recap, time slider and bump waiting.
    func runScript2() {
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
            createNeighbor("chan", remind: true)
            neighborGoesOut("chan")
            banner = nil
            let t0 = Date()
            @MainActor func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[script2] t=\(Int(at)) \(name)")
                action()
            }
            await step(2, "Neighbors screen") { tab = .neighbors }
            await step(2.6, "Mrs Chan invites you") { partnerInvites("chan") }
            await step(7, "Landmark information card") { banner = nil; select(.landmark(landmarks.first?.id ?? "")) }
            await step(11, "Rename") { renaming = selection.flatMap { if case .landmark(let id) = $0 { return id } else { return nil } } }
            await step(15, "Choose a phrase") { select(nil); phrasePicker = true }
            await step(19, "Voice recap card") { handle(L.t("約陳太聽日下晝三點一齊行", "约陈太明天下午三点一起走", "Invite 陳太 for a walk tomorrow 3 pm")) }
            await step(23, "Time slider") { rejectVoice(); showTimeSlider = true }
            await step(28, "Waiting to pair") { showTimeSlider = false; residents.indices.forEach { if !residents[$0].isMe && residents[$0].id != "chan" { residents[$0].isNeighbor = false } }; startBump() }
            await step(31, "End") { }
        }
    }
}

/// -resetOnboarding -scriptOnboarding walks through onboarding for screen inspection.
/// Five steps: welcome, privacy consent, locate/select home, floor/nickname, example microphone trial, then completion.
extension AppStore {
    func runOnboardingScriptIfNeeded() {
        guard LaunchArgs.has("-scriptOnboarding") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            print("[script] Start"); onbHush(); phase = .onboarding(.consent)
            try? await Task.sleep(for: .seconds(4))
            print("[script] Consent"); onbHush(); consent()
            try? await Task.sleep(for: .seconds(3))
            if !loadingMap && map == nil { print("[script] Confirm location lookup"); onbHush(); startLocating() }
            while map == nil || loadingMap || phase != .onboarding(.pickHome) { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(4))
            if let id = pendingHome {
                print("[script] Suggested building: \(map?.building(id: id)?.name ?? "\(id)")")
            } else if let b = residentialBuildings().first(where: { $0.name != nil }) ?? residentialBuildings().first {
                print("[script] Select building"); pickHome(b.id)
                try? await Task.sleep(for: .seconds(3))
            }
            print("[script] Confirm home"); onbHush(); confirmHome()
            try? await Task.sleep(for: .seconds(3))
            print("[script] Floor and nickname"); floorChoice = min(12, max(1, homeLevels))
            setNickname(nickname.isEmpty ? (LaunchArgs.value("-nickname") ?? "行路友") : nickname)   // -debugNickname was already applied at startup.
            try? await Task.sleep(for: .seconds(3))
            print("[script] Try once"); onbHush(); phase = .onboarding(.tryMic)
            try? await Task.sleep(for: .seconds(4))
            print("[script] Tap the weather example"); NotificationCenter.default.post(name: .onbTryPhrase, object: nil)
            try? await Task.sleep(for: .seconds(6))
            print("[script] Complete"); onbHush(); finishOnboarding()
        }
    }
}

extension AppStore {
    // MARK: - Demo

    /// A35: Reload Map clears cache and refetches the home tile while retaining the saved building.
    func regenerateHere() {
        walk = nil; if find != nil { endFind() }; findFullScreen = false; track = WalkTrack()
        TileCache.clear()
        let home = (UserDefaults.standard.object(forKey: "homeBuilding") as? NSNumber)?.int64Value
        Task { await loadMap(home: home, animated: true) }
    }

    func resetDemo() {
        ticker?.cancel()
        walk = nil; if find != nil { endFind() }; findFullScreen = false; proposal = nil; voiceCard = nil; banner = nil; track = WalkTrack()
        weather = .normal; weatherTip = nil; demoHour = LaunchArgs.hour
        resetDemoData()
        scene.setRoute(nil); scene.setTrail([]); scene.highlightLandmark(nil); scene.followID = nil
        populate()
        updateSun(animated: true)
        scene.resetCamera()
        useLiveWeather()
    }
}

extension AppStore {
    /// -script3 covers meeting lifecycle, voice reschedule, report replies, departure reminders, expiry and unlinking.
    /// Results persist; launch again without a script to check restoration.
    func runScript3() {
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            let t0 = Date()
            @MainActor func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[script3] t=\(Int(at)) \(name)")
                action()
            }
            await step(1, "Pair and invite Mrs Chan") { createNeighbor("chan", remind: true); proposeMeetup(with: "chan") }
            await step(4, "Confirm") { confirmProposal() }
            await step(10, "Accepted: Today screen") { banner = nil; tab = .today }
            await step(13, "Voice: change to 5 pm") { handle(L.t("改做下晝五點", "改到下午五点", "Change to 5 pm")) }
            await step(17, "Confirm") { confirmVoice() }
            await step(23, "Rename landmark and report") { banner = nil; if let id = landmarks.first?.id { rename(id, to: "大樹底") }; report(.noSeat) }
            await step(26, "Estate management reply") { simulateFollowUp() }
            await step(33, "Mrs Chan invites you: Neighbors screen") { banner = nil; tab = .neighbors; partnerInvites("chan") }
            await step(38, "Reschedule card") { banner = nil; if let a = todaysAppointments.first { startEditing(a.id) } }
            await step(42, "Rankings") { cancelProposal(); tab = .board }
            await step(46, "4:36 pm departure reminder") { tab = .today; setDemoHour(16.6) }
            await step(52, "6:12 pm expiration") { banner = nil; setDemoHour(18.2) }
            await step(57, "Remove neighbor") { tab = .neighbors; unlinkNeighbor("chan") }
            await step(62, "Settings") { saveNow(); showSettings = true }
            await step(68, "End") { showSettings = false }
        }
    }
}
