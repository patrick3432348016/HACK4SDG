import Foundation
import Testing
@testable import StreetWalk

// 10-17 walk fixes: departure detection around 50 m, no immediate start/end, manual controls,
// manual first-day checks (J-2) and meeting details (J-3b).

struct WalkGateFixTests {
    let t0 = SunShadeTests.hk("2026-10-17 10:00")
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test func 定位好时离家五十几米就开始() {
        var gate = LiveWalkGate()
        _ = gate.decide(fromHome: 56, acc: 5, at: at(0), recording: false, moving: true)
        #expect(gate.decide(fromHome: 58, acc: 5, at: at(6), recording: false, moving: true) == .start)
    }

    @Test func 楼密精度四十米行到一百米都开始() {
        var gate = LiveWalkGate()
        _ = gate.decide(fromHome: 100, acc: 40, at: at(0), recording: false, moving: true)
        #expect(gate.decide(fromHome: 104, acc: 40, at: at(6), recording: false, moving: true) == .start, "以前要精度 ≤30 m，楼密嘅地方一直唔开始")
        var bad = LiveWalkGate()
        _ = bad.decide(fromHome: 150, acc: 60, at: at(0), recording: false, moving: true)
        #expect(bad.decide(fromHome: 150, acc: 60, at: at(6), recording: false, moving: true) == .none, "精度太差（60 m）唔开始")
    }

    @Test func 精度三十八米只计时间唔画路() {
        var gate = LiveWalkGate()
        #expect(gate.decide(fromHome: 120, acc: 38, at: at(0), recording: true, moving: true) == .step)
        #expect(gate.decide(fromHome: 120, acc: 45, at: at(5), recording: true, moving: true) == .minutesOnly)
    }

    @Test func 收尾之后唔即刻再开始() {
        var gate = LiveWalkGate()
        gate.quiet(until: at(LiveWalkGate.restartGap))
        _ = gate.decide(fromHome: 80, acc: 5, at: at(10), recording: false, moving: true)
        #expect(gate.decide(fromHome: 82, acc: 5, at: at(20), recording: false, moving: true) == .none)
        _ = gate.decide(fromHome: 80, acc: 5, at: at(100), recording: false, moving: true)
        #expect(gate.decide(fromHome: 82, acc: 5, at: at(110), recording: false, moving: true) == .start, "90 秒后照常")
    }

    @Test func 自己结束散步之后返到屋企先再自动开始() {
        var gate = LiveWalkGate()
        gate.quiet(until: at(LiveWalkGate.userEndQuiet), untilHome: true)
        _ = gate.decide(fromHome: 300, acc: 5, at: at(200), recording: false, moving: true)
        #expect(gate.decide(fromHome: 302, acc: 5, at: at(210), recording: false, moving: true) == .none, "仲喺外面：唔会即刻又「检测到你出门了」")
        _ = gate.decide(fromHome: 10, acc: 5, at: at(600), recording: false, moving: false)   // Return home.
        _ = gate.decide(fromHome: 80, acc: 5, at: at(900), recording: false, moving: true)
        #expect(gate.decide(fromHome: 82, acc: 5, at: at(910), recording: false, moving: true) == .start)
    }

    @Test func 手动开始喺屋企唔会即刻收尾() {
        var gate = LiveWalkGate()
        gate.awaitingLeave = true
        #expect(gate.decide(fromHome: 10, acc: 10, at: at(0), recording: true, moving: true) == .step, "未出门：唔收尾")
        #expect(gate.decide(fromHome: 90, acc: 10, at: at(60), recording: true, moving: true) == .step)
        #expect(gate.awaitingLeave == false)
        #expect(gate.decide(fromHome: 20, acc: 10, at: at(600), recording: true, moving: true) == .finish, "行出去再返屋企：收尾")
    }
}

@MainActor
struct FirstDayFixTests {
    func makeStore() -> AppStore {
        let s = AppStore()
        s.restoring = true
        s.clockTask?.cancel()
        s.announcer.voiceOverRunning = { false }
        s.demoHour = 10
        s.appointments = []
        return s
    }

    @Test func 打咗勾可以取消再打返() {
        let s = makeStore()
        s.firstDay = FirstDayProgress(started: Date(), walkMinutes: 12, bumped: true)
        #expect(s.firstDayDone(.walk) && s.firstDayDone(.bump))
        s.firstDayToggle(.bump)
        #expect(!s.firstDayDone(.bump) && s.firstDay?.bumpMark == false)
        s.firstDayCheck()
        #expect(!s.firstDayDone(.bump), "自动判断唔会盖过用户自己取消")
        s.firstDayToggle(.bump)
        #expect(s.firstDayDone(.bump))
        // Unchecking the walk task resets progress; another 10 minutes checks it again.
        s.firstDayToggle(.walk)
        #expect(!s.firstDayDone(.walk) && s.firstDay?.walkMinutes == 0)
        s.firstDayWalked(10)
        #expect(s.firstDayDone(.walk) && s.firstDay?.walkMark == nil)
        // Manual checks count toward completing all three tasks.
        s.firstDayToggle(.invite)
        #expect(s.firstDayDone(.invite) && s.firstDay?.finishedAt != nil)
        s.firstDayToggle(.invite)
        #expect(s.firstDay?.finishedAt == nil, "取消一件：唔再算做齐")
    }

    @Test func 自己打勾嘅状态存得返旧存档读得返() throws {
        var f = FirstDayProgress(started: Date(timeIntervalSince1970: 1_790_000_000), walkMinutes: 3)
        f.walkMark = true
        f.bumpMark = false
        let back = try JSONDecoder().decode(FirstDayProgress.self, from: JSONEncoder().encode(f))
        #expect(back.isDone(.walk) && !back.isDone(.bump) && back.inviteMark == nil)
        let old = try JSONDecoder().decode(FirstDayProgress.self, from: Data(#"{"walkMinutes":4,"bumped":true}"#.utf8))
        #expect(old.walkMark == nil && old.isDone(.bump) && !old.isDone(.walk))
    }
}

// 10-18 walk fixes: active movement must not end, sitting 10 minutes must end, and minutes exclude idle time.
// Also guard home-door GPS jumps, avoid invitations on leave days and omit floor numbers from daily greetings.
struct WalkClockTests {
    let t0 = SunShadeTests.hk("2026-10-18 10:00")
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test func 一路行分钟跟住钟走() {
        var c = WalkMotionClock(start: at(0), now: at(0))
        // Walk 20 minutes, moving roughly 40 m every 30 seconds with increasing pedometer counts.
        for i in 1...40 {
            c.fix(Vec2(x: Double(i) * 45, y: 0), acc: 10, at: at(Double(i) * 30))
            c.steps(i * 50, at: at(Double(i) * 30))
        }
        #expect(!c.shouldFinish(at(1200), nearHome: false), "行紧唔会收尾")
        #expect(WalkMotionClock.minutes(start: c.start, end: c.endTime(at(1200)), steps: 2000, now: at(1200)) == 20)
    }

    @Test func 坐低定位漂移唔当行路() {
        var c = WalkMotionClock(start: at(0), now: at(0))
        c.fix(Vec2(x: 0, y: 0), acc: 10, at: at(0))
        c.fix(Vec2(x: 500, y: 0), acc: 10, at: at(8 * 60))   // Eight minutes walked.
        // Sit for 12 minutes with GPS jitter inside 30 m and larger low-accuracy outliers.
        for i in 1...72 {
            let j = Double(i % 5) * 7
            c.fix(Vec2(x: 500 + j, y: j - 10), acc: 15, at: at(8 * 60 + Double(i) * 10))
            if i % 6 == 0 { c.fix(Vec2(x: 580, y: 40), acc: 65, at: at(8 * 60 + Double(i) * 10)) }
        }
        let now = at(20 * 60)
        #expect(c.lastMoveAt == at(8 * 60))
        #expect(c.shouldFinish(now, nearHome: false), "喺外面坐咗 10 分钟以上：收尾")
        #expect(c.endTime(now) == at(8 * 60), "坐低嘅时间唔计")
        #expect(WalkMotionClock.minutes(start: c.start, end: c.endTime(now), steps: nil, now: now) == 8)
    }

    @Test func 屋企附近停五分钟收尾外面要十分钟() {
        let c = WalkMotionClock(start: at(0), now: at(60))
        #expect(!c.shouldFinish(at(60 + 4 * 60), nearHome: true))
        #expect(c.shouldFinish(at(60 + 5 * 60), nearHome: true))
        #expect(!c.shouldFinish(at(60 + 9 * 60), nearHome: false))
        #expect(c.shouldFinish(at(60 + 10 * 60), nearHome: false))
    }

    @Test func 啱啱开始唔会被之前嘅静止计时收咗() {
        // A stale pre-walk idle timer and delayed motion report must not end a GPS-speed-triggered start.
        let c = WalkMotionClock(start: at(-120), now: at(0))
        #expect(c.lastMoveAt == at(0))
        #expect(!c.shouldFinish(at(4 * 60), nearHome: true), "开始 4 分钟内乜都冇收到都唔收尾")
    }

    @Test func 计步器做分钟下限() {
        // With poor GPS but 1500 steps, count at least 12 minutes, capped by elapsed wall time.
        #expect(WalkMotionClock.minutes(start: at(0), end: at(180), steps: 1500, now: at(15 * 60)) == 12)
        #expect(WalkMotionClock.minutes(start: at(0), end: at(180), steps: 9000, now: at(15 * 60)) == 15)
        // A few shake-generated steps while stationary do not imply movement.
        var c = WalkMotionClock(start: at(0), now: at(0))
        c.steps(5, at: at(300))
        #expect(c.lastMoveAt == at(0))
        c.steps(20, at: at(310))
        #expect(c.lastMoveAt == at(310))
    }

    @Test func 冇任何讯号就冇signal() {
        var c = WalkMotionClock(start: at(0), now: at(0))
        #expect(!c.signal, "手动开始冇权限：按钟计、唔自动收尾")
        c.fix(Vec2(x: 0, y: 0), acc: 80, at: at(10))
        #expect(c.signal)
    }

    @Test func 门口定位跳唔会一开就收() {
        var gate = LiveWalkGate()
        // A just-started walk at 88 m with 50 m accuracy must not end under the relaxed home check.
        #expect(gate.decide(fromHome: 100, acc: 30, at: at(0), recording: true, moving: true) == .step)
        #expect(gate.decide(fromHome: 88, acc: 50, at: at(20), recording: true, moving: true) == .minutesOnly)
        // Actually entering 40 m still ends the walk.
        #expect(gate.decide(fromHome: 30, acc: 10, at: at(40), recording: true, moving: true) == .finish)
    }
}

@MainActor
struct LeaveWordingTests {
    func makeStore() -> AppStore {
        let s = AppStore()
        s.restoring = true
        s.clockTask?.cancel()
        s.announcer.voiceOverRunning = { false }
        s.demoHour = 10
        s.appointments = []
        return s
    }

    @Test func 明天不出门三件事改约休息完() {
        let s = makeStore()
        s.leaveDays = []
        #expect(s.nextWalkDayOffset == 1)
        let tomorrowTitle = s.firstDayInviteTitle
        s.leaveDays = Set(s.leaveKeys(LeaveRequest(startOffset: 0, days: 7)))
        #expect(s.nextWalkDayOffset == 7, "今日起 7 日唔出門：第 7 日先约")
        #expect(s.firstDayInviteTitle != tomorrowTitle)
        #expect(s.firstDayInviteTitle.contains(s.dateLabel(s.now.addingTimeInterval(7 * 86400))))
    }

    @Test func 今日一句唔用楼层() {
        let ai = TemplateAI()
        var me = Resident(id: "me", name: "你", floor: 7, colorIndex: 6, mobility: .walk, streakDays: 1, todayLine: "", isMe: true)
        me.onLeave = true
        #expect(!ai.dailyLine(for: me, passed: []).contains("7"), "唔再讲「7 樓」")
        me.nickname = "行路友"
        #expect(ai.dailyLine(for: me, passed: []).contains("行路友"))
        var chan = Resident(id: "chan", name: "陳太", floor: 8, colorIndex: 0, mobility: .walk, streakDays: 3, todayLine: "")
        chan.onLeave = false
        #expect(ai.dailyLine(for: chan, passed: []).contains("陳太") && !ai.dailyLine(for: chan, passed: []).contains("8"))
    }
}
