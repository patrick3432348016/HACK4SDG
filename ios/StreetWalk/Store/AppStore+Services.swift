import UIKit

// 真实服务的接线：天文台天气、真机散步检测、打电话
extension AppStore {
    /// 回到前台 / 退到后台（StreetWalkApp 按 scenePhase 调用，启动时也会来一次；.inactive 不调）。
    func appActive(_ active: Bool) {
        if active {
            refreshLiveWeather()
            hko.keepFresh(true) { [weak self] in self?.refreshLiveWeather() }
            startWalkDetection()
        } else {
            hko.keepFresh(false) {}
            walkDetector.stop()
        }
    }

    // MARK: - 打电话（找人超时卡片）

    func call(_ id: String) {
        guard let p = resident(id) else { return }
        guard let number = PhoneBook.number(for: id), let url = URL(string: "tel:\(number)") else {
            toast(demoMode ? "示範街坊冇電話號碼，真機會直接打俾佢。" : "未有\(p.name)嘅電話號碼。")
            return
        }
        // 不用 canOpenURL（要在 Info.plist 声明 tel），直接 open，打不到（模拟器、iPad）再讲。
        UIApplication.shared.open(url) { [weak self] ok in
            if !ok { self?.toast("呢部機打唔到電話，用手機會直接打俾\(p.name)。") }
        }
    }
}
