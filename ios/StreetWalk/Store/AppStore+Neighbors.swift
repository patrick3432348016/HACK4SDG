import SwiftUI

// F5 碰一碰、F6 出门提醒
extension AppStore {
    // MARK: - F5 碰一碰

    func startBump() {
        renaming = nil
        // 演示模式先讲清楚点解碰唔到：圈入面冇其他人，同"都係街坊"係两回事（A38）。
        // 真机（2026-10-10）：对方唔使喺圈入面，照碰；过程同二维码后备见 AppStore+Bump。
        if community.isSimulated {
            guard residents.contains(where: { !$0.isMe }) else {
                toast("圈入面暫時只有你。")
                return
            }
            guard residents.contains(where: { !$0.isMe && !$0.isNeighbor }) else {
                toast("圈入面嘅人都已經係你街坊。")
                return
            }
        }
        bumpStage = .searching
        beginBumpSearch()
    }

    /// 碰到咗（演示：示範街坊；真机：addLinkedNeighbor 插好对方之后可以用）：
    /// 两人喺场景并排、语音讲成为街坊、2.6 秒后问开唔开出门提醒。
    func bumpMet(_ r: Resident) {
        Haptics.success()
        bumpStage = .found(r.id)
        say("你同\(r.floor > 0 ? r.floorLabel : "")\(r.name)而家係街坊。")
        syncScene()
        scene.setCamera(target: bumpMeetSpot(), distance: scene.overviewDistance * 0.7, animated: true, duration: 1.0)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard self.bumpStage == .found(r.id) else { return }
            self.remindPromptFor = r.id
            // 问题都要讲出嚟（§4），讲明係双向（F6，A15）。
            self.say("開唔開出門提醒？開咗之後，佢出門你會知，你出門佢都會知。", prompt: true)
        }
    }

    func cancelBump() {
        stopBumpWork()
        bumpQR = nil
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
        say(remind ? "開咗出門提醒，你哋出門都會互相話知（只講地標）。" : "冇問題，之後想開隨時可以。")
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
        // 唔再係街坊：唔好留低佢嘅出门位置，下次碰一碰唔会带出旧位置（A13）。
        residents[i].isOut = false
        residents[i].atLandmarkID = nil
        community.unlinkNeighbor(id)
        storeLink(residents[i])
        // 未完成的约会一并取消（会通知对方约会取消，但唔会讲解除街坊）。
        var cancelled = 0
        for k in appointments.indices where appointments[k].partnerID == id && appointments[k].isOpen {
            appointments[k].status = .cancelled
            community.updateMeetup(appointments[k])
            cancelled += 1
        }
        if case .person(id) = selection { select(nil) }
        syncScene()
        // 同确认框讲法一致（A70）：解除本身唔通知；有约会就讲明对方会收到「約會取消」。
        say(cancelled == 0 ? "已經同\(name)解除街坊，佢唔會收到解除通知。"
            : "已經同\(name)解除街坊，佢唔會收到解除通知；\(cancelled) 個約會已經取消，佢會收到約會取消。")
        Haptics.light()
    }

    // MARK: - F6 出门提醒

    /// 而家喺唔喺接收提醒嘅时段。
    var inRemindWindow: Bool {
        let h = Self.hk.component(.hour, from: now)
        if remindFrom == remindTo { return true }   // 由、到一樣當全日（A66）
        return remindFrom <= remindTo ? (remindFrom..<remindTo).contains(h) : (h >= remindFrom || h < remindTo)
    }

    /// 演示：圈里某人出门（经 CommunityService 送回来，跟真后端一样走 receive）。
    func neighborGoesOut(_ id: String = "chan") {
        guard let r = resident(id), let lm = r.homeLandmarkID ?? landmarks.first?.id else { return }
        // 真后端唔会将非街坊嘅出门送嚟；演示菜单撳咗就讲规则，唔讲楼层同名（A13）。
        guard r.isNeighbor else { toast("示範：佢仲未係你街坊，出門你唔會收到。"); return }
        localCommunity?.simulateOut(id, at: lm)
    }

    func neighborGoesHome(_ id: String = "chan") { localCommunity?.simulateHome(id) }

    func neighborWentOut(_ id: String, at landmarkID: String) {
        // 非街坊：唔记状态、唔提示（永远唔进场景，也唔会知佢出咗门）。
        guard let i = residents.firstIndex(where: { $0.id == id }), residents[i].isNeighbor else { return }
        residents[i].isOut = true
        residents[i].atLandmarkID = landmarkID
        let r = residents[i]
        syncScene()
        guard remindAll, r.receiveRemind, inRemindWindow, let place = placeName(r.atLandmarkID) else { return }
        let text = "\(r.floorLabel)\(r.name)啱啱出門，應該喺\(place)嗰邊。"
        showBanner(BannerItem(symbol: "figure.walk", text: text, action: walk != nil ? .goFind(r.id) : .invite(r.id), actionTitle: walk != nil ? "過去搵佢" : "約佢"))
        say(text)
    }

    func neighborWentHome(_ id: String) {
        guard let i = residents.firstIndex(where: { $0.id == id }), residents[i].isNeighbor else { return }
        residents[i].isOut = false
        residents[i].atLandmarkID = nil
        syncScene()
    }
}
