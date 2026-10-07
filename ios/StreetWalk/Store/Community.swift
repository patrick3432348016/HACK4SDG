import Foundation

/// 成员 A：要和别人同步的数据——圈成员、街坊关系、约会、出门状态、反映、地标改名、全邨匿名汇总。
/// 上线时用 Supabase 实现同一协议（表结构见 docs/backend_supabase.md）；
/// 现在是 LocalCommunityService：数据只在本机，对方由「示範街坊」模拟。
/// 只上传地标级信息：出门状态是地标 id，反映挂在地标上，原始轨迹永远不离开手机。
@MainActor
protocol CommunityService: AnyObject {
    /// 别人那边发生的事（街坊出门、应承约会、约你、反映有回覆）。
    var onEvent: ((CommunityEvent) -> Void)? { get set }
    /// 单机演示：圈里其他人都是模拟的。
    var isSimulated: Bool { get }

    /// F2 圈成员（不含我）。blocks 是附近有名字的住宅楼，landmarks 是这个底座的地标。
    func circleMembers(blocks: [String], landmarks: [Landmark]) -> [Resident]

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

    // F3 / F10
    func renameLandmark(_ id: String, to name: String)
    func submitReport(_ r: Report)

    // 全邨匿名汇总（只出地标级、人数够多的数字）
    func passersToday(at landmark: Landmark) -> (count: Int, isDemo: Bool)?
    func circleRace(placeName: String, myMonthSteps: Int) -> CircleRace
    func monthlyStats(myWalks: Int, myMeetups: Int, estateHomes: Int) -> MonthlyStats
    /// 其他居民的匿名反映（月报用）。
    func othersReports(landmarks: [Landmark]) -> [Report]
}

enum CommunityEvent {
    case neighborOut(residentID: String, landmarkID: String)
    case neighborHome(residentID: String)
    case inviteAnswered(appointmentID: UUID, accepted: Bool)
    case invited(Appointment)
    case reportFollowUp(reportID: UUID, text: String)
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
    /// 关掉演示模式后，圈里只有你（还没接后端）。
    var demoEnabled: Bool
    /// 演示菜单「陳太唔方便（下一次）」：下一次邀请 / 询问会被拒绝。
    var declineNext = false

    init(demoEnabled: Bool) { self.demoEnabled = demoEnabled }

    /// 示範街坊：同一格子每次一样。住在附近的住宅楼，常去的地标各不相同；连续天数是示範数据。
    private static let roster: [(id: String, name: String, floor: Int, color: Int, mobility: Mobility, streak: Int)] = [
        ("chan", "陳太", 8, 0, .walk, 21), ("wong", "黃太", 3, 1, .walk, 30), ("lee", "李伯", 15, 2, .wheelchair, 14),
        ("leung", "梁太", 6, 3, .stroller, 12), ("ho", "何生", 21, 4, .walk, 5), ("cheung", "張伯", 9, 5, .cane, 2),
    ]

    func circleMembers(blocks: [String], landmarks: [Landmark]) -> [Resident] {
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
        if a.status == .waiting { answerLater(a.id, after: 3) }
    }

    private func answerLater(_ id: UUID, after s: Double) {
        let accept = !declineNext
        declineNext = false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(s))
            self.onEvent?(.inviteAnswered(appointmentID: id, accepted: accept))
        }
    }

    // MARK: 演示触发（演示菜单 / 自动脚本）

    func simulateOut(_ id: String, at landmarkID: String) { onEvent?(.neighborOut(residentID: id, landmarkID: landmarkID)) }
    func simulateHome(_ id: String) { onEvent?(.neighborHome(residentID: id)) }
    func simulateInvite(_ a: Appointment) { onEvent?(.invited(a)) }
    func simulateFollowUp(_ r: Report, place: String) {
        let text: String
        switch r.kind {
        case .sunny: text = "屋邨管理回覆：\(place)下個月加遮陽篷。"
        case .noSeat: text = "屋邨管理回覆：\(place)會加兩張櫈。"
        case .rough: text = "屋邨管理回覆：\(place)嘅路面已經安排整平。"
        }
        onEvent?(.reportFollowUp(reportID: r.id, text: text))
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
        return CircleRace(ourName: "\(placeName)圈", ourSteps: ours, rivalName: "對面圈", rivalSteps: rival, isDemo: demoEnabled)
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
