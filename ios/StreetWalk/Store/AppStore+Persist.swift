import SwiftUI

// LocalStore persistence, daily records, streaks and CommunityService events.
extension AppStore {
    // MARK: - Loading and saving

    /// Restore prior data on launch; -script, -script2 and -resetData start clean.
    func restoreSaved() {
        // A05: demo defaults on for simulator, off for devices; respect -demo and saved Settings overrides.
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
        firstDay = s.firstDay
        if demoMode && walkLog.isEmpty { seedDemoHistory() }
        restoring = false
    }

    /// Debounce consecutive changes into one disk write after 0.5 seconds.
    func scheduleSave() {
        guard !restoring else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.saveNow()
            self.syncNotifications()
            self.firstDayCheck()     // Neighbor / meeting changes update the first-day task checklist.
        }
    }

    func saveNow() {
        LocalStore.save(SavedState(mapKey: savedMapKey, neighbors: savedNeighbors, appointments: appointments, reports: reports,
                                   landmarkNames: landmarkNames, walkLog: walkLog, leaveDays: leaveDays, firstDay: firstDay))
    }

    var currentMapKey: String? { map.map { "\($0.tile)|\(scene.homeBuildingID.map(String.init) ?? "-")" } }

    /// Record the initial tile and building; clear map-dependent data only on an actual homeChanged event.
    /// Opening elsewhere, missing location and offline fallback must not clear it.
    func adoptMapKey() {
        guard savedMapKey == nil, let key = currentMapKey else { return }
        savedMapKey = key
        scheduleSave()
    }

    /// Changing home invalidates meeting places, reports and renamed landmarks; retain relationships / walk history and notify peers of unfinished-meeting cancellation.
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

    /// Synchronize relationship changes to the persisted relationship table.
    func storeLink(_ r: Resident) {
        if r.isNeighbor {
            savedNeighbors[r.id] = NeighborLink(since: r.neighborSince ?? Date(), send: r.sendRemind, receive: r.receiveRemind)
        } else {
            savedNeighbors[r.id] = nil
        }
        scheduleSave()
    }

    /// Clear local records from Settings and restore canonical landmark names.
    func clearAllData() {
        LocalStore.clear()
        restoring = true
        savedNeighbors = [:]; appointments = []; reports = []; landmarkNames = [:]; walkLog = [:]; leaveDays = []; firstDay = nil
        if demoMode { seedDemoHistory() }
        restoring = false
        restoreOriginalNames()
        saveNow()
        if isMainStore { LocationMonitor.shared.clearRecords() }   // Clear overnight locations and location records too.
        clearServerData()
    }

    func restoreOriginalNames() {
        for i in landmarks.indices {
            guard let o = originalLandmarkNames[landmarks[i].id], o != landmarks[i].name else { continue }
            landmarks[i].name = o
            scene.renameLandmark(landmarks[i].id, to: o)
        }
    }

    /// Reset Demo clears demo relationships, meetings, replies and records while preserving real personal records.
    func resetDemoData() {
        let demoIDs = Set(residents.filter(\.isDemo).map(\.id))
        for id in demoIDs { savedNeighbors[id] = nil }
        appointments.removeAll { demoIDs.contains($0.partnerID) }
        for i in reports.indices where reports[i].followUpDemo == true { reports[i].followUp = nil; reports[i].followUpDemo = nil }
        walkLog = walkLog.filter { !$0.value.demo }
        // Fill only dates without records; preserve dates with real activity.
        seedDemoHistory()
        scheduleSave()
    }

    /// Hide unfinished demo meetings when demo mode ends or the peer disappears; no notification is needed for absent demo peers.
    /// Only prune demo meetings; real backend meetings remain authoritative while circle members are loading.
    func closeOrphanAppointments() {
        for i in appointments.indices where appointments[i].isOpen && resident(appointments[i].partnerID) == nil
            && UUID(uuidString: appointments[i].partnerID) == nil {
            appointments[i].status = .cancelled
        }
    }

    // MARK: - Daily records and streaks

    func log(for d: Date) -> DayLog {
        guard let l = walkLog[LocalStore.dayKey(d)], demoMode || !l.demo else { return DayLog() }
        return l
    }

    func myStreak() -> Int { LocalStore.streak(walkLog, leaves: leaveDays, today: now, includeDemo: demoMode) }

    /// Whether the streak includes demo records, requiring a visible label.
    var streakHasDemo: Bool {
        guard demoMode else { return false }
        return LocalStore.streakKeys(walkLog, leaves: leaveDays, today: now, includeDemo: true).contains { walkLog[$0]?.demo == true }
    }

    /// Monthly steps use device measurements; unmeasured simulator, demo or backfilled days estimate about 100 steps per minute.
    var myMonthSteps: Int {
        monthLogs.reduce(0) { $0 + $1.stepEstimate }
    }

    /// Whether monthly steps include estimates and require an approximation label.
    var myMonthStepsEstimated: Bool { monthLogs.contains(where: \.stepsEstimated) }

    private var monthLogs: [DayLog] {
        let prefix = String(LocalStore.dayKey(now).prefix(7))
        return walkLog.filter { $0.key.hasPrefix(prefix) && (demoMode || !$0.value.demo) }.map(\.value)
    }

    var myMonthWalks: Int {
        let prefix = String(LocalStore.dayKey(now).prefix(7))
        return walkLog.filter { $0.key.hasPrefix(prefix) && (demoMode || !$0.value.demo) }.reduce(0) { $0 + $1.value.walks }
    }

    /// Record simulated walks separately from real device walks; never overwrite or mix real daily records with demo data.
    /// day identifies the original walking date when backfilling.
    func recordWalk(minutes: Int, landmarks passed: [String], simulated: Bool, day: Date? = nil, steps: Int? = nil, stops: [String] = []) {
        LocalStore.record(&walkLog, key: LocalStore.dayKey(day ?? now), minutes: minutes, landmarks: passed, stops: stops,
                          steps: steps, simulated: simulated)
        refreshMe()
        uploadDay(day ?? now)
        firstDayWalked(minutes)     // First-day task: walk outside for 10 minutes (AppStore+FirstDay).
        noteWalkRecorded(minutes: minutes, simulated: simulated, backfilled: day != nil, steps: steps)   // Location records (AppStore+Location).
    }

    /// Upload profiles after onboarding, nickname / floor / avatar changes and foreground return; skip unchanged data.
    func uploadProfile() {
        if let p = communityProfile() { community.updateProfile(p) }
    }

    /// Upload one walks summary per user per day after recording or a rename that changes the daily greeting.
    /// Do not upload demo records or pass-through landmarks; F1 / A12 shares only the stopping landmark.
    func uploadDay(_ day: Date) {
        let key = LocalStore.dayKey(day)
        guard let l = walkLog[key], !l.demo, l.walks > 0 else { return }
        let line = key == LocalStore.dayKey(now) ? me.todayLine : ""
        community.uploadDay(day: key, minutes: l.minutes, steps: l.stepEstimate, landmarkIDs: [], stopLandmarkIDs: l.stops, line: line)
    }

    /// Update my leaderboard streak, leave status and daily greeting from records.
    func refreshMe() {
        guard let i = residents.firstIndex(where: \.isMe) else { return }
        residents[i].streakDays = myStreak()
        residents[i].onLeave = leaveDays.contains(LocalStore.dayKey(now))
        residents[i].todayLine = myTodayLine(residents[i])
    }

    /// Circle-visible daily greetings include only the stopping landmark, never the route passed through.
    func myTodayLine(_ r: Resident) -> String {
        guard !landmarks.isEmpty else { return "" }   // Wait until the map loads before speaking.
        let today = log(for: now)
        guard !r.onLeave, today.walks > 0 else { return ai.dailyLine(for: r, passed: []) }
        let stops = today.stops.compactMap(landmark)
        if let s = stops.last { return s.hasSeat ? L.t("\(r.lineSubject)喺\(s.name)坐咗陣", "\(r.lineSubject)在\(s.name)坐了一会", "Sat a while at \(s.name)") : ai.dailyLine(for: r, passed: stops) }
        // For minute-only demo records, use the demo person's usual destination to avoid contradictory no-outing text.
        if today.demo, let home = landmark(r.homeLandmarkID) { return ai.dailyLine(for: r, passed: [home]) }
        // For real walks without a stopping landmark, including backfills, report minutes without inventing a place.
        return L.t("\(r.lineSubject)今日行咗 \(today.minutes) 分鐘", "\(r.lineSubject)今天走了 \(today.minutes) 分钟", "Walked \(today.minutes) min today")
    }

    /// Seed nine demo days, including this morning; label all demo, exclude when disabled and preserve existing records.
    func seedDemoHistory() {
        LocalStore.seedDemo(&walkLog, today: now)
    }

    /// Before the map loads, calculate my values from actual records rather than fallback numbers.
    func ensureMeBeforeMap() {
        guard residents.isEmpty, phase == .main else { return }
        residents = [Resident(id: "me", name: L.t("你", "你", "You"), floor: floorChoice, colorIndex: colorChoice, mobility: mobilityChoice,
                              streakDays: myStreak(), todayLine: "", isMe: true)]
        refreshMe()
    }

    // MARK: - CommunityService peer events

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
