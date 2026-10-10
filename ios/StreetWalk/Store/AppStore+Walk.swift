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
        beginWalk(route: route)
        startTicker()
    }

    private func beginWalk(route: [Vec2]) {
        walk = WalkSession(start: Date(), route: route)
        community.publishOuting(landmarkID: nearestLandmark(to: route[0])?.id)
        paceTip = nil
        tab = .today
        say("偵測到你出咗門，開始記錄，唔使撳任何掣。")
        Haptics.light()
        scene.followID = "me"
        scene.setCamera(target: route[0], distance: scene.overviewDistance * 0.85, animated: true)
        syncScene()
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
        else if var w = walk, !walkDetector.recording { tickWalk(&w, dt) }
        // 真机散步由定位推动，不用计时器
        if find == nil && (walk == nil || walkDetector.recording) { ticker?.cancel(); ticker = nil }
    }

    func tickWalk(_ w: inout WalkSession, _ dt: Double) {
        w.travelled += dt * Self.walkSpeed
        let total = pathLength(w.route)
        w.minutes = Int(Date().timeIntervalSince(w.start))
        let (pos, _) = point(along: w.route, at: w.travelled)
        markPassed(&w, at: pos)
        scene.setTrail(prefix(of: w.route, upTo: w.travelled))
        if w.minutes == 18 && paceTip == nil, let seat = landmarks.first(where: { $0.hasSeat && !w.passed.contains($0.id) }) ?? landmarks.first(where: \.hasSeat) {
            paceTip = "行慢咗少少。前面\(seat.name)有櫈，可以唞陣。"
            showBanner(BannerItem(symbol: "chair.lounge.fill", text: paceTip!)); say(paceTip!)
        }
        walk = w
        if w.travelled >= total { finishWalk() }
    }

    func markPassed(_ w: inout WalkSession, at pos: Vec2) {
        for l in landmarks where !w.passed.contains(l.id) && l.pos.distance(to: pos) < 26 {
            w.passed.append(l.id)
            community.publishOuting(landmarkID: l.id)
            if var meR = residents.first(where: \.isMe), let i = residents.firstIndex(where: \.isMe) {
                meR.todayLine = ai.dailyLine(for: meR, passed: w.passed.compactMap(landmark))
                residents[i] = meR
            }
        }
    }

    func finishWalk() {
        guard let w = walk else { return }
        let live = walkDetector.recording
        walk = nil
        walkDetector.reset()
        scene.followID = nil
        scene.setTrail([])
        recordWalk(minutes: max(w.minutes, 1), landmarks: w.passed, simulated: !live)
        community.publishOuting(landmarkID: nil)
        paceTip = nil
        syncScene()
        scene.resetCamera()
        say("返到屋企喇。今日行咗 \(max(w.minutes, 1)) 分鐘，經過 \(w.passed.count) 個地方。而家已經隱身。")
        Haptics.success()
    }

    // MARK: - F1 真机散步检测（只在真机、关咗演示模式、完成首次使用后；见 WalkDetector）

    static let homeRadius = 40.0    // 我屋企 40 m 内算返到屋企
    static let leaveRadius = 55.0   // 离开 55 m 才算出门，防定位在门口抖动
    static let nearHome = 80.0      // 停低 5 分钟又喺呢个范围内，都算返到屋企
    static let staleWalk: TimeInterval = 15 * 60

    /// 权限框（动作与健身、定位）要等首次使用的同意页之后先弹。
    func startWalkDetection() {
        guard WalkDetector.isAvailable, !demoMode, phase == .main else { return }
        walkDetector.onEvent = { [weak self] e in self?.handleWalkEvent(e) }
        walkDetector.start()
        // 记录中退咗后台好耐：按最后一个定位点收尾，唔好将喺屋企嘅时间都算落去
        if walkDetector.recording, walk != nil,
           let t = walkDetector.lastFixAt, Date().timeIntervalSince(t) > Self.staleWalk {
            finishLiveWalk()
        }
    }

    /// 真机散步分钟数：开始 → 最后一个定位点。
    func finishLiveWalk() {
        if let t = walkDetector.lastFixAt, let s = walk?.start { walk?.minutes = max(0, Int(t.timeIntervalSince(s) / 60)) }
        finishWalk()
    }

    func handleWalkEvent(_ e: WalkDetector.Event) {
        let d = walkDetector
        switch e {
        case .walking(let on):
            // 行路时开定位；停低但仲喺外面（记录中）也保持
            d.setLocating(on || d.recording)
        case .riding:
            // 坐车 / 踩单车唔算散步
            if d.recording { finishLiveWalk() }
            d.setLocating(false)
        case .still:
            // 停低 5 分钟又喺屋企附近（楼里 GPS 差，可能一直收唔到 40 m 内嘅点）
            guard d.recording, walk != nil, let fix = d.lastFix, let m = map else { return }
            if m.scenePoint(fix.0).distance(to: scene.homeTarget) - fix.accuracy < Self.nearHome { finishLiveWalk() }
        case .location(let g, let acc):
            // 散步被别处清掉（重置演示、重新生成）时同步收尾
            if d.recording, walk == nil { d.reset() }
            guard let m = map, phase == .main, find == nil else { return }
            let p = m.scenePoint(g)
            let inside = abs(p.x) <= m.half - 4 && abs(p.y) <= m.half - 4
            let fromHome = p.distance(to: scene.homeTarget)
            // 精度差（屋企楼里）时放宽：扣掉误差仍在 40 m 内，且不超过 100 m
            let home = fromHome < Self.homeRadius || (fromHome - acc < Self.homeRadius && fromHome < 100)
            if d.recording {
                if home { finishLiveWalk() } else if acc <= 30 { liveStep(p, inside: inside) } else { liveMinutes() }
            } else if walk == nil, acc <= 30, inside, fromHome > Self.leaveRadius {
                d.recording = true
                d.trail = [p]
                beginWalk(route: [p])
            }
        }
    }

    /// 真机：每个新定位点接到轨迹上；走出底座的点不画，只计时间。
    func liveStep(_ p: Vec2, inside: Bool) {
        liveMinutes()
        guard var w = walk else { return }
        let d = walkDetector
        if inside, d.trail.last.map({ $0.distance(to: p) >= 3 }) ?? true {
            d.trail.append(p)
            markPassed(&w, at: p)
            w.route = d.trail
            w.travelled = pathLength(d.trail)
            scene.setTrail(d.trail)
            walk = w
            syncScene()
        }
    }

    func liveMinutes() {
        guard let s = walk?.start, let t = walkDetector.lastFixAt else { return }
        walk?.minutes = max(0, Int(t.timeIntervalSince(s) / 60))
    }

    // MARK: - F4 请假

    /// 请假：今日算进连续天数（保留不断），排行榜上显示「今日請咗假」。
    func toggleLeave() {
        let key = LocalStore.dayKey(now)
        if leaveDays.contains(key) { leaveDays.remove(key) } else { leaveDays.insert(key) }
        refreshMe()
        say(me.onLeave ? "收到，今日請假。連續 \(me.streakDays) 日會保留。" : "撤回咗請假。")
        Haptics.light()
    }
}
