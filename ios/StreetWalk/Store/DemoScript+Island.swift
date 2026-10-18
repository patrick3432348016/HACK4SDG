#if DEBUG
import Foundation

/// -scriptIsland checks Dynamic Island in the simulator; omit -hour so Live Activities use the actual clock.
/// -scriptIsland walk starts walking immediately; inspect island side labels, then the real island and Lock Screen after Home.
/// -scriptIsland meet schedules Mrs Chan in 20 minutes and exercises reminder expansion and countdown side labels.
/// -scriptIsland find approaches Mrs Chan during a walk; distance / arrow hide in full-screen finding and return on the main screen.
/// -scriptIsland banner emits a banner every 4 seconds for frame-by-frame animation inspection.
extension AppStore {
    func runScriptIsland() {
        let mode = LaunchArgs.value("-scriptIsland") ?? "walk"
        Task { @MainActor in
            while map == nil || residents.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            let t0 = Date()
            @MainActor func step(_ at: Double, _ name: String, _ action: () -> Void) async {
                let wait = at - Date().timeIntervalSince(t0)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                print("[scriptIsland] t=\(at) \(name)")
                action()
            }
            await step(0.5, "做街坊") { createNeighbor("chan", remind: true) }
            switch mode {
            case "meet":
                await step(2, "約咗 20 分鐘後") {
                    let date = Date().addingTimeInterval(20 * 60 + 30)
                    appointments.append(Appointment(partnerID: "chan", date: date, landmarkID: landmarks.first?.id ?? "", reason: "", status: .accepted))
                    checkAppointments()
                }
            case "find":
                await step(2, "出門") { startWalk() }
                await step(5, "過去搵陳太") { neighborGoesOut("chan"); goFind("chan") }
                await step(9, "去") { startGoing() }
                await step(14, "返主畫面") { findFullScreen = false }
            case "banner":
                let lines = [("figure.walk", L.t("8 樓陳太啱啱出門，應該喺涼亭嗰邊。", "8 楼陳太刚刚出门，应该在涼亭那边。", "陳太 (8/F) just went out, probably near 涼亭.")), ("checkmark.circle.fill", L.t("陳太應承咗聽日下晝三點喺涼亭一齊行。", "陳太答应了明天下午三点在涼亭一起走。", "陳太 said yes: walk at 涼亭, tomorrow 3 pm.")),
                             ("sun.max.fill", L.t("今日酷熱，下晝三點後涼亭有樓影，可以嗰陣先出門。", "今天酷热，下午三点后涼亭有楼影，可以那时再出门。", "Very hot today. 涼亭 is shaded after 3 pm. Go out then."))]
                for (k, l) in lines.enumerated() {
                    await step(2 + Double(k) * 4, "橫幅 \(k)") {
                        showBanner(BannerItem(symbol: l.0, text: l.1, action: k == 0 ? .invite("chan") : .none, actionTitle: k == 0 ? L.t("約佢", "约她", "Invite") : nil))
                    }
                }
                await step(16, "收埋") { banner = nil }
                await step(18, "出門") { startWalk() }
                await step(22, "出門時有橫幅") { showBanner(BannerItem(symbol: "chair.lounge.fill", text: L.t("行慢咗少少。前面涼亭有櫈，可以唞陣。", "走慢了一点。前面涼亭有凳子，可以歇一会。", "Slowing down a bit. Seats at 涼亭 ahead. Take a rest."))) }
            default:
                await step(2, "出門") { startWalk() }
            }
        }
    }
}
#endif
