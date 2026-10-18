import SwiftUI

/// -videoShot <shot> with -demo -videoClean records a short flow per shot for later editing.
/// Shot names from the historical demo_video_script: scene / walk / board / bump / alert / voice / invited / find / report / care.
/// Log each step with a [video] timestamp to align with recordings.
extension AppStore {
    private static var videoStarted = false

    func runVideoShotIfNeeded() {
        guard !Self.videoStarted, let shot = LaunchArgs.value("-videoShot") else { return }
        Self.videoStarted = true
        if shot == "lang" {
            // Welcome language selector (-resetOnboarding -lang yue): Cantonese, Mandarin, English.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.0)); AppLanguage.shared.set(.cmn); print("[video] Mandarin")
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
            /// Sweep sunlight from from to to in 60 steps over seconds.
            @MainActor func sweep(_ from: Double, _ to: Double, seconds: Double) async {
                for i in 0...60 {
                    setDemoHour(from + (to - from) * Double(i) / 60)
                    try? await Task.sleep(for: .seconds(seconds / 60))
                }
            }
            // Choose the currently shadiest bench landmark for the Seats here / Shady now card.
            let seatSpot = landmarks.filter(\.hasSeat).max { (shadeValue($0.id, at: now) ?? 0) < (shadeValue($1.id, at: now) ?? 0) }?.id ?? landmarks.first?.id
            switch shot {
            case "scene":
                await step(0.5, "Scene") { tab = .today }
            case "walk":
                await step(1.5, "Go out") { startWalk() }
                await step(9, "Building shade sweep") {}
                await sweep(8, 17.5, seconds: 2.6)
                await step(12.5, "Return to current time") { setDemoHour(LaunchArgs.hour ?? 10) }
                await step(13.5, "Landmark card") { if let id = seatSpot { select(.landmark(id)) } }
                await step(20, "End") {}
            case "board":
                await step(0.5, "Rankings") { tab = .board }
            case "bump":
                await step(0.5, "Neighbors screen") { tab = .neighbors }
                await step(2, "Pair phones") { startBump() }
                // Wait for simulated pairing and the outing-alert prompt 2.6 seconds after bumpMet.
                while remindPromptFor == nil, Date().timeIntervalSince(t0) < 30 { try? await Task.sleep(for: .milliseconds(200)) }
                print("[video] t=\(Date().timeIntervalSince(t0)) Ask about outing alerts")
            case "alert":
                await step(0.2, "Become neighbors") { createNeighbor("chan", remind: true); banner = nil }
                await step(0.5, "Today") { tab = .today }
                await step(2.5, "Mrs Chan goes out") { neighborGoesOut("chan") }
            case "voice":
                let line = LaunchArgs.value("-videoLine") ?? "聽日三點約陳太去公園行吓"
                await step(0.2, "Become neighbors") { createNeighbor("chan", remind: true); banner = nil; tab = .today }
                await step(1.5, "Tap microphone") { listening = true; heardPartial = "" }
                for (i, ch) in line.enumerated() {
                    await step(2.2 + Double(i) * 0.22, "Text") { heardPartial.append(ch) }
                }
                await step(2.2 + Double(line.count) * 0.22 + 0.8, "Speech finished") { listening = false; heardPartial = ""; handle(line) }
                await step(2.2 + Double(line.count) * 0.22 + 7.5, "Confirm") { confirmVoice() }
            case "invited":
                // Mrs Chan's phone uses -nickname "Mrs Chan"; Uncle Lee invites her tomorrow at three, with -videoPlace matching his landmark.
                let want = LaunchArgs.value("-videoPlace")
                let place = landmarks.first { $0.id == want || $0.name == want }?.id ?? seatSpot ?? ""
                await step(0.2, "Become neighbors") { createNeighbor("lee", remind: true); banner = nil; tab = .today }
                var id = UUID()
                await step(2, "Mr Lee invites you") {
                    let a = Appointment(partnerID: "lee", date: Self.today(at: 15, dayOffset: 1), landmarkID: place,
                                        reason: L.t("嗰陣有樓遮，有櫈坐", "那时有楼遮阴，有凳子", "Shaded by buildings then, seats here"), status: .waiting, fromPartner: true)
                    id = a.id
                    localCommunity?.simulateInvite(a)
                }
                await step(7.5, "Accept") { banner = nil; acceptInvitation(id) }
            case "find":
                await step(0.2, "Meetup agreed") {
                    createNeighbor("chan", remind: true); banner = nil; tab = .today
                    appointments.insert(Appointment(partnerID: "chan", date: now.addingTimeInterval(30 * 60), landmarkID: seatSpot ?? "",
                                                    reason: "", status: .accepted), at: 0)
                }
                await step(1.5, "Departure reminder") { checkAppointments() }
                await step(5.5, "Depart") { banner = nil; if let a = appointments.first(where: { $0.status == .accepted }) { departForAppointment(a) } }
            case "report":
                await step(0.5, "Go out") { startWalk() }
                await step(5, "Too sunny here") { handle(LaunchArgs.value("-videoLine") ?? "Too sunny here") }
                await step(10, "Monthly report") { banner = nil; showReport = true }
            case "care":
                await step(0.5, "Settings") { showSettings = true }
                await step(2.5, "Large text") { TextSizeSetting.shared.set(.large) }
                await step(3.3, "Extra large") { TextSizeSetting.shared.set(.xlarge) }
                await step(5, "Mandarin") { AppLanguage.shared.set(.cmn) }
                await step(6.5, "Cantonese") { AppLanguage.shared.set(.yue) }
                await step(8, "English") { AppLanguage.shared.set(.en) }
                await step(9.5, "Close settings") { showSettings = false; TextSizeSetting.shared.set(.standard) }
                await step(11, "Fall scenario") { handle("I fell") }
            default:
                print("[video] Unknown shot: \(shot)")
            }
        }
    }
}
