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

    var currentMapKey: String? { map.map { "\($0.tile)|\(scene.homeBuildingID.map(String.init) ?? "-")" } }

    /// 第一次装好底座时记下是哪一格、哪座楼。之后只在真正改咗住嘅楼时（homeChanged）先清跟地图有关的数据，
    /// 喺外面打开、冇定位、离线兜底都唔会清。
    func adoptMapKey() {
        guard savedMapKey == nil, let key = currentMapKey else { return }
        savedMapKey = key
        scheduleSave()
    }

    /// 首次使用 / 改楼完成：换咗楼就作废约会地点、反映位置、改过的地标名（街坊关系和散步记录保留），未完成的约会会通知对方取消。
    func homeChanged() {
        guard let key = currentMapKey else { return }
        if let old = savedMapKey, old != key {
            for i in appointments.indices where appointments[i].isOpen {
                appointments[i].status = .cancelled
                community.updateMeetup(appointments[i])
            }
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

    /// 清除本机全部记录（设置页）。地标改回原名。
    func clearAllData() {
        LocalStore.clear()
        restoring = true
        savedNeighbors = [:]; appointments = []; reports = []; landmarkNames = [:]; walkLog = [:]; leaveDays = []
        if demoMode { seedDemoHistory() }
        restoring = false
        restoreOriginalNames()
        saveNow()
    }

    func restoreOriginalNames() {
        for i in landmarks.indices {
            guard let o = originalLandmarkNames[landmarks[i].id], o != landmarks[i].name else { continue }
            landmarks[i].name = o
            scene.renameLandmark(landmarks[i].id, to: o)
        }
    }

    /// 演示菜单「重置演示」：只清同示範街坊有关的东西（关系、约会、示範回覆、示範纪录），你自己的真实记录唔郁。
    func resetDemoData() {
        let demoIDs = Set(residents.filter(\.isDemo).map(\.id))
        for id in demoIDs { savedNeighbors[id] = nil }
        appointments.removeAll { demoIDs.contains($0.partnerID) }
        for i in reports.indices where reports[i].followUpDemo == true { reports[i].followUp = nil; reports[i].followUpDemo = nil }
        walkLog = walkLog.filter { !$0.value.demo }
        if walkLog[LocalStore.dayKey(now)] == nil { seedDemoHistory() }
        scheduleSave()
    }

    /// 关咗演示模式 / 对方已经唔喺圈入面：未完成的约会收埋（对方都唔存在，唔使通知）。
    func closeOrphanAppointments() {
        for i in appointments.indices where appointments[i].isOpen && resident(appointments[i].partnerID) == nil {
            appointments[i].status = .cancelled
        }
    }

    // MARK: - 每日记录与连续天数

    func log(for d: Date) -> DayLog {
        guard let l = walkLog[LocalStore.dayKey(d)], demoMode || !l.demo else { return DayLog() }
        return l
    }

    func myStreak() -> Int { LocalStore.streak(walkLog, leaves: leaveDays, today: now, includeDemo: demoMode) }

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

    /// 记一次散步。演示散步（模拟路线）算示範纪录；真机散步是真实纪录，唔会同示範纪录混埋。
    func recordWalk(minutes: Int, landmarks passed: [String], simulated: Bool) {
        let key = LocalStore.dayKey(now)
        var l = walkLog[key] ?? DayLog(demo: simulated)
        if simulated { l.demo = true } else if l.demo { l = DayLog() }
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
        case .reportFollowUp(let id, let text, let isDemo): reportFollowedUp(id, text: text, isDemo: isDemo)
        }
    }

    var localCommunity: LocalCommunityService? { community as? LocalCommunityService }
}
