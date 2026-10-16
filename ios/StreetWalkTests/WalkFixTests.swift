import Foundation
import Testing
@testable import StreetWalk

// 10-17 真机测试修正（walk 组）：出门 50 米认到（C-1）、唔会一开一收、手动开始 / 结束（A-3）、
// 「今日三件事」自己打勾 / 取消（J-2）、约好咗写出嚟（J-3b）。

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
        _ = gate.decide(fromHome: 10, acc: 5, at: at(600), recording: false, moving: false)   // 返到屋企
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
        // 取消「出去行」：由 0 重新计，再行够 10 分钟自动打返
        s.firstDayToggle(.walk)
        #expect(!s.firstDayDone(.walk) && s.firstDay?.walkMinutes == 0)
        s.firstDayWalked(10)
        #expect(s.firstDayDone(.walk) && s.firstDay?.walkMark == nil)
        // 未做嘅自己打勾；三件齐就算做齐
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
