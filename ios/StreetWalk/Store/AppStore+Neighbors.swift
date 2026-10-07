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
        residents[i].neighborSince = Date()
        residents[i].sendRemind = remind
        residents[i].receiveRemind = remind
        community.linkNeighbor(residentID, send: remind, receive: remind)
        storeLink(residents[i])
        remindPromptFor = nil
        bumpStage = .idle
        syncScene()
        scene.resetCamera()
        speaker.speak(remind ? "開咗出門提醒。" : "冇問題，之後想開隨時可以。")
    }

    /// F6：发送、接收可以分开开关。
    func setRemind(_ id: String, send: Bool? = nil, receive: Bool? = nil) {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        if let send { residents[i].sendRemind = send }
        if let receive { residents[i].receiveRemind = receive }
        community.updateRemind(id, send: residents[i].sendRemind, receive: residents[i].receiveRemind)
        storeLink(residents[i])
    }

    /// F5：解除街坊。只删自己这边，对方不会收到通知；佢之后喺地图上唔会再出现。
    func unlinkNeighbor(_ id: String) {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        let name = residents[i].name
        residents[i].isNeighbor = false
        residents[i].neighborSince = nil
        community.unlinkNeighbor(id)
        storeLink(residents[i])
        // 未完成的约会一并取消（会通知对方约会取消，但唔会讲解除街坊）。
        for k in appointments.indices where appointments[k].partnerID == id && appointments[k].isOpen {
            appointments[k].status = .cancelled
            community.updateMeetup(appointments[k])
        }
        if case .person(id) = selection { select(nil) }
        syncScene()
        speaker.speak("已經同\(name)解除街坊。佢唔會收到通知。")
        Haptics.light()
    }

    // MARK: - F6 出门提醒

    /// 而家喺唔喺接收提醒嘅时段。
    var inRemindWindow: Bool {
        let h = Calendar.current.component(.hour, from: now)
        return remindFrom <= remindTo ? (remindFrom..<remindTo).contains(h) : (h >= remindFrom || h < remindTo)
    }

    /// 演示：圈里某人出门（经 CommunityService 送回来，跟真后端一样走 receive）。
    func neighborGoesOut(_ id: String = "chan") {
        guard let r = resident(id), let lm = r.homeLandmarkID ?? landmarks.first?.id else { return }
        localCommunity?.simulateOut(id, at: lm)
    }

    func neighborGoesHome(_ id: String = "chan") { localCommunity?.simulateHome(id) }

    func neighborWentOut(_ id: String, at landmarkID: String) {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        residents[i].isOut = true
        residents[i].atLandmarkID = landmarkID
        let r = residents[i]
        guard r.isNeighbor else {
            // 非街坊永远不进场景，也不会收到佢嘅位置。
            toast("\(r.floorLabel)出咗門，但佢未係你街坊，所以地圖上唔會見到佢。")
            return
        }
        syncScene()
        guard remindAll, r.receiveRemind, inRemindWindow, let lm = landmark(r.atLandmarkID) else { return }
        let text = "\(r.floorLabel)\(r.name)啱啱出門，應該喺\(lm.name)嗰邊。"
        showBanner(BannerItem(symbol: "figure.walk", text: text, action: walk != nil ? .goFind(r.id) : .invite(r.id), actionTitle: walk != nil ? "過去搵佢" : "約佢"))
        speaker.speak(text)
    }

    func neighborWentHome(_ id: String) {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        residents[i].isOut = false
        residents[i].atLandmarkID = nil
        syncScene()
    }
}
