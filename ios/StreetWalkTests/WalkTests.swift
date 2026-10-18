import Foundation
import Testing
@testable import StreetWalk

// Walk/data tests: stops, device gates, backfill, cadence, leave, demo isolation, legacy saves and notifications.

struct WalkLogicTests {
    let t0 = SunShadeTests.hk("2026-10-07 10:00")
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test func 落脚点要停够两分钟() {
        var d = StopDetector()
        var found: [Vec2] = []
        // Moving at 1.2 m/s for 60 seconds is not a stop.
        for i in 0...60 { if let c = d.add(Vec2(x: Double(i) * 1.2, y: 0), at: at(Double(i))) { found.append(c) } }
        #expect(found.isEmpty)
        // Movement within 10 m around (80,0) for 150 seconds forms one stop.
        for i in 0...30 {
            if let c = d.add(Vec2(x: 80 + Double(i % 5) * 2, y: Double(i % 3) * 3), at: at(70 + Double(i) * 5)) { found.append(c) }
        }
        #expect(found.count == 1)
        #expect(found.first.map { $0.distance(to: Vec2(x: 84, y: 3)) < 15 } == true)
    }

    @Test func 企定冇新定位都计到落脚点() {
        var d = StopDetector()
        let first = d.add(Vec2(x: 0, y: 0), at: at(0)), h1 = d.hold(at: at(60)), h2 = d.hold(at: at(125)), h3 = d.hold(at: at(200))
        #expect(first == nil && h1 == nil)
        #expect(h2 != nil)
        #expect(h3 == nil, "每段只报一次")
    }

    @Test func 定位跳一下唔会开始() {
        var gate = LiveWalkGate()
        func g_decide(fromHome: Double, acc: Double, at t: Date, recording: Bool, moving: Bool) -> LiveWalkGate.Action {
            gate.decide(fromHome: fromHome, acc: acc, at: t, recording: recording, moving: moving)
        }
        #expect(g_decide(fromHome: 90, acc: 10, at: at(0), recording: false, moving: true) == .none)
        #expect(g_decide(fromHome: 10, acc: 10, at: at(3), recording: false, moving: true) == .none)
        #expect(g_decide(fromHome: 90, acc: 10, at: at(6), recording: false, moving: true) == .none, "要重新数")
        #expect(g_decide(fromHome: 95, acc: 10, at: at(12), recording: false, moving: true) == .start)
    }

    @Test func 开始条件() {
        var gate = LiveWalkGate()
        func g_decide(fromHome: Double, acc: Double, at t: Date, recording: Bool, moving: Bool) -> LiveWalkGate.Action {
            gate.decide(fromHome: fromHome, acc: acc, at: t, recording: recording, moving: moving)
        }
        // Do not start without Core Motion walking.
        _ = g_decide(fromHome: 90, acc: 10, at: at(0), recording: false, moving: false)
        #expect(g_decide(fromHome: 90, acc: 10, at: at(10), recording: false, moving: false) == .none)
        // Start outside the visible base at 150 m.
        _ = g_decide(fromHome: 150, acc: 10, at: at(20), recording: false, moving: true)
        #expect(g_decide(fromHome: 160, acc: 10, at: at(30), recording: false, moving: true) == .start)
        // Beyond 400 m does not count as a normal departure start.
        _ = g_decide(fromHome: 500, acc: 10, at: at(40), recording: false, moving: true)
        #expect(g_decide(fromHome: 510, acc: 10, at: at(50), recording: false, moving: true) == .none)
        // At 55–70 m with 25 m uncertainty, adjusted distance is below 55 m; avoid start/end oscillation.
        _ = g_decide(fromHome: 65, acc: 25, at: at(60), recording: false, moving: true)
        #expect(g_decide(fromHome: 68, acc: 25, at: at(70), recording: false, moving: true) == .none)
    }

    @Test func 精度差唔会提早收尾() {
        var gate = LiveWalkGate()
        func g_decide(fromHome: Double, acc: Double, at t: Date, recording: Bool, moving: Bool) -> LiveWalkGate.Action {
            gate.decide(fromHome: fromHome, acc: acc, at: t, recording: recording, moving: moving)
        }
        #expect(g_decide(fromHome: 99, acc: 60, at: at(0), recording: true, moving: true) == .minutesOnly)
        #expect(g_decide(fromHome: 65, acc: 25, at: at(5), recording: true, moving: true) == .step)
        #expect(g_decide(fromHome: 70, acc: 45, at: at(10), recording: true, moving: true) == .minutesOnly, "啱啱开始 2 分钟内：门口定位跳一跳唔收尾")
        #expect(g_decide(fromHome: 70, acc: 45, at: at(130), recording: true, moving: true) == .finish, "扣误差喺 40 m 内、精度 ≤50")
        #expect(g_decide(fromHome: 30, acc: 80, at: at(135), recording: true, moving: false) == .finish)
    }

    @Test func 背景补记行路时段() {
        typealias S = WalkBackfill.Sample
        let samples = [S(start: at(0), moving: false), S(start: at(60), moving: true), S(start: at(20 * 60), moving: false),
                       S(start: at(21 * 60), moving: true), S(start: at(30 * 60), moving: false),
                       S(start: at(60 * 60), moving: true), S(start: at(63 * 60), moving: false),
                       S(start: at(90 * 60), moving: true)]
        let segs = WalkBackfill.segments(samples, until: at(100 * 60))
        #expect(segs.count == 2, "等过马路嗰 1 分钟合并；3 分钟嗰段太短")
        #expect(segs.first == DateInterval(start: at(60), end: at(30 * 60)))
        #expect(segs.last == DateInterval(start: at(90 * 60), end: at(100 * 60)), "仲行紧：到而家")
    }

    @Test func 最后一段啱啱停都会补记() {
        typealias S = WalkBackfill.Sample
        let to = at(60 * 60)
        // Walk 20 minutes while locked, return home and open after 30 seconds stopped.
        let home = [S(start: at(0), moving: false), S(start: at(10 * 60), moving: true), S(start: at(30 * 60), moving: false),
                    S(start: at(40 * 60), moving: true), S(start: to.addingTimeInterval(-30), moving: false)]
        let (done, tail) = WalkBackfill.split(home, until: to)
        #expect(done == [DateInterval(start: at(10 * 60), end: at(30 * 60))], "早啲嗰段即刻补记")
        #expect(tail == PendingWalk(start: at(40 * 60), end: to.addingTimeInterval(-30)))
        #expect(tail?.interval(stoppedAt: to.addingTimeInterval(120)) == DateInterval(start: at(40 * 60), end: to.addingTimeInterval(-30)),
                "冇接到真机散步：按停低嘅时间补记，唔计之后坐低嘅时间")

        // If still walking after 25 minutes, potentially beyond 400 m, transfer to location without the usual 10-minute start-age limit.
        let walking = [S(start: at(0), moving: false), S(start: to.addingTimeInterval(-25 * 60), moving: true)]
        let (done2, tail2) = WalkBackfill.split(walking, until: to)
        #expect(done2.isEmpty)
        #expect(tail2 == PendingWalk(start: to.addingTimeInterval(-25 * 60), end: nil))
        #expect(tail2?.interval(stoppedAt: to.addingTimeInterval(10 * 60))?.duration == TimeInterval(35 * 60), "之后停低：行到停低为止")

        // Do not record three minutes walking indoors at home.
        let short = [S(start: to.addingTimeInterval(-4 * 60), moving: true), S(start: to.addingTimeInterval(-60), moving: false)]
        #expect(WalkBackfill.split(short, until: to).tail?.interval(stoppedAt: to) == nil)
        // After a long stop, backfill directly instead of handing over the final segment.
        let old = [S(start: at(0), moving: true), S(start: at(15 * 60), moving: false)]
        let (done3, tail3) = WalkBackfill.split(old, until: to)
        #expect(done3.count == 1 && tail3 == nil)
    }

    @Test func 轮椅补记唔当唔知做郁紧() {
        func moving(walking: Bool = false, stationary: Bool = false, automotive: Bool = false, unknown: Bool = false, seated: Bool) -> Bool {
            WalkBackfill.isMoving(walking: walking, running: false, stationary: stationary, automotive: automotive, cycling: false, unknown: unknown, seated: seated)
        }
        #expect(moving(seated: true), "推轮椅：冇一样认到，但唔係停低")
        #expect(!moving(unknown: true, seated: true), "手机拎喺手 / 放袋：唔知唔算")
        #expect(!moving(stationary: true, seated: true))
        #expect(!moving(automotive: true, seated: true))
        #expect(moving(walking: true, seated: false))
        #expect(!moving(seated: false))
    }

    @Test func 步频持续下降先提示一次() {
        var w = CadenceWatch()
        var fired = 0
        for i in 0..<24 { if w.add(2.0, at: at(Double(i) * 30), walkStart: t0) { fired += 1 } }       // Twelve minutes at normal cadence.
        for i in 0..<3 { if w.add(1.2, at: at(720 + Double(i) * 30), walkStart: t0) { fired += 1 } }  // One minute slower is insufficient.
        #expect(fired == 0)
        for i in 3..<8 { if w.add(1.2, at: at(720 + Double(i) * 30), walkStart: t0) { fired += 1 } }
        #expect(fired == 1)
        let again = w.add(1.0, at: at(1200), walkStart: t0)
        #expect(!again, "提示过就唔再讲")
    }

    @Test func 请假日子() {
        #expect(LeaveRequest.parse("今日請假") == LeaveRequest(startOffset: 0, days: 1))
        #expect(LeaveRequest.parse("聽日請假") == LeaveRequest(startOffset: 1, days: 1))
        #expect(LeaveRequest.parse("請三日假") == LeaveRequest(startOffset: 0, days: 3))
        #expect(LeaveRequest.parse("聽日起請一個禮拜假") == LeaveRequest(startOffset: 1, days: 7))
        #expect(LeaveRequest.parse("後日請兩日假") == LeaveRequest(startOffset: 2, days: 2))
        #expect(LeaveRequest.parse("我想請十日假") == LeaveRequest(startOffset: 0, days: 10))
        #expect(LeaveRequest.parse("請 30 日假").days == LeaveRequest.maxDays)
        // 2026-10-07 is Wednesday; next week starts Monday 12 October, preserving explicit duration.
        #expect(LeaveRequest.parse("下星期去旅行請三日假", today: t0) == LeaveRequest(startOffset: 5, days: 3))
        #expect(LeaveRequest.parse("下個禮拜請假", today: t0) == LeaveRequest(startOffset: 5, days: 1))
        #expect(LeaveRequest.parse("請一個星期假", today: t0) == LeaveRequest(startOffset: 0, days: 7))
    }
}

struct WalkStoreTests {
    let today = SunShadeTests.hk("2026-10-07 10:00")
    func key(_ daysAgo: Int) -> String { LocalStore.dayKey(today.addingTimeInterval(-Double(daysAgo) * 86400)) }

    @Test func 请假保留但唔加连续天数() {
        var log: [String: DayLog] = [:]
        for d in 1...9 { log[key(d)] = DayLog(minutes: 30, walks: 1) }
        #expect(LocalStore.streak(log, leaves: [], today: today, includeDemo: true) == 9)
        #expect(LocalStore.streak(log, leaves: [key(0)], today: today, includeDemo: true) == 9, "今日请假：保留 9 日，唔会变 10")
        // Daily leave never increases a streak.
        let leaves = Set((0...5).map(key))
        #expect(LocalStore.streak([:], leaves: leaves, today: today, includeDemo: true) == 0)
        // Intervening leave days do not break the streak.
        log[key(3)] = nil
        #expect(LocalStore.streak(log, leaves: [key(3)], today: today, includeDemo: true) == 8)
    }

    @Test func 重置演示唔盖真实纪录() {
        var log: [String: DayLog] = [:]
        for d in 1...3 { log[key(d)] = DayLog(minutes: 40, walks: 1, landmarks: ["park-0"]) }
        // Reset Demo deletes and reseeds sample records.
        log = log.filter { !$0.value.demo }
        LocalStore.seedDemo(&log, today: today)
        for d in 1...3 { #expect(log[key(d)] == DayLog(minutes: 40, walks: 1, landmarks: ["park-0"])) }
        #expect(log[key(0)]?.demo == true)
        #expect(log[key(5)]?.demo == true)
        #expect(LocalStore.streak(log, leaves: [], today: today, includeDemo: false) == 3, "关演示：真实连续 3 日")
    }

    @Test func 演示散步唔改真实纪录() {
        var log = [key(0): DayLog(minutes: 30, walks: 1, landmarks: ["a"])]
        let recorded = LocalStore.record(&log, key: key(0), minutes: 20, landmarks: ["b"], simulated: true)
        #expect(!recorded)
        #expect(log[key(0)] == DayLog(minutes: 30, walks: 1, landmarks: ["a"]))
        // Real walking replaces sample data and preserves steps/stops.
        var demo = [key(0): DayLog(minutes: 24, walks: 1, demo: true)]
        LocalStore.record(&demo, key: key(0), minutes: 12, landmarks: ["a", "b"], stops: ["b"], steps: 1500, simulated: false)
        #expect(demo[key(0)] == DayLog(minutes: 12, walks: 1, landmarks: ["a", "b"], demo: false, stops: ["b"], steps: 1500))
    }

    @Test func 冇量步数嘅散步照估算() {
        var log: [String: DayLog] = [:]
        // Combine 1500 measured steps with another 12-minute unmeasured walk that day.
        LocalStore.record(&log, key: key(0), minutes: 15, landmarks: [], steps: 1500, simulated: false)
        #expect(log[key(0)]?.stepEstimate == 1500 && log[key(0)]?.stepsEstimated == false)
        LocalStore.record(&log, key: key(0), minutes: 12, landmarks: [], steps: nil, simulated: false)
        #expect(log[key(0)]?.stepEstimate == 1500 + 1200, "冇量嗰次唔会被量到嘅盖过")
        #expect(log[key(0)]?.stepsEstimated == true)
        // A fully unmeasured wheelchair day estimates all steps from minutes.
        LocalStore.record(&log, key: key(1), minutes: 30, landmarks: [], steps: nil, simulated: false)
        #expect(log[key(1)]?.stepEstimate == 3000 && log[key(1)]?.stepsEstimated == true)
        // Legacy records lack steps and unmeasured fields.
        #expect(DayLog(minutes: 20, walks: 1).stepEstimate == 2000)
    }

    @Test func 旧存档缺字段都读得返() throws {
        let json = """
        {"version":1,"mapKey":"0_0|1","neighbors":{"chan":{"since":800000000,"send":true,"receive":false}},
         "appointments":[{"id":"6F1C5C3A-1D7A-4F55-9A0B-0C1D2E3F4A5B","partnerID":"chan","date":800100000,"landmarkID":"park-0","reason":"有櫈","status":"accepted"}],
         "reports":[],"landmarkNames":{"park-0":"大樹底"},
         "walkLog":{"2026-10-06":{"minutes":30,"walks":1,"landmarks":["park-0"]}}}
        """
        let s = try JSONDecoder().decode(SavedState.self, from: Data(json.utf8))
        #expect(s.appointments.count == 1)
        #expect(s.appointments.first?.reminded == false && s.appointments.first?.fromPartner == false)
        #expect(s.walkLog["2026-10-06"]?.demo == false)
        #expect(s.walkLog["2026-10-06"]?.minutes == 30)
        #expect(s.leaveDays.isEmpty)
        #expect(s.landmarkNames["park-0"] == "大樹底")
    }

    @Test func 读唔到唔会冚咗原文件() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("walktests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        try Data("{ 壞咗".utf8).write(to: url)
        #expect(LocalStore.load(from: url) == SavedState())
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("state.bad-") }, "原文件留咗备份")

        // Skip one damaged meeting, recover the rest and retain a backup.
        let url2 = dir.appendingPathComponent("b").appendingPathExtension("json")
        let json = """
        {"appointments":[{"partnerID":"chan","date":800100000,"landmarkID":"a","reason":"","status":"唔識"},
                         {"partnerID":"wong","date":800100000,"landmarkID":"a","reason":"","status":"waiting"}],
         "leaveDays":["2026-10-07"]}
        """
        try Data(json.utf8).write(to: url2)
        let s = LocalStore.load(from: url2)
        #expect(s.appointments.map(\.partnerID) == ["wong"])
        #expect(s.leaveDays == ["2026-10-07"])
    }

    @Test func 约会通知() {
        let now = today
        let acc = Appointment(partnerID: "chan", date: now.addingTimeInterval(2 * 3600), landmarkID: "a", reason: "", status: .accepted)
        var reminded = acc; reminded.id = UUID(); reminded.reminded = true
        let waiting = Appointment(partnerID: "wong", date: now.addingTimeInterval(20 * 60), landmarkID: "a", reason: "", status: .waiting)
        let cancelled = Appointment(partnerID: "lee", date: now.addingTimeInterval(3 * 3600), landmarkID: "a", reason: "", status: .cancelled)
        let past = Appointment(partnerID: "ho", date: now.addingTimeInterval(-2 * 3600), landmarkID: "a", reason: "", status: .accepted)
        let items = NotificationPlan.items([acc, reminded, waiting, cancelled, past], now: now, partner: { $0 == "chan" ? "陳太" : "街坊" }, place: { _ in "涼亭" })
        #expect(items.filter { $0.id.hasSuffix("-remind") }.map(\.at) == [acc.date.addingTimeInterval(-1800)])
        #expect(items.first?.body == "30 分鐘後約咗陳太喺涼亭。")
        #expect(items.filter { $0.id.hasSuffix("-expire") }.count == 3, "未完成嘅：到期提醒")
        #expect(!items.contains { $0.id.contains(cancelled.id.uuidString) || $0.id.contains(past.id.uuidString) })
    }
}
