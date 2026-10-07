import SwiftUI

// F5 碰一碰、F6 出门提醒
extension AppStore {
    // MARK: - F5 碰一碰

    func startBump() {
        bumpStage = .searching
        bump.startSearching(candidates: residents) { [weak self] r in
            guard let self else { return }
            Haptics.success()
            self.bumpStage = .found(r.id)
            self.speaker.speak("你同\(r.floorLabel)\(r.name)而家係街坊。")
            self.syncScene()
            self.scene.setCamera(target: self.scene.homeTarget + Vec2(x: 0, y: -18), distance: self.scene.overviewDistance * 0.7, animated: true, duration: 1.0)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.6))
                self.remindPromptFor = r.id
            }
        }
        if case .searching = bumpStage, residents.allSatisfy({ $0.isMe || $0.isNeighbor }) {
            bumpStage = .idle
            toast("圈入面嘅人都已經係你街坊")
        }
    }

    func cancelBump() {
        bump.cancel()
        bumpStage = .idle
        syncScene()
    }

    func createNeighbor(_ residentID: String, remind: Bool) {
        guard let i = residents.firstIndex(where: { $0.id == residentID }) else { return }
        residents[i].isNeighbor = true
        residents[i].sendRemind = remind
        residents[i].receiveRemind = remind
        remindPromptFor = nil
        bumpStage = .idle
        syncScene()
        scene.resetCamera()
        speaker.speak(remind ? "開咗出門提醒。" : "冇問題，之後想開隨時可以。")
    }

    func setRemind(_ id: String, _ on: Bool) {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        residents[i].receiveRemind = on
        residents[i].sendRemind = on
    }

    // MARK: - F6 出门提醒

    func neighborGoesOut(_ id: String = "chan") {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        residents[i].isOut = true
        residents[i].atLandmarkID = residents[i].homeLandmarkID
        let r = residents[i]
        guard r.isNeighbor else {
            toast("\(r.floorLabel)出咗門，但佢未係你街坊，所以地圖上唔會見到佢。")
            return
        }
        syncScene()
        guard r.receiveRemind, let lm = landmark(r.atLandmarkID) else { return }
        let text = "\(r.floorLabel)\(r.name)啱啱出門，應該喺\(lm.name)嗰邊。"
        showBanner(BannerItem(symbol: "figure.walk", text: text, action: walk != nil ? .goFind(r.id) : .invite(r.id), actionTitle: walk != nil ? "過去搵佢" : "約佢"))
        speaker.speak(text)
    }
}
