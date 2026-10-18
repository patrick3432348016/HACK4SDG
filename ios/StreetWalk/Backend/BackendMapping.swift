import Foundation

// Pure mappings between server rows and Resident/Appointment/Report, tested in StreetWalkTests/BackendTests.

/// Uploaded profile: block/floor visible only to mutual neighbors; home location represented by a 400 m grid and estate name.
struct CommunityProfile: Equatable {
    var nickname: String
    var mobility: Mobility
    var colorIndex: Int
    var skinTone: Int
    var ageGroup: AgeGroup
    var tileX: Int
    var tileY: Int
    var communityName: String?
    var block: String?
    var floor: Int?
    var streak: Int
    /// Hong Kong date through which the streak is valid (yyyy-MM-dd); the server displays zero two days later.
    var streakDay: String

    static let nicknameLimit = 20

    /// Nickname: trim surrounding whitespace and require 1–20 Unicode characters, matching server char_length.
    static func cleanNickname(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.unicodeScalars.count <= nicknameLimit else { return nil }
        return t
    }

    func upsert(id: String) -> ProfileUpsert {
        ProfileUpsert(id: id, nickname: nickname,
                      avatar: BackendMapping.avatar(mobility: mobility, color: colorIndex, skin: skinTone, age: ageGroup),
                      tile_x: tileX, tile_y: tileY, community_name: communityName, block: block, floor: floor,
                      streak: streak, streak_day: streakDay)
    }
}

/// Incoming F8 request from a walking neighbor asking whether they may come over.
struct IncomingFindAsk: Equatable, Identifiable {
    var id: String { askID }
    var askID: String
    var fromID: String
    var landmarkID: String
    var at = Date()
}

/// Map server landmark names to local IDs on each phone.
/// If unmatched, use a synthetic lmname:<name> ID and text-only display; do not place it in the scene.
struct LandmarkIndex: Equatable {
    var landmarks: [Landmark] = []
    /// Landmark ID → original name before local renaming.
    var originals: [String: String] = [:]

    static let syntheticPrefix = "lmname:"
    static func syntheticID(_ name: String) -> String { syntheticPrefix + name }
    static func syntheticName(_ id: String?) -> String? {
        guard let id, id.hasPrefix(syntheticPrefix) else { return nil }
        return String(id.dropFirst(syntheticPrefix.count))
    }

    /// Upload the original name so the other phone can match it.
    func publishName(_ id: String?) -> String? {
        guard let id else { return nil }
        if let n = Self.syntheticName(id) { return n }
        return originals[id] ?? landmarks.first { $0.id == id }?.name
    }

    /// Resolve received names against original names, then current names; otherwise create a synthetic ID.
    func id(forName name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        if let (id, _) = originals.first(where: { $0.value == name }), landmarks.contains(where: { $0.id == id }) { return id }
        if let l = landmarks.first(where: { $0.name == name }) { return l.id }
        return Self.syntheticID(name)
    }
}

enum BackendMapping {
    /// Treat an outing not updated for more than three hours as ended, covering stale server state after crashes/network loss.
    static let staleOuting: TimeInterval = 3 * 3600

    static func avatar(mobility: Mobility, color: Int, skin: Int, age: AgeGroup) -> AvatarJSON {
        AvatarJSON(mobility: mobility.rawValue, color: color, skin: skin, age: age.rawValue)
    }

    static func look(_ a: AvatarJSON?) -> (mobility: Mobility, color: Int, skin: Int, age: AgeGroup) {
        let color = a?.color.map { min(max($0, 0), Palette.people.count - 1) } ?? 0
        let skin = a?.skin.map { min(max($0, 0), Palette.skins.count - 1) } ?? 1
        return (Mobility(rawValue: a?.mobility ?? "") ?? .walk, color, skin, AgeGroup(rawValue: a?.age ?? "") ?? .adult)
    }

    static func isOut(_ n: NeighborRow, now: Date) -> Bool {
        guard let at = n.out_at, !at.isEmpty else { return false }
        if let since = n.out_since, now.timeIntervalSince(since) > staleOuting { return false }
        return true
    }

    /// Merge nearby residents and neighbors into circle members. Non-neighbors expose only nickname, avatar, and streak, without block/floor or daily sentence.
    /// Neighbors additionally expose block/floor, daily sentence, outing landmark, and reminder settings. Exclude self.
    static func residents(board: [BoardRow], neighbors: [NeighborRow], myID: String?, landmarks: LandmarkIndex, now: Date) -> [Resident] {
        var out: [Resident] = []
        var seen = Set<String>()
        let byID = Dictionary(neighbors.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        func make(id: String, nickname: String, avatar: AvatarJSON?, streak: Int, line: String?, n: NeighborRow?) -> Resident {
            let lk = look(avatar ?? n?.avatar)
            var r = Resident(id: id, name: nickname, floor: n?.floor ?? 0, blockName: n?.block, colorIndex: lk.color,
                             mobility: lk.mobility, streakDays: max(0, streak), todayLine: "")
            r.skinTone = lk.skin
            r.ageGroup = lk.age
            if let n {
                r.isNeighbor = true
                r.neighborSince = n.since
                r.sendRemind = n.send_remind ?? true
                r.receiveRemind = n.receive_remind ?? true
                r.todayLine = n.daily_line ?? line ?? ""
                if isOut(n, now: now) {
                    r.isOut = true
                    r.atLandmarkID = landmarks.id(forName: n.out_at)
                }
            }
            return r
        }
        for b in board {
            let id = b.id.lowercased()
            guard !b.is_me, id != myID, seen.insert(id).inserted else { continue }
            out.append(make(id: id, nickname: b.nickname, avatar: b.avatar, streak: b.streak, line: b.daily_line, n: byID[id]))
        }
        for n in neighbors {
            let id = n.id.lowercased()
            guard id != myID, seen.insert(id).inserted else { continue }
            out.append(make(id: id, nickname: n.nickname, avatar: n.avatar, streak: n.streak ?? 0, line: nil, n: n))
        }
        return out
    }

    static func resident(_ p: LinkedPeer) -> Resident {
        var r = Resident(id: p.id, name: p.nickname, floor: p.floor ?? 0, blockName: p.block, colorIndex: p.colorIndex,
                         mobility: p.mobility, streakDays: 0, todayLine: "")
        r.skinTone = p.skinTone
        r.ageGroup = p.ageGroup
        r.isNeighbor = true
        r.neighborSince = Date()
        return r
    }

    static func peer(_ row: LinkRow) -> LinkedPeer {
        let lk = look(row.avatar)
        return LinkedPeer(id: row.id.lowercased(), nickname: row.nickname, mobility: lk.mobility, colorIndex: lk.color,
                          skinTone: lk.skin, ageGroup: lk.age, block: row.block, floor: row.floor)
    }

    static func neighborRow(_ p: LinkedPeer) -> NeighborRow {
        NeighborRow(id: p.id, nickname: p.nickname, avatar: avatar(mobility: p.mobility, color: p.colorIndex, skin: p.skinTone, age: p.ageGroup),
                    block: p.block, floor: p.floor, streak: 0, since: Date(), send_remind: true, receive_remind: true,
                    out_at: nil, out_since: nil, daily_line: nil)
    }

    // MARK: - Meetups

    static func serverStatus(_ s: Appointment.Status) -> String {
        switch s {
        case .waiting: return "waiting"
        case .accepted: return "accepted"
        case .done: return "done"
        case .cancelled: return "cancelled"
        case .expired: return "expired"
        }
    }

    static func appointment(_ m: MeetupRow, me: String, landmarks: LandmarkIndex) -> Appointment? {
        guard let id = UUID(uuidString: m.id) else { return nil }
        let partner = (m.inviter.lowercased() == me ? m.invitee : m.inviter).lowercased()
        let status: Appointment.Status
        switch m.status {
        case "accepted": status = .accepted
        case "done": status = .done
        case "expired": status = .expired
        case "declined", "cancelled": status = .cancelled
        default: status = .waiting
        }
        let byOther = (m.updated_by ?? m.inviter).lowercased() != me
        return Appointment(id: id, partnerID: partner, date: m.at, landmarkID: landmarks.id(forName: m.landmark_name) ?? "",
                           reason: m.reason ?? "", status: status, fromPartner: status == .waiting && byOther)
    }

    enum MeetupChange: Equatable {
        case invited            // New invitation from the other person.
        case answered(Bool)     // The other person accepts/declines my invitation.
        case changed            // The other person changes time/place; confirmation is required again.
        case cancelled          // The other person cancels.
    }

    /// Compare with the last observed state. Do not emit events for changes made by self (updated_by).
    static func meetupChange(_ row: MeetupRow, seen: MeetupRow?, me: String, now: Date) -> MeetupChange? {
        let byOther = (row.updated_by ?? row.inviter).lowercased() != me
        guard byOther else { return nil }
        guard let seen else {
            // On first observation, emit only a still-valid incoming invitation. Merely remember other records, such as old meetups after reinstalling.
            if row.invitee.lowercased() == me, row.status == "waiting", row.at > now.addingTimeInterval(-3600) { return .invited }
            return nil
        }
        guard row.updated_at != seen.updated_at || row.status != seen.status || row.at != seen.at || row.landmark_name != seen.landmark_name else { return nil }
        switch row.status {
        case "accepted": return seen.status == "accepted" ? nil : .answered(true)
        case "declined": return seen.status == "declined" ? nil : .answered(false)
        case "cancelled": return seen.status == "cancelled" ? nil : .cancelled
        case "waiting": return .changed
        default: return nil
        }
    }

    // MARK: - Reports

    static func serverKind(_ k: ReportKind) -> String {
        switch k {
        case .sunny: return "sunny"
        case .noSeat: return "no_seat"
        case .rough: return "rough"
        }
    }

    static func reportKind(_ s: String) -> ReportKind? {
        switch s {
        case "sunny": return .sunny
        case "no_seat": return .noSeat
        case "rough": return .rough
        default: return nil
        }
    }

    /// Monthly report: one anonymous report per resident, attached only to a matching local landmark.
    static func reports(_ rows: [MonthlyRow], landmarks: [Landmark], index: LandmarkIndex, now: Date) -> [Report] {
        rows.flatMap { row -> [Report] in
            guard let kind = reportKind(row.kind), let id = index.id(forName: row.landmark_name),
                  let lm = landmarks.first(where: { $0.id == id }) else { return [] }
            return (0..<max(0, row.people)).map { _ in Report(kind: kind, pos: lm.pos, landmarkID: lm.id, date: now) }
        }
    }

    // MARK: - Streaks

    /// streak_day is today when walking/on leave, extended through consecutive future leave days; otherwise yesterday.
    /// Extend streak_day through long leave so the server's two-day expiry does not zero the board mid-leave.
    static func streakDay(today: Date, streak: Int, walkedOrLeave: (String) -> Bool, leave: (String) -> Bool) -> String {
        var day = walkedOrLeave(LocalStore.dayKey(today)) || streak == 0 ? today : today.addingTimeInterval(-86400)
        for _ in 0..<60 {
            let next = day.addingTimeInterval(86400)
            guard leave(LocalStore.dayKey(next)) else { break }
            day = next
        }
        return LocalStore.dayKey(day)
    }
}
