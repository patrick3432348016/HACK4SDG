import SwiftUI

// F1 散步、F4 请假
extension AppStore {
    // MARK: - F1 散步（演示：1 秒 = 1 分钟）

    static let walkSpeed = 9.0     // 米/秒（演示加速）
    static let findSpeed = 7.0

    func startWalk() {
        guard walk == nil, find == nil, map != nil else { return }
        let start = scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
        var stops = landmarks.sorted { $0.pos.distance(to: start) < $1.pos.distance(to: start) }.prefix(3).map(\.pos)
        if stops.count >= 2 { stops = [stops[0], stops[2 % stops.count], stops[1]] }
        var route: [Vec2] = [start]
        var prev = start
        for s in stops + [start] {
            let leg = scene.route(from: prev, to: scene.nearestWalkable(s))
            route += leg.dropFirst()
            prev = route.last!
        }
        walk = WalkSession(start: Date(), route: route)
        community.publishOuting(landmarkID: nearestLandmark(to: start)?.id)
        paceTip = nil
        tab = .today
        speaker.speak("偵測到你出咗門，開始記錄，唔使撳任何掣。")
        Haptics.light()
        scene.followID = "me"
        scene.setCamera(target: start, distance: scene.overviewDistance * 0.85, animated: true)
        syncScene()
        startTicker()
    }

    func remainingRoute(_ w: WalkSession) -> [Vec2] {
        let (pt, idx) = point(along: w.route, at: w.travelled)
        return [pt] + w.route.dropFirst(idx + 1)
    }

    func myPosition() -> Vec2 {
        if let p = scene.personPosition("me") { return p }
        if let w = walk { return point(along: w.route, at: w.travelled).0 }
        return scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
    }

    func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                let dt = Date().timeIntervalSince(last)
                last = Date()
                self.tick(dt)
            }
        }
    }

    func tick(_ dt: Double) {
        if var f = find { tickFind(&f, dt); find = f }
        else if var w = walk { tickWalk(&w, dt) }
        if walk == nil && find == nil { ticker?.cancel(); ticker = nil }
    }

    func tickWalk(_ w: inout WalkSession, _ dt: Double) {
        w.travelled += dt * Self.walkSpeed
        let total = pathLength(w.route)
        w.minutes = Int(Date().timeIntervalSince(w.start))
        let (pos, _) = point(along: w.route, at: w.travelled)
        for l in landmarks where !w.passed.contains(l.id) && l.pos.distance(to: pos) < 26 {
            w.passed.append(l.id)
            community.publishOuting(landmarkID: l.id)
            if var meR = residents.first(where: \.isMe), let i = residents.firstIndex(where: \.isMe) {
                meR.todayLine = ai.dailyLine(for: meR, passed: w.passed.compactMap(landmark))
                residents[i] = meR
            }
        }
        scene.setTrail(prefix(of: w.route, upTo: w.travelled))
        if w.minutes == 18 && paceTip == nil, let seat = landmarks.first(where: { $0.hasSeat && !w.passed.contains($0.id) }) ?? landmarks.first(where: \.hasSeat) {
            paceTip = "行慢咗少少。前面\(seat.name)有櫈，可以唞陣。"
            speaker.speak(paceTip!)
        }
        walk = w
        if w.travelled >= total { finishWalk() }
    }

    func finishWalk() {
        guard let w = walk else { return }
        walk = nil
        scene.followID = nil
        scene.setTrail([])
        recordWalk(minutes: max(w.minutes, 1), landmarks: w.passed)
        community.publishOuting(landmarkID: nil)
        paceTip = nil
        syncScene()
        scene.resetCamera()
        speaker.speak("返到屋企喇。今日行咗 \(max(w.minutes, 1)) 分鐘，經過 \(w.passed.count) 個地方。而家已經隱身。")
        Haptics.success()
    }

    // MARK: - F4 请假

    /// 请假：今日算进连续天数（保留不断），排行榜上显示「今日請咗假」。
    func toggleLeave() {
        let key = LocalStore.dayKey(now)
        if leaveDays.contains(key) { leaveDays.remove(key) } else { leaveDays.insert(key) }
        refreshMe()
        speaker.speak(me.onLeave ? "收到，今日請假。連續 \(me.streakDays) 日會保留。" : "撤回咗請假。")
        Haptics.light()
    }
}
