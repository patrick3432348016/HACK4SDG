import Foundation
import Network
import Observation

/// Supabase implementation of CommunityService and NeighborLinker for normal, non-demo mode.
///
/// Receive through foreground Realtime: refetch outings/neighbors/meetups after changes, but consume signal rows directly.
/// Also refresh every 60 seconds, and once through backgroundRefresh() on wake-up; AppStore posts local notifications.
/// Queue durable writes through Outbox. Send time-sensitive availability requests directly and report delivery failure immediately.
/// Ordinary community rows use original landmark names rather than coordinates/unit numbers. On return home, set the outing landmark to null instead of deleting.
/// Realtime DELETE events bypass row filtering and expose primary keys to subscribers, revealing who returned home.
@MainActor
@Observable
final class SupabaseCommunityService: CommunityService, NeighborLinker {
    static let shared = SupabaseCommunityService()

    enum Status: Equatable {
        /// Not signed in: onboarding/nickname is incomplete.
        case idle
        case online
        /// Show disconnected only after system network loss persists for pathGrace, or at least two request failures span failGrace.
        /// Do not count a single timeout, Realtime reconnect, or foreground transition as offline (tester D-1).
        case offline
    }
    private(set) var status: Status = .idle
    var isOffline: Bool { status == .offline }
    /// Detect when system settings restrict this app to Wi-Fi or disable its data access.
    /// Explain how to enable cellular data instead of reporting only a generic disconnection.
    private(set) var cellularDenied = false
    /// Debounce system network loss; switching between Wi-Fi and cellular can briefly interrupt connectivity.
    static let pathGrace: TimeInterval = 3
    /// Required failure duration and count before displaying disconnected.
    static let failGrace: TimeInterval = 8
    static let failCount = 2

    @ObservationIgnored var onEvent: ((CommunityEvent) -> Void)?
    var isSimulated: Bool { false }
    var hasServer: Bool { true }
    var sharesLandmarkNames: Bool { false }
    var ownsNeighborLinks: Bool { true }

    /// AppStore supplies the current profile, or nil before onboarding/nickname. Reupload streaks after walking/leave changes.
    @ObservationIgnored var profileProvider: (() -> CommunityProfile?)?

    enum Part: Hashable, CaseIterable { case neighbors, board, meetups, signals, followUps, monthly, passers }
    /// Maximum wait for an availability response before reporting no reply yet.
    static let askTimeout: TimeInterval = 120

    let api: SupabaseAPI
    @ObservationIgnored private var realtime: RealtimeClient!
    @ObservationIgnored private var channel: RealtimeChannel?
    @ObservationIgnored private var cache: BackendCache
    @ObservationIgnored private var outbox: Outbox
    @ObservationIgnored private var index = LandmarkIndex()
    @ObservationIgnored private(set) var myID: String?
    @ObservationIgnored private(set) var active = false
    @ObservationIgnored private var foreground = true
    /// Process meetups/signals only after circleMembers first loads the people, avoiding events being discarded before UI setup.
    @ObservationIgnored private var uiReady = false
    @ObservationIgnored private var lastMembers: [Resident] = []
    @ObservationIgnored private var pendingAsks: [String: PendingAsk] = [:]
    @ObservationIgnored private var tripHandlers: [UUID: (PartnerTrip) -> Void] = [:]
    @ObservationIgnored private var lastTrips: [UUID: PartnerTrip] = [:]
    /// Locally unlinked neighbors whose deletion is still pending; do not restore them during refresh.
    @ObservationIgnored private var pendingUnlinks: Set<String> = []
    @ObservationIgnored private var remindOverrides: [String: (send: Bool, receive: Bool)] = [:]
    @ObservationIgnored private var pendingOutingStart: Date?
    @ObservationIgnored private var clearedOutingThisLaunch = false
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryDelay: Double = 5
    @ObservationIgnored private var refreshTimer: Task<Void, Never>?
    @ObservationIgnored private var queued: Set<Part> = []
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastBackgroundRun: Date?
    private let monitor = NWPathMonitor()
    @ObservationIgnored private var monitorStarted = false
    /// Debounce state: system path availability, loss start time, consecutive failure count, and first failure time.
    @ObservationIgnored private var pathOK = true
    @ObservationIgnored private var pathDownSince: Date?
    @ObservationIgnored private var failStreak = 0
    @ObservationIgnored private var failingSince: Date?
    @ObservationIgnored private var lastFailAt: Date?
    @ObservationIgnored private var offlineCheck: Task<Void, Never>?
    private let dir: URL
    let log: Bool

    private struct PendingAsk {
        var askID: String
        var answer: (Bool) -> Void
        var timeout: Task<Void, Never>
    }

    init(api: SupabaseAPI? = nil, directory: URL? = nil) {
        log = LaunchArgs.has("-logBackend")
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StreetWalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dir = base
        let store = KeychainSessionStore()
        if LaunchArgs.has("-resetBackendSession") {
            store.save(nil)
            try? FileManager.default.removeItem(at: base.appendingPathComponent("backend.json"))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("outbox.json"))
        }
        self.api = api ?? SupabaseAPI(baseURL: BackendConfig.url, apiKey: BackendConfig.publishableKey, store: store, log: log)
        cache = BackendCache.load(base.appendingPathComponent("backend.json"))
        outbox = Outbox.load(base.appendingPathComponent("outbox.json"))
        let api = self.api
        realtime = RealtimeClient(baseURL: BackendConfig.url, apiKey: BackendConfig.publishableKey, log: log) {
            try? await api.accessToken()
        }
        realtime.onStateChange = { [weak self] s in
            // Poll more frequently while disconnected and refresh immediately on reconnection.
            if s == .connected { self?.scheduleRefresh([.neighbors, .meetups, .signals]) }
        }
        Task { [weak self] in
            await api.setTokenListener { token in Task { @MainActor in self?.realtime.updateToken(token) } }
        }
    }

    // MARK: - Lifecycle

    /// Switch to the real backend at normal-mode startup or when demo mode is disabled.
    func activate() {
        guard !active else { return }
        active = true
        startMonitor()
        Task {
            if let id = await api.userID { adopt(id) }
            if foreground { startForegroundWork() }
            flush()
        }
    }

    /// Stop services when entering demo mode, retaining login for the next switch back.
    func deactivate() {
        active = false
        uiReady = false
        stopForegroundWork()
    }

    /// Foreground/background transition from AppStore.appActive.
    func setForeground(_ on: Bool) {
        foreground = on
        // Reset failures on foreground entry; stale sockets/Reatime reconnection do not immediately imply offline status.
        if on { failStreak = 0; failingSince = nil }
        guard active else { return }
        if on { startForegroundWork() } else { stopForegroundWork(); saveCacheNow() }
    }

    private func startForegroundWork() {
        flush()
        guard myID != nil else { return }
        connectRealtime()
        startPoller()
        scheduleRefresh(Set(Part.allCases), delay: 0.1)
    }

    private func stopForegroundWork() {
        poller?.cancel(); poller = nil
        realtime.disconnect()
    }

    private func startMonitor() {
        guard !monitorStarted else { return }
        monitorStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            let cellDenied = !ok && path.unsatisfiedReason == .cellularDenied
            Task { @MainActor in self?.pathChanged(ok: ok, cellularDenied: cellDenied) }
        }
        monitor.start(queue: DispatchQueue(label: "streetwalk.backend.path"))
    }

    private func pathChanged(ok: Bool, cellularDenied denied: Bool) {
        let wasOK = pathOK
        pathOK = ok
        if cellularDenied != denied { cellularDenied = denied }
        if ok {
            pathDownSince = nil
            // On network recovery/change, discard previous failures and hide disconnected immediately; new failures can show it again.
            if !wasOK { failStreak = 0; failingSince = nil }
            if status == .offline, failStreak < Self.failCount { status = myID != nil ? .online : .idle }
            guard active else { return }
            retryDelay = 5
            flush()
            if foreground, myID != nil { scheduleRefresh([.neighbors, .board, .meetups, .signals]) }
        } else {
            if pathDownSince == nil { pathDownSince = Date() }
            updateOffline()
        }
    }

    /// Hide disconnected as soon as a request succeeds or the server responds.
    private func markOnline() {
        failStreak = 0
        failingSince = nil
        if status != .online { status = .online }
    }

    /// Record transient request failures; display offline only after count/time thresholds. Retry shortly after the first failure to confirm.
    private func noteFailure() {
        let now = Date()
        if let last = lastFailAt, now.timeIntervalSince(last) > 60 { failStreak = 0; failingSince = nil }   // Ignore failures from too long ago.
        lastFailAt = now
        failStreak += 1
        if failingSince == nil { failingSince = now }
        if failStreak == 1, active, foreground, myID != nil { scheduleRefresh([.neighbors], delay: 4) }
        updateOffline()
    }

    /// Apply the debounce rules; schedule another check if the threshold has not elapsed.
    private func updateOffline() {
        let now = Date()
        var wait: TimeInterval?
        var down = false
        if !pathOK, let since = pathDownSince {
            let left = Self.pathGrace - now.timeIntervalSince(since)
            if left <= 0 { down = true } else { wait = left }
        }
        if !down, failStreak >= 1, let since = failingSince {
            let left = Self.failGrace - now.timeIntervalSince(since)
            if failStreak >= Self.failCount && left <= 0 { down = true } else if left > 0 { wait = min(wait ?? left, left) }
        }
        if down {
            if status != .offline, myID != nil || !outbox.isEmpty { status = .offline }
            return
        }
        guard let wait else { return }
        offlineCheck?.cancel()
        offlineCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait + 0.1))
            guard !Task.isCancelled else { return }
            self?.updateOffline()
        }
    }

    /// On background/location wake-up, flush queued writes and fetch neighbors, meetups, and signals.
    /// AppStore posts local notifications for new outings/invitations/finding requests. Refresh at most once per 60 seconds.
    func backgroundRefresh() async {
        guard active else { return }
        if let t = lastBackgroundRun, Date().timeIntervalSince(t) < 60 { return }
        lastBackgroundRun = Date()
        // Wait up to ten seconds for circle members during cold/background startup so events have a receiver.
        for _ in 0..<50 where !uiReady { try? await Task.sleep(for: .milliseconds(200)) }
        await flushNow()
        if let id = await api.userID { adopt(id) }
        guard myID != nil else { return }
        for _ in 0..<50 where refreshing { try? await Task.sleep(for: .milliseconds(200)) }
        await refresh([.neighbors, .board, .meetups, .signals, .followUps])
        saveCacheNow()
    }

    // MARK: - Authentication

    private func adopt(_ id: String) {
        let id = id.lowercased()
        guard myID != id else { return }
        myID = id
        // Recreate channels when identity changes; their filters refer to the previous user ID.
        if let ch = channel, ch.name != "sw:\(id)" { realtime.remove(ch); channel = nil }
        if cache.userID != id {
            cache = BackendCache(userID: id)
            lastMembers = []
            saveCacheSoon()
        }
        if active, foreground { startForegroundWork() }
    }

    /// Return the current user ID if signed in. Otherwise log in anonymously only when consented onboarding has produced a profile.
    private func ensureSignedIn(allowSignUp: Bool) async throws -> String {
        if let id = await api.userID { adopt(id); return id.lowercased() }
        guard allowSignUp else { throw BackendError.notSignedIn }
        let s = try await api.signInAnonymously()
        if log { print("[backend] signed up \(s.userID)") }
        adopt(s.userID)
        return s.userID
    }

    // MARK: - Realtime

    private func connectRealtime() {
        guard let me = myID else { return }
        if channel == nil {
            let ch = realtime.channel("sw:\(me)", postgresChanges: [
                PostgresChangeSpec(table: "outings"),
                PostgresChangeSpec(table: "neighbors"),
                PostgresChangeSpec(table: "meetups"),
                PostgresChangeSpec(event: "INSERT", table: "signals", filter: "to_user=eq.\(me)"),
            ])
            ch.onPostgresChange = { [weak self] c in self?.handleChange(c) }
            channel = ch
        }
        realtime.connect()
    }

    private func handleChange(_ c: PostgresChange) {
        switch c.table {
        case "outings": scheduleRefresh([.neighbors])
        case "neighbors": scheduleRefresh([.neighbors, .board])
        case "meetups": scheduleRefresh([.meetups])
        case "signals":
            if uiReady, let row = try? c.record?.decode(SignalRow.self) { processSignals([row]) } else { scheduleRefresh([.signals]) }
        default: break
        }
    }

    /// Wake every five seconds in foreground, fully refresh every 60, and poll signals faster while awaiting availability, meeting, or disconnected from Realtime.
    private func startPoller() {
        poller?.cancel()
        poller = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                tick += 1
                var parts: Set<Part> = []
                let urgent = !self.pendingAsks.isEmpty || !self.tripHandlers.isEmpty
                let socketDown = self.realtime.state != .connected
                if tick % 12 == 0 { parts.formUnion([.neighbors, .board, .meetups, .signals, .followUps]) }
                if urgent || (socketDown && tick % 3 == 0) { parts.formUnion([.signals, .meetups, .neighbors]) }
                if tick % 120 == 0 { parts.insert(.passers) }
                if tick % 360 == 0 { parts.insert(.monthly) }
                if !parts.isEmpty { self.scheduleRefresh(parts, delay: 0) }
                if !self.outbox.isEmpty, self.retryTask == nil { self.flush() }
            }
        }
    }

    // MARK: - Fetching data

    func scheduleRefresh(_ parts: Set<Part>, delay: Double = 0.3) {
        guard active else { return }
        queued.formUnion(parts)
        guard refreshTimer == nil else { return }
        refreshTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.refreshTimer = nil
            let p = self.queued
            self.queued = []
            await self.refresh(p)
        }
    }

    private func refresh(_ parts: Set<Part>) async {
        guard active, myID != nil, !parts.isEmpty else { return }
        if refreshing { queued.formUnion(parts); return }
        refreshing = true
        do {
            if parts.contains(.neighbors) || parts.contains(.board) { try await refreshMembers(board: parts.contains(.board) || cache.board.isEmpty) }
            if uiReady {
                if parts.contains(.meetups) { try await refreshMeetups() }
                if parts.contains(.signals) { try await refreshSignals() }
                if parts.contains(.followUps) { try await refreshFollowUps() }
            } else if !parts.isDisjoint(with: [.meetups, .signals, .followUps]) {
                queued.formUnion(parts.intersection([.meetups, .signals, .followUps]))
            }
            if parts.contains(.monthly) || cache.monthlyAt.map({ Date().timeIntervalSince($0) > 1800 }) ?? true { try await refreshMonthly() }
            if parts.contains(.passers) || cache.passersDay != LocalStore.dayKey(Date()) { try await refreshPassers() }
            markOnline()
        } catch {
            handle(error, during: "refresh")
        }
        refreshing = false
        saveCacheSoon()
        if !queued.isEmpty, uiReady || !queued.isSubset(of: [.meetups, .signals, .followUps]) {
            let q = queued
            queued = []
            scheduleRefresh(q, delay: 0.3)
        }
    }

    private func refreshMembers(board: Bool) async throws {
        let rows: [NeighborRow] = try await api.rpc("my_neighbors")
        if board { cache.board = try await api.rpc("community_board") }
        var nb = rows.filter { !pendingUnlinks.contains($0.id.lowercased()) }
        for i in nb.indices {
            if let o = remindOverrides[nb[i].id.lowercased()] { nb[i].send_remind = o.send; nb[i].receive_remind = o.receive }
        }
        let events = outingTransitions(nb)
        cache.neighbors = nb
        rebuildMembers()
        for e in events { onEvent?(e) }
    }

    /// Only a new outing start time triggers a departure reminder. Mid-walk landmark changes update position silently.
    private func outingTransitions(_ rows: [NeighborRow]) -> [CommunityEvent] {
        var events: [CommunityEvent] = []
        let now = Date()
        var stillOut = Set<String>()
        for n in rows {
            let id = n.id.lowercased()
            guard BackendMapping.isOut(n, now: now) else { continue }
            stillOut.insert(id)
            let since = n.out_since ?? now
            guard cache.lastOut[id] != since else { continue }
            cache.lastOut[id] = since
            // If an outing is first observed long after departure, update silently rather than saying just left.
            if now.timeIntervalSince(since) < 30 * 60, let lm = index.id(forName: n.out_at) {
                events.append(.neighborOut(residentID: id, landmarkID: lm))
            }
        }
        for id in cache.lastOut.keys where !stillOut.contains(id) {
            cache.lastOut[id] = nil
            events.append(.neighborHome(residentID: id))
        }
        return events
    }

    private func members() -> [Resident] {
        BackendMapping.residents(board: cache.board, neighbors: cache.neighbors, myID: myID, landmarks: index, now: Date())
    }

    private func rebuildMembers() {
        let m = members()
        guard m != lastMembers else { return }
        lastMembers = m
        onEvent?(.membersChanged)
    }

    private func refreshMeetups() async throws {
        guard let me = myID else { return }
        let since = BackendTime.format(Date().addingTimeInterval(-2 * 86400))
        let rows: [MeetupRow] = try await api.select("meetups", query: "select=*&at=gt.\(PG.q(since))&order=updated_at.asc")
        for row in rows { processMeetup(row, me: me) }
        cache.seenMeetups = cache.seenMeetups.filter { $0.value.at > Date().addingTimeInterval(-3 * 86400) }
    }

    private func processMeetup(_ row: MeetupRow, me: String) {
        let key = row.id.lowercased()
        let change = BackendMapping.meetupChange(row, seen: cache.seenMeetups[key], me: me, now: Date())
        cache.seenMeetups[key] = row
        guard let change, let a = BackendMapping.appointment(row, me: me, landmarks: index) else { return }
        if log { print("[backend] meetup \(key.prefix(8)) \(change)") }
        switch change {
        case .invited: onEvent?(.invited(a))
        case .answered(let ok): onEvent?(.inviteAnswered(appointmentID: a.id, accepted: ok))
        case .changed: onEvent?(.meetupChanged(a))
        case .cancelled: onEvent?(.meetupCancelled(appointmentID: a.id))
        }
    }

    private func refreshSignals() async throws {
        guard let me = myID else { return }
        let wm = cache.lastSignalID ?? 0
        let rows: [SignalRow] = try await api.select("signals", query: "select=*&to_user=eq.\(me)&id=gt.\(wm)&order=id.asc&limit=100")
        processSignals(rows)
    }

    private func processSignals(_ rows: [SignalRow]) {
        guard let me = myID else { return }
        let now = Date()
        for s in rows.sorted(by: { $0.id < $1.id }) where s.id > (cache.lastSignalID ?? 0) && s.to_user.lowercased() == me {
            cache.lastSignalID = s.id
            let from = s.from_user.lowercased()
            let age = now.timeIntervalSince(s.created_at ?? now)
            let p = s.payload
            if log { print("[backend] signal \(s.id) \(s.kind) from \(from.prefix(8)) \(p)") }
            switch s.kind {
            case "find_ask":
                guard age < 180, let ask = p["ask"]?.string else { continue }
                let lm = index.id(forName: p["landmark"]?.string) ?? ""
                onEvent?(.findAsked(IncomingFindAsk(askID: ask, fromID: from, landmarkID: lm, at: s.created_at ?? now)))
            case "find_answer":
                guard let ask = p["ask"]?.string, let pending = pendingAsks[from], pending.askID == ask else { continue }
                pendingAsks[from] = nil
                pending.timeout.cancel()
                pending.answer(p["accepted"]?.bool ?? false)
            case "find_cancel":
                guard age < 600, let ask = p["ask"]?.string else { continue }
                onEvent?(.findAskCancelled(askID: ask))
            case "say":
                guard age < 600, let text = p["text"]?.string, !text.isEmpty else { continue }
                onEvent?(.partnerSaid(partnerID: from, text: text))
            case "trip":
                guard age < 3 * 3600, let mid = p["meetup"]?.string.flatMap(UUID.init(uuidString:)) else { continue }
                let state = p["state"]?.string ?? "depart"
                let trip = PartnerTrip(etaMinutes: p["eta"]?.int, arrived: state == "arrived")
                if state != "ended", let h = tripHandlers[mid] {
                    h(trip)
                } else {
                    lastTrips[mid] = state == "ended" ? nil : trip
                    onEvent?(.partnerTrip(appointmentID: mid, partnerID: from, trip: trip, ended: state == "ended"))
                }
            default:
                continue
            }
        }
        saveCacheSoon()
    }

    private func refreshFollowUps() async throws {
        let rows: [ReportFollowUpRow] = try await api.select("reports", query: "select=id,follow_up&follow_up=not.is.null")
        for r in rows {
            guard let text = r.follow_up, !text.isEmpty, !cache.seenFollowUps.contains(r.id.lowercased()),
                  let id = UUID(uuidString: r.id) else { continue }
            cache.seenFollowUps.insert(r.id.lowercased())
            onEvent?(.reportFollowUp(reportID: id, text: text, isDemo: false))
        }
    }

    private func refreshMonthly() async throws {
        cache.monthly = try await api.rpc("monthly_report")
        cache.monthlyAt = Date()
    }

    private func refreshPassers() async throws {
        let today = LocalStore.dayKey(Date())
        var out: [String: Int] = [:]
        for l in index.landmarks.prefix(6) {
            guard let name = index.publishName(l.id) else { continue }
            let n: Int? = try await api.rpc("passers_today", ["p_landmark": .string(name)])
            if let n { out[name] = n }
        }
        cache.passers = out
        cache.passersDay = today
    }

    // MARK: - Writes through Outbox

    private func enqueue(_ op: OutboxOp) {
        outbox.add(op)
        outbox.save(dir.appendingPathComponent("outbox.json"))
        flush()
    }

    private func flush() {
        guard active, flushTask == nil, retryTask == nil, !outbox.isEmpty else { return }
        flushTask = Task { [weak self] in
            await self?.runFlush()
            self?.flushTask = nil
        }
    }

    /// Flush immediately and await completion.
    func flushNow() async {
        retryTask?.cancel(); retryTask = nil
        if let t = flushTask { await t.value }
        guard !outbox.isEmpty else { return }
        flush()
        if let t = flushTask { await t.value }
    }

    private func runFlush() async {
        while let op = outbox.next() {
            do {
                let me = try await ensureSignedIn(allowSignUp: outbox.contains(key: "profile"))
                let r = op.resolved(me: me)
                _ = try await api.request(op.method, r.path, query: r.query, body: r.body, prefer: op.prefer)
                outbox.remove(op.id)
                outbox.save(dir.appendingPathComponent("outbox.json"))
                markOnline()
                retryDelay = 5
                opDone(op, ok: true)
            } catch BackendError.notSignedIn {
                return      // Wait for a profile while onboarding is incomplete.
            } catch let e as BackendError where e.isRetryable {
                handle(e, during: "flush \(op.key ?? op.path)")
                scheduleRetry()
                return
            } catch {
                // Drop permanent permission/format rejections rather than retrying.
                if log { print("[backend] drop \(op.method) \(op.path) \(op.key ?? ""): \(error)") }
                outbox.remove(op.id)
                outbox.save(dir.appendingPathComponent("outbox.json"))
                opDone(op, ok: false)
            }
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        let d = retryDelay
        retryDelay = min(retryDelay * 2, 60)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(d))
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.flush()
        }
    }

    private func opDone(_ op: OutboxOp, ok: Bool) {
        guard let key = op.key else { return }
        if key == "profile", ok, let body = op.body, let p = try? BackendCoding.decoder.decode(ProfileUpsert.self, from: body) {
            let first = cache.lastProfile == nil
            cache.lastProfile = p
            saveCacheSoon()
            if first, active, foreground { startForegroundWork() }
        } else if key.hasPrefix("remind:") {
            remindOverrides[String(key.dropFirst(7))] = nil
        } else if key.hasPrefix("unlink:") {
            pendingUnlinks.remove(String(key.dropFirst(7)))
        } else if key == "outing", ok, let body = op.body,
                  let o = try? BackendCoding.decoder.decode(OutingUpsert.self, from: body), o.started_at != nil, o.started_at == pendingOutingStart {
            pendingOutingStart = nil
        }
    }

    private func json<T: Encodable>(_ v: T) -> Data? { try? BackendCoding.encoder.encode(v) }

    private func handle(_ error: Error, during what: String) {
        if log { print("[backend] \(what) ✗ \(error)") }
        guard let e = error as? BackendError else { return }
        switch e {
        case .offline: noteFailure()
        case .notSignedIn:
            Task { if await self.api.userID == nil { self.myID = nil; self.status = .idle } }
        case .rejected:
            // A server rejection still proves connectivity; do not leave the offline indicator visible.
            if myID != nil { markOnline() }
        }
    }

    // MARK: - CommunityService: circle members

    func circleMembers(blocks: [String], landmarks: [Landmark]) -> [Resident] {
        let first = !uiReady
        uiReady = true
        lastMembers = members()
        if first, active, myID != nil { scheduleRefresh(Set(Part.allCases), delay: 0.1) }
        return lastMembers
    }

    func setLandmarks(_ landmarks: [Landmark], originals: [String: String]) {
        index = LandmarkIndex(landmarks: landmarks, originals: originals)
    }

    // MARK: - Profiles, daily summaries, and leave

    func updateProfile(_ p: CommunityProfile) {
        let body = p.upsert(id: OutboxOp.me)
        var known = cache.lastProfile
        known?.id = OutboxOp.me
        guard body != known || outbox.contains(key: "profile") else { return }
        enqueue(OutboxOp(key: "profile", method: "POST", path: "/rest/v1/profiles", query: "on_conflict=id", body: json(body),
                         prefer: "resolution=merge-duplicates,return=minimal", priority: 10))
    }

    private func reuploadProfile() {
        if let p = profileProvider?() { updateProfile(p) }
    }

    func uploadDay(day: String, minutes: Int, steps: Int, landmarkIDs: [String], stopLandmarkIDs: [String], line: String) {
        let stops = stopLandmarkIDs.compactMap(index.publishName)
        let body = WalkUpsert(user_id: OutboxOp.me, day: day, minutes: minutes, steps: steps, stop_landmarks: stops,
                              daily_line: line.isEmpty ? nil : line)
        enqueue(OutboxOp(key: "walk:\(day)", method: "POST", path: "/rest/v1/walks", query: "on_conflict=user_id,day", body: json(body),
                         prefer: "resolution=merge-duplicates,return=minimal"))
        reuploadProfile()
    }

    func setLeave(day: String, on: Bool) {
        if on {
            enqueue(OutboxOp(key: "leave:\(day)", method: "POST", path: "/rest/v1/leaves", query: "on_conflict=user_id,day",
                             body: Data("{\"user_id\":\"\(OutboxOp.me)\",\"day\":\"\(day)\"}".utf8), prefer: "resolution=ignore-duplicates,return=minimal"))
        } else {
            enqueue(OutboxOp(key: "leave:\(day)", method: "DELETE", path: "/rest/v1/leaves", query: "user_id=eq.\(OutboxOp.me)&day=eq.\(day)"))
        }
        reuploadProfile()
    }

    // MARK: - Neighbor relationships

    func linkNeighbor(_ id: String, send: Bool, receive: Bool) { updateRemind(id, send: send, receive: receive) }

    func updateRemind(_ id: String, send: Bool, receive: Bool) {
        remindOverrides[id] = (send, receive)
        if let i = cache.neighbors.firstIndex(where: { $0.id.lowercased() == id }) {
            cache.neighbors[i].send_remind = send
            cache.neighbors[i].receive_remind = receive
            lastMembers = members()
        }
        enqueue(OutboxOp(key: "remind:\(id)", method: "PATCH", path: "/rest/v1/neighbors",
                         query: "owner=eq.\(OutboxOp.me)&other=eq.\(id)",
                         body: Data("{\"send_remind\":\(send),\"receive_remind\":\(receive)}".utf8), prefer: "return=minimal"))
    }

    func unlinkNeighbor(_ id: String) {
        pendingUnlinks.insert(id)
        remindOverrides[id] = nil
        outbox.remove(key: "remind:\(id)")
        cache.neighbors.removeAll { $0.id.lowercased() == id }
        cache.lastOut[id] = nil
        lastMembers = members()
        enqueue(OutboxOp(key: "unlink:\(id)", method: "DELETE", path: "/rest/v1/neighbors", query: "owner=eq.\(OutboxOp.me)&other=eq.\(id)"))
    }

    /// Submit the one-time bump/QR code (NeighborLinking.swift). Upload the profile first because pair_codes references profiles.
    func link(code: String) async throws -> LinkedPeer? {
        if cache.lastProfile == nil || outbox.contains(key: "profile") {
            reuploadProfile()
            await flushNow()
            guard cache.lastProfile != nil else { throw BackendError.notSignedIn }
        }
        _ = try await ensureSignedIn(allowSignUp: false)
        let rows: [LinkRow]
        do { rows = try await api.rpc("link_neighbor", ["p_code": .string(code)]) } catch { handle(error, during: "link"); throw error }
        markOnline()
        guard let row = rows.first else { return nil }
        let peer = BackendMapping.peer(row)
        pendingUnlinks.remove(peer.id)
        if !cache.neighbors.contains(where: { $0.id.lowercased() == peer.id }) {
            cache.neighbors.append(BackendMapping.neighborRow(peer))
        }
        saveCacheSoon()
        scheduleRefresh([.neighbors, .board], delay: 1)
        return peer
    }

    /// Private pair channel for temporary live-finding location: pair:<lower UUID>:<higher UUID>.
    /// The server admits only two mutual neighbors; coordinates are relayed through the channel, not stored in a table.
    /// Usage: let ch = service.openPairChannel(with: id); set onBroadcast, then call broadcast("loc", ...).
    /// Close with service.closePairChannel(ch). Backgrounding disconnects; foregrounding rejoins automatically.
    func openPairChannel(with partnerID: String) -> RealtimeChannel? {
        guard let me = myID else { return nil }
        let other = partnerID.lowercased()
        let (lo, hi) = me < other ? (me, other) : (other, me)
        let ch = realtime.channel("pair:\(lo):\(hi)", isPrivate: true)
        realtime.connect()
        return ch
    }

    func closePairChannel(_ ch: RealtimeChannel) { realtime.remove(ch) }

    // MARK: - Outing state

    func publishOuting(landmarkID: String?) {
        let body: OutingUpsert
        if let landmarkID {
            guard let name = index.publishName(landmarkID) else { return }
            if !cache.outingActive { pendingOutingStart = Date() }
            cache.outingActive = true
            body = OutingUpsert(user_id: OutboxOp.me, landmark_name: name, started_at: pendingOutingStart, updated_at: Date())
        } else {
            // Home/hidden: set the landmark to null without deleting. Clear once at startup in case the previous run crashed.
            guard cache.outingActive || !clearedOutingThisLaunch else { return }
            guard cache.lastProfile != nil || outbox.contains(key: "profile") else { return }
            clearedOutingThisLaunch = true
            cache.outingActive = false
            pendingOutingStart = nil
            body = OutingUpsert(user_id: OutboxOp.me, landmark_name: nil, started_at: nil, updated_at: Date())
        }
        saveCacheSoon()
        enqueue(OutboxOp(key: "outing", method: "POST", path: "/rest/v1/outings", query: "on_conflict=user_id", body: json(body),
                         prefer: "resolution=merge-duplicates,return=minimal"))
    }

    // MARK: - F7 Meetups

    func sendInvite(_ a: Appointment) {
        let id = a.id.uuidString.lowercased()
        let row = MeetupRow(id: id, inviter: OutboxOp.me, invitee: a.partnerID, at: a.date, landmark_name: index.publishName(a.landmarkID),
                            reason: a.reason, status: "waiting", updated_by: OutboxOp.me, updated_at: Date())
        rememberOwn(row)
        enqueue(OutboxOp(key: "meetup-new:\(id)", method: "POST", path: "/rest/v1/meetups", body: json(row), prefer: "return=minimal"))
    }

    func respond(to a: Appointment, accept: Bool) {
        patchMeetup(a, fields: ["status": .string(accept ? "accepted" : "declined")])
    }

    func updateMeetup(_ a: Appointment) {
        patchMeetup(a, fields: ["at": .string(BackendTime.format(a.date)),
                                "landmark_name": index.publishName(a.landmarkID).map(JSONValue.string) ?? .null,
                                "reason": .string(a.reason),
                                "status": .string(BackendMapping.serverStatus(a.status))])
    }

    private func patchMeetup(_ a: Appointment, fields: [String: JSONValue]) {
        let id = a.id.uuidString.lowercased()
        var f = fields
        f["updated_by"] = .string(OutboxOp.me)
        f["updated_at"] = .string(BackendTime.format(Date()))
        if var seen = cache.seenMeetups[id] {
            if let s = fields["status"]?.string { seen.status = s }
            if let at = fields["at"]?.string, let d = BackendTime.parse(at) { seen.at = d }
            if let l = fields["landmark_name"] { seen.landmark_name = l.string }
            seen.updated_by = myID ?? OutboxOp.me
            seen.updated_at = Date()
            cache.seenMeetups[id] = seen
        }
        enqueue(OutboxOp(key: "meetup:\(id)", method: "PATCH", path: "/rest/v1/meetups", query: "id=eq.\(id)",
                         body: json(JSONValue.object(f)), prefer: "return=minimal"))
    }

    /// The voice server inserted this meetup with my credentials. Remember it as my invitation for later responses; do not upload it again.
    func adoptServerInvite(_ a: Appointment) {
        rememberOwn(MeetupRow(id: a.id.uuidString.lowercased(), inviter: OutboxOp.me, invitee: a.partnerID, at: a.date,
                              landmark_name: index.publishName(a.landmarkID), reason: a.reason, status: "waiting",
                              updated_by: OutboxOp.me, updated_at: Date()))
    }

    private func rememberOwn(_ row: MeetupRow) {
        var r = row
        if let me = myID { r.inviter = r.inviter == OutboxOp.me ? me : r.inviter; r.updated_by = me }
        cache.seenMeetups[row.id] = r
        saveCacheSoon()
    }

    func resume(_ appointments: [Appointment]) {}

    // MARK: - F3 / F10

    /// The backend has no landmark-renaming table. Rename locally and upload original names for cross-device matching.
    func renameLandmark(_ id: String, to name: String) {}

    func submitReport(_ r: Report) {
        guard let name = index.publishName(r.landmarkID), let p = profileProvider?() else { return }
        let body = ReportInsert(id: r.id.uuidString.lowercased(), user_id: OutboxOp.me, tile_x: p.tileX, tile_y: p.tileY,
                                landmark_name: name, kind: BackendMapping.serverKind(r.kind), raw_text: r.rawText)
        enqueue(OutboxOp(key: "report:\(body.id)", method: "POST", path: "/rest/v1/reports", body: json(body), prefer: "return=minimal"))
    }

    func retractReport(_ id: UUID) {
        let k = id.uuidString.lowercased()
        if outbox.contains(key: "report:\(k)") { outbox.remove(key: "report:\(k)"); outbox.save(dir.appendingPathComponent("outbox.json")); return }
        enqueue(OutboxOp(key: "report-del:\(k)", method: "DELETE", path: "/rest/v1/reports", query: "id=eq.\(k)"))
    }

    // MARK: - Anonymous aggregates across nearby 3×3 grids; suppress insufficient counts

    func passersToday(at landmark: Landmark) -> (count: Int, isDemo: Bool)? {
        guard cache.passersDay == LocalStore.dayKey(Date()), let name = index.publishName(landmark.id), let n = cache.passers[name] else { return nil }
        return (n, false)
    }

    /// No real rival-circle data: rivalSteps = 0 and show only this circle's total, without inventing a comparison.
    func circleRace(placeName: String, myMonthSteps: Int) -> CircleRace {
        let others = cache.board.filter { !$0.is_me && $0.id.lowercased() != myID }.reduce(0) { $0 + max(0, $1.month_steps ?? 0) }
        return CircleRace(ourName: L.t("我哋呢頭", "我们这边", "Our area"), ourSteps: others + myMonthSteps, rivalName: "", rivalSteps: 0, isDemo: false)
    }

    func monthlyStats(myWalks: Int, myMeetups: Int, estateHomes: Int) -> MonthlyStats {
        guard let r = cache.monthly.first else {
            return MonthlyStats(walks: myWalks, walkers: myWalks > 0 ? 1 : 0, meetups: myMeetups, isDemo: false)
        }
        return MonthlyStats(walks: max(r.walk_count, myWalks), walkers: max(r.walkers, myWalks > 0 ? 1 : 0), meetups: myMeetups, isDemo: false)
    }

    func othersReports(landmarks: [Landmark]) -> [Report] {
        BackendMapping.reports(cache.monthly, landmarks: landmarks, index: index, now: Date())
    }

    // MARK: - F8 Finding

    func askToFind(partnerID: String, landmarkID: String, answer: @escaping (Bool) -> Void) {
        if let old = pendingAsks.removeValue(forKey: partnerID) { old.timeout.cancel() }
        let askID = UUID().uuidString.lowercased()
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.askTimeout))
            guard let self, !Task.isCancelled, self.pendingAsks[partnerID]?.askID == askID else { return }
            self.pendingAsks[partnerID] = nil
            self.onEvent?(.findAskUnanswered(partnerID: partnerID, offline: false))
        }
        pendingAsks[partnerID] = PendingAsk(askID: askID, answer: answer, timeout: timeout)
        let payload: JSONValue = .object(["ask": .string(askID), "landmark": .string(index.publishName(landmarkID) ?? "")])
        Task {
            do {
                try await sendSignalNow(to: partnerID, kind: "find_ask", payload: payload)
            } catch {
                guard let p = pendingAsks[partnerID], p.askID == askID else { return }
                p.timeout.cancel()
                pendingAsks[partnerID] = nil
                onEvent?(.findAskUnanswered(partnerID: partnerID, offline: (error as? BackendError)?.isRetryable ?? true))
            }
        }
    }

    func cancelFindAsk(partnerID: String) {
        guard let p = pendingAsks.removeValue(forKey: partnerID) else { return }
        p.timeout.cancel()
        queueSignal(to: partnerID, kind: "find_cancel", payload: .object(["ask": .string(p.askID)]), ttl: 180)
    }

    func answerFindAsk(_ ask: IncomingFindAsk, accepted: Bool) {
        let payload: JSONValue = .object(["ask": .string(ask.askID), "accepted": .bool(accepted)])
        Task {
            do { try await sendSignalNow(to: ask.fromID, kind: "find_answer", payload: payload) }
            catch { queueSignal(to: ask.fromID, kind: "find_answer", payload: payload, ttl: 180) }
        }
    }

    func broadcast(to partnerID: String, text: String) {
        queueSignal(to: partnerID, kind: "say", payload: .object(["text": .string(text)]), ttl: 600)
    }

    func departForMeetup(_ appointmentID: UUID, etaMinutes: Int, partnerUpdate: @escaping (PartnerTrip) -> Void) {
        tripHandlers[appointmentID] = partnerUpdate
        if let t = lastTrips[appointmentID] {
            // If the other person left first, notify the app on the next turn after finding state is initialized.
            Task { @MainActor in partnerUpdate(t) }
        }
        guard let partner = partner(of: appointmentID) else { return }
        queueSignal(to: partner, kind: "trip", payload: .object(["meetup": .string(appointmentID.uuidString.lowercased()),
                                                                  "state": .string("depart"), "eta": .number(Double(etaMinutes))]), ttl: 3600)
    }

    func endMeetupTrip(_ appointmentID: UUID, met: Bool) {
        tripHandlers[appointmentID] = nil
        lastTrips[appointmentID] = nil
        guard let partner = partner(of: appointmentID) else { return }
        queueSignal(to: partner, kind: "trip", payload: .object(["meetup": .string(appointmentID.uuidString.lowercased()),
                                                                  "state": .string(met ? "arrived" : "ended")]), ttl: 1800)
    }

    private func partner(of meetup: UUID) -> String? {
        guard let row = cache.seenMeetups[meetup.uuidString.lowercased()] else { return nil }
        let me = myID ?? OutboxOp.me
        let p = row.inviter.lowercased() == me || row.inviter == OutboxOp.me ? row.invitee : row.inviter
        return p.lowercased()
    }

    /// Send transient signals directly with two attempts; throw on failure for the caller to inform the user.
    private func sendSignalNow(to: String, kind: String, payload: JSONValue) async throws {
        let me = try await ensureSignedIn(allowSignUp: false)
        let body = try BackendCoding.encoder.encode(SignalInsert(from_user: me, to_user: to, kind: kind, payload: payload))
        var last: Error?
        for attempt in 0..<2 {
            do {
                _ = try await api.request("POST", "/rest/v1/signals", body: body, prefer: "return=minimal")
                markOnline()
                return
            } catch let e as BackendError where e.isRetryable {
                last = e
                noteFailure()
                if attempt == 0 { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        throw last ?? BackendError.offline("signal")
    }

    private func queueSignal(to: String, kind: String, payload: JSONValue, ttl: TimeInterval) {
        let body = SignalInsert(from_user: OutboxOp.me, to_user: to, kind: kind, payload: payload)
        enqueue(OutboxOp(method: "POST", path: "/rest/v1/signals", body: json(body), prefer: "return=minimal",
                         expires: Date().addingTimeInterval(ttl)))
    }

    // MARK: - Clear server data from the Settings deletion action

    /// Clear walks, leave, reports, outing state, and neighbor relationships. Without profile-delete permission, de-identify and move the profile to an unused grid.
    /// Then sign out; the next upload uses a new anonymous identity. Return false on network failure.
    func deleteMyServerData() async -> Bool {
        guard let me = await api.userID?.lowercased() else { resetLocalState(); return true }
        do {
            // Clear outing landmark to null; delete other tables individually. Skip permission-denied tables; only network failure counts as failure here.
            try await api.upsert("outings", OutingUpsert(user_id: me, landmark_name: nil, started_at: nil, updated_at: Date()), onConflict: "user_id")
            for (table, col) in [("walks", "user_id"), ("leaves", "user_id"), ("reports", "user_id"), ("neighbors", "owner")] {
                do { _ = try await api.request("DELETE", "/rest/v1/\(table)", query: "\(col)=eq.\(me)") }
                catch BackendError.rejected(let code, let msg) { if log { print("[backend] delete \(table) rejected \(code) \(msg)") } }
            }
            let gone = ProfileUpsert(id: me, nickname: "已離開", avatar: AvatarJSON(), tile_x: 1_000_000_000, tile_y: 1_000_000_000,
                                     community_name: nil, block: nil, floor: nil, streak: 0, streak_day: nil)
            try await api.upsert("profiles", gone, onConflict: "id")
        } catch {
            handle(error, during: "delete my data")
            return false
        }
        await api.signOut()
        resetLocalState()
        return true
    }

    private func resetLocalState() {
        if let ch = channel { realtime.remove(ch) }
        channel = nil
        realtime.disconnect()
        poller?.cancel(); poller = nil
        myID = nil
        cache = BackendCache()
        outbox = Outbox()
        outbox.save(dir.appendingPathComponent("outbox.json"))
        saveCacheNow()
        lastMembers = []
        pendingAsks.values.forEach { $0.timeout.cancel() }
        pendingAsks = [:]
        tripHandlers = [:]
        lastTrips = [:]
        failStreak = 0
        failingSince = nil
        offlineCheck?.cancel(); offlineCheck = nil
        status = .idle
    }

    // MARK: - Persisting cache

    private func saveCacheSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.saveCacheNow()
        }
    }

    private func saveCacheNow() {
        saveTask?.cancel(); saveTask = nil
        cache.save(dir.appendingPathComponent("backend.json"))
    }
}

/// Cache server data for immediate restart display and remember processed meetups/signals to avoid duplicate reminders.
struct BackendCache: Codable, Equatable {
    var userID: String?
    var board: [BoardRow] = []
    var neighbors: [NeighborRow] = []
    /// Latest observed meetup states, used to identify the other person's changes.
    var seenMeetups: [String: MeetupRow] = [:]
    var lastSignalID: Int64?
    var seenFollowUps: Set<String> = []
    var monthly: [MonthlyRow] = []
    var monthlyAt: Date?
    /// Today's passers per landmark, available only at counts of at least five.
    var passers: [String: Int] = [:]
    var passersDay: String?
    /// Neighbor outing start times, used to distinguish new departures.
    var lastOut: [String: Date] = [:]
    /// Whether my server state currently indicates an outing.
    var outingActive = false
    /// Last successfully uploaded profile; skip identical uploads.
    var lastProfile: ProfileUpsert?

    static func load(_ url: URL) -> BackendCache {
        guard let d = try? Data(contentsOf: url), let c = try? BackendCoding.decoder.decode(BackendCache.self, from: d) else { return BackendCache() }
        return c
    }

    func save(_ url: URL) {
        guard let d = try? BackendCoding.encoder.encode(self) else { return }
        try? d.write(to: url, options: .atomic)
    }
}
