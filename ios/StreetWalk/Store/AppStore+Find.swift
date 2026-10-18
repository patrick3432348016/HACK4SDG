import SwiftUI

// F8 finding.
extension AppStore {
    // MARK: - F8 Scheduled or impromptu finding

    func goFind(_ partnerID: String) {
        guard let p = resident(partnerID), p.isNeighbor else { return }
        guard let lm = landmark(p.atLandmarkID ?? p.homeLandmarkID) else {
            // A real-backend off-map landmark has only a name and cannot supply a local route.
            if let place = placeName(p.atLandmarkID) { toast(L.t("\(p.name)喺\(place)附近，唔喺你附近嘅地圖入面。可以約佢或者打電話。", "\(p.name)在\(place)附近，不在你附近的地图里。可以约他或者打电话。")) }
            return
        }
        // Changing/repeating a request cancels the previous request and clears old acceptance/route state (A22).
        if let old = find { community.cancelFindAsk(partnerID: old.partnerID) }
        banner = nil
        renaming = nil
        selection = nil
        walkingWith = nil
        partnerAgreed = false
        findAppointment = nil
        partnerRoute = nil
        let start = myPosition()
        findRoute = scene.route(from: start, to: scene.nearestWalkable(lm.pos + Vec2(x: -4, y: -3)))
        findTravelled = 0
        let session = FindSession(partnerID: partnerID, landmarkID: lm.id, spontaneous: true, stage: .asking)
        find = session
        scene.setRoute(findRoute)
        scene.highlightLandmark(lm.id)
        syncScene()
        // Ask the peer through CommunityService; demo mode simulates the response.
        let token = session.token
        community.askToFind(partnerID: partnerID, landmarkID: lm.id) { [weak self] accepted in
            self?.findAnswered(token: token, accepted: accepted)
        }
    }

    /// Accept only a reply with the current finding token, never a delayed reply from an older session.
    func findAnswered(token: UUID, accepted: Bool) {
        guard var f = find, f.token == token, f.stage == .asking, !partnerAgreed, let p = resident(f.partnerID) else { return }
        if !accepted {
            f.stage = .declined
            find = f
            say(L.t("\(p.name)而家唔方便。", "\(p.name)现在不方便。"))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if self.find?.token == token { self.endFind() }
            }
            return
        }
        if canShareLive(with: f.partnerID) {
            // For a real neighbor, begin mutual location sharing and arrow guidance immediately after agreement, without another Go tap.
            Haptics.success()
            say(L.t("\(p.name)話好。而家同\(p.name)分享緊位置，跟住箭咀行。", "\(p.name)答应了。正在和\(p.name)共享位置，跟着箭头走。"))
            startGoing()
            return
        }
        say(L.t("\(p.name)話好，喺\(landmark(f.landmarkID)?.name ?? "")等你。撳「去」就出發。", "\(p.name)答应了，在\(landmark(f.landmarkID)?.name ?? "")等你。按「去」就出发。"), prompt: true)
        Haptics.success()
        partnerAgreed = true
    }

    func startGoing() {
        guard var f = find else { return }
        f.stage = .going
        if canShareLive(with: f.partnerID) { startLiveFind(&f) }
        find = f
        findFullScreen = true
        partnerAgreed = false
        scene.followID = nil
        startTicker()
        syncScene()
        if let lm = landmark(f.landmarkID) { frameFind(on: lm.pos) }
    }

    /// Centre the finding camera between self and destination and frame both, addressing UX finding 19.
    func frameFind(on spot: Vec2) {
        let me = myPosition()
        let mid = (me + spot) * 0.5
        let span = Float(me.distance(to: spot))
        // Portrait orthographic framing needs more distance to include both people: from 0.8× overview at close range to 2× at maximum.
        let d = min(scene.overviewDistance * 2, max(scene.overviewDistance * 0.8, scene.overviewDistance * span / 50))
        scene.setCamera(target: mid, distance: d, animated: true, duration: 1.0)
    }

    func departForAppointment(_ a: Appointment) {
        // Depart only for an agreed meetup with a current neighbor; non-neighbors never enter the scene.
        guard a.status == .accepted, let p = resident(a.partnerID), p.isNeighbor else { return }
        guard let lm = landmark(a.landmarkID) else { toast(L.t("搵唔到約會個地點（地圖更新咗），撳「改時間地點」揀過。", "找不到约会地点（地图更新了），按「改时间地点」重新选。")); return }
        if let old = find { community.cancelFindAsk(partnerID: old.partnerID) }
        renaming = nil
        selection = nil
        walkingWith = nil
        let start = myPosition()
        findRoute = scene.route(from: start, to: scene.nearestWalkable(lm.pos + Vec2(x: -4, y: -3)))
        // Before peer departure, keep them out of the scene and remember only the simulated route origin (A19/A67).
        let theirStart = scene.nearestWalkable((landmark(p.homeLandmarkID)?.pos ?? lm.pos) + Vec2(x: 30, y: 25))
        partnerRoute = [theirStart]
        findTravelled = 0
        partnerTravelled = 0
        partnerAgreed = false
        findAppointment = a.id
        var session = FindSession(partnerID: p.id, landmarkID: lm.id, spontaneous: false, stage: .going, partnerOut: false)
        startLiveFind(&session)
        find = session
        findFullScreen = true
        scene.setRoute(findRoute)
        scene.highlightLandmark(lm.id)
        syncScene()
        startTicker()
        frameFind(on: lm.pos)
        say(session.live ? L.t("今日約咗\(p.name)喺\(lm.name)。而家同\(p.name)分享緊位置。", "今天约了\(p.name)在\(lm.name)。正在和\(p.name)共享位置。") : L.t("今日約咗\(p.name)喺\(lm.name)。等緊\(p.name)出門。", "今天约了\(p.name)在\(lm.name)。在等\(p.name)出门。"))
        let myMinutes = max(1, Int((pathLength(findRoute ?? []) / 70).rounded(.up)))
        let token = session.token
        community.departForMeetup(a.id, etaMinutes: myMinutes) { [weak self] trip in
            self?.partnerUpdate(token: token, trip: trip)
        }
    }

    /// First peer progress means departure: add them to the scene, begin movement, and state their estimated arrival.
    /// Later minutes/arrival updates align the simulated position with the reported progress; local demo may report only once.
    func partnerUpdate(token: UUID, trip: PartnerTrip) {
        guard var f = find, f.token == token, !f.spontaneous, f.stage != .met, let p = resident(f.partnerID),
              let lm = landmark(f.landmarkID) else { return }
        let departing = !f.partnerOut
        if departing {
            guard let start = partnerRoute?.first else { return }
            partnerRoute = scene.route(from: start, to: scene.nearestWalkable(lm.pos + Vec2(x: 5, y: 3)))
            partnerTravelled = 0
            f.partnerOut = true
        }
        let total = pathLength(partnerRoute ?? [])
        let wasThere = partnerTravelled >= total
        if trip.arrived { partnerTravelled = total }
        else if let m = trip.etaMinutes { partnerTravelled = min(total, max(0, total - Double(m) * 70)) }
        // Without reported minutes in a local demo, estimate from the simulated route.
        f.etaMinutes = trip.arrived ? 0 : trip.etaMinutes ?? max(1, Int(((total - partnerTravelled) / 70).rounded(.up)))
        find = f
        if departing {
            syncScene()
            say(trip.arrived ? L.t("\(p.name)已經喺\(lm.name)等你。", "\(p.name)已经在\(lm.name)等你。") : L.t("\(p.name)出咗門，大約 \(f.etaMinutes) 分鐘到\(lm.name)。", "\(p.name)出门了，大约 \(f.etaMinutes) 分钟到\(lm.name)。"))
        } else if trip.arrived && !wasThere {
            say(L.t("\(p.name)到咗\(lm.name)。", "\(p.name)到\(lm.name)了。"))
        }
    }

    func tickFind(_ f: inout FindSession, _ dt: Double) {
        if f.live { tickLiveFind(&f); return }
        guard f.stage == .going || f.stage == .near, let route = findRoute else { return }
        findTravelled = min(pathLength(route), findTravelled + dt * Self.findSpeed)
        if !f.spontaneous, f.partnerOut, let pr = partnerRoute { partnerTravelled = min(pathLength(pr), partnerTravelled + dt * Self.findSpeed * 0.8) }
        let mePos = point(along: route, at: findTravelled).0
        let spot = landmark(f.landmarkID).map { scene.nearestWalkable($0.pos + Vec2(x: 5, y: 3)) } ?? mePos
        // Impromptu finding targets a waiting landmark. Before scheduled peer departure, point toward the meeting place rather than an absent person.
        let partnerPos = f.spontaneous || !f.partnerOut ? spot : point(along: partnerRoute ?? [spot], at: partnerTravelled).0
        let d = mePos.distance(to: partnerPos)
        f.distance = d
        // ETA (A67): scheduled flow reports the peer's remaining trip to the meeting point; impromptu flow reports my remaining trip.
        if f.spontaneous {
            f.etaMinutes = max(0, Int(((pathLength(route) - findTravelled) / 70).rounded(.up)))
        } else if f.partnerOut, let pr = partnerRoute {
            f.etaMinutes = max(0, Int(((pathLength(pr) - partnerTravelled) / 70).rounded(.up)))
        }
        // Screen-up is northwest because the camera faces from southeast; subtract 315 degrees from bearing.
        let bearing = atan2(partnerPos.x - mePos.x, partnerPos.y - mePos.y) * 180 / .pi
        f.bearing = bearing - 315
        // A peer who has not departed cannot be nearby or found.
        if d <= 50 && f.stage == .going && f.partnerOut {
            f.stage = .near
            Haptics.success()
            say(L.t("\(resident(f.partnerID)?.name ?? "")喺附近，跟住箭咀行。", "\(resident(f.partnerID)?.name ?? "")在附近，跟着箭头走。"))
        }
        let partnerThere = f.spontaneous || (f.partnerOut && partnerTravelled >= pathLength(partnerRoute ?? []))
        if f.partnerOut && (d <= 9 || (findTravelled >= pathLength(route) && partnerThere)) {
            f.stage = .met
            Haptics.success()
            say(L.t("見到喇！", "看到了！"))
            if let id = findAppointment, let i = appointments.firstIndex(where: { $0.id == id }) { appointments[i].status = .done }
            walkingWith = f.partnerID
            let finished = f
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if self.find == finished || self.find?.stage == .met { self.endFind() }
            }
            return
        }
        checkLate(&f)
    }

    /// F8: after ten minutes past the meetup without meeting, offer a call once per meetup (A20).
    func checkLate(_ f: inout FindSession) {
        guard !f.spontaneous, f.stage != .met, !f.latePrompt, let id = findAppointment,
              let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].status == .accepted,
              appointments[i].lateAsked != true, now.timeIntervalSince(appointments[i].date) > 600 else { return }
        appointments[i].lateAsked = true
        f.latePrompt = true
        // Without a phone number, suggest looking nearby rather than offering an unusable call action.
        let name = resident(f.partnerID)?.name ?? ""
        let next = PhoneBook.number(for: f.partnerID) != nil ? L.t("要唔要打電話俾佢？", "要不要给他打电话？") : L.t("喺附近搵吓。", "在附近找找。")
        say(L.t("過咗約定時間 10 分鐘，仲未見到\(name)。", "过了约定时间 10 分钟，还没见到\(name)。") + next, prompt: true)
    }

    /// Demo advances to eleven minutes late so automatic checking triggers the prompt, rather than opening the card directly.
    func lateDemo() {
        guard let f = find, !f.spontaneous, let id = findAppointment, let a = appointments.first(where: { $0.id == id }) else {
            toast(L.t("示範：約好咗、撳咗「出發」先用得。", "示范：约好了、按了「出发」才能用。"))
            return
        }
        setDemoHour(a.date.timeIntervalSince(Self.hk.startOfDay(for: Date())) / 3600 + 11.0 / 60)
    }

    /// Relay the confirmed original phrase. Button wording distinguishes being at the meetup place from approaching it in impromptu finding (A11).
    func broadcastHere(_ text: String? = nil) {
        guard var f = find else { return }
        // Real finding can lack a local landmark, especially for the waiting/off-map peer; still relay the original phrase.
        guard let msg = text ?? landmark(f.landmarkID).map({ f.spontaneous ? L.t("我就到\($0.name)", "我马上到\($0.name)") : L.t("我喺\($0.name)", "我在\($0.name)") }) else { return }
        f.broadcast = msg
        find = f
        community.broadcast(to: f.partnerID, text: msg)
        say(L.t("已經話俾\(resident(f.partnerID)?.name ?? "")知：\(msg)。", "已经告诉\(resident(f.partnerID)?.name ?? "")：\(msg)。"))
        Haptics.light()
    }

    // MARK: - Shared finding primary action (UX 19/22)

    enum FindStep: Equatable { case depart, almost, waiting, met }

    /// Stages: departed → nearly there → found; the waiting peer uses waiting here → found.
    func findStep(_ f: FindSession) -> FindStep {
        if f.stage == .near || f.stage == .met { return .met }
        if f.incoming { return f.told == 0 ? .waiting : .met }
        switch f.told {
        case 0: return .depart
        case 1: return .almost
        default: return .met
        }
    }

    func findStepTitle(_ s: FindStep) -> String {
        switch s {
        case .depart: return L.t("出發喇", "出发了")
        case .almost: return L.t("我就到", "我马上到")
        case .waiting: return L.t("我喺度等你", "我在这儿等你")
        case .met: return L.t("見到喇", "见到了")
        }
    }

    /// Earlier primary actions relay status; the final found action ends the session.
    func findStepTapped() {
        guard let f = find, f.stage != .met else { return }
        let place = placeName(f.landmarkID)
        switch findStep(f) {
        case .depart:
            broadcastHere(L.t("我出發喇", "我出发了"))
            find?.told = 1
        case .almost:
            broadcastHere(place.map { L.t("我就到\($0)", "我马上到\($0)") } ?? L.t("我就到", "我马上到"))
            find?.told = 2
        case .waiting:
            broadcastHere(L.t("我喺度等你", "我在这儿等你"))
            find?.told = 1
        case .met:
            if f.live { liveMetTapped() } else { findMetTapped() }
        }
    }

    /// Demo found confirmation follows automatic arrival behavior and dismisses after three seconds.
    func findMetTapped() {
        guard var f = find, !f.live, f.stage != .met else { return }
        f.stage = .met
        f.etaMinutes = 0
        Haptics.success()
        say(L.t("見到喇！", "看到了！"))
        if let id = findAppointment, let i = appointments.firstIndex(where: { $0.id == id }) { appointments[i].status = .done }
        walkingWith = f.partnerID
        find = f
        let token = f.token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if self.find?.token == token { self.endFind() }
        }
    }

    func endFind() {
        if let f = find {
            if f.live { stopLiveFind(notify: true, met: f.stage == .met) }
            community.cancelFindAsk(partnerID: f.partnerID)
            if let id = findAppointment { community.endMeetupTrip(id, met: f.stage == .met) }
        }
        find = nil
        findFullScreen = false
        findRoute = nil
        partnerRoute = nil
        findAppointment = nil
        partnerAgreed = false
        // Do not leave a landmark card open after finding ends (UX 23).
        selection = nil
        renaming = nil
        scene.setRoute(nil)
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
        if walk != nil, walkDetector.recording {
            // During a real walk, keep following location rather than animating a return home.
            walk?.route = walkDetector.trail.isEmpty ? [myPosition()] : walkDetector.trail
            walk?.travelled = pathLength(walk?.route ?? [])
            scene.followID = "me"
        } else if walk != nil {
            // After simulated finding, continue the walk from the current position toward home.
            let here = myPosition()
            walk?.route = scene.route(from: here, to: scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18)))
            walk?.travelled = 0
            scene.followID = "me"
            startTicker()
        } else {
            scene.resetCamera()
        }
        syncScene()
    }

    /// Demo: LocalCommunityService rejects the next finding/invitation request to Mrs Chan.
    func declineNextAsk() { localCommunity?.declineNext = true }
}
