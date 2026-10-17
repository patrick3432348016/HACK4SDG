import SwiftUI

/// 一次散步嘅附加状态（唔使刷新界面）：演示时钟、落脚点、步数、真机行咗几远。
struct WalkTrack {
    /// 演示散步累计秒数（1 秒 = 1 分钟）。每格最多当 1 秒，退后台再返嚟唔会一下跳几百分钟。
    var elapsed = 0.0
    var stops = StopDetector()
    /// 今次嘅落脚点（地标 id）。
    var stopIDs: [String] = []
    /// 自己撳「现在出去走走」开始（A-3）：分钟按钟计，唔使等定位。
    var manual = false
    /// 演示：喺呢个有櫈嘅地标停一停，形成落脚点。
    var pauseAt: Vec2?
    var pauseSeat: String?
    var pauseLeft = 0.0
    /// 真机：计步器步数、步频、行咗几远（太短唔记）。
    var steps: Int?
    var cadence = CadenceWatch()
    var distance = 0.0
    var lastPoint: Vec2?
    /// 真机：几时真系郁过（分钟、停低收尾按佢计，10-18）。
    var clock: WalkMotionClock?
}

// F1 散步、F4 请假
extension AppStore {
    // MARK: - F1 散步（演示：1 秒 = 1 分钟）

    static let walkSpeed = 9.0     // 米/秒（演示加速）
    static let findSpeed = 7.0
    /// 演示：喺有櫈嘅地标停 3 秒（= 3 分钟，够一个落脚点）。
    static let demoPause = 3.0
    /// 演示散步每分钟只行 9 m（真人约 70 m），落脚点半径按比例缩细。
    static let demoStopRadius = 4.0
    /// 落脚点吸附到 60 m 内最近嘅地标；再远就唔算，唔好乱讲地标。
    static let stopSnap = 60.0

    /// manual：用户自己撳「现在出去走走」（演示模式 / 模拟器用演示散步）。
    func startWalk(manual: Bool = false) {
        guard walk == nil, find == nil, map != nil else { return }
        let start = scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
        var near = Array(landmarks.sorted { $0.pos.distance(to: start) < $1.pos.distance(to: start) }.prefix(3))
        // 路线上要有一个有櫈嘅地标（演示落脚点）
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
        // 自己撳「出門」先切去今日页；真机自动开始唔切页（A92）
        tab = .today
        beginWalk(route: route, manual: manual)
        track.pauseAt = seat?.0
        track.pauseSeat = seat?.1
        startTicker()
    }

    private func beginWalk(route: [Vec2], start: Date = Date(), live: Bool = false, manual: Bool = false) {
        walk = WalkSession(start: start, route: route)
        track = WalkTrack()
        track.manual = manual
        if live { track.clock = WalkMotionClock(start: start, now: Date()) }
        if !live { track.stops = StopDetector(radius: Self.demoStopRadius) }
        if live { walkDetector.startSteps(from: start) }
        community.publishOuting(landmarkID: nearestLandmark(to: route[0])?.id)     // 出门提醒（E-1）：自动 / 手动开始都发
        paceTip = nil
        say(manual ? L.t("好，開始記錄今次散步。行完撳「結束散步」，返到屋企都會自動停。", "好，开始记录这次散步。走完点「结束散步」，回到家也会自动停。", "OK, recording this walk. Tap “End walk” when done. It also stops when you get home.")
                   : L.t("偵測到你出咗門，開始記錄，唔使撳任何掣。", "检测到你出门了，开始记录，不用按任何按钮。", "Looks like you're out. Recording now, no need to tap anything."))
        Haptics.light()
        scene.followID = "me"
        scene.setCamera(target: route[0], distance: scene.overviewDistance * 0.85, animated: true)
        syncScene()
        walkBegan(live: live)      // 定位纪录、背景通知（AppStore+Location）
    }

    /// A-3：自己撳「现在出去走走（开始记录）」：即刻开始记录同播报。真机用定位（未行出屋企前唔会因为喺屋企收尾）；
    /// 演示模式、冇动作感应（模拟器）就用演示散步。走满 10 分钟「今日三件事」照样打勾。
    func startManualWalk() {
        guard walk == nil, find == nil, let m = map else { return }
        let d = walkDetector
        guard WalkDetector.isAvailable, !demoMode, phase == .main else { startWalk(manual: true); return }
        if !d.running { startWalkDetection() }
        d.requestWhenInUseIfNeeded()
        // 之前锁机时已经行紧嘅一段先补记，今次由而家计
        settlePendingWalk(stoppedAt: Date())
        d.pendingWalk = nil
        let home = scene.nearestWalkable(scene.homeTarget + Vec2(x: 0, y: -18))
        var first = home, here: Vec2?, away = false
        if let fix = d.lastFix, let at = d.lastFixAt, Date().timeIntervalSince(at) < 120 {
            let p = m.scenePoint(fix.0)
            let lim = m.half - 4
            here = p
            first = scene.nearestWalkable(Vec2(x: max(-lim, min(lim, p.x)), y: max(-lim, min(lim, p.y))))
            away = LiveWalkGate.isAway(fromHome: p.distance(to: scene.homeTarget), acc: fix.accuracy)
        }
        d.recording = true
        d.gate.awaitingLeave = !away
        d.trail = here.map { abs($0.x) <= m.half - 4 && abs($0.y) <= m.half - 4 ? [scene.nearestWalkable($0)] : [] } ?? []
        tab = .today
        beginWalk(route: [first], start: Date(), live: true, manual: true)
        track.lastPoint = here
        d.setLocating(true)
        startTicker()       // 真机散步：每格更新分钟、睇停低咗几耐
    }

    /// A-3：自己撳「结束散步」。真机按而家计分钟；仲喺外面就等返到屋企先再自动开始（唔会即刻又「检测到你出门了」）。
    func endWalkByUser() {
        guard walk != nil else { return }
        let d = walkDetector
        guard d.recording else { finishWalk(reason: .user); return }     // 演示散步
        let away = d.lastFix != nil && !lastFixAtHome
        finishLiveWalk(endAt: liveEndTime(), reason: .user)
        if away { d.gate.quiet(until: Date().addingTimeInterval(LiveWalkGate.userEndQuiet), untilHome: true) }
    }

    func remainingRoute(_ w: WalkSession) -> [Vec2] {
        let (pt, idx) = point(along: w.route, at: w.travelled)
        // 演示落脚点：停喺度
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
                // 每格最多当 1 秒：退咗后台再返嚟唔会一下记几百分钟（A75）；机慢偶然一格长啲都照计
                let dt = min(Date().timeIntervalSince(last), 1)
                last = Date()
                self.tick(dt)
            }
        }
    }

    func tick(_ dt: Double) {
        if walk != nil, !walkDetector.recording {
            // 演示散步嘅时钟：过去搵人途中都照计（都係行紧路）
            track.elapsed += dt
            if find != nil, let w = walk {
                if w.minutes != Int(track.elapsed) { walk?.minutes = Int(track.elapsed) }
                // 等对方、见面倾偈都係停低：照样计落脚点
                if let c = track.stops.add(myPosition(), at: w.start.addingTimeInterval(track.elapsed * 60)) { addStop(at: c) }
            }
        }
        if var f = find { tickFind(&f, dt); find = f }
        else if var w = walk, !walkDetector.recording { tickWalk(&w, dt) }
        else if walk != nil { liveTick() }      // 真机散步（自动、手动）：分钟按真系郁过嘅时间，停低够耐就收尾
        if find == nil && walk == nil { ticker?.cancel(); ticker = nil }
    }

    func tickWalk(_ w: inout WalkSession, _ dt: Double) {
        let total = pathLength(w.route)
        var pos = point(along: w.route, at: w.travelled).0
        if track.pauseLeft > 0 {
            track.pauseLeft -= dt
            if track.pauseLeft <= 0 { paceTip = nil; walk = w; syncScene() }      // 唞完，起身继续行
        } else if let p = track.pauseAt, pos.distance(to: p) < 5 {
            track.pauseAt = nil
            track.pauseLeft = Self.demoPause
            walk = w; syncScene()                                    // 喺櫈度坐低
        } else {
            w.travelled += dt * Self.walkSpeed
            pos = point(along: w.route, at: w.travelled).0
        }
        w.minutes = Int(track.elapsed)
        markPassed(&w, at: pos)
        if let c = track.stops.add(pos, at: w.start.addingTimeInterval(track.elapsed * 60)) { addStop(at: c) }
        scene.setTrail(prefix(of: w.route, upTo: w.travelled))
        // 演示「行慢咗」：指住前面会坐低嗰张櫈（未坐过先讲）
        let ahead = track.pauseAt != nil ? landmark(track.pauseSeat) : nil
        if w.minutes == 18 && paceTip == nil,
           let seat = ahead ?? landmarks.first(where: { $0.hasSeat && !w.passed.contains($0.id) }) ?? landmarks.first(where: \.hasSeat) {
            paceTip = L.t("行慢咗少少。前面\(seat.name)有櫈，可以唞陣。", "走得慢了一点。前面\(seat.name)有凳子，可以歇一会。", "You've slowed down a bit. There are seats at \(seat.name) ahead. Take a rest.")
            showBanner(BannerItem(symbol: "chair.lounge.fill", text: paceTip!)); say(paceTip!)
        }
        walk = w
        if w.travelled >= total { finishWalk() }
    }

    /// 经过地标（26 m 内）：出门状态更新做呢个地标（只发俾开咗提醒嘅街坊）。
    /// 今日一句唔喺行紧时改：全圈都见到，行紧路时讲会话晒俾人知你出咗門。
    func markPassed(_ w: inout WalkSession, at pos: Vec2) {
        for l in landmarks where !w.passed.contains(l.id) && l.pos.distance(to: pos) < 26 {
            w.passed.append(l.id)
            community.publishOuting(landmarkID: l.id)
        }
    }

    /// 落脚点 → 最近地标（F1：对外只用落脚点对应嘅地标）。
    func addStop(at c: Vec2) {
        guard let l = nearestLandmark(to: c), l.pos.distance(to: c) <= Self.stopSnap, !track.stopIDs.contains(l.id) else { return }
        track.stopIDs.append(l.id)
        community.publishOuting(landmarkID: l.id)
    }

    enum WalkEnd { case home, stopped, riding, user }

    /// 收尾。endAt：真机按几时停低 / 最后定位计分钟。
    func finishWalk(endAt: Date? = nil, reason: WalkEnd = .home) {
        guard let w = walk else { return }
        walkingWith = nil
        let live = walkDetector.recording
        var minutes = w.minutes
        if live {
            // 10-18：计到最后真系郁过嗰刻（坐低唔计），步数做下限
            let end = endAt ?? liveEndTime()
            minutes = WalkMotionClock.minutes(start: w.start, end: end, steps: walkDetector.seated ? nil : track.steps, now: max(end, Date()))
        }
        // 真机：唔够 2 分钟又行唔到 100 m（定位跳咗一下），唔记录（A74）
        let tooShort = live && minutes < 2 && track.distance < 100
        let t = track
        walk = nil
        walkDetector.reset()
        scene.followID = nil
        scene.setTrail([])
        if !tooShort {
            // 轮椅唔记步数（按分钟估算）
            recordWalk(minutes: max(minutes, 1), landmarks: w.passed, simulated: !live, steps: live && !walkDetector.seated ? t.steps : nil, stops: t.stopIDs)
        }
        community.publishOuting(landmarkID: nil)
        paceTip = nil
        track = WalkTrack()
        syncScene()
        scene.resetCamera()
        let m = max(minutes, 1)
        switch (tooShort, reason) {
        case (true, _): say(L.t("行得太短，今次唔記錄。而家已經隱身。", "走得太短，这次不记录。现在已经隐身。", "Too short to record this time. You're now hidden."))
        case (_, .home): say(L.t("返到屋企喇。今日行咗 \(m) 分鐘，經過 \(w.passed.count) 個地方。而家已經隱身。", "到家了。今天走了 \(m) 分钟，经过 \(w.passed.count) 个地方。现在已经隐身。", "You're home. You walked \(m) min today and passed \(w.passed.count) places. You're now hidden."))
        case (_, .stopped): say(L.t("停低咗一陣，今次散步記好咗：行咗 \(m) 分鐘。而家已經隱身。", "停了一会儿，这次散步已记好：走了 \(m) 分钟。现在已经隐身。", "You stopped for a while. Walk saved: \(m) min. You're now hidden."))
        case (_, .riding): say(L.t("上咗車，今次散步記好咗：行咗 \(m) 分鐘。而家已經隱身。", "上车了，这次散步已记好：走了 \(m) 分钟。现在已经隐身。", "You got on a vehicle. Walk saved: \(m) min. You're now hidden."))
        case (_, .user): say(L.t("好，今次散步記好咗：行咗 \(m) 分鐘。而家已經隱身。", "好，这次散步记好了：走了 \(m) 分钟。现在已经隐身。", "OK, walk saved: \(m) min. You're now hidden."))
        }
        Haptics.success()
        walkEnded(live: live, minutes: m, places: w.passed.count, reason: reason, recorded: !tooShort)   // AppStore+Location
    }

    // MARK: - F1 真机散步检测（只在真机、关咗演示模式、完成首次使用后；见 WalkDetector）

    static let nearHome = 80.0      // 停低 5 分钟又喺呢个范围内，都算返到屋企
    static let staleWalk: TimeInterval = 15 * 60
    static let backgroundKey = "walkBackgroundSince"

    /// 权限框（动作与健身、定位、通知）要等首次使用的同意页之后先弹。
    func startWalkDetection() {
        requestNotificationsIfReady()
        guard WalkDetector.isAvailable, !demoMode, phase == .main else { return }
        let d = walkDetector
        d.onEvent = { [weak self] e in self?.handleWalkEvent(e) }
        d.seated = mobilityChoice == .wheelchair
        let since = takeBackgroundMark()
        let resuming = d.recording && walk != nil
        // 返前台：睇完活动纪录先开定位、判断开始 / 收尾（唔好俾第一个定位抢先收尾或者开始，A55）
        guard resuming || since != nil else {
            d.start()
            d.setLocating(d.moving || d.recording)     // 前台：一直开准确定位（已经开紧检测都要，C-1）
            return
        }
        if since != nil { d.pendingWalk = nil }     // 由 mark 起重新睇过
        d.catchUps += 1
        d.start()
        Task {
            if resuming { await resumeLiveWalk() } else if let since { await backfill(from: since, to: Date()) }
            d.catchUps -= 1
            if !d.catchingUp, d.running { d.setLocating(d.moving || d.recording) }
        }
    }

    /// 退到后台：记低由几时开始冇定位（记录中就由今次散步开始计；未接手嘅最后一段由佢开始计），
    /// 返前台（或者下次打开）用嚟补记。
    func markBackground() {
        let d = walkDetector
        guard d.running else { return }
        let mark = d.recording ? (walk?.start ?? Date()) : min(d.pendingWalk?.start ?? Date(), Date())
        UserDefaults.standard.set(mark, forKey: Self.backgroundKey)
        // 前台先一直开嘅准确定位：退后台就按返行唔行路（记录紧照开）
        if !d.recording { d.setLocating(d.moving) }
    }

    func takeBackgroundMark() -> Date? {
        let d = UserDefaults.standard.object(forKey: Self.backgroundKey) as? Date
        UserDefaults.standard.removeObject(forKey: Self.backgroundKey)
        // 系统只留 7 日活动纪录
        return d.map { max($0, Date().addingTimeInterval(-7 * 86400)) }
    }

    /// 记录中退过后台（锁屏放入袋）：用 Core Motion 活动纪录睇吓背景期间行到几时。
    func resumeLiveWalk() async {
        let d = walkDetector
        guard let w = walk, d.recording else { return }
        let now = Date()
        let seen = d.lastFixAt ?? w.start
        guard now.timeIntervalSince(seen) > 2 * 60 else { return }      // 只係离开咗一阵：继续跟定位
        let samples = await d.activities(from: w.start, to: now)
        guard walk?.start == w.start, d.recording else { return }
        guard let samples else {
            // 冇活动纪录：离开好耐就按最后一个定位收尾，唔好将喺屋企嘅时间都算落去
            if now.timeIntervalSince(seen) > Self.staleWalk { finishLiveWalk(endAt: seen) }
            return
        }
        let segs = WalkBackfill.segments(samples, until: now, minLength: 0)
        let current = segs.first { $0.start <= seen.addingTimeInterval(120) && $0.end >= seen.addingTimeInterval(-120) }
        let end = max(seen, current?.end ?? seen)
        if end >= now.addingTimeInterval(-60) { track.clock?.moved(at: now); return }   // 仲行紧：继续跟定位
        finishLiveWalk(endAt: end)
        await backfill(from: end, to: now)
    }

    /// A05：背景 / 锁屏期间冇定位，用 Core Motion 活动纪录补记行路时段（只有分钟、步数，冇地标、冇落脚点）。
    /// 最后一段（仲行紧 / 2 分钟内啱啱停）先交俾定位接手；接唔到（停低咗、返到屋企、喺 400 m 外）就按停低嘅时间补记。
    func backfill(from: Date, to: Date) async {
        let d = walkDetector
        guard to.timeIntervalSince(from) >= 60, let samples = await d.activities(from: from, to: to) else { return }
        let (done, tail) = WalkBackfill.split(samples, until: to)
        var total = 0
        for s in done { total += await recordBackfill(s) }
        if total > 0 { toast(L.t("App 喺背景嗰陣你行咗 \(total) 分鐘，已經補記低（冇地標）。", "App 在后台时你走了 \(total) 分钟，已补记（没有地标）。", "You walked \(total) min while the app was in the background. Added it (no landmarks).")) }
        guard let tail, !d.recording else { return }
        d.pendingWalk = tail
        // 2 分钟后都未开始真机散步、而家又冇行路：按停低嘅时间补记
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(WalkBackfill.mergeGap))
            guard let self, d.pendingWalk == tail, !d.moving else { return }
            self.settlePendingWalk(stoppedAt: d.stillSince ?? Date())
        }
    }

    /// 补记一段（轮椅唔记步数）。返回分钟数。
    private func recordBackfill(_ s: DateInterval) async -> Int {
        let m = Int(s.duration / 60)
        guard m > 0 else { return 0 }
        let steps = await walkDetector.steps(from: s.start, to: s.end)
        recordWalk(minutes: m, landmarks: [], simulated: false, day: s.start, steps: steps)
        return m
    }

    /// 最后一段冇接到真机散步：按停低嘅时间补记（少过 5 分钟唔记）。
    func settlePendingWalk(stoppedAt: Date) {
        let d = walkDetector
        guard let p = d.pendingWalk, !d.recording else { return }
        d.pendingWalk = nil
        guard let s = p.interval(stoppedAt: stoppedAt) else { return }
        Task {
            let m = await recordBackfill(s)
            if m > 0 { toast(L.t("App 喺背景嗰陣你行咗 \(m) 分鐘，已經補記低（冇地標）。", "App 在后台时你走了 \(m) 分钟，已补记（没有地标）。", "You walked \(m) min while the app was in the background. Added it (no landmarks).")) }
        }
    }

    /// 最后一个定位喺屋企附近（用嚟决定最后一段即刻补记）。
    private var lastFixAtHome: Bool {
        guard let fix = walkDetector.lastFix, let m = map else { return false }
        return LiveWalkGate.isHome(fromHome: m.scenePoint(fix.0).distance(to: scene.homeTarget), acc: fix.accuracy)
    }

    /// 真机收尾；之后冇行路就熄定位（A74）。
    func finishLiveWalk(endAt: Date? = nil, reason: WalkEnd = .home) {
        finishWalk(endAt: endAt, reason: reason)
        walkDetector.setLocating(walkDetector.moving)
    }

    func handleWalkEvent(_ e: WalkDetector.Event) {
        let d = walkDetector
        // 返前台睇紧活动纪录：只收步数，其他等睇完先算（睇完会按 moving 开返定位）
        if d.catchingUp, !e.isSteps { return }
        switch e {
        case .walking(let on):
            // 行路时开定位；停低但仲喺外面（记录中）也保持
            d.setLocating(on || d.recording)
            if on, d.recording { track.clock?.moved(at: Date()) }
            // 背景补记嘅最后一段：返到屋企停低就即刻补记
            if !on, d.pendingWalk != nil, lastFixAtHome { settlePendingWalk(stoppedAt: Date()) }
        case .riding:
            // 坐车 / 踩单车唔算散步
            if d.recording { finishLiveWalk(reason: .riding) }
            settlePendingWalk(stoppedAt: Date())
            d.setLocating(false)
        case .still(let since):
            // 停低 2 分钟：未接手嘅最后一段按停低嘅时间补记
            settlePendingWalk(stoppedAt: since)
            guard d.recording, walk != nil else { return }
            // 停低 2 分钟：落脚点（定位企定唔出新点，靠呢度计时）
            if let c = track.stops.hold(at: Date()) { addStop(at: c) }
            // 收唔收尾由 liveTick 按「最后真系郁过」判断（10-18：以前用呢个计时，散步前已经开始嘅计时会即刻收咗啱开始嘅散步）
            liveTick()
        case .location(let g, let acc):
            // 散步被别处清掉（重置演示、重新生成）时同步收尾
            if d.recording, walk == nil { d.reset() }
            guard let m = map, phase == .main, find == nil else { return }
            let p = m.scenePoint(g)
            let inside = abs(p.x) <= m.half - 4 && abs(p.y) <= m.half - 4
            let fromHome = p.distance(to: scene.homeTarget)
            if d.recording, walk != nil {
                let t = d.lastFixAt ?? Date()
                track.clock?.fix(p, acc: acc, at: t)
                if d.moving { track.clock?.moved(at: t) }
            }
            switch d.gate.decide(fromHome: fromHome, acc: acc, at: d.lastFixAt ?? Date(), recording: d.recording, moving: d.stepping, maxStart: d.maxStart) {
            case .finish: finishLiveWalk()
            case .step: liveStep(p, inside: inside, half: m.half)
            case .minutesOnly: liveMinutes()
            case .start:
                // 底座外都照样开始（A06）：镜头同起点夹返入底座，轨迹只画底座内
                d.recording = true
                d.trail = inside ? [scene.nearestWalkable(p)] : []
                let lim = m.half - 4
                let first = scene.nearestWalkable(Vec2(x: max(-lim, min(lim, p.x)), y: max(-lim, min(lim, p.y))))
                // 开始时间：背景补记嘅最后一段（锁屏时已经开始行）；冇就用 Core Motion 判断开始行路嘅时间（10 分钟内先信）
                let start = d.pendingWalk?.start ?? d.movingSince.flatMap { Date().timeIntervalSince($0) < 600 ? $0 : nil } ?? Date()
                d.pendingWalk = nil
                beginWalk(route: [first], start: start, live: true)
                track.lastPoint = p
                startTicker()       // 分钟、停低收尾每格睇
            case .none:
                // 背景补记嘅最后一段：人已经喺屋企（Core Motion 判咗停低）就即刻补记
                if let pw = d.pendingWalk, pw.end != nil || !d.moving, LiveWalkGate.isHome(fromHome: fromHome, acc: acc) {
                    settlePendingWalk(stoppedAt: d.lastFixAt ?? Date())
                }
            }
        case .steps(let n, let cadence):
            // 轮椅唔计步数、步频（按分钟估算）
            guard d.recording, !d.seated, let w = walk else { return }
            track.steps = n
            track.clock?.steps(n, at: Date())
            // F9：步频明显下降就提示休息，讲一次
            if let c = cadence, paceTip == nil, track.cadence.add(c, at: Date(), walkStart: w.start) {
                let here = myPosition()
                let seat = landmarks.filter(\.hasSeat).min { $0.pos.distance(to: here) < $1.pos.distance(to: here) }
                paceTip = seat.map { L.t("行慢咗少少。附近\($0.name)有櫈，可以唞陣。", "走得慢了一点。附近\($0.name)有凳子，可以歇一会。", "You've slowed down a bit. There are seats at \($0.name) nearby. Take a rest.") } ?? L.t("行慢咗少少，搵個地方唞陣先。", "走得慢了一点，先找个地方歇一会。", "You've slowed down a bit. Find a place to rest.")
                showBanner(BannerItem(symbol: "chair.lounge.fill", text: paceTip!)); say(paceTip!)
            }
        }
    }

    /// 真机：每个新定位点接到轨迹上；走出底座的点不画，只计时间、距离、落脚点，小人停喺底座边（C-2）。
    func liveStep(_ p: Vec2, inside: Bool, half: Double) {
        liveMinutes()
        if let last = track.lastPoint { track.distance += last.distance(to: p) }
        track.lastPoint = p
        if let t = walkDetector.lastFixAt, let c = track.stops.add(p, at: t) { addStop(at: c) }
        guard var w = walk else { return }
        let d = walkDetector
        // 10-18：小人同轨迹贴返最近嘅路（GPS 点成日落喺楼入面，小人俾楼顶遮住，睇落似冇小人）
        let q = inside ? scene.nearestWalkable(p) : p
        if inside, d.trail.last.map({ $0.distance(to: q) >= 3 }) ?? true {
            d.trail.append(q)
            markPassed(&w, at: p)
            w.route = d.trail
            w.travelled = pathLength(d.trail)
            scene.setTrail(d.trail)
            walk = w
            syncScene()
        } else if !inside {
            // 行出模型：小人停喺最近嘅底座边（唔画出去嗰段路）
            let lim = half - 4
            let edge = scene.nearestWalkable(Vec2(x: max(-lim, min(lim, p.x)), y: max(-lim, min(lim, p.y))))
            guard w.route.last.map({ $0.distance(to: edge) >= 3 }) ?? true else { return }
            w.route = d.trail + [edge]
            w.travelled = pathLength(w.route)
            walk = w
            syncScene()
        }
    }

    /// 散步分钟（10-18）：按最后真系郁过嘅时间计（行紧就跟住钟走，坐低就停），步数做下限。
    /// 手动开始又乜讯号都收唔到（冇定位、冇动作权限）：按钟计。
    func liveMinutes() {
        guard let w = walk else { return }
        let now = Date()
        let m = WalkMotionClock.minutes(start: w.start, end: liveEndTime(now), steps: walkDetector.seated ? nil : track.steps, now: now)
        if w.minutes != m { walk?.minutes = m }
    }

    /// 真机散步计到几时：行紧到而家；停低咗到最后郁嗰刻。
    func liveEndTime(_ now: Date = Date()) -> Date {
        guard let c = track.clock, c.signal || !track.manual else { return now }
        return c.endTime(now)
    }

    /// 真机散步每格：Core Motion 话行紧就当郁紧；更新分钟；停低够耐（屋企附近 5 分钟、外面 10 分钟）就收尾，坐嘅时间唔计。
    func liveTick() {
        let d = walkDetector
        guard d.recording, walk != nil, !d.catchingUp, var c = track.clock else { return }
        let now = Date()
        if d.moving { c.moved(at: now) }
        track.clock = c
        liveMinutes()
        guard c.signal || !track.manual else { return }
        let home = liveNearHome
        guard c.shouldFinish(now, nearHome: home) else { return }
        finishLiveWalk(endAt: c.lastMoveAt, reason: home ? .home : .stopped)
    }

    /// 最后一个定位喺屋企附近（楼里 GPS 差，可能一直收唔到 40 m 内嘅点）。手动开始未行出屋企唔算。
    private var liveNearHome: Bool {
        guard !walkDetector.gate.awaitingLeave, let fix = walkDetector.lastFix, let m = map else { return false }
        return m.scenePoint(fix.0).distance(to: scene.homeTarget) - fix.accuracy < Self.nearHome
    }

    // MARK: - F4 请假（请假日连续天数唔断、唔加）

    /// 请假按钮嘅选项：今日、聽日、由今日起 3 日、7 日。
    static let leaveChoices = [LeaveRequest(startOffset: 0, days: 1), LeaveRequest(startOffset: 1, days: 1),
                               LeaveRequest(startOffset: 0, days: 3), LeaveRequest(startOffset: 0, days: 7)]

    /// 由今日起第 startOffset 日开始请 days 日假（0 = 今日）。语音「聽日請假」「請三日假」用 LeaveRequest.parse 再调呢个。
    func requestLeave(days: Int = 1, startOffset: Int = 0) {
        let r = LeaveRequest(startOffset: max(0, startOffset), days: max(1, min(LeaveRequest.maxDays, days)))
        let added = leaveKeys(r).filter { !leaveDays.contains($0) }
        leaveDays.formUnion(added)
        uploadLeave(added, on: true)
        refreshMe()
        say(L.t("收到，\(leaveTitle(r))。連續 \(me.streakDays) 日會保留。", "收到，\(leaveTitle(r))。连续 \(me.streakDays) 天会保留。", "Got it: \(leaveTitle(r)). Your \(me.streakDays)-day streak is kept."))
        Haptics.light()
    }

    /// 撤回某次请假（例如语音复述卡按「唔係」）。
    func cancelLeave(days: Int = 1, startOffset: Int = 0) {
        let removed = leaveKeys(LeaveRequest(startOffset: max(0, startOffset), days: max(1, days))).filter(leaveDays.contains)
        leaveDays.subtract(removed)
        uploadLeave(removed, on: false)
        refreshMe()
    }

    /// 语音请假（语音线喺 handle 嘅 .leave 调）：按原句判断日子（「聽日請假」「請三日假」），请假，返回复述卡标题。
    @discardableResult
    func requestLeave(fromVoice text: String) -> String {
        let r = LeaveRequest.parse(text, today: now)
        requestLeave(days: r.days, startOffset: r.startOffset)
        return leaveTitle(r)
    }

    /// 语音请假卡按「唔係」：按原句撤回同一段。
    func cancelLeave(fromVoice text: String) {
        let r = LeaveRequest.parse(text, today: now)
        cancelLeave(days: r.days, startOffset: r.startOffset)
    }

    /// 请假逐日上传（leaves 表）：只传真系变咗嘅日子。
    private func uploadLeave(_ keys: [String], on: Bool) {
        for k in keys { community.setLeave(day: k, on: on) }
    }

    func leaveKeys(_ r: LeaveRequest) -> [String] {
        let base = now
        return (0..<r.days).map { LocalStore.dayKey(base.addingTimeInterval(Double(r.startOffset + $0) * 86400)) }
    }

    /// 「今日請假」「聽日請假」「由今日起請 3 日假（到 10 月 10 號）」。
    func leaveTitle(_ r: LeaveRequest) -> String {
        let from = r.startOffset < 4 ? (L.isEn ? ["today", "tomorrow", "the day after", "in 3 days"] : L.isCmn ? ["今天", "明天", "后天", "大后天"] : ["今日", "聽日", "後日", "大後日"])[r.startOffset] : dateLabel(now.addingTimeInterval(Double(r.startOffset) * 86400))
        guard r.days > 1 else { return L.t("\(from)請假", "\(from)请假", "Day off \(from)") }
        return L.t("由\(from)起請 \(r.days) 日假（到 \(dateLabel(now.addingTimeInterval(Double(r.startOffset + r.days - 1) * 86400)))）", "从\(from)起请 \(r.days) 天假（到 \(dateLabel(now.addingTimeInterval(Double(r.startOffset + r.days - 1) * 86400)))）", "\(r.days) days off from \(from) (until \(dateLabel(now.addingTimeInterval(Double(r.startOffset + r.days - 1) * 86400))))")
    }

    /// 请假选单上嘅字：画面上唔讲「請假」（似返工），讲「唔出門」（UX 评审 16；10-18 测试：「不走」睇唔明）。语音照认「請假」。
    func leaveMenuLabel(_ r: LeaveRequest) -> String {
        guard r.days > 1 else {
            let from = r.startOffset < 4 ? (L.isEn ? ["today", "tomorrow", "the day after", "in 3 days"] : L.isCmn ? ["今天", "明天", "后天", "大后天"] : ["今日", "聽日", "後日", "大後日"])[r.startOffset] : dateLabel(now.addingTimeInterval(Double(r.startOffset) * 86400))
            return L.t("\(from)唔出門", "\(from)不出门", "Not going out \(from)")
        }
        let last = dateLabel(now.addingTimeInterval(Double(r.startOffset + r.days - 1) * 86400))
        return L.t("接住 \(r.days) 日唔出門（到 \(last)）", "接下来 \(r.days) 天不出门（到 \(last)）", "Not going out for \(r.days) days (until \(last))")
    }

    /// 英文日期用：月份缩写（「20 Oct」）。
    nonisolated static func monthAbbr(_ m: Int) -> String {
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][max(1, min(12, m)) - 1]
    }

    func dateLabel(_ d: Date) -> String {
        let c = Self.hk.dateComponents([.month, .day], from: d)
        return L.t("\(c.month ?? 0) 月 \(c.day ?? 0) 號", "\(c.month ?? 0) 月 \(c.day ?? 0) 日", "\(c.day ?? 0) \(Self.monthAbbr(c.month ?? 1))")
    }

    /// 今日或之后请咗嘅连续一段（用日数，唔好用 Date 比较：now 每次都係新嘅 Date()）。
    private var upcomingLeave: LeaveRequest? {
        let base = now
        func on(_ i: Int) -> Bool { leaveDays.contains(LocalStore.dayKey(base.addingTimeInterval(Double(i) * 86400))) }
        guard let first = (0...LeaveRequest.maxDays).first(where: on) else { return nil }
        var days = 1
        while on(first + days) && days < 366 { days += 1 }
        return LeaveRequest(startOffset: first, days: days)
    }

    /// 今日页请假一栏：冇请假时 nil。
    var leaveSummary: String? {
        guard let u = upcomingLeave else { return nil }
        let last = dateLabel(now.addingTimeInterval(Double(u.startOffset + u.days - 1) * 86400))
        switch (u.startOffset, u.days) {
        case (0, 1): return L.t("今日唔出門，連續日數唔會斷", "今天不出门，连续天数不会断", "Not going out today. Streak won't break.")
        case (0, _): return L.t("到 \(last)都唔出門，連續日數唔會斷", "到 \(last)都不出门，连续天数不会断", "Not going out until \(last). Streak won't break.")
        case (1, 1): return L.t("聽日唔出門，連續日數唔會斷", "明天不出门，连续天数不会断", "Not going out tomorrow. Streak won't break.")
        default: return L.t("\(dateLabel(now.addingTimeInterval(Double(u.startOffset) * 86400)))起唔出門，連續日數唔會斷", "\(dateLabel(now.addingTimeInterval(Double(u.startOffset) * 86400)))起不出门，连续天数不会断", "Not going out from \(dateLabel(now.addingTimeInterval(Double(u.startOffset) * 86400))). Streak won't break.")
        }
    }

    /// 今日请咗假就只撤回今日（之后请咗嘅照留；语音复述卡按「唔係」都係行呢度）；冇就请今日。
    func toggleLeave() {
        guard leaveDays.contains(LocalStore.dayKey(now)) else { requestLeave(); return }
        cancelLeave(days: 1, startOffset: 0)
        say(L.t("撤回咗今日嘅請假。", "已撤回今天的请假。", "Today's day off cancelled."))
        Haptics.light()
    }

    /// 请假选单入面嘅「撤回」（今日未请、之后有假时）：例如「撤回聽日嘅假」「撤回 10 月 12 號起嘅假」。
    var withdrawLeaveLabel: String? {
        guard let u = upcomingLeave, u.startOffset > 0 else { return nil }
        let from = u.startOffset == 1 ? L.t("聽日", "明天", "tomorrow") : dateLabel(now.addingTimeInterval(Double(u.startOffset) * 86400))
        return u.days == 1 ? L.t("\(from)照出門（撤回）", "\(from)照常出门（撤回）", "Going out \(from) after all (undo)") : L.t("\(from)起照出門（撤回 \(u.days) 日）", "\(from)起照常出门（撤回 \(u.days) 天）", "Going out from \(from) after all (undo \(u.days) days)")
    }

    /// 由聽日起第一日冇请假嘅日子（1 = 聽日）：「今日三件事」约人唔好约喺唔出門嗰几日（10-18）。
    var nextWalkDayOffset: Int {
        let base = now
        return (1...(LeaveRequest.maxDays + 1)).first { !leaveDays.contains(LocalStore.dayKey(base.addingTimeInterval(Double($0) * 86400))) } ?? 1
    }

    /// 请假选单嘅选项：已经全部请咗嘅唔再列。
    var leaveMenuChoices: [LeaveRequest] {
        Self.leaveChoices.filter { !leaveKeys($0).allSatisfy(leaveDays.contains) }
    }

    /// 「撤回」：撤回今日或之后最近嗰一段假（连住嗰几日一齐）。
    func withdrawLeave() {
        guard let u = upcomingLeave else { return }
        let removed = leaveKeys(u).filter(leaveDays.contains)
        leaveDays.subtract(removed)
        uploadLeave(removed, on: false)
        refreshMe()
        say(L.t("撤回咗請假。", "已撤回请假。", "Day off cancelled."))
        Haptics.light()
    }
}
