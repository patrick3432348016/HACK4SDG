import SwiftUI

// F8 找人
extension AppStore {
    // MARK: - F8 找人（约好的当天 / 散步中临时）

    func goFind(_ partnerID: String) {
        guard let p = resident(partnerID), p.isNeighbor, let lm = landmark(p.atLandmarkID ?? p.homeLandmarkID) else { return }
        // 换人 / 再问：撤回上一个询问，清走上次留低嘅「話好」同约会路线（A22）。
        if let old = find { community.cancelFindAsk(partnerID: old.partnerID) }
        banner = nil
        renaming = nil
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
            say("\(p.name)而家唔方便。")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if self.find?.token == token { self.endFind() }
            }
            return
        }
        say("\(p.name)話好，喺\(landmark(f.landmarkID)?.name ?? "")等你。撳「去」就出發。", prompt: true)
        Haptics.success()
        partnerAgreed = true
    }

    func startGoing() {
        guard var f = find else { return }
        f.stage = .going
        find = f
        findFullScreen = true
        partnerAgreed = false
        scene.followID = nil
        startTicker()
        syncScene()
        if let lm = landmark(f.landmarkID) { scene.setCamera(target: lm.pos + Vec2(x: -10, y: -10), distance: scene.overviewDistance * 0.8, animated: true, duration: 1.0) }
    }

    func departForAppointment(_ a: Appointment) {
        // 只有约好咗、对方仍然係街坊先可以出发（非街坊永远唔入场景）。
        guard a.status == .accepted, let p = resident(a.partnerID), p.isNeighbor else { return }
        guard let lm = landmark(a.landmarkID) else { toast("搵唔到約會個地點（地圖更新咗），撳「改時間地點」揀過。"); return }
        if let old = find { community.cancelFindAsk(partnerID: old.partnerID) }
        renaming = nil
        let start = myPosition()
        findRoute = scene.route(from: start, to: scene.nearestWalkable(lm.pos + Vec2(x: -4, y: -3)))
        // 对方未出门：唔入场景（syncScene 只画出咗门嘅对方），呢度只记低模拟路线嘅起点（A19 / A67）。
        let theirStart = scene.nearestWalkable((landmark(p.homeLandmarkID)?.pos ?? lm.pos) + Vec2(x: 30, y: 25))
        partnerRoute = [theirStart]
        findTravelled = 0
        partnerTravelled = 0
        partnerAgreed = false
        findAppointment = a.id
        let session = FindSession(partnerID: p.id, landmarkID: lm.id, spontaneous: false, stage: .going, partnerOut: false)
        find = session
        findFullScreen = true
        scene.setRoute(findRoute)
        scene.highlightLandmark(lm.id)
        syncScene()
        startTicker()
        scene.setCamera(target: lm.pos + Vec2(x: -10, y: -10), distance: scene.overviewDistance * 0.8, animated: true, duration: 1.0)
        say("今日約咗\(p.name)喺\(lm.name)。等緊\(p.name)出門。")
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
            say(trip.arrived ? "\(p.name)已經喺\(lm.name)等你。" : "\(p.name)出咗門，大約 \(f.etaMinutes) 分鐘到\(lm.name)。")
        } else if trip.arrived && !wasThere {
            say("\(p.name)到咗\(lm.name)。")
        }
    }

    func tickFind(_ f: inout FindSession, _ dt: Double) {
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
            say("\(resident(f.partnerID)?.name ?? "")喺附近，跟住箭咀行。")
        }
        let partnerThere = f.spontaneous || (f.partnerOut && partnerTravelled >= pathLength(partnerRoute ?? []))
        if f.partnerOut && (d <= 9 || (findTravelled >= pathLength(route) && partnerThere)) {
            f.stage = .met
            Haptics.success()
            say("見到喇！")
            if let id = findAppointment, let i = appointments.firstIndex(where: { $0.id == id }) { appointments[i].status = .done }
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
        say("過咗約定時間 10 分鐘，仲未見到\(resident(f.partnerID)?.name ?? "")。要唔要打電話俾佢？", prompt: true)
    }

    /// 演示：将时间拨到约定时间后 11 分钟，等自动检查问「要唔要打電話」（唔再直接弹卡）。
    func lateDemo() {
        guard let f = find, !f.spontaneous, let id = findAppointment, let a = appointments.first(where: { $0.id == id }) else {
            toast("示範：約好咗、撳咗「出發」先用得。")
            return
        }
        setDemoHour(a.date.timeIntervalSince(Self.hk.startOfDay(for: Date())) / 3600 + 11.0 / 60)
    }

    /// 「我喺X」播送。text 係语音复述过嘅原话；撳掣时：约会讲「我喺X」，临时找人讲「我就到X」（A11）。
    func broadcastHere(_ text: String? = nil) {
        guard var f = find, let lm = landmark(f.landmarkID) else { return }
        let msg = text ?? (f.spontaneous ? "我就到\(lm.name)" : "我喺\(lm.name)")
        f.broadcast = msg
        find = f
        community.broadcast(to: f.partnerID, text: msg)
        say("已經話俾\(resident(f.partnerID)?.name ?? "")知：\(msg)。")
        Haptics.light()
    }

    func endFind() {
        if let f = find {
            community.cancelFindAsk(partnerID: f.partnerID)
            if let id = findAppointment { community.endMeetupTrip(id, met: f.stage == .met) }
        }
        find = nil
        findFullScreen = false
        findRoute = nil
        partnerRoute = nil
        findAppointment = nil
        partnerAgreed = false
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
