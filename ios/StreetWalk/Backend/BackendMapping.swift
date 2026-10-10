import Foundation

// 服务器行 ↔ App 资料（Resident、Appointment、Report）嘅对应。纯函数，单元测试直接测（StreetWalkTests/BackendTests）。

/// 上传嘅个人资料（profiles）。座数楼层只俾互为街坊睇；屋企位置只上传 400 m 格子同屋邨名。
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
    /// 连续天数计到边日（"yyyy-MM-dd"，香港日期）；服务器过咗呢日两日就当 0。
    var streakDay: String

    static let nicknameLimit = 20

    /// 网名规则：去头尾空格，1–20 个字（同服务器 char_length 一致，按 Unicode 字符计）。
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

/// 街坊散步中想過嚟搵我：问我「方唔方便」（收到嘅一方，F8）。
struct IncomingFindAsk: Equatable, Identifiable {
    var id: String { askID }
    var askID: String
    var fromID: String
    var landmarkID: String
    var at = Date()
}

/// 地标名 ↔ 本机地标 id。服务器只有地标名；两部手机按名对返自己地图上同名嘅地标。
/// 对唔上（对方喺我底座外面、或者改咗名）就用合成 id「lmname:<名>」，只显示文字，唔入场景。
struct LandmarkIndex: Equatable {
    var landmarks: [Landmark] = []
    /// 地标 id → 原名（用户改名之前，大家都一样嘅名）。
    var originals: [String: String] = [:]

    static let syntheticPrefix = "lmname:"
    static func syntheticID(_ name: String) -> String { syntheticPrefix + name }
    static func syntheticName(_ id: String?) -> String? {
        guard let id, id.hasPrefix(syntheticPrefix) else { return nil }
        return String(id.dropFirst(syntheticPrefix.count))
    }

    /// 上传用嘅名：用原名（改过名都系），对方先对得上。
    func publishName(_ id: String?) -> String? {
        guard let id else { return nil }
        if let n = Self.syntheticName(id) { return n }
        return originals[id] ?? landmarks.first { $0.id == id }?.name
    }

    /// 收到嘅地标名 → 本机 id：先对原名，再对而家嘅名；都冇就合成 id。
    func id(forName name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        if let (id, _) = originals.first(where: { $0.value == name }), landmarks.contains(where: { $0.id == id }) { return id }
        if let l = landmarks.first(where: { $0.name == name }) { return l.id }
        return Self.syntheticID(name)
    }
}

enum BackendMapping {
    /// 出门超过 3 个钟仍未更新：当佢已经返咗屋企（App 闪退、冇咗网络，状态留咗喺服务器）。
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

    /// 排行榜（附近真人）∪ 我的街坊 → 圈成员。非街坊：只有网名、小人、连续日数（冇座数楼层、冇今日一句）；
    /// 街坊：加座数楼层、今日一句、出门地标、提醒开关。唔包括我。
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

    // MARK: - 约会

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
        case invited            // 对方约我（新）
        case answered(Bool)     // 对方应承 / 拒绝我嘅约
        case changed            // 对方改咗时间地点（要我再确认）
        case cancelled          // 对方取消
    }

    /// 对比上次见过嘅样子，睇对方做咗乜。自己改嘅（updated_by == 我）唔出事件。
    static func meetupChange(_ row: MeetupRow, seen: MeetupRow?, me: String, now: Date) -> MeetupChange? {
        let byOther = (row.updated_by ?? row.inviter).lowercased() != me
        guard byOther else { return nil }
        guard let seen else {
            // 第一次见：对方约我（仲未过期）先算；其他（例如重装之后见返旧约）只记低。
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

    // MARK: - 反映

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

    /// 月报：其他居民嘅匿名反映（每个人一条，放喺对得上嘅地标；对唔上嘅唔计）。
    static func reports(_ rows: [MonthlyRow], landmarks: [Landmark], index: LandmarkIndex, now: Date) -> [Report] {
        rows.flatMap { row -> [Report] in
            guard let kind = reportKind(row.kind), let id = index.id(forName: row.landmark_name),
                  let lm = landmarks.first(where: { $0.id == id }) else { return [] }
            return (0..<max(0, row.people)).map { _ in Report(kind: kind, pos: lm.pos, landmarkID: lm.id, date: now) }
        }
    }

    // MARK: - 连续天数

    /// streak_day：今日有行 / 请假就系今日（再顺延到之后连住请咗嘅假），否则系琴日（连续天数由琴日起计）。
    /// 服务器喺 streak_day 两日之后就显示 0，所以请长假时要顺延，排行榜先唔会中途变 0。
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
