import SwiftUI

/// 自动演示：启动参数 `-script` 时按顺序跑一遍主要流程，用于检查和录演示视频。
/// 每一步打印 "[script] t=秒 步骤"，方便对照截图。
extension AppStore {
    private static var scriptStarted = false

    func runScriptIfNeeded() {
        guard !Self.scriptStarted else { return }
        if LaunchArgs.has("-script2") { Self.scriptStarted = true; runScript2(); return }
        if LaunchArgs.has("-script3") { Self.scriptStarted = true; runScript3(); return }
        if LaunchArgs.has("-autoWalk") { Self.scriptStarted = true; runAutoWalk(); return }
        if LaunchArgs.has("-scriptWalk") { Self.scriptStarted = true; runScriptWalk(); return }
        guard LaunchArgs.has("-script") else { return }
        Self.scriptStarted = true
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            let t0 = Date()
            // 必须 @MainActor：否则 sleep 之后在后台线程恢复，脚本动作会在后台改 store 和场景（界面不刷新、数据竞争）。
            @MainActor func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[script] t=\(Int(at)) \(name)")
                action()
            }
            // 字幕（-captions）：中文一句 + 英文一句，配合录屏。
            @MainActor func cap(_ zh: String, _ en: String) { if LaunchArgs.has("-captions") { withAnimation(DS.motion(DS.snappy)) { caption = (zh, en) } } }
            await step(1, "開場") { cap("北都新屋邨：每日行嘅路，就係認識街坊嘅地方", "New estates in the Northern Metropolis: your daily walk is where neighbours meet") }
            await step(4, "排行榜") { tab = .board; cap("排行榜：同區常行嘅人；未係街坊只見樓層", "Circle board: regular walkers nearby — strangers show only their floor") }
            await step(9, "街坊 · 碰一碰") { tab = .neighbors; startBump(); cap("碰一碰：兩部手機貼近，就成為街坊", "Bump phones to become neighbours — the only way to connect") }
            await step(19, "開出門提醒") { createNeighbor("chan", remind: true); cap("成為街坊時問一次：開唔開出門提醒", "Opt in to going-out alerts, once") }
            await step(22, "今日 · 陳太出門") { tab = .today; neighborGoesOut("chan"); cap("街坊出門：只講地標，唔顯示地圖坐標", "A neighbour heads out — shown by landmark, never coordinates") }
            await step(28, "出門散步") { banner = nil; startWalk(); cap("出門自動記錄散步，唔使撳任何掣", "Walks are recorded automatically — no buttons") }
            await step(36, "過去搵陳太") { goFind("chan"); cap("散步中一撳：先問對方方唔方便", "Drop by: the app asks your neighbour first") }
            await step(41, "去") { startGoing(); cap("50 米內震動，大箭咀指住對方，唔用地圖", "Within 50 m: haptics and a big arrow, no map") }
            await step(62, "語音約陳太") { cap("講一句就約好：AI 揀有樓遮、有櫈、兩個都近嘅地方", "Say one sentence — AI picks a shaded spot with seats, near you both") ; handle("約陳太聽日下晝三點一齊行") }
            await step(68, "好") { confirmVoice() }
            await step(73, "應承") { cap("影響別人嘅動作，一定先複述再按「好」", "Anything that affects others is read back for confirmation first") }
            await step(79, "天氣 + 遮蔭") { banner = nil; setDemoHour(15); setWeather(.hot); cap("天文台天氣 + 樓影遮蔭：建議幾點出門", "HK Observatory weather + building shade: when to head out") }
            await step(87, "反映：呢度好曬") { banner = nil; report(.sunny); cap("講一句「呢度好曬」，記低喺最近嘅地標", "Say \"too sunny here\" — it's pinned to the nearest landmark") }
            await step(92, "月尾報告") { showReport = true; cap("月報：只出 10 人以上嘅匿名匯總，交社工同屋邨管理", "Monthly report: anonymous, 10+ residents only, for social workers & estate management") }
            await step(101, "完") { showReport = false; caption = nil }
        }
    }
}

extension AppStore {
    /// 开发用（-autoWalk）：自动行一次演示散步（唔搵人），打印落脚点同记低嘅纪录，检查 F1 落脚点。
    func runAutoWalk() {
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
            startWalk()
            var seen = 0
            while walk != nil {
                try? await Task.sleep(for: .milliseconds(250))
                for id in track.stopIDs.dropFirst(seen) { print("[autoWalk] 落腳點 \(landmark(id)?.name ?? id) t=\(walk?.minutes ?? 0)") }
                seen = max(seen, track.stopIDs.count)
            }
            let l = log(for: now)
            print("[autoWalk] 完 \(l.minutes) 分鐘 落腳點 \(l.stops.compactMap { landmark($0)?.name }) 一句：\(me.todayLine)")
        }
    }
}

extension AppStore {
    /// 开发用（-scriptWalk）：请假几日、提醒时段、关演示模式、改楼途中返上一步同「唔改」，逐步截图检查。
    /// 跑完会还原提醒时段同演示模式（佢哋存喺 UserDefaults）。
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
            await step(1, "請 3 日假") { tab = .today; requestLeave(days: 3) }
            await step(4, "聽日請假") { withdrawLeave(); _ = requestLeave(fromVoice: "聽日請假") }
            await step(7, "演示時間 + 酷熱") { withdrawLeave(); setDemoHour(15); setWeather(.hot) }
            await step(10, "設定：由、到一樣") { banner = nil; remindFrom = 21; remindTo = 21; showSettings = true }
            await step(14, "關演示模式") { setDemoMode(false) }
            await step(17, "返主畫面") { showSettings = false }
            await step(21, "改樓") { remindFrom = from; remindTo = to; setDemoMode(true); beginChangeHome() }
            while phase != .onboarding(.pickHome) { try? await Task.sleep(for: .milliseconds(200)) }
            await step(27, "揀樓") { if let b = residentialBuildings().first(where: { $0.name != nil }) { pickHome(b.id) } }
            await step(30, "確認") { confirmHome() }
            await step(34, "返上一步") { backToPickHome() }
            await step(38, "唔改") { cancelChangeHome() }
            // 定位一步就按「唔改」（人喺外面时嗰格要上网拉，旧嘅 loadMap 会迟啲先返）：最后要係屋企格、已存嘅楼
            await step(44, "再改樓") { beginChangeHome() }
            await step(44.3, "定位中按唔改") { print("[scriptWalk] phase=\(phase) loadingMap=\(loadingMap)"); cancelChangeHome() }
            await step(56, "檢查底座") {
                let saved = (UserDefaults.standard.object(forKey: "homeBuilding") as? NSNumber)?.int64Value
                let tile = UserDefaults.standard.string(forKey: "homeTile") ?? "-"
                print("[scriptWalk] 底座 \(map.map { "\($0.tile.ix),\($0.tile.iy)" } ?? "-")（屋企格 \(tile)）樓 \(scene.homeBuildingID.map(String.init) ?? "-")（已存 \(saved.map(String.init) ?? "-")）\(phase)")
            }
            await step(58, "完") {}
        }
    }
}

extension AppStore {
    /// 第二段：街坊页、地标信息卡、揀一句、语音复述卡、时间滑杆、碰一碰等待画面。
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
            await step(2, "街坊頁") { tab = .neighbors }
            await step(2.6, "陳太約你") { partnerInvites("chan") }
            await step(7, "地標資料卡") { banner = nil; select(.landmark(landmarks.first?.id ?? "")) }
            await step(11, "改名") { renaming = selection.flatMap { if case .landmark(let id) = $0 { return id } else { return nil } } }
            await step(15, "揀一句") { select(nil); phrasePicker = true }
            await step(19, "語音複述卡") { handle("約陳太聽日下晝三點一齊行") }
            await step(23, "時間滑杆") { rejectVoice(); showTimeSlider = true }
            await step(28, "碰一碰等待") { showTimeSlider = false; residents.indices.forEach { if !residents[$0].isMe && residents[$0].id != "chan" { residents[$0].isNeighbor = false } }; startBump() }
            await step(31, "完") { }
        }
    }
}

/// 自动走一遍首次使用（启动参数 `-resetOnboarding -scriptOnboarding`），用于检查每一步的画面。
extension AppStore {
    func runOnboardingScriptIfNeeded() {
        guard LaunchArgs.has("-scriptOnboarding") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            print("[script] 同意"); consent()
            while map == nil || loadingMap { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(4))
            if let b = residentialBuildings().first(where: { $0.name != nil }) ?? residentialBuildings().first { print("[script] 揀樓"); pickHome(b.id) }
            try? await Task.sleep(for: .seconds(4))
            print("[script] 確認"); confirmHome()
            try? await Task.sleep(for: .seconds(4))
            print("[script] 揀小人"); floorChoice = 12; phase = .onboarding(.avatar)
            try? await Task.sleep(for: .seconds(2))
            mobilityChoice = .cane
            try? await Task.sleep(for: .seconds(3))
            print("[script] 完成"); finishOnboarding()
        }
    }
}

extension AppStore {
    // MARK: - 演示

    /// 演示菜单「重新載入地圖」：清缓存再拉一次（有存过屋企就係屋企嗰格），住嘅楼照用已存嘅（A35）。
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
    /// 第三段（-script3）：约会生命周期、语音改约、反映回覆、出发前提醒、过期、解除街坊。
    /// 跑完数据会存盘；之后不带脚本再开一次，可以检查重启后有没有保留。
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
            await step(1, "做街坊 + 約陳太") { createNeighbor("chan", remind: true); proposeMeetup(with: "chan") }
            await step(4, "好") { confirmProposal() }
            await step(10, "應承咗 · 今日頁") { banner = nil; tab = .today }
            await step(13, "語音：改做下晝五點") { handle("改做下晝五點") }
            await step(17, "好") { confirmVoice() }
            await step(23, "改地標名 + 反映") { banner = nil; if let id = landmarks.first?.id { rename(id, to: "大樹底") }; report(.noSeat) }
            await step(26, "屋邨管理回覆") { simulateFollowUp() }
            await step(33, "陳太約你（街坊頁）") { banner = nil; tab = .neighbors; partnerInvites("chan") }
            await step(38, "改約卡") { banner = nil; if let a = todaysAppointments.first { startEditing(a.id) } }
            await step(42, "排行榜") { cancelProposal(); tab = .board }
            await step(46, "下晝 4:36 · 出發提醒") { tab = .today; setDemoHour(16.6) }
            await step(52, "夜晚 6:12 · 過期") { banner = nil; setDemoHour(18.2) }
            await step(57, "解除街坊") { tab = .neighbors; unlinkNeighbor("chan") }
            await step(62, "設定") { saveNow(); showSettings = true }
            await step(68, "完") { showSettings = false }
        }
    }
}
