import SwiftUI

/// Non-published per-walk state: demo clock, stopping places, steps and real-device distance.
struct WalkTrack {
    /// Demo elapsed seconds map 1:1 to minutes; cap each tick at one second to avoid huge jumps after backgrounding.
    var elapsed = 0.0
    var stops = StopDetector()
    /// Stopping landmark IDs for this walk.
    var stopIDs: [String] = []
    /// Demo stops at a landmark with a bench to form a stopping place.
    var pauseAt: Vec2?
    var pauseSeat: String?
    var pauseLeft = 0.0
    /// Device steps, cadence and distance; discard overly short walks.
    var steps: Int?
    var cadence = CadenceWatch()
    var distance = 0.0
    var lastPoint: Vec2?
}

// F1 walking and F4 leave.
extension AppStore {
    // MARK: - F1 walking; demo speed is one second per minute

    static let walkSpeed = 9.0     // Meters per second with demo acceleration.
    static let findSpeed = 7.0
    /// Demo bench stop: 3 seconds represent 3 minutes, sufficient for a stopping place.
    static let demoPause = 3.0
    /// Demo movement covers 9 m per minute versus roughly 70 m in reality; scale the stopping radius accordingly.
    static let demoStopRadius = 4.0
    /// Snap stops only to the nearest landmark within 60 m; do not invent a more distant place.
    static let stopSnap = 60.0

    func startWalk() {
        guard walk == nil, find == nil, map != nil else { return }
        let start = scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
        var near = Array(landmarks.sorted { $0.pos.distance(to: start) < $1.pos.distance(to: start) }.prefix(3))
        // Include a bench landmark on the demo route for a stopping place.
        if !near.isEmpty, !near.contains(where: \.hasSeat),
           let seat = landmarks.filter(\.hasSeat).min(by: { $0.pos.distance(to: start) < $1.pos.distance(to: start) }) {
            near[near.count - 1] = seat
        }
        if near.count >= 2 { near = [near[0], near[2 % near.count], near[1]] }
        var route: [Vec2] = [start]
        var prev = start
        var seat: (Vec2, String)?
        for l in near {
            route += scene.route(from: prev, to: scene.nearestWalkable(l.pos)).dropFirst()
            prev = route.last!
            if seat == nil, l.hasSeat { seat = (prev, l.id) }
        }
        route += scene.route(from: prev, to: start).dropFirst()
        // A92: switch to Today only for manual departure, not automatic device detection.
        tab = .today
        beginWalk(route: route)
        track.pauseAt = seat?.0
        track.pauseSeat = seat?.1
        startTicker()
    }

    private func beginWalk(route: [Vec2], start: Date = Date(), live: Bool = false) {
        walk = WalkSession(start: start, route: route)
        track = WalkTrack()
        if !live { track.stops = StopDetector(radius: Self.demoStopRadius) }
        if live { walkDetector.startSteps(from: start) }
        community.publishOuting(landmarkID: nearestLandmark(to: route[0])?.id)
        paceTip = nil
        say(L.t("偵測到你出咗門，開始記錄，唔使撳任何掣。", "检测到你出门了，开始记录，不用按任何按钮。"))
        Haptics.light()
        scene.followID = "me"
        scene.setCamera(target: route[0], distance: scene.overviewDistance * 0.85, animated: true)
        syncScene()
        walkBegan(live: live)      // Location records and background notifications (AppStore+Location).
    }

    func remainingRoute(_ w: WalkSession) -> [Vec2] {
        let (pt, idx) = point(along: w.route, at: w.travelled)
        // Remain still at the demo stopping place.
        if track.pauseLeft > 0 { return [pt] }
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
                // A75: cap each tick at one second to avoid hundreds of minutes after backgrounding while allowing minor slow-frame variation.
                let dt = min(Date().timeIntervalSince(last), 1)
                last = Date()
                self.tick(dt)
            }
        }
    }

    func tick(_ dt: Double) {
        if walk != nil, !walkDetector.recording {
            // Continue the demo walking clock while traveling to find a neighbor.
            track.elapsed += dt
            if find != nil, let w = walk {
                if w.minutes != Int(track.elapsed) { walk?.minutes = Int(track.elapsed) }
                // Waiting and talking count as stops for stopping-place detection.
                if let c = track.stops.add(myPosition(), at: w.start.addingTimeInterval(track.elapsed * 60)) { addStop(at: c) }
            }
        }
        if var f = find { tickFind(&f, dt); find = f }
        else if var w = walk, !walkDetector.recording { tickWalk(&w, dt) }
        // Real-device walks advance through location updates, without a timer.
        if find == nil && (walk == nil || walkDetector.recording) { ticker?.cancel(); ticker = nil }
    }

    func tickWalk(_ w: inout WalkSession, _ dt: Double) {
        let total = pathLength(w.route)
        var pos = point(along: w.route, at: w.travelled).0
        if track.pauseLeft > 0 {
            track.pauseLeft -= dt
            if track.pauseLeft <= 0 { paceTip = nil; walk = w; syncScene() }      // Resume walking after resting.
        } else if let p = track.pauseAt, pos.distance(to: p) < 5 {
            track.pauseAt = nil
            track.pauseLeft = Self.demoPause
            walk = w; syncScene()                                    // Sit on the bench.
        } else {
            w.travelled += dt * Self.walkSpeed
            pos = point(along: w.route, at: w.travelled).0
        }
        w.minutes = Int(track.elapsed)
        markPassed(&w, at: pos)
        if let c = track.stops.add(pos, at: w.start.addingTimeInterval(track.elapsed * 60)) { addStop(at: c) }
        scene.setTrail(prefix(of: w.route, upTo: w.travelled))
        // Demo slowdown points to the upcoming bench only before the first rest.
        let ahead = track.pauseAt != nil ? landmark(track.pauseSeat) : nil
        if w.minutes == 18 && paceTip == nil,
           let seat = ahead ?? landmarks.first(where: { $0.hasSeat && !w.passed.contains($0.id) }) ?? landmarks.first(where: \.hasSeat) {
            paceTip = L.t("行慢咗少少。前面\(seat.name)有櫈，可以唞陣。", "走得慢了一点。前面\(seat.name)有凳子，可以歇一会。")
            showBanner(BannerItem(symbol: "chair.lounge.fill", text: paceTip!)); say(paceTip!)
        }
        walk = w
        if w.travelled >= total { finishWalk() }
    }

    /// Passing within 26 m updates the outing landmark for neighbors with alerts enabled.
    /// Do not update circle-visible daily greetings during a walk, which would disclose the outing to everyone.
    func markPassed(_ w: inout WalkSession, at pos: Vec2) {
        for l in landmarks where !w.passed.contains(l.id) && l.pos.distance(to: pos) < 26 {
            w.passed.append(l.id)
            community.publishOuting(landmarkID: l.id)
        }
    }

    /// F1: map the stopping place to its nearest landmark for external sharing.
    func addStop(at c: Vec2) {
        guard let l = nearestLandmark(to: c), l.pos.distance(to: c) <= Self.stopSnap, !track.stopIDs.contains(l.id) else { return }
        track.stopIDs.append(l.id)
        community.publishOuting(landmarkID: l.id)
    }

    enum WalkEnd { case home, stopped, riding }

    /// Finish recording; endAt uses the stop time or last device fix.
    func finishWalk(endAt: Date? = nil, reason: WalkEnd = .home) {
        guard let w = walk else { return }
        walkingWith = nil
        let live = walkDetector.recording
        var minutes = w.minutes
        if live, let end = endAt ?? walkDetector.lastFixAt { minutes = max(0, Int(end.timeIntervalSince(w.start) / 60)) }
        // A74: discard device walks shorter than both 2 minutes and 100 m as possible GPS jumps.
        let tooShort = live && minutes < 2 && track.distance < 100
        let t = track
        walk = nil
        walkDetector.reset()
        scene.followID = nil
        scene.setTrail([])
        if !tooShort {
            // Do not record wheelchair steps; estimate from minutes.
            recordWalk(minutes: max(minutes, 1), landmarks: w.passed, simulated: !live, steps: live && !walkDetector.seated ? t.steps : nil, stops: t.stopIDs)
        }
        community.publishOuting(landmarkID: nil)
        paceTip = nil
        track = WalkTrack()
        syncScene()
        scene.resetCamera()
        let m = max(minutes, 1)
        switch (tooShort, reason) {
        case (true, _): say(L.t("行得太短，今次唔記錄。而家已經隱身。", "走得太短，这次不记录。现在已经隐身。"))
        case (_, .home): say(L.t("返到屋企喇。今日行咗 \(m) 分鐘，經過 \(w.passed.count) 個地方。而家已經隱身。", "到家了。今天走了 \(m) 分钟，经过 \(w.passed.count) 个地方。现在已经隐身。"))
        case (_, .stopped): say(L.t("停低咗一陣，今次散步記好咗：行咗 \(m) 分鐘。而家已經隱身。", "停了一会儿，这次散步已记好：走了 \(m) 分钟。现在已经隐身。"))
        case (_, .riding): say(L.t("上咗車，今次散步記好咗：行咗 \(m) 分鐘。而家已經隱身。", "上车了，这次散步已记好：走了 \(m) 分钟。现在已经隐身。"))
        }
        Haptics.success()
        walkEnded(live: live, minutes: m, places: w.passed.count, reason: reason, recorded: !tooShort)   // AppStore+Location
    }

    // MARK: - F1 device walk detection after onboarding with demo disabled; see WalkDetector

    static let nearHome = 80.0      // Five minutes stopped within this radius also counts as returning home.
    static let staleWalk: TimeInterval = 15 * 60
    static let backgroundKey = "walkBackgroundSince"

    /// Request motion, location and notification permissions only after onboarding consent.
    func startWalkDetection() {
        requestNotificationsIfReady()
        guard WalkDetector.isAvailable, !demoMode, phase == .main else { return }
        let d = walkDetector
        d.onEvent = { [weak self] e in self?.handleWalkEvent(e) }
        d.seated = mobilityChoice == .wheelchair
        let since = takeBackgroundMark()
        let resuming = d.recording && walk != nil
        // A55: on foreground return, read activity history before location can start or finish a walk.
        guard resuming || since != nil else { d.start(); return }
        if since != nil { d.pendingWalk = nil }     // Re-read from mark.
        d.catchUps += 1
        d.start()
        Task {
            if resuming { await resumeLiveWalk() } else if let since { await backfill(from: since, to: Date()) }
            d.catchUps -= 1
            if !d.catchingUp, d.running { d.setLocating(d.moving || d.recording) }
        }
    }

    /// On backgrounding, record when location became unavailable, using the current walk or unhandled final segment's start.
    /// Use this marker for backfilling on foreground return or next launch.
    func markBackground() {
        let d = walkDetector
        guard d.running else { return }
        let mark = d.recording ? (walk?.start ?? Date()) : min(d.pendingWalk?.start ?? Date(), Date())
        UserDefaults.standard.set(mark, forKey: Self.backgroundKey)
    }

    func takeBackgroundMark() -> Date? {
        let d = UserDefaults.standard.object(forKey: Self.backgroundKey) as? Date
        UserDefaults.standard.removeObject(forKey: Self.backgroundKey)
        // The system retains only 7 days of motion history.
        return d.map { max($0, Date().addingTimeInterval(-7 * 86400)) }
    }

    /// After backgrounding during recording, use Core Motion history to find when walking stopped.
    func resumeLiveWalk() async {
        let d = walkDetector
        guard let w = walk, d.recording else { return }
        let now = Date()
        let seen = d.lastFixAt ?? w.start
        guard now.timeIntervalSince(seen) > 2 * 60 else { return }      // For a brief absence, continue following location.
        let samples = await d.activities(from: w.start, to: now)
        guard walk?.start == w.start, d.recording else { return }
        guard let samples else {
            // Without motion history after a long absence, finish at the last fix to avoid counting time spent home.
            if now.timeIntervalSince(seen) > Self.staleWalk { finishLiveWalk(endAt: seen) }
            return
        }
        let segs = WalkBackfill.segments(samples, until: now, minLength: 0)
        let current = segs.first { $0.start <= seen.addingTimeInterval(120) && $0.end >= seen.addingTimeInterval(-120) }
        let end = max(seen, current?.end ?? seen)
        if end >= now.addingTimeInterval(-60) { return }   // Still walking: continue following location.
        finishLiveWalk(endAt: end)
        await backfill(from: end, to: now)
    }

    /// A05: backfill background / locked-screen walking from Core Motion with minutes and steps, without landmarks or stops.
    /// Hand the final active or recently stopped segment to location; if takeover fails, backfill through its stop time.
    func backfill(from: Date, to: Date) async {
        let d = walkDetector
        guard to.timeIntervalSince(from) >= 60, let samples = await d.activities(from: from, to: to) else { return }
        let (done, tail) = WalkBackfill.split(samples, until: to)
        var total = 0
        for s in done { total += await recordBackfill(s) }
        if total > 0 { toast(L.t("App 喺背景嗰陣你行咗 \(total) 分鐘，已經補記低（冇地標）。", "App 在后台时你走了 \(total) 分钟，已补记（没有地标）。")) }
        guard let tail, !d.recording else { return }
        d.pendingWalk = tail
        // After two minutes without a live walk and no current movement, backfill through the stop time.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(WalkBackfill.mergeGap))
            guard let self, d.pendingWalk == tail, !d.moving else { return }
            self.settlePendingWalk(stoppedAt: d.stillSince ?? Date())
        }
    }

    /// Backfill one segment, excluding wheelchair steps; return minutes.
    private func recordBackfill(_ s: DateInterval) async -> Int {
        let m = Int(s.duration / 60)
        guard m > 0 else { return 0 }
        let steps = await walkDetector.steps(from: s.start, to: s.end)
        recordWalk(minutes: m, landmarks: [], simulated: false, day: s.start, steps: steps)
        return m
    }

    /// If the final segment never became a live walk, backfill through its stop time; discard segments under 5 minutes.
    func settlePendingWalk(stoppedAt: Date) {
        let d = walkDetector
        guard let p = d.pendingWalk, !d.recording else { return }
        d.pendingWalk = nil
        guard let s = p.interval(stoppedAt: stoppedAt) else { return }
        Task {
            let m = await recordBackfill(s)
            if m > 0 { toast(L.t("App 喺背景嗰陣你行咗 \(m) 分鐘，已經補記低（冇地標）。", "App 在后台时你走了 \(m) 分钟，已补记（没有地标）。")) }
        }
    }

    /// Whether the latest fix is near home, used to decide immediate final-segment backfill.
    private var lastFixAtHome: Bool {
        guard let fix = walkDetector.lastFix, let m = map else { return false }
        return LiveWalkGate.isHome(fromHome: m.scenePoint(fix.0).distance(to: scene.homeTarget), acc: fix.accuracy)
    }

    /// A74: finish the device walk and disable location if no longer moving.
    func finishLiveWalk(endAt: Date? = nil, reason: WalkEnd = .home) {
        finishWalk(endAt: endAt, reason: reason)
        walkDetector.setLocating(walkDetector.moving)
    }

    func handleWalkEvent(_ e: WalkDetector.Event) {
        let d = walkDetector
        // While foreground motion history loads, accept steps only; defer other decisions until moving restores location control.
        if d.catchingUp, !e.isSteps { return }
        switch e {
        case .walking(let on):
            // Enable location while walking and keep it during stops outside if recording.
            d.setLocating(on || d.recording)
            // Backfill the final background segment immediately when stopped at home.
            if !on, d.pendingWalk != nil, lastFixAtHome { settlePendingWalk(stoppedAt: Date()) }
        case .riding:
            // Vehicle travel and cycling do not count as walking.
            if d.recording { finishLiveWalk(reason: .riding) }
            settlePendingWalk(stoppedAt: Date())
            d.setLocating(false)
        case .still(let since):
            // After two minutes stopped, backfill any unhandled final segment through its stop time.
            settlePendingWalk(stoppedAt: since)
            guard d.recording, let w = walk else { return }
            // Two minutes stopped forms a stopping place; stationary GPS may produce no new fixes, so use this timer.
            if let c = track.stops.hold(at: Date()) { addStop(at: c) }
            let stillFor = Date().timeIntervalSince(since)
            let end = max(since, w.start)
            // Stationary for five minutes near home; indoor GPS may never produce a point within 40 m.
            if stillFor >= 5 * 60 - 5, let fix = d.lastFix, let m = map,
               m.scenePoint(fix.0).distance(to: scene.homeTarget) - fix.accuracy < Self.nearHome {
                finishLiveWalk(endAt: end)
            } else if stillFor >= 10 * 60 - 5 {
                // After ten stationary minutes away from home, end the walk at the stop time and exclude sitting time (A55).
                finishLiveWalk(endAt: end, reason: .stopped)
            }
        case .location(let g, let acc):
            // Synchronize completion if another flow clears the walk, such as demo reset or map regeneration.
            if d.recording, walk == nil { d.reset() }
            guard let m = map, phase == .main, find == nil else { return }
            let p = m.scenePoint(g)
            let inside = abs(p.x) <= m.half - 4 && abs(p.y) <= m.half - 4
            let fromHome = p.distance(to: scene.homeTarget)
            switch d.gate.decide(fromHome: fromHome, acc: acc, at: d.lastFixAt ?? Date(), recording: d.recording, moving: d.moving, maxStart: d.maxStart) {
            case .finish: finishLiveWalk()
            case .step: liveStep(p, inside: inside)
            case .minutesOnly: liveMinutes()
            case .start:
                // A06: permit starts outside the base; clamp camera / avatar and draw only the in-base route.
                d.recording = true
                d.trail = inside ? [p] : []
                let lim = m.half - 4
                let first = Vec2(x: max(-lim, min(lim, p.x)), y: max(-lim, min(lim, p.y)))
                // Use the final backfill segment's start, otherwise a Core Motion start no older than 10 minutes.
                let start = d.pendingWalk?.start ?? d.movingSince.flatMap { Date().timeIntervalSince($0) < 600 ? $0 : nil } ?? Date()
                d.pendingWalk = nil
                beginWalk(route: [first], start: start, live: true)
                track.lastPoint = p
            case .none:
                // Backfill the final segment immediately when already home and Core Motion reports stopped.
                if let pw = d.pendingWalk, pw.end != nil || !d.moving, LiveWalkGate.isHome(fromHome: fromHome, acc: acc) {
                    settlePendingWalk(stoppedAt: d.lastFixAt ?? Date())
                }
            }
        case .steps(let n, let cadence):
            // Exclude wheelchair steps and cadence; estimate from minutes.
            guard d.recording, !d.seated, let w = walk else { return }
            track.steps = n
            // F9: suggest rest once when cadence drops substantially.
            if let c = cadence, paceTip == nil, track.cadence.add(c, at: Date(), walkStart: w.start) {
                let here = myPosition()
                let seat = landmarks.filter(\.hasSeat).min { $0.pos.distance(to: here) < $1.pos.distance(to: here) }
                paceTip = seat.map { L.t("行慢咗少少。附近\($0.name)有櫈，可以唞陣。", "走得慢了一点。附近\($0.name)有凳子，可以歇一会。") } ?? L.t("行慢咗少少，搵個地方唞陣先。", "走得慢了一点，先找个地方歇一会。")
                showBanner(BannerItem(symbol: "chair.lounge.fill", text: paceTip!)); say(paceTip!)
            }
        }
    }

    /// Append real-device location updates to the track; outside the diorama, record time, distance and visits without drawing points.
    func liveStep(_ p: Vec2, inside: Bool) {
        liveMinutes()
        if let last = track.lastPoint { track.distance += last.distance(to: p) }
        track.lastPoint = p
        if let t = walkDetector.lastFixAt, let c = track.stops.add(p, at: t) { addStop(at: c) }
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

    // MARK: - F4 leave preserves streaks without increasing them

    /// Leave options: today, tomorrow, 3 days or 7 days from today.
    static let leaveChoices = [LeaveRequest(startOffset: 0, days: 1), LeaveRequest(startOffset: 1, days: 1),
                               LeaveRequest(startOffset: 0, days: 3), LeaveRequest(startOffset: 0, days: 7)]

    /// Take days of leave starting startOffset days from today; LeaveRequest.parse supplies voice requests.
    func requestLeave(days: Int = 1, startOffset: Int = 0) {
        let r = LeaveRequest(startOffset: max(0, startOffset), days: max(1, min(LeaveRequest.maxDays, days)))
        let added = leaveKeys(r).filter { !leaveDays.contains($0) }
        leaveDays.formUnion(added)
        uploadLeave(added, on: true)
        refreshMe()
        say(L.t("收到，\(leaveTitle(r))。連續 \(me.streakDays) 日會保留。", "收到，\(leaveTitle(r))。连续 \(me.streakDays) 天会保留。"))
        Haptics.light()
    }

    /// Withdraw a specific leave request, including a cancelled voice recap.
    func cancelLeave(days: Int = 1, startOffset: Int = 0) {
        let removed = leaveKeys(LeaveRequest(startOffset: max(0, startOffset), days: max(1, days))).filter(leaveDays.contains)
        leaveDays.subtract(removed)
        uploadLeave(removed, on: false)
        refreshMe()
    }

    /// Voice leave parses the original date / duration, applies leave and returns the recap title.
    @discardableResult
    func requestLeave(fromVoice text: String) -> String {
        let r = LeaveRequest.parse(text, today: now)
        requestLeave(days: r.days, startOffset: r.startOffset)
        return leaveTitle(r)
    }

    /// Cancelling the voice leave card withdraws the same interval parsed from the original input.
    func cancelLeave(fromVoice text: String) {
        let r = LeaveRequest.parse(text, today: now)
        cancelLeave(days: r.days, startOffset: r.startOffset)
    }

    /// Upload only changed dates to leaves.
    private func uploadLeave(_ keys: [String], on: Bool) {
        for k in keys { community.setLeave(day: k, on: on) }
    }

    func leaveKeys(_ r: LeaveRequest) -> [String] {
        let base = now
        return (0..<r.days).map { LocalStore.dayKey(base.addingTimeInterval(Double(r.startOffset + $0) * 86400)) }
    }

    /// Localized leave descriptions include start date, duration and end date where applicable.
    func leaveTitle(_ r: LeaveRequest) -> String {
        let from = r.startOffset < 4 ? (L.isCmn ? ["今天", "明天", "后天", "大后天"] : ["今日", "聽日", "後日", "大後日"])[r.startOffset] : dateLabel(now.addingTimeInterval(Double(r.startOffset) * 86400))
        guard r.days > 1 else { return L.t("\(from)請假", "\(from)请假") }
        return L.t("由\(from)起請 \(r.days) 日假（到 \(dateLabel(now.addingTimeInterval(Double(r.startOffset + r.days - 1) * 86400)))）", "从\(from)起请 \(r.days) 天假（到 \(dateLabel(now.addingTimeInterval(Double(r.startOffset + r.days - 1) * 86400)))）")
    }

    /// Use everyday wording for skipping a walk instead of work-like leave terminology (UX finding 16); still recognize the spoken leave command.
    func leaveMenuLabel(_ r: LeaveRequest) -> String {
        guard r.days > 1 else {
            let from = r.startOffset < 4 ? (L.isCmn ? ["今天", "明天", "后天", "大后天"] : ["今日", "聽日", "後日", "大後日"])[r.startOffset] : dateLabel(now.addingTimeInterval(Double(r.startOffset) * 86400))
            return L.t("\(from)唔行", "\(from)不走")
        }
        return L.t("由今日起 \(r.days) 日唔行（到 \(dateLabel(now.addingTimeInterval(Double(r.startOffset + r.days - 1) * 86400)))）", "从今天起 \(r.days) 天不走（到 \(dateLabel(now.addingTimeInterval(Double(r.startOffset + r.days - 1) * 86400)))）")
    }

    func dateLabel(_ d: Date) -> String {
        let c = Self.hk.dateComponents([.month, .day], from: d)
        return L.t("\(c.month ?? 0) 月 \(c.day ?? 0) 號", "\(c.month ?? 0) 月 \(c.day ?? 0) 日")
    }

    /// Find a consecutive leave interval from today onward using day offsets, not changing Date() values.
    private var upcomingLeave: LeaveRequest? {
        let base = now
        func on(_ i: Int) -> Bool { leaveDays.contains(LocalStore.dayKey(base.addingTimeInterval(Double(i) * 86400))) }
        guard let first = (0...LeaveRequest.maxDays).first(where: on) else { return nil }
        var days = 1
        while on(first + days) && days < 366 { days += 1 }
        return LeaveRequest(startOffset: first, days: days)
    }

    /// Today's leave row, or nil when absent.
    var leaveSummary: String? {
        guard let u = upcomingLeave else { return nil }
        let last = dateLabel(now.addingTimeInterval(Double(u.startOffset + u.days - 1) * 86400))
        switch (u.startOffset, u.days) {
        case (0, 1): return L.t("今日唔行，連續日數照計", "今天不走，连续天数照算")
        case (0, _): return L.t("唔行到 \(last)，連續日數照計", "不走到 \(last)，连续天数照算")
        case (1, 1): return L.t("聽日唔行，連續日數照計", "明天不走，连续天数照算")
        default: return L.t("\(dateLabel(now.addingTimeInterval(Double(u.startOffset) * 86400)))起唔行，連續日數照計", "\(dateLabel(now.addingTimeInterval(Double(u.startOffset) * 86400)))起不走，连续天数照算")
        }
    }

    /// Toggle only today's leave while preserving future dates; voice cancellation uses this path too.
    func toggleLeave() {
        guard leaveDays.contains(LocalStore.dayKey(now)) else { requestLeave(); return }
        cancelLeave(days: 1, startOffset: 0)
        say(L.t("撤回咗今日嘅請假。", "已撤回今天的请假。"))
        Haptics.light()
    }

    /// Withdrawal label for future leave when today is not on leave.
    var withdrawLeaveLabel: String? {
        guard let u = upcomingLeave, u.startOffset > 0 else { return nil }
        let from = u.startOffset == 1 ? L.t("聽日", "明天") : dateLabel(now.addingTimeInterval(Double(u.startOffset) * 86400))
        return u.days == 1 ? L.t("\(from)照行（撤回）", "\(from)照走（撤回）") : L.t("\(from)起照行（撤回 \(u.days) 日）", "\(from)起照走（撤回 \(u.days) 天）")
    }

    /// Omit leave options whose entire interval is already booked.
    var leaveMenuChoices: [LeaveRequest] {
        Self.leaveChoices.filter { !leaveKeys($0).allSatisfy(leaveDays.contains) }
    }

    /// Withdraw the nearest consecutive leave interval from today onward.
    func withdrawLeave() {
        guard let u = upcomingLeave else { return }
        let removed = leaveKeys(u).filter(leaveDays.contains)
        leaveDays.subtract(removed)
        uploadLeave(removed, on: false)
        refreshMe()
        say(L.t("撤回咗請假。", "已撤回请假。"))
        Haptics.light()
    }
}
