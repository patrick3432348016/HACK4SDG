import SwiftUI

// F8 找人
extension AppStore {
    // MARK: - F8 找人（约好的当天 / 散步中临时）

    func goFind(_ partnerID: String) {
        guard let p = resident(partnerID), p.isNeighbor, let lm = landmark(p.atLandmarkID ?? p.homeLandmarkID) else { return }
        banner = nil
        let start = myPosition()
        findRoute = scene.route(from: start, to: scene.nearestWalkable(lm.pos + Vec2(x: -4, y: -3)))
        findTravelled = 0
        find = FindSession(partnerID: partnerID, landmarkID: lm.id, spontaneous: true, stage: .asking)
        scene.setRoute(findRoute)
        scene.highlightLandmark(lm.id)
        syncScene()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard var f = self.find, f.stage == .asking else { return }
            if self.localCommunity?.declineNext == true {
                self.localCommunity?.declineNext = false
                f.stage = .declined
                self.find = f
                self.speaker.speak("\(p.name)而家唔方便。")
                try? await Task.sleep(for: .seconds(2))
                self.endFind()
                return
            }
            self.speaker.speak("\(p.name)話好，喺\(lm.name)等你。")
            Haptics.success()
            f.stage = .going
            f.etaMinutes = 0
            self.find = f
            self.find?.stage = .asking   // 等用户按「去」
            self.partnerAgreed = true
        }
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
        guard let p = resident(a.partnerID), let lm = landmark(a.landmarkID) else { return }
        let start = myPosition()
        findRoute = scene.route(from: start, to: scene.nearestWalkable(lm.pos + Vec2(x: -4, y: -3)))
        let theirStart = landmark(p.homeLandmarkID)?.pos ?? lm.pos
        partnerRoute = scene.route(from: scene.nearestWalkable(theirStart + Vec2(x: 30, y: 25)), to: scene.nearestWalkable(lm.pos + Vec2(x: 5, y: 3)))
        findTravelled = 0
        partnerTravelled = 0
        findAppointment = a.id
        find = FindSession(partnerID: p.id, landmarkID: lm.id, spontaneous: false, stage: .going)
        findFullScreen = true
        scene.setRoute(findRoute)
        scene.highlightLandmark(lm.id)
        syncScene()
        startTicker()
        scene.setCamera(target: lm.pos + Vec2(x: -10, y: -10), distance: scene.overviewDistance * 0.8, animated: true, duration: 1.0)
        speaker.speak("今日約咗\(p.name)喺\(lm.name)。\(p.name)出咗門，大約 \(max(1, Int(pathLength(partnerRoute ?? []) / 70))) 分鐘到。")
    }

    func tickFind(_ f: inout FindSession, _ dt: Double) {
        guard f.stage == .going || f.stage == .near, let route = findRoute else { return }
        findTravelled = min(pathLength(route), findTravelled + dt * Self.findSpeed)
        if !f.spontaneous, let pr = partnerRoute { partnerTravelled = min(pathLength(pr), partnerTravelled + dt * Self.findSpeed * 0.8) }
        let mePos = point(along: route, at: findTravelled).0
        let partnerPos: Vec2 = {
            if f.spontaneous { return landmark(f.landmarkID).map { scene.nearestWalkable($0.pos + Vec2(x: 5, y: 3)) } ?? mePos }
            return point(along: partnerRoute ?? [mePos], at: partnerTravelled).0
        }()
        let d = mePos.distance(to: partnerPos)
        f.distance = d
        f.etaMinutes = max(0, Int((d / 70).rounded(.up)))
        // 屏幕上方 = 西北（相机从东南看），所以把方位角减 315°。
        let bearing = atan2(partnerPos.x - mePos.x, partnerPos.y - mePos.y) * 180 / .pi
        f.bearing = bearing - 315
        if d <= 50 && f.stage == .going {
            f.stage = .near
            Haptics.success()
            speaker.speak("\(resident(f.partnerID)?.name ?? "")喺附近，跟住箭咀行。")
        }
        if d <= 9 || (findTravelled >= pathLength(route) && (f.spontaneous || partnerTravelled >= pathLength(partnerRoute ?? []))) {
            f.stage = .met
            Haptics.success()
            speaker.speak("見到喇！")
            if let id = findAppointment, let i = appointments.firstIndex(where: { $0.id == id }) { appointments[i].status = .done }
            let finished = f
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if self.find == finished || self.find?.stage == .met { self.endFind() }
            }
        }
    }

    func lateDemo() {
        guard var f = find else { return }
        f.latePrompt = true
        find = f
        speaker.speak("過咗約定時間 10 分鐘，仲未見到\(resident(f.partnerID)?.name ?? "")。要唔要打電話俾佢？")
    }

    func broadcastHere() {
        guard var f = find, let lm = landmark(f.landmarkID) else { return }
        f.broadcast = "我喺\(lm.name)"
        find = f
        speaker.speak("已經話俾\(resident(f.partnerID)?.name ?? "")知：我喺\(lm.name)。")
        Haptics.light()
    }

    func endFind() {
        find = nil
        findFullScreen = false
        findRoute = nil
        partnerRoute = nil
        findAppointment = nil
        partnerAgreed = false
        scene.setRoute(nil)
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
        if walk != nil {
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

    /// 演示：下一次问陈太（过去搵佢 / 约佢）会被拒绝。
    func declineNextAsk() { localCommunity?.declineNext = true }
}
