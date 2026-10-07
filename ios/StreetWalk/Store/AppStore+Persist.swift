import SwiftUI

// 持久化（LocalStore）、每日记录与连续天数、CommunityService 事件
extension AppStore {
    // MARK: - 读取与保存

    /// 启动时读回上次的数据。自动演示（-script / -script2）和 -resetData 从干净状态开始。
    func restoreSaved() {
        if LaunchArgs.has("-script") || LaunchArgs.has("-script2") || LaunchArgs.has("-script3") || LaunchArgs.has("-resetData") || LaunchArgs.has("-resetOnboarding") {
            LocalStore.clear()
        }
        let s = LocalStore.load()
        restoring = true
        savedMapKey = s.mapKey
        savedNeighbors = s.neighbors
        appointments = s.appointments
        reports = s.reports
        landmarkNames = s.landmarkNames
        walkLog = s.walkLog
        leaveDays = s.leaveDays
        if demoMode && walkLog.isEmpty { seedDemoHistory() }
        restoring = false
    }

    /// 改动后 0.5 秒写盘（连续改动只写一次）。
    func scheduleSave() {
        guard !restoring else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        LocalStore.save(SavedState(mapKey: savedMapKey, neighbors: savedNeighbors, appointments: appointments, reports: reports,
                                   landmarkNames: landmarkNames, walkLog: walkLog, leaveDays: leaveDays))
    }

    /// 底座换了（另一格或另一座楼）：约会地点、反映位置、改过的地标名都作废，街坊关系和散步记录保留。
    func adoptMapKey() {
        guard let m = map else { return }
        let key = "\(m.tile)|\(scene.homeBuildingID.map(String.init) ?? "-")"
        guard key != savedMapKey else { return }
        if savedMapKey != nil {
            appointments = []
            reports = []
            landmarkNames = [:]
        }
        savedMapKey = key
        scheduleSave()
    }

    func applyLandmarkNames() {
        for i in landmarks.indices {
            guard let name = landmarkNames[landmarks[i].id] else { continue }
            landmarks[i].name = name
            scene.renameLandmark(landmarks[i].id, to: name)
        }
    }

    /// 街坊关系变了：同步到保存的关系表。
    func storeLink(_ r: Resident) {
        if r.isNeighbor {
            savedNeighbors[r.id] = NeighborLink(since: r.neighborSince ?? Date(), send: r.sendRemind, receive: r.receiveRemind)
        } else {
            savedNeighbors[r.id] = nil
        }
        scheduleSave()
    }

    /// 清除本机全部记录（设置页）。
    func clearAllData() {
        LocalStore.clear()
        restoring = true
        savedNeighbors = [:]; appointments = []; reports = []; landmarkNames = [:]; walkLog = [:]; leaveDays = []
        if demoMode { seedDemoHistory() }
        restoring = false
        saveNow()
    }

    // MARK: - 每日记录与连续天数

    func log(for d: Date) -> DayLog {
        guard let l = walkLog[LocalStore.dayKey(d)], demoMode || !l.demo else { return DayLog() }
        return l
    }

    /// 连续天数：从今日（今日未行就从昨日）往回数，行过或请过假都算一日。演示模式关掉后不计示範纪录。
    func myStreak() -> Int {
        var day = now
        func counts(_ d: Date) -> Bool { log(for: d).walks > 0 || leaveDays.contains(LocalStore.dayKey(d)) }
        if !counts(day) { day = day.addingTimeInterval(-86400) }
        var n = 0
        while counts(day) && n < 3650 { n += 1; day = day.addingTimeInterval(-86400) }
        return n
    }

    /// 连续天数里有没有示範纪录（界面要标明）。
    var streakHasDemo: Bool {
        guard demoMode else { return false }
        var day = now
        for _ in 0..<max(myStreak() + 1, 1) {
            if walkLog[LocalStore.dayKey(day)]?.demo == true { return true }
            day = day.addingTimeInterval(-86400)
        }
        return false
    }

    /// 本月我行咗几多步（按每分钟约 100 步估算；没有计步器时的近似）。
    var myMonthSteps: Int {
        let prefix = String(LocalStore.dayKey(now).prefix(7))
        return walkLog.filter { $0.key.hasPrefix(prefix) && (demoMode || !$0.value.demo) }.reduce(0) { $0 + $1.value.minutes * 100 }
    }

    var myMonthWalks: Int {
        let prefix = String(LocalStore.dayKey(now).prefix(7))
        return walkLog.filter { $0.key.hasPrefix(prefix) && (demoMode || !$0.value.demo) }.reduce(0) { $0 + $1.value.walks }
    }

    /// 记一次散步。
    func recordWalk(minutes: Int, landmarks passed: [String]) {
        let key = LocalStore.dayKey(now)
        var l = walkLog[key] ?? DayLog()
        if l.demo { l = DayLog(minutes: l.minutes, walks: l.walks, landmarks: l.landmarks, demo: false) }
        l.minutes += minutes
        l.walks += 1
        l.landmarks += passed.filter { !l.landmarks.contains($0) }
        walkLog[key] = l
        refreshMe()
    }

    /// 我在排行榜上的连续天数、请假状态、今日一句跟着记录更新。
    func refreshMe() {
        guard let i = residents.firstIndex(where: \.isMe) else { return }
        residents[i].streakDays = myStreak()
        residents[i].onLeave = leaveDays.contains(LocalStore.dayKey(now))
        let today = log(for: now)
        var passed = today.landmarks.compactMap(landmark)
        // 示範纪录只有分钟数：当佢行过自己常去嗰度，免得"行咗 24 分鐘"同"仲未出門"矛盾。
        if passed.isEmpty, today.walks > 0, let home = landmark(residents[i].homeLandmarkID) { passed = [home] }
        residents[i].todayLine = ai.dailyLine(for: residents[i], passed: passed)
    }

    /// 演示模式第一次启动：放过去 8 日 + 今日早上的示範纪录，连续 9 日。都标 demo，关掉演示模式就不算。
    func seedDemoHistory() {
        let mins = [32, 28, 41, 25, 36, 30, 22, 38]
        for (i, m) in mins.enumerated() {
            walkLog[LocalStore.dayKey(now.addingTimeInterval(-Double(i + 1) * 86400))] = DayLog(minutes: m, walks: 1, landmarks: [], demo: true)
        }
        walkLog[LocalStore.dayKey(now)] = DayLog(minutes: 24, walks: 1, landmarks: [], demo: true)
    }

    // MARK: - 别人那边的事（CommunityService 事件）

    func receive(_ e: CommunityEvent) {
        switch e {
        case .neighborOut(let id, let lm): neighborWentOut(id, at: lm)
        case .neighborHome(let id): neighborWentHome(id)
        case .inviteAnswered(let id, let accepted): partnerAnswered(id, accepted: accepted)
        case .invited(let a): invitedBy(a)
        case .reportFollowUp(let id, let text): reportFollowedUp(id, text: text)
        }
    }

    var localCommunity: LocalCommunityService? { community as? LocalCommunityService }
}
