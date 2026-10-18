import Foundation

/// A's synchronized data: circle members, relationships, meetings, outings, reports, landmark names and anonymous estate aggregates.
/// LocalCommunityService simulates peers locally in demo mode.
/// Normal mode uses Backend/SupabaseCommunityService; schema is in supabase/migrations/001_init.sql.
/// Community records share landmark-level outings and reports, not raw walking tracks. Live finding has a separate temporary-coordinate channel.
@MainActor
protocol CommunityService: AnyObject {
    /// Peer events: outings, meeting acceptance, invitations and report responses.
    var onEvent: ((CommunityEvent) -> Void)? { get set }
    /// Single-device demo simulates all other circle members.
    var isSimulated: Bool { get }
    /// A real or simulated server accepts reports and supplies other leaderboard residents.
    var hasServer: Bool { get }
    /// Circle-wide landmark renaming awaits a backend table; current renaming remains local.
    var sharesLandmarkNames: Bool { get }
    /// Server relationships take precedence over locally saved relationships.
    var ownsNeighborLinks: Bool { get }

    /// F2 circle members exclude me; blocks are nearby named residences and landmarks belong to this base.
    /// Real backend returns cache, refreshes asynchronously and emits membersChanged for AppStore to repopulate.
    func circleMembers(blocks: [String], landmarks: [Landmark]) -> [Resident]
    /// Current and canonical landmark names map exchanged names back to local IDs.
    func setLandmarks(_ landmarks: [Landmark], originals: [String: String])

    // F5 / F6 neighbor relationships.
    func linkNeighbor(_ id: String, send: Bool, receive: Bool)
    /// Remove only my relationship; do not notify the peer of removal.
    func unlinkNeighbor(_ id: String)
    func updateRemind(_ id: String, send: Bool, receive: Bool)
    /// My outing landmark, or nil on return; send only to neighbors with sending enabled.
    func publishOuting(landmarkID: String?)

    // F7 meetings.
    func sendInvite(_ a: Appointment)
    func respond(to a: Appointment, accept: Bool)
    /// Time / place changes require renewed peer confirmation; cancellation notifies directly.
    func updateMeetup(_ a: Appointment)

    /// Resume unfinished work after restart, including pending meeting confirmation.
    func resume(_ appointments: [Appointment])

    // F3 / F10
    func renameLandmark(_ id: String, to name: String)
    func submitReport(_ r: Report)

    // Estate aggregates expose landmark-level counts only above the anonymity threshold.
    func passersToday(at landmark: Landmark) -> (count: Int, isDemo: Bool)?
    func circleRace(placeName: String, myMonthSteps: Int) -> CircleRace
    func monthlyStats(myWalks: Int, myMeetups: Int, estateHomes: Int) -> MonthlyStats
    /// Other residents' anonymous reports for monthly summaries.
    func othersReports(landmarks: [Landmark]) -> [Report]

    // MARK: F8 finding, added 2026-10-08
    // These events carry landmark IDs, minutes and spoken messages; live coordinates use the separate LiveFindSession channel.

    /// Ask permission before approaching during a walk; answer returns the peer's response through Realtime on the real backend.
    func askToFind(partnerID: String, landmarkID: String, answer: @escaping (_ accepted: Bool) -> Void)
    /// Withdraw an unanswered request when cancelling or ending finding.
    func cancelFindAsk(partnerID: String)
    /// Respond to an incoming findAsked event with acceptance or refusal.
    func answerFindAsk(_ ask: IncomingFindAsk, accepted: Bool)
    /// Send a short location or arrival message to the peer.
    func broadcast(to partnerID: String, text: String)
    /// On meeting departure, share estimated arrival minutes; partnerUpdate may report departure, progress and arrival repeatedly.
    /// The first update indicates departure. These progress events contain no coordinates; live finding uses its own consented channel.
    func departForMeetup(_ appointmentID: UUID, etaMinutes: Int, partnerUpdate: @escaping (_ trip: PartnerTrip) -> Void)
    /// Stop notifications after meeting or ending finding.
    func endMeetupTrip(_ appointmentID: UUID, met: Bool)

    // MARK: Daily summaries, leave, profiles and report withdrawal, added 2026-10-08

    /// Daily walks summary includes minutes, steps and daily greeting; only stopping landmarks are shared, not pass-through landmarks.
    func uploadDay(day: String, minutes: Int, steps: Int, landmarkIDs: [String], stopLandmarkIDs: [String], line: String)
    /// Leave records preserve streaks.
    func setLeave(day: String, on: Bool)
    /// Profiles include nickname, mobility / avatar, home grid, estate, neighbor-visible building / floor and streak.
    func updateProfile(_ p: CommunityProfile)
    /// Withdraw one of my reports.
    func retractReport(_ id: UUID)
}

/// F8 meeting-day progress contains minutes and arrival state, without coordinates.
struct PartnerTrip: Equatable {
    /// Estimated minutes to the meeting place; nil means unreported. Local demo estimates from its simulated route.
    var etaMinutes: Int?
    var arrived = false
}

enum CommunityEvent {
    case neighborOut(residentID: String, landmarkID: String)
    case neighborHome(residentID: String)
    case inviteAnswered(appointmentID: UUID, accepted: Bool)
    case invited(Appointment)
    case reportFollowUp(reportID: UUID, text: String, isDemo: Bool)
    // Real-backend additions, 2026-10-10.
    /// AppStore repopulates after circle members, relationships or outing landmarks change.
    case membersChanged
    /// Peer changed meeting time / place, requiring my confirmation.
    case meetupChanged(Appointment)
    /// Peer cancelled the meeting.
    case meetupCancelled(appointmentID: UUID)
    /// A walking neighbor asks permission to approach.
    case findAsked(IncomingFindAsk)
    /// Peer withdrew the unanswered request.
    case findAskCancelled(askID: String)
    /// My finding request failed to send or remained unanswered.
    case findAskUnanswered(partnerID: String, offline: Bool)
    /// Peer sent a spoken location message during finding.
    case partnerSaid(partnerID: String, text: String)
    /// Meeting-day departure, arrival or abandonment before I depart or while no partnerUpdate handler is active.
    case partnerTrip(appointmentID: UUID, partnerID: String, trip: PartnerTrip, ended: Bool)
}

/// Circle-versus-circle monthly step total.
struct CircleRace: Equatable {
    var ourName: String
    var ourSteps: Int
    var rivalName: String
    var rivalSteps: Int
    var isDemo: Bool
}

/// Local implementation uses fixed-delay demo reactions and numbers derived from sample data and local records.
@MainActor
final class LocalCommunityService: CommunityService {
    var onEvent: ((CommunityEvent) -> Void)?
    var isSimulated: Bool { demoEnabled }
    var hasServer: Bool { demoEnabled }
    var sharesLandmarkNames: Bool { demoEnabled }
    var ownsNeighborLinks: Bool { false }
    /// Demo circle contains sample neighbors; disabling demo switches to SupabaseCommunityService.
    var demoEnabled: Bool
    /// The demo refusal action rejects the next invitation or request.
    var declineNext = false
    /// Keep only each meeting's latest simulated reply; edits invalidate older replies.
    private var pending: [UUID: Task<Void, Never>] = [:]
    /// After restart wait for circleMembers before scheduling replies, avoiding blank names and places.
    private var resumeLater: [UUID] = []
    /// Keep only the latest simulated finding request / departure per peer or meeting.
    private var findAsks: [String: Task<Void, Never>] = [:]
    private var trips: [UUID: Task<Void, Never>] = [:]

    init(demoEnabled: Bool) { self.demoEnabled = demoEnabled }

    /// Deterministic demo neighbors per tile, assigned nearby residences and varied destinations; streaks are sample data.
    private static let roster: [(id: String, name: String, floor: Int, color: Int, mobility: Mobility, streak: Int)] = [
        ("chan", "陳太", 8, 0, .walk, 21), ("wong", "黃太", 3, 1, .walk, 30), ("lee", "李伯", 15, 2, .wheelchair, 14),
        ("leung", "梁太", 6, 3, .stroller, 12), ("ho", "何生", 21, 4, .walk, 5), ("cheung", "張伯", 9, 5, .cane, 2),
    ]

    func circleMembers(blocks: [String], landmarks: [Landmark]) -> [Resident] {
        defer { flushResume() }
        guard demoEnabled else { return [] }
        let seatFirst = landmarks.sorted { ($0.hasSeat ? 0 : 1, $0.pos.length) < ($1.hasSeat ? 0 : 1, $1.pos.length) }
        return Self.roster.enumerated().map { i, r in
            var res = Resident(id: r.id, name: r.name, floor: r.floor, blockName: blocks.isEmpty ? nil : blocks[i % blocks.count],
                               colorIndex: r.color, mobility: r.mobility, streakDays: r.streak, todayLine: "")
            res.homeLandmarkID = seatFirst.isEmpty ? nil : seatFirst[i % seatFirst.count].id
            res.isDemo = true
            return res
        }
    }

    func setLandmarks(_ landmarks: [Landmark], originals: [String: String]) {}
    func linkNeighbor(_ id: String, send: Bool, receive: Bool) {}
    func unlinkNeighbor(_ id: String) {}
    func updateRemind(_ id: String, send: Bool, receive: Bool) {}
    func publishOuting(landmarkID: String?) {}
    func respond(to a: Appointment, accept: Bool) {}
    func renameLandmark(_ id: String, to name: String) {}
    func submitReport(_ r: Report) {}

    func sendInvite(_ a: Appointment) { answerLater(a.id, after: 4) }

    func updateMeetup(_ a: Appointment) {
        // Cancellation applies immediately; time / place edits require reconfirmation.
        if a.status == .waiting { answerLater(a.id, after: 3) } else { pending[a.id]?.cancel(); pending[a.id] = nil }
    }

    func resume(_ appointments: [Appointment]) {
        resumeLater = appointments.filter { $0.status == .waiting && !$0.fromPartner && $0.date > Date() }.map(\.id)
    }

    private func flushResume() {
        let ids = resumeLater
        resumeLater = []
        for id in ids { answerLater(id, after: 3) }
    }

    private func answerLater(_ id: UUID, after s: Double) {
        let accept = !declineNext
        declineNext = false
        pending[id]?.cancel()
        pending[id] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(s))
            guard !Task.isCancelled else { return }
            self.pending[id] = nil
            self.onEvent?(.inviteAnswered(appointmentID: id, accepted: accept))
        }
    }

    // MARK: F8 simulated finding: reply after 2.4 seconds; the demo refusal option rejects once

    func askToFind(partnerID: String, landmarkID: String, answer: @escaping (Bool) -> Void) {
        findAsks[partnerID]?.cancel()
        findAsks[partnerID] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self.findAsks[partnerID] = nil
            // Consume the refusal option only when answering, not if cancelled earlier.
            let accept = !self.declineNext
            self.declineNext = false
            answer(accept)
        }
    }

    func cancelFindAsk(partnerID: String) {
        findAsks[partnerID]?.cancel()
        findAsks[partnerID] = nil
    }

    /// Local demo has no peer phone to send incoming finding requests.
    func answerFindAsk(_ ask: IncomingFindAsk, accepted: Bool) {}

    /// Without a peer phone, local demo broadcasts appear only locally.
    func broadcast(to partnerID: String, text: String) {}

    /// The demo peer departs after 1.5 seconds and reports once; subsequent movement follows the App's simulated route.
    func departForMeetup(_ appointmentID: UUID, etaMinutes: Int, partnerUpdate: @escaping (PartnerTrip) -> Void) {
        trips[appointmentID]?.cancel()
        trips[appointmentID] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self.trips[appointmentID] = nil
            partnerUpdate(PartnerTrip(etaMinutes: nil))
        }
    }

    func endMeetupTrip(_ appointmentID: UUID, met: Bool) {
        trips[appointmentID]?.cancel()
        trips[appointmentID] = nil
    }

    // MARK: Local summaries, leave, profiles and withdrawals require no upload

    func uploadDay(day: String, minutes: Int, steps: Int, landmarkIDs: [String], stopLandmarkIDs: [String], line: String) {}
    func setLeave(day: String, on: Bool) {}
    func updateProfile(_ p: CommunityProfile) {}
    func retractReport(_ id: UUID) {}

    // MARK: Demo-menu and scripted triggers

    func simulateOut(_ id: String, at landmarkID: String) { onEvent?(.neighborOut(residentID: id, landmarkID: landmarkID)) }
    func simulateHome(_ id: String) { onEvent?(.neighborHome(residentID: id)) }
    func simulateInvite(_ a: Appointment) { onEvent?(.invited(a)) }
    func simulateFollowUp(_ r: Report, place: String) {
        let text: String
        switch r.kind {
        case .sunny: text = L.t("屋邨管理回覆：\(place)下個月加遮陽篷。", "小区管理处回复：\(place)下个月加遮阳篷。")
        case .noSeat: text = L.t("屋邨管理回覆：\(place)會加兩張櫈。", "小区管理处回复：\(place)会加两张凳子。")
        case .rough: text = L.t("屋邨管理回覆：\(place)嘅路面已經安排整平。", "小区管理处回复：\(place)的路面已安排整平。")
        }
        onEvent?(.reportFollowUp(reportID: r.id, text: text, isDemo: true))
    }

    // MARK: Sample anonymous aggregates seeded by estate / landmark names for repeatability

    private func seed(_ s: String) -> Int { s.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } }

    func passersToday(at landmark: Landmark) -> (count: Int, isDemo: Bool)? {
        guard demoEnabled else { return nil }
        return (9 + seed(landmark.id) % 9, true)
    }

    func circleRace(placeName: String, myMonthSteps: Int) -> CircleRace {
        let members = demoEnabled ? Self.roster.reduce(0) { $0 + min($1.streak, 30) * 2_900 } : 0
        let ours = members + myMonthSteps
        let rival = demoEnabled ? Int(Double(ours) * 0.93) / 100 * 100 : 0
        return CircleRace(ourName: L.t("我哋呢頭", "我们这边"), ourSteps: ours, rivalName: L.t("隔籬", "隔壁"), rivalSteps: rival, isDemo: demoEnabled)
    }

    func monthlyStats(myWalks: Int, myMeetups: Int, estateHomes: Int) -> MonthlyStats {
        guard demoEnabled else { return MonthlyStats(walks: myWalks, walkers: myWalks > 0 ? 1 : 0, meetups: myMeetups, isDemo: false) }
        // Demo assumptions: 3% adoption, 9 walks per user per month, and 10% of walks with neighbors.
        let walkers = max(12, estateHomes * 3 / 100)
        let walks = walkers * 9 + myWalks
        return MonthlyStats(walks: walks, walkers: walkers, meetups: walks / 8 + myMeetups, isDemo: true)
    }

    func othersReports(landmarks: [Landmark]) -> [Report] {
        guard demoEnabled, landmarks.count >= 3 else { return [] }
        let base: [(Int, ReportKind, Int)] = [(0, .sunny, 23), (1, .noSeat, 14), (2, .rough, 11)]
        return base.flatMap { i, k, n in
            (0..<n).map { _ in Report(kind: k, pos: landmarks[i].pos, landmarkID: landmarks[i].id, date: Date()) }
        }
    }
}
