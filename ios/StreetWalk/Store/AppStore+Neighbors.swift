import SwiftUI

// F5 bump pairing and F6 outing alerts.
extension AppStore {
    // MARK: - F5 bump pairing

    func startBump() {
        renaming = nil
        // A38: explain why pairing is unavailable in demo mode; an empty circle differs from everyone already being a neighbor.
        // Real devices (2026-10-10) can pair outside the circle; see AppStore+Bump for the flow and QR fallback.
        if community.isSimulated {
            guard residents.contains(where: { !$0.isMe }) else {
                toast(L.t("附近暫時只有你。", "附近暂时只有你。", "Only you nearby for now."))
                return
            }
            guard residents.contains(where: { !$0.isMe && !$0.isNeighbor }) else {
                toast(L.t("附近嘅人都已經係你街坊。", "附近的人都已经是你的邻居了。", "Everyone nearby is already your neighbour."))
                return
            }
        }
        bumpStage = .searching
        beginBumpSearch()
    }

    /// After demo pairing, or after addLinkedNeighbor inserts a real peer:
    /// stand together, announce the new relationship, then ask about outing alerts after 2.6 seconds.
    func bumpMet(_ r: Resident) {
        Haptics.success()
        bumpStage = .found(r.id)
        say(L.t("你同\(r.name)而家係街坊。", "你和\(r.name)现在是邻居了。", "You and \(r.name) are now neighbours."))
        syncScene()
        scene.setCamera(target: bumpMeetSpot(), distance: scene.overviewDistance * 0.7, animated: true, duration: 1.0)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard self.bumpStage == .found(r.id) else { return }
            self.remindPromptFor = r.id
            // Speak the question and explain that alerts are bidirectional (section 4, F6, A15).
            self.say(L.t("開唔開出門提醒？開咗之後，佢出門你會知，你出門佢都會知。", "要开出门提醒吗？开了之后，他出门你会知道，你出门他也会知道。", "Turn on out-and-about alerts? You’ll know when they go out, and they’ll know when you do."), prompt: true)
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
        say(remind ? L.t("開咗出門提醒，你哋出門都會互相話知（只講地標）。", "出门提醒开了，你们出门都会互相通知（只说地标）。", "Out-and-about alerts on. You’ll tell each other when you go out (landmark only).") : L.t("冇問題，之後想開隨時可以。", "没问题，之后想开随时可以。", "No problem. You can turn them on any time."))
        if remind { requestNotificationsIfReady() }   // Request notification permission after the first neighbor enables alerts (AppStore+Services).
    }

    /// F6: sending and receiving alerts have separate switches.
    func setRemind(_ id: String, send: Bool? = nil, receive: Bool? = nil) {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        if let send { residents[i].sendRemind = send }
        if let receive { residents[i].receiveRemind = receive }
        community.updateRemind(id, send: residents[i].sendRemind, receive: residents[i].receiveRemind)
        storeLink(residents[i])
    }

    /// F5: remove the local neighbor relationship without notifying the peer; remove them from the map.
    func unlinkNeighbor(_ id: String) {
        guard let i = residents.firstIndex(where: { $0.id == id }) else { return }
        let name = residents[i].name
        residents[i].isNeighbor = false
        residents[i].neighborSince = nil
        // A13: clear former neighbors' outing locations so a future pairing cannot expose stale locations.
        residents[i].isOut = false
        residents[i].atLandmarkID = nil
        community.unlinkNeighbor(id)
        storeLink(residents[i])
        // Cancel unfinished meetings too; the peer receives meeting cancellation, not relationship removal.
        var cancelled = 0
        for k in appointments.indices where appointments[k].partnerID == id && appointments[k].isOpen {
            appointments[k].status = .cancelled
            community.updateMeetup(appointments[k])
            cancelled += 1
        }
        if case .person(id) = selection { select(nil) }
        syncScene()
        // A70: match the confirmation text: removal itself is silent, but existing meetings generate cancellation notices.
        say(cancelled == 0 ? L.t("已經同\(name)解除街坊，佢唔會收到解除通知。", "已和\(name)解除邻居关系，他不会收到解除通知。", "\(name) is no longer your neighbour. They won’t be told.")
            : L.t("已經同\(name)解除街坊，佢唔會收到解除通知；\(cancelled) 個約會已經取消，佢會收到約會取消。", "已和\(name)解除邻居关系，他不会收到解除通知；\(cancelled) 个约会已取消，他会收到约会取消通知。", "\(name) is no longer your neighbour. They won’t be told. \(cancelled) walk plan(s) cancelled. They will get a cancel notice."))
        Haptics.light()
    }

    /// D-3: search nicknames, buildings and floors ignoring spaces, case and simplified/traditional variants; blank matches all.
    func neighbors(matching query: String) -> [Resident] {
        let q = Self.searchKey(query)
        guard !q.isEmpty else { return neighbors }
        return neighbors.filter { r in
            [r.name, r.blockName ?? "", r.placeLabel].contains { Self.searchKey($0).contains(q) }
        }
    }

    nonisolated static func searchKey(_ s: String) -> String {
        let simple = s.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? s
        return simple.lowercased().filter { !$0.isWhitespace }
    }

    // MARK: - F6 outing alerts

    /// Whether the current time falls in the receiving window.
    var inRemindWindow: Bool {
        let h = Self.hk.component(.hour, from: now)
        if remindFrom == remindTo { return true }   // Equal start and end mean all day (A66).
        return remindFrom <= remindTo ? (remindFrom..<remindTo).contains(h) : (h >= remindFrom || h < remindTo)
    }

    /// Demo outing events use CommunityService and the same receive path as the real backend.
    func neighborGoesOut(_ id: String = "chan") {
        guard let r = resident(id), let lm = r.homeLandmarkID ?? landmarks.first?.id else { return }
        // The real backend excludes non-neighbor outings; demo explanations must not expose their names or floors (A13).
        guard r.isNeighbor else { toast(L.t("示範：佢仲未係你街坊，出門你唔會收到。", "示范：他还不是你的邻居，他出门你不会收到。", "Demo: not your neighbour yet, so no alert when they go out.")); return }
        localCommunity?.simulateOut(id, at: lm)
    }

    func neighborGoesHome(_ id: String = "chan") { localCommunity?.simulateHome(id) }

    func neighborWentOut(_ id: String, at landmarkID: String) {
        // Do not store, announce or display outings by non-neighbors.
        guard let i = residents.firstIndex(where: { $0.id == id }), residents[i].isNeighbor else { return }
        residents[i].isOut = true
        residents[i].atLandmarkID = landmarkID
        let r = residents[i]
        syncScene()
        guard remindAll, r.receiveRemind, inRemindWindow, let place = placeName(r.atLandmarkID) else { return }
        let text = L.t("\(r.name)啱啱出門，應該喺\(place)嗰邊。", "\(r.name)刚刚出门，应该在\(place)那边。", "\(r.name) just went out, probably near \(place).")
        showBanner(BannerItem(symbol: "figure.walk", text: text, action: walk != nil ? .goFind(r.id) : .invite(r.id), actionTitle: walk != nil ? L.t("過去搵佢", "过去找他", "Go find them") : L.t("約佢", "约他", "Invite")))
        say(text)
    }

    func neighborWentHome(_ id: String) {
        guard let i = residents.firstIndex(where: { $0.id == id }), residents[i].isNeighbor else { return }
        residents[i].isOut = false
        residents[i].atLandmarkID = nil
        syncScene()
    }
}
