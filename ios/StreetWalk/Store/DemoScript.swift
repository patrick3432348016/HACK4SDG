import Foundation

/// 自动演示：启动参数 `-script` 时按顺序跑一遍主要流程，用于检查和录演示视频。
/// 每一步打印 "[script] t=秒 步骤"，方便对照截图。
extension AppStore {
    private static var scriptStarted = false

    func runScriptIfNeeded() {
        guard !Self.scriptStarted else { return }
        if LaunchArgs.has("-script2") { Self.scriptStarted = true; runScript2(); return }
        if LaunchArgs.has("-script3") { Self.scriptStarted = true; runScript3(); return }
        guard LaunchArgs.has("-script") else { return }
        Self.scriptStarted = true
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            let t0 = Date()
            func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[script] t=\(Int(at)) \(name)")
                action()
            }
            await step(3, "排行榜") { tab = .board }
            await step(7, "街坊 · 碰一碰") { tab = .neighbors; startBump() }
            await step(17, "開出門提醒") { createNeighbor("chan", remind: true) }
            await step(20, "今日 · 陳太出門") { tab = .today; neighborGoesOut("chan") }
            await step(26, "出門散步") { startWalk() }
            await step(34, "過去搵陳太") { goFind("chan") }
            await step(39, "去") { startGoing() }
            await step(62, "約陳太") { proposeMeetup(with: "chan") }
            await step(66, "換個時間") { nextProposalTime() }
            await step(69, "好") { confirmProposal() }
            await step(76, "酷熱 + 下晝三點") { setDemoHour(15); setWeather(.hot) }
            await step(83, "反映：呢度好曬") { report(.sunny) }
            await step(88, "月尾報告") { showReport = true }
            await step(94, "完") { showReport = false }
        }
    }
}

extension AppStore {
    /// 第二段：街坊页、地标信息卡、揀一句、语音复述卡、时间滑杆、碰一碰等待画面。
    func runScript2() {
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            createNeighbor("chan", remind: true)
            neighborGoesOut("chan")
            banner = nil
            let t0 = Date()
            func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[script2] t=\(Int(at)) \(name)")
                action()
            }
            await step(2, "街坊頁 + 陳太約你") { tab = .neighbors; partnerInvites("chan") }
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
            if let b = residentialBuildings().first(where: { $0.name != nil }) { print("[script] 揀樓"); pickHome(b.id) }
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

    func regenerateHere() {
        walk = nil; find = nil; findFullScreen = false
        TileCache.clear()
        Task { await loadMap(home: nil, animated: true) }
    }

    func resetDemo() {
        ticker?.cancel()
        walk = nil; find = nil; findFullScreen = false; proposal = nil; voiceCard = nil; banner = nil
        weather = .normal; weatherTip = nil; demoHour = LaunchArgs.hour
        clearAllData()
        scene.setRoute(nil); scene.setTrail([]); scene.highlightLandmark(nil); scene.followID = nil
        populate()
        updateSun(animated: true)
        scene.resetCamera()
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
