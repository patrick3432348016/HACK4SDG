import SwiftUI

// 持久化（LocalStore）、每日记录与连续天数、CommunityService 事件
extension AppStore {
    // MARK: - 读取与保存

    /// 启动时读回上次的数据。自动演示（-script / -script2）和 -resetData 从干净状态开始。
    func restoreSaved() {
        // 演示模式默认：模拟器开、真机关（A05）；-demo 参数或者设置里改过就照用。
        UserDefaults.standard.register(defaults: ["demoMode": WalkDetector.demoByDefault])
        demoMode = LaunchArgs.has("-demo") || UserDefaults.standard.bool(forKey: "demoMode")
        localCommunity?.demoEnabled = demoMode
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
            self.syncNotifications()
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
        changingHome = false
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
        clearServerData()
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
        // 只补冇纪录嘅日子（真实纪录嗰几日照旧）
        seedDemoHistory()
        scheduleSave()
    }

    /// 关咗演示模式 / 对方已经唔喺圈入面：未完成的约会收埋（对方都唔存在，唔使通知）。
    /// 只收示範街坊嘅约（真后端嘅约以服务器为准：圈成员未拉到唔等于对方唔存在）。
    func closeOrphanAppointments() {
        for i in appointments.indices where appointments[i].isOpen && resident(appointments[i].partnerID) == nil
            && UUID(uuidString: appointments[i].partnerID) == nil {
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
        return LocalStore.streakKeys(walkLog, leaves: leaveDays, today: now, includeDemo: true).contains { walkLog[$0]?.demo == true }
    }

    /// 本月我行咗几多步：真机用计步器量到嘅；冇量到嘅日子（模拟器、演示、背景补记冇步数）按每分钟约 100 步估算。
    var myMonthSteps: Int {
        monthLogs.reduce(0) { $0 + $1.stepEstimate }
    }

    /// 本月步数有冇用估算（界面要写「約」）。
    var myMonthStepsEstimated: Bool { monthLogs.contains(where: \.stepsEstimated) }

    private var monthLogs: [DayLog] {
        let prefix = String(LocalStore.dayKey(now).prefix(7))
        return walkLog.filter { $0.key.hasPrefix(prefix) && (demoMode || !$0.value.demo) }.map(\.value)
    }

    var myMonthWalks: Int {
        let prefix = String(LocalStore.dayKey(now).prefix(7))
        return walkLog.filter { $0.key.hasPrefix(prefix) && (demoMode || !$0.value.demo) }.reduce(0) { $0 + $1.value.walks }
    }

    /// 记一次散步。演示散步（模拟路线）算示範纪录，唔会改当日嘅真实纪录；真机散步是真实纪录，唔会同示範纪录混埋。
    /// day：背景补记时係嗰段行路嘅日子。
    func recordWalk(minutes: Int, landmarks passed: [String], simulated: Bool, day: Date? = nil, steps: Int? = nil, stops: [String] = []) {
        LocalStore.record(&walkLog, key: LocalStore.dayKey(day ?? now), minutes: minutes, landmarks: passed, stops: stops,
                          steps: steps, simulated: simulated)
        refreshMe()
        uploadDay(day ?? now)
    }

    /// 个人资料上传（profiles 表）：完成首次使用、设置页改网名 / 楼层 / 小人、返前台时调（一样就唔再传）。
    func uploadProfile() {
        if let p = communityProfile() { community.updateProfile(p) }
    }

    /// 当日汇总上传（walks 表，一人一日一行）：散步记完、改名令今日一句变咗时调。
    /// 示範纪录唔上传；经过嘅地标只留喺手机（F1 对外只用落脚点，A12），所以只传落脚点。
    func uploadDay(_ day: Date) {
        let key = LocalStore.dayKey(day)
        guard let l = walkLog[key], !l.demo, l.walks > 0 else { return }
        let line = key == LocalStore.dayKey(now) ? me.todayLine : ""
        community.uploadDay(day: key, minutes: l.minutes, steps: l.stepEstimate, landmarkIDs: [], stopLandmarkIDs: l.stops, line: line)
    }

    /// 我在排行榜上的连续天数、请假状态、今日一句跟着记录更新。
    func refreshMe() {
        guard let i = residents.firstIndex(where: \.isMe) else { return }
        residents[i].streakDays = myStreak()
        residents[i].onLeave = leaveDays.contains(LocalStore.dayKey(now))
        residents[i].todayLine = myTodayLine(residents[i])
    }

    /// 今日一句（全圈见到）：只用落脚点地标，唔讲经过边度（F1 对外只有落脚点）。
    func myTodayLine(_ r: Resident) -> String {
        guard !landmarks.isEmpty else { return "" }   // 地图未装好：先唔讲
        let today = log(for: now)
        guard !r.onLeave, today.walks > 0 else { return ai.dailyLine(for: r, passed: []) }
        let stops = today.stops.compactMap(landmark)
        if let s = stops.last { return s.hasSeat ? "\(r.floorLabel)喺\(s.name)坐咗陣" : ai.dailyLine(for: r, passed: stops) }
        // 示範纪录只有分钟数：当佢行过自己常去嗰度，免得"行咗 24 分鐘"同"仲未出門"矛盾。
        if today.demo, let home = landmark(r.homeLandmarkID) { return ai.dailyLine(for: r, passed: [home]) }
        // 真实散步冇落脚点（或者喺背景补记）：照实讲分钟数，唔好编地标。
        return "\(r.floorLabel)今日行咗 \(today.minutes) 分鐘"
    }

    /// 演示模式：放过去 8 日 + 今日早上的示範纪录，连续 9 日。都标 demo，关掉演示模式就不算；已有纪录嘅日子唔郁。
    func seedDemoHistory() {
        LocalStore.seedDemo(&walkLog, today: now)
    }

    /// 地图未装好前，「我」都用真实纪录算（唔好显示后备值）。
    func ensureMeBeforeMap() {
        guard residents.isEmpty, phase == .main else { return }
        residents = [Resident(id: "me", name: "你", floor: floorChoice, colorIndex: colorChoice, mobility: mobilityChoice,
                              streakDays: myStreak(), todayLine: "", isMe: true)]
        refreshMe()
    }

    // MARK: - 别人那边的事（CommunityService 事件）

    func receive(_ e: CommunityEvent) {
        switch e {
        case .neighborOut(let id, let lm): neighborWentOut(id, at: lm); notifyNeighborOut(id)
        case .neighborHome(let id): neighborWentHome(id)
        case .inviteAnswered(let id, let accepted): partnerAnswered(id, accepted: accepted)
        case .invited(let a): receiveInvite(a)
        case .reportFollowUp(let id, let text, let isDemo): reportFollowedUp(id, text: text, isDemo: isDemo)
        default: receiveBackend(e)
        }
    }

    var localCommunity: LocalCommunityService? { community as? LocalCommunityService }
}
