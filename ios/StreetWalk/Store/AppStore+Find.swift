import SwiftUI

// F8 找人
extension AppStore {
    // MARK: - F8 找人（约好的当天 / 散步中临时）

    func goFind(_ partnerID: String) {
        guard let p = resident(partnerID), p.isNeighbor else { return }
        guard let lm = landmark(p.atLandmarkID ?? p.homeLandmarkID) else {
            // 真后端：佢喺我地图外面嘅地标（只有名），带唔到路
            if let place = placeName(p.atLandmarkID) { toast(L.t("\(p.name)喺\(place)附近，唔喺你附近嘅地圖入面。可以約佢或者打電話。", "\(p.name)在\(place)附近，不在你附近的地图里。可以约他或者打电话。")) }
            return
        }
        // 换人 / 再问：撤回上一个询问，清走上次留低嘅「話好」同约会路线（A22）。
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
        // 先问对方（经 CommunityService；单机由示範街坊模拟回覆）。
        let token = session.token
        community.askToFind(partnerID: partnerID, landmarkID: lm.id) { [weak self] accepted in
            self?.findAnswered(token: token, accepted: accepted)
        }
    }

    /// 对方答咗：只认同一次找人（token），旧嘅回覆唔会落到新一次。
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
            // 真街坊：即刻一齐分享位置、跟箭咀去搵佢（唔使再撳「去」）
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

    /// 找人镜头：对准「我」同目的地中间，拉远到两个都睇到（UX 评审 19：以前「你」喺画面外）。
    func frameFind(on spot: Vec2) {
        let me = myPosition()
        let mid = (me + spot) * 0.5
        let span = Float(me.distance(to: spot))
        // 全屏系竖嘅（正交镜头按高度计），要拉远啲先阔到包住两个人：相距越远镜头越远，最近同以前一样（总览 0.8），最远两倍总览。
        let d = min(scene.overviewDistance * 2, max(scene.overviewDistance * 0.8, scene.overviewDistance * span / 50))
        scene.setCamera(target: mid, distance: d, animated: true, duration: 1.0)
    }

    func departForAppointment(_ a: Appointment) {
        // 只有约好咗、对方仍然係街坊先可以出发（非街坊永远唔入场景）。
        guard a.status == .accepted, let p = resident(a.partnerID), p.isNeighbor else { return }
        guard let lm = landmark(a.landmarkID) else { toast(L.t("搵唔到約會個地點（地圖更新咗），撳「改時間地點」揀過。", "找不到约会地点（地图更新了），按「改时间地点」重新选。")); return }
        if let old = find { community.cancelFindAsk(partnerID: old.partnerID) }
        renaming = nil
        selection = nil
        walkingWith = nil
        let start = myPosition()
        findRoute = scene.route(from: start, to: scene.nearestWalkable(lm.pos + Vec2(x: -4, y: -3)))
        // 对方未出门：唔入场景（syncScene 只画出咗门嘅对方），呢度只记低模拟路线嘅起点（A19 / A67）。
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

    /// 对方嘅进度（CommunityService 通知，可以多次）。第一次 = 出咗门：先入场景、开始行，讲大约几耐到。
    /// 之后嘅分钟数 / 到咗：将模拟位置拉到同佢讲嘅一致（单机只报一次，之后靠模拟路线）。
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
        // 对方冇传分钟数（单机模拟）就按佢条路估。
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
        // 临时找人：对方喺地标等。约会未出门：箭咀指去约定地方（对方唔喺场景，A19）。
        let partnerPos = f.spontaneous || !f.partnerOut ? spot : point(along: partnerRoute ?? [spot], at: partnerTravelled).0
        let d = mePos.distance(to: partnerPos)
        f.distance = d
        // 到达估计（A67）：约会讲对方仲要几耐到约定地方（0 = 已经喺度等）；临时找人讲我仲要几耐到。
        if f.spontaneous {
            f.etaMinutes = max(0, Int(((pathLength(route) - findTravelled) / 70).rounded(.up)))
        } else if f.partnerOut, let pr = partnerRoute {
            f.etaMinutes = max(0, Int(((pathLength(pr) - partnerTravelled) / 70).rounded(.up)))
        }
        // 屏幕上方 = 西北（相机从东南看），所以把方位角减 315°。
        let bearing = atan2(partnerPos.x - mePos.x, partnerPos.y - mePos.y) * 180 / .pi
        f.bearing = bearing - 315
        // 对方未出门：唔会「喺附近」，亦唔会「見到」。
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

    /// F8：过咗约定时间 10 分钟仍未碰头，问要唔要打电话。每个约会只问一次（A20）。
    func checkLate(_ f: inout FindSession) {
        guard !f.spontaneous, f.stage != .met, !f.latePrompt, let id = findAppointment,
              let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].status == .accepted,
              appointments[i].lateAsked != true, now.timeIntervalSince(appointments[i].date) > 600 else { return }
        appointments[i].lateAsked = true
        f.latePrompt = true
        say(L.t("過咗約定時間 10 分鐘，仲未見到\(resident(f.partnerID)?.name ?? "")。要唔要打電話俾佢？", "过了约定时间 10 分钟，还没见到\(resident(f.partnerID)?.name ?? "")。要不要给他打电话？"), prompt: true)
    }

    /// 演示：将时间拨到约定时间后 11 分钟，等自动检查问「要唔要打電話」（唔再直接弹卡）。
    func lateDemo() {
        guard let f = find, !f.spontaneous, let id = findAppointment, let a = appointments.first(where: { $0.id == id }) else {
            toast(L.t("示範：約好咗、撳咗「出發」先用得。", "示范：约好了、按了「出发」才能用。"))
            return
        }
        setDemoHour(a.date.timeIntervalSince(Self.hk.startOfDay(for: Date())) / 3600 + 11.0 / 60)
    }

    /// 「我喺X」播送。text 係语音复述过嘅原话；撳掣时：约会讲「我喺X」，临时找人讲「我就到X」（A11）。
    func broadcastHere(_ text: String? = nil) {
        guard var f = find else { return }
        // 真街坊嘅找人可能冇本机地标（被搵嗰边、对方喺地图外）：照传原话
        guard let msg = text ?? landmark(f.landmarkID).map({ f.spontaneous ? L.t("我就到\($0.name)", "我马上到\($0.name)") : L.t("我喺\($0.name)", "我在\($0.name)") }) else { return }
        f.broadcast = msg
        find = f
        community.broadcast(to: f.partnerID, text: msg)
        say(L.t("已經話俾\(resident(f.partnerID)?.name ?? "")知：\(msg)。", "已经告诉\(resident(f.partnerID)?.name ?? "")：\(msg)。"))
        Haptics.light()
    }

    // MARK: - 底栏主按钮（两条找人流程同一条底栏，UX 评审 19 / 22）

    enum FindStep: Equatable { case depart, almost, waiting, met }

    /// 按阶段：「出發喇」→「我就到」→（够近或者讲咗就到）「見到喇」；被搵嗰边：「我喺度等你」→「見到喇」。
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

    /// 撳底栏主按钮：前几步话俾对方知（播送），最后一步「見到喇」结束。
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

    /// 模拟找人（示範街坊）撳「見到喇」：同自动见到一样，3 秒后收埋。
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
        // 找完人唔好留低地标卡（UX 评审 23）
        selection = nil
        renaming = nil
        scene.setRoute(nil)
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
        if walk != nil, walkDetector.recording {
            // 真机散步：继续跟定位，唔好自己行返屋企
            walk?.route = walkDetector.trail.isEmpty ? [myPosition()] : walkDetector.trail
            walk?.travelled = pathLength(walk?.route ?? [])
            scene.followID = "me"
        } else if walk != nil {
            // 找完人继续散步：从当前位置回屋企。
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

    /// 演示：下一次问陈太（过去搵佢 / 约佢）会被拒绝（由 LocalCommunityService 模拟）。
    func declineNextAsk() { localCommunity?.declineNext = true }
}
