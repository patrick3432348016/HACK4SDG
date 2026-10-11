#if DEBUG
import Foundation

/// 开发用（-scriptIsland）：喺模拟器检查灵动岛。用真实时钟（唔好加 -hour），等实时活动自己倒数。
/// - `-scriptIsland walk`：即刻出门散步（岛两侧「🚶 N 分」；撳 Home 键后真·灵动岛同锁屏）。
/// - `-scriptIsland meet`：同陳太约咗 20 分钟后（出发提醒横幅由岛长出嚟、收埋后两侧「20 分鐘後」）。
/// - `-scriptIsland find`：散步中过去搵陳太（两侧「35 米」+ 箭咀；搵人全屏时收埋，返主画面再出）。
/// - `-scriptIsland banner`：每 4 秒出一个横幅（逐帧睇展开、收埋、换句）。
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
                let lines = [("figure.walk", L.t("8 樓陳太啱啱出門，應該喺涼亭嗰邊。", "8 楼陳太刚刚出门，应该在涼亭那边。")), ("checkmark.circle.fill", L.t("陳太應承咗聽日下晝三點喺涼亭一齊行。", "陳太答应了明天下午三点在涼亭一起走。")),
                             ("sun.max.fill", L.t("今日酷熱，下晝三點後涼亭有樓影，可以嗰陣先出門。", "今天酷热，下午三点后涼亭有楼影，可以那时再出门。"))]
                for (k, l) in lines.enumerated() {
                    await step(2 + Double(k) * 4, "橫幅 \(k)") {
                        showBanner(BannerItem(symbol: l.0, text: l.1, action: k == 0 ? .invite("chan") : .none, actionTitle: k == 0 ? L.t("約佢", "约她") : nil))
                    }
                }
                await step(16, "收埋") { banner = nil }
                await step(18, "出門") { startWalk() }
                await step(22, "出門時有橫幅") { showBanner(BannerItem(symbol: "chair.lounge.fill", text: L.t("行慢咗少少。前面涼亭有櫈，可以唞陣。", "走慢了一点。前面涼亭有凳子，可以歇一会。"))) }
            default:
                await step(2, "出門") { startWalk() }
            }
        }
    }
}
#endif
