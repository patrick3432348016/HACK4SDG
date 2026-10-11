import Foundation

/// 成员 A：要和别人同步的数据——圈成员、街坊关系、约会、出门状态、反映、地标改名、全邨匿名汇总。
/// 两个实现：演示模式用 LocalCommunityService（数据只在本机，对方由「示範街坊」模拟）；
/// 关咗演示模式用 SupabaseCommunityService（Backend/，真后端，表结构见 supabase/migrations/001_init.sql）。
/// 只上传地标级信息：出门状态是地标名，反映挂在地标上，原始轨迹永远不离开手机。
@MainActor
protocol CommunityService: AnyObject {
    /// 别人那边发生的事（街坊出门、应承约会、约你、反映有回覆）。
    var onEvent: ((CommunityEvent) -> Void)? { get set }
    /// 单机演示：圈里其他人都是模拟的。
    var isSimulated: Bool { get }
    /// 有服务器（真后端，或者演示时模拟嘅服务器）：反映会交出去、排行榜有其他人。
    var hasServer: Bool { get }
    /// 改地标名同圈都会见到（真后端未有地标改名表：只喺本机）。
    var sharesLandmarkNames: Bool { get }
    /// 街坊关系以服务器为准（唔用本机存档嘅关系表）。
    var ownsNeighborLinks: Bool { get }

    /// F2 圈成员（不含我）。blocks 是附近有名字的住宅楼，landmarks 是这个底座的地标。
    /// 真后端：返回缓存，背景刷新，有变就发 .membersChanged（AppStore 重新 populate）。
    func circleMembers(blocks: [String], landmarks: [Landmark]) -> [Resident]
    /// 底座嘅地标（而家嘅名 + 改名前嘅原名）：上传 / 收到地标名时对返本机地标 id。
    func setLandmarks(_ landmarks: [Landmark], originals: [String: String])

    // F5 / F6 街坊关系
    func linkNeighbor(_ id: String, send: Bool, receive: Bool)
    /// 解除街坊：只删自己这边的关系，对方不会收到通知。
    func unlinkNeighbor(_ id: String)
    func updateRemind(_ id: String, send: Bool, receive: Bool)
    /// 我出门（地标）/ 回家隐身（nil）。只发给开了"发送"的街坊。
    func publishOuting(landmarkID: String?)

    // F7 约会
    func sendInvite(_ a: Appointment)
    func respond(to a: Appointment, accept: Bool)
    /// 改时间、改地点或取消。改动要对方再确认，取消直接通知对方。
    func updateMeetup(_ a: Appointment)

    /// 重启后接返未完成的事（例如仲等紧对方确认的约会）。
    func resume(_ appointments: [Appointment])

    // F3 / F10
    func renameLandmark(_ id: String, to name: String)
    func submitReport(_ r: Report)

    // 全邨匿名汇总（只出地标级、人数够多的数字）
    func passersToday(at landmark: Landmark) -> (count: Int, isDemo: Bool)?
    func circleRace(placeName: String, myMonthSteps: Int) -> CircleRace
    func monthlyStats(myWalks: Int, myMeetups: Int, estateHomes: Int) -> MonthlyStats
    /// 其他居民的匿名反映（月报用）。
    func othersReports(landmarks: [Landmark]) -> [Report]

    // MARK: F8 找人（2026-10-08 补）
    // 只传地标 id、分钟数同一句播送；双方位置唔离开手机。

    /// 散步中临时"過去搵佢"：先问对方方唔方便。对方答复经 answer 送返（真后端：对方撳「好 / 唔方便」，Realtime 推返嚟）。
    func askToFind(partnerID: String, landmarkID: String, answer: @escaping (_ accepted: Bool) -> Void)
    /// 我取消 / 结束咗：撤回仲未答嘅询问。
    func cancelFindAsk(partnerID: String)
    /// 收到街坊问「方唔方便」（.findAsked），我撳「好 / 唔方便」。
    func answerFindAsk(_ ask: IncomingFindAsk, accepted: Bool)
    /// 播送一句俾对方（「我喺X」「我就到X」）。
    func broadcast(to partnerID: String, text: String)
    /// 约会当日我出发：话俾对方知我大约几分钟到。对方出门、途中、到达都经 partnerUpdate 送返（可以多次；
    /// 第一次 = 佢出咗门）。真后端双方位置都唔离开手机，App 只靠呢度知道对方几耐到、到咗未。
    func departForMeetup(_ appointmentID: UUID, etaMinutes: Int, partnerUpdate: @escaping (_ trip: PartnerTrip) -> Void)
    /// 见到面 / 结束找人：停止通知。
    func endMeetupTrip(_ appointmentID: UUID, met: Bool)

    // MARK: 每日汇总、请假、个人资料、撤回反映（2026-10-08 补）

    /// 当日汇总（walks 表）：分钟数、步数（圈对圈）、经过的地标、落脚点地标、当日一句。排行榜上别人睇到嘅就係呢啲。
    func uploadDay(day: String, minutes: Int, steps: Int, landmarkIDs: [String], stopLandmarkIDs: [String], line: String)
    /// 请假（leaves 表）：连续天数唔断。
    func setLeave(day: String, on: Bool)
    /// 个人资料（profiles 表）：网名、小人（行动方式、颜色、肤色、年纪）、屋企格子、屋邨名、座数楼层（只俾街坊睇）、连续天数。
    func updateProfile(_ p: CommunityProfile)
    /// 撤回自己的一条反映。
    func retractReport(_ id: UUID)
}

/// F8 约会当日对方嘅进度（只有分钟数同到咗未，冇坐标）。
struct PartnerTrip: Equatable {
    /// 大约仲要几分钟到约定地方；nil = 对方冇讲（单机由 App 按模拟路线估）。
    var etaMinutes: Int?
    var arrived = false
}

enum CommunityEvent {
    case neighborOut(residentID: String, landmarkID: String)
    case neighborHome(residentID: String)
    case inviteAnswered(appointmentID: UUID, accepted: Bool)
    case invited(Appointment)
    case reportFollowUp(reportID: UUID, text: String, isDemo: Bool)
    // 2026-10-10 真后端追加
    /// 圈成员（排行榜、街坊、出门地标）变咗：AppStore 重新 populate。
    case membersChanged
    /// 对方改咗约会时间 / 地点（要我再确认）。
    case meetupChanged(Appointment)
    /// 对方取消咗约会。
    case meetupCancelled(appointmentID: UUID)
    /// 街坊散步中想過嚟搵我：问我方唔方便。
    case findAsked(IncomingFindAsk)
    /// 佢撤回咗个询问（我未答）。
    case findAskCancelled(askID: String)
    /// 我问街坊方唔方便：问唔到（未连线）或者佢一直冇回覆。
    case findAskUnanswered(partnerID: String, offline: Bool)
    /// 找人时对方播送一句（「我喺涼亭」）。
    case partnerSaid(partnerID: String, text: String)
    /// 约会当日对方出门 / 到达 / 放弃（我未撳出发，冇人接 partnerUpdate 时）。
    case partnerTrip(appointmentID: UUID, partnerID: String, trip: PartnerTrip, ended: Bool)
}

/// 圈对圈：本月圈内总步数。
struct CircleRace: Equatable {
    var ourName: String
    var ourSteps: Int
    var rivalName: String
    var rivalSteps: Int
    var isDemo: Bool
}

/// 单机实现。示範街坊的反应用固定延时模拟，数字由示範数据和本机记录推算。
@MainActor
final class LocalCommunityService: CommunityService {
    var onEvent: ((CommunityEvent) -> Void)?
    var isSimulated: Bool { demoEnabled }
    var hasServer: Bool { demoEnabled }
    var sharesLandmarkNames: Bool { demoEnabled }
    var ownsNeighborLinks: Bool { false }
    /// 演示模式用：圈里系示範街坊。（关咗演示模式 AppStore 会换 SupabaseCommunityService。）
    var demoEnabled: Bool
    /// 演示菜单「陳太唔方便（下一次）」：下一次邀请 / 询问会被拒绝。
    var declineNext = false
    /// 每个约会只留最新一次模拟回覆（改咗时间地点，旧回覆作废）。
    private var pending: [UUID: Task<Void, Never>] = [:]
    /// 重启后要接返的约会：等圈成员装好（circleMembers）先排回覆，免得横幅出空名、空地点。
    private var resumeLater: [UUID] = []
    /// 找人询问、约会当日对方出门：每个对方 / 约会只留最新一次模拟。
    private var findAsks: [String: Task<Void, Never>] = [:]
    private var trips: [UUID: Task<Void, Never>] = [:]

    init(demoEnabled: Bool) { self.demoEnabled = demoEnabled }

    /// 示範街坊：同一格子每次一样。住在附近的住宅楼，常去的地标各不相同；连续天数是示範数据。
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
        // 取消直接生效；改时间 / 地点要对方再确认。
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

    // MARK: F8 找人（模拟：示範街坊 2.4 秒后答；演示菜单「陳太唔方便（下一次）」会拒绝一次）

    func askToFind(partnerID: String, landmarkID: String, answer: @escaping (Bool) -> Void) {
        findAsks[partnerID]?.cancel()
        findAsks[partnerID] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self.findAsks[partnerID] = nil
            // 答嗰陣先用「唔方便」：中途取消唔会用咗佢。
            let accept = !self.declineNext
            self.declineNext = false
            answer(accept)
        }
    }

    func cancelFindAsk(partnerID: String) {
        findAsks[partnerID]?.cancel()
        findAsks[partnerID] = nil
    }

    /// 单机：示範街坊唔会问你（冇对方部手机）。
    func answerFindAsk(_ ask: IncomingFindAsk, accepted: Bool) {}

    /// 单机：冇对方部手机，播送只喺本机显示。
    func broadcast(to partnerID: String, text: String) {}

    /// 单机：示範街坊 1.5 秒后出门，只报一次（之后嘅进度、到达由 App 按模拟路线自己行）。
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

    // MARK: 每日汇总、请假、个人资料、撤回反映（单机：只存本机，冇嘢要上传）

    func uploadDay(day: String, minutes: Int, steps: Int, landmarkIDs: [String], stopLandmarkIDs: [String], line: String) {}
    func setLeave(day: String, on: Bool) {}
    func updateProfile(_ p: CommunityProfile) {}
    func retractReport(_ id: UUID) {}

    // MARK: 演示触发（演示菜单 / 自动脚本）

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

    // MARK: 匿名汇总（示範数据：按地名 / 地标名做种子，同一屋邨每次一样）

    private func seed(_ s: String) -> Int { s.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } }

    func passersToday(at landmark: Landmark) -> (count: Int, isDemo: Bool)? {
        guard demoEnabled else { return nil }
        return (9 + seed(landmark.id) % 9, true)
    }

    func circleRace(placeName: String, myMonthSteps: Int) -> CircleRace {
        let members = demoEnabled ? Self.roster.reduce(0) { $0 + min($1.streak, 30) * 2_900 } : 0
        let ours = members + myMonthSteps
        let rival = demoEnabled ? Int(Double(ours) * 0.93) / 100 * 100 : 0
        return CircleRace(ourName: "\(placeName)圈", ourSteps: ours, rivalName: L.t("對面圈", "对面圈"), rivalSteps: rival, isDemo: demoEnabled)
    }

    func monthlyStats(myWalks: Int, myMeetups: Int, estateHomes: Int) -> MonthlyStats {
        guard demoEnabled else { return MonthlyStats(walks: myWalks, walkers: myWalks > 0 ? 1 : 0, meetups: myMeetups, isDemo: false) }
        // 假设 3% 住户用 App、每人每月行 9 次、一成散步係同街坊一齊。
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
