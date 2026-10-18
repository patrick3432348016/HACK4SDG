import SwiftUI

/// 录宣传片（-videoShot <镜头>，配 -demo -videoClean）：每个镜头一段短流程，逐段录屏再剪。
/// 镜头对应 docs/pitch/demo_video_script.md：scene / walk / board / bump / alert / voice / invited / find / report / care。
/// 每一步打印 "[video] t=秒 步骤"，方便对照录屏。
extension AppStore {
    private static var videoStarted = false

    func runVideoShotIfNeeded() {
        guard !Self.videoStarted, let shot = LaunchArgs.value("-videoShot") else { return }
        Self.videoStarted = true
        if shot == "lang" {
            // 欢迎页顶部嘅语言切换（-resetOnboarding -lang yue）：粵語 → 普通话 → English
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.0)); AppLanguage.shared.set(.cmn); print("[video] 普通话")
                try? await Task.sleep(for: .seconds(1.6)); AppLanguage.shared.set(.en); print("[video] English")
            }
            return
        }
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            let t0 = Date()
            @MainActor func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[video] t=\(at) \(name)")
                action()
            }
            /// 太阳慢慢扫过：由 from 点拉到 to 点，seconds 秒内分 60 步。
            @MainActor func sweep(_ from: Double, _ to: Double, seconds: Double) async {
                for i in 0...60 {
                    setDemoHour(from + (to - from) * Double(i) / 60)
                    try? await Task.sleep(for: .seconds(seconds / 60))
                }
            }
            // 有凳、而家最多楼遮嘅地标（地标卡出「Seats here」「Shady now」）
            let seatSpot = landmarks.filter(\.hasSeat).max { (shadeValue($0.id, at: now) ?? 0) < (shadeValue($1.id, at: now) ?? 0) }?.id ?? landmarks.first?.id
            switch shot {
            case "scene":
                await step(0.5, "場景") { tab = .today }
            case "walk":
                await step(1.5, "出門") { startWalk() }
                await step(9, "楼影扫过") {}
                await sweep(8, 17.5, seconds: 2.6)
                await step(12.5, "返而家") { setDemoHour(LaunchArgs.hour ?? 10) }
                await step(13.5, "地標卡") { if let id = seatSpot { select(.landmark(id)) } }
                await step(20, "完") {}
            case "board":
                await step(0.5, "排行榜") { tab = .board }
            case "bump":
                await step(0.5, "街坊頁") { tab = .neighbors }
                await step(2, "碰一碰") { startBump() }
                // 等模拟碰到、问开唔开出门提醒（bumpMet 2.6 秒后）
                while remindPromptFor == nil, Date().timeIntervalSince(t0) < 30 { try? await Task.sleep(for: .milliseconds(200)) }
                print("[video] t=\(Date().timeIntervalSince(t0)) 問出門提醒")
            case "alert":
                await step(0.2, "做街坊") { createNeighbor("chan", remind: true); banner = nil }
                await step(0.5, "今日") { tab = .today }
                await step(2.5, "陳太出門") { neighborGoesOut("chan") }
            case "voice":
                let line = LaunchArgs.value("-videoLine") ?? "聽日三點約陳太去公園行吓"
                await step(0.2, "做街坊") { createNeighbor("chan", remind: true); banner = nil; tab = .today }
                await step(1.5, "撳咪") { listening = true; heardPartial = "" }
                for (i, ch) in line.enumerated() {
                    await step(2.2 + Double(i) * 0.22, "字") { heardPartial.append(ch) }
                }
                await step(2.2 + Double(line.count) * 0.22 + 0.8, "聽完") { listening = false; heardPartial = ""; handle(line) }
                await step(2.2 + Double(line.count) * 0.22 + 7.5, "好") { confirmVoice() }
            case "invited":
                // 陳太部手机：-nickname "Mrs Chan"；李伯约佢听日三点（-videoPlace 用李伯嗰边揀嘅地标）
                let want = LaunchArgs.value("-videoPlace")
                let place = landmarks.first { $0.id == want || $0.name == want }?.id ?? seatSpot ?? ""
                await step(0.2, "做街坊") { createNeighbor("lee", remind: true); banner = nil; tab = .today }
                var id = UUID()
                await step(2, "李伯約你") {
                    let a = Appointment(partnerID: "lee", date: Self.today(at: 15, dayOffset: 1), landmarkID: place,
                                        reason: L.t("嗰陣有樓遮，有櫈坐", "那时有楼遮阴，有凳子", "Shaded by buildings then, seats here"), status: .waiting, fromPartner: true)
                    id = a.id
                    localCommunity?.simulateInvite(a)
                }
                await step(7.5, "應承") { banner = nil; acceptInvitation(id) }
            case "find":
                await step(0.2, "約好") {
                    createNeighbor("chan", remind: true); banner = nil; tab = .today
                    appointments.insert(Appointment(partnerID: "chan", date: now.addingTimeInterval(30 * 60), landmarkID: seatSpot ?? "",
                                                    reason: "", status: .accepted), at: 0)
                }
                await step(1.5, "出發提醒") { checkAppointments() }
                await step(5.5, "出發") { banner = nil; if let a = appointments.first(where: { $0.status == .accepted }) { departForAppointment(a) } }
            case "report":
                await step(0.5, "出門") { startWalk() }
                await step(5, "呢度好曬") { handle(LaunchArgs.value("-videoLine") ?? "Too sunny here") }
                await step(10, "月報") { banner = nil; showReport = true }
            case "care":
                await step(0.5, "設定") { showSettings = true }
                await step(2.5, "大字") { TextSizeSetting.shared.set(.large) }
                await step(3.3, "特大") { TextSizeSetting.shared.set(.xlarge) }
                await step(5, "普通话") { AppLanguage.shared.set(.cmn) }
                await step(6.5, "粵語") { AppLanguage.shared.set(.yue) }
                await step(8, "English") { AppLanguage.shared.set(.en) }
                await step(9.5, "收設定") { showSettings = false; TextSizeSetting.shared.set(.standard) }
                await step(11, "跌親") { handle("I fell") }
            default:
                print("[video] 唔識呢個鏡頭：\(shot)")
            }
        }
    }
}
