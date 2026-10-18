import Foundation
import Testing
@testable import StreetWalk

// Background tests: HomeLearner, TriggerRules, location records and coordinate conversion.

struct HomeLearnerTests {
    let cal = AppStore.hk
    let home = GeoPoint(lat: 22.5044, lon: 114.1563)          // Queen's Hill Estate.
    let shenzhen = GeoPoint(lat: 22.5431, lon: 114.0579)      // Roughly 11 km away.
    func t(_ s: String) -> Date { SunShadeTests.hk(s) }

    /// Simulate a visit overnight at p from day 22:30 to next day 06:30.
    func night(_ day: String, at p: GeoPoint) -> NightSample {
        let s = t("\(day) 22:30")
        return NightSample(lat: p.lat, lon: p.lon, start: s, end: s.addingTimeInterval(8 * 3600), source: .visit)
    }

    func learner(_ samples: [NightSample], now: Date) -> HomeLearner {
        var l = HomeLearner()
        for s in samples { l.add(s, now: now, calendar: cal) }
        return l
    }

    func offset(_ p: GeoPoint, east: Double, north: Double = 0) -> GeoPoint {
        LocalProjection(origin: p).toGeo(Vec2(x: east, y: north))
    }

    @Test func 夜晚归属同一晚() {
        #expect(HomeLearner.nightKey(t("2026-10-10 23:00"), calendar: cal) == "2026-10-10")
        #expect(HomeLearner.nightKey(t("2026-10-11 03:00"), calendar: cal) == "2026-10-10")
        #expect(HomeLearner.isNight(t("2026-10-10 22:00"), calendar: cal))
        #expect(HomeLearner.isNight(t("2026-10-11 05:59"), calendar: cal))
        #expect(!HomeLearner.isNight(t("2026-10-11 06:00"), calendar: cal))
        #expect(!HomeLearner.isNight(t("2026-10-10 12:00"), calendar: cal))
        #expect(HomeLearner.previousKey("2026-10-01", calendar: cal) == "2026-09-30")
    }

    @Test func 到访按晚计停留() {
        let now = t("2026-10-12 12:00")
        // A 20:00–08:00 visit contributes only the 22:00–06:00 window: 8 hours.
        let a = NightSample(lat: home.lat, lon: home.lon, start: t("2026-10-08 20:00"), end: t("2026-10-09 08:00"), source: .visit)
        #expect(HomeLearner.pieces(a, now: now, calendar: cal) == [.init(night: "2026-10-08", seconds: 8 * 3600)])
        // Spans two nights.
        let b = NightSample(lat: home.lat, lon: home.lon, start: t("2026-10-08 21:00"), end: t("2026-10-10 07:00"), source: .visit)
        #expect(HomeLearner.pieces(b, now: now, calendar: cal).map(\.night) == ["2026-10-08", "2026-10-09"])
        // A night point contributes 15 minutes; daytime points contribute none.
        let p = NightSample(lat: home.lat, lon: home.lon, start: t("2026-10-09 01:00"), end: t("2026-10-09 01:00"), source: .significant)
        #expect(HomeLearner.pieces(p, now: now, calendar: cal) == [.init(night: "2026-10-08", seconds: 15 * 60)])
        let d = NightSample(lat: home.lat, lon: home.lon, start: t("2026-10-09 13:00"), end: t("2026-10-09 13:00"), source: .significant)
        #expect(HomeLearner.pieces(d, now: now, calendar: cal).isEmpty)
    }

    @Test func 日头嘅到访唔记_坐标四舍五入() {
        let now = t("2026-10-12 20:00")
        var l = HomeLearner()
        l.add(NightSample(lat: 22.50441234, lon: 114.15639876, start: t("2026-10-12 09:00"), end: t("2026-10-12 17:00"), source: .visit), now: now, calendar: cal)
        #expect(l.samples.isEmpty, "日头去过边唔记")
        l.add(NightSample(lat: 22.50441234, lon: 114.15639876, start: t("2026-10-11 23:00"), end: t("2026-10-12 06:00"), source: .visit), now: now, calendar: cal)
        #expect(l.samples.count == 1)
        #expect(l.samples[0].lat == 22.5044 && l.samples[0].lon == 114.1564, "只留小数点后 4 位（约 11 米）")
    }

    @Test func 同一个到访离开时更新() {
        let now = t("2026-10-12 08:00")
        var l = HomeLearner()
        let start = t("2026-10-11 19:00")
        l.add(NightSample(lat: home.lat, lon: home.lon, start: start, end: nil, source: .visit), now: start, calendar: cal)
        #expect(l.samples.count == 1 && l.samples[0].end == nil)
        l.add(NightSample(lat: home.lat, lon: home.lon, start: start, end: t("2026-10-12 07:30"), source: .visit), now: now, calendar: cal)
        #expect(l.samples.count == 1)
        #expect(l.samples[0].end == t("2026-10-12 07:30"))
    }

    @Test func 屋企范围未离开都计_离开就收() {
        var l = HomeLearner()
        l.add(NightSample(lat: home.lat, lon: home.lon, start: t("2026-10-11 19:00"), end: nil, source: .region), now: t("2026-10-11 19:00"), calendar: cal)
        // At 02:00, count four elapsed night hours.
        #expect(HomeLearner.pieces(l.samples[0], now: t("2026-10-12 02:00"), calendar: cal).first?.seconds == Double(4 * 3600))
        #expect(l.hasOpen(.region))
        let closed = l.close(.region, at: t("2026-10-12 07:00"))
        #expect(closed)
        #expect(!l.hasOpen(.region))
        #expect(HomeLearner.pieces(l.samples[0], now: t("2026-10-12 12:00"), calendar: cal).first?.seconds == Double(8 * 3600))
    }

    @Test func 十四日前嘅清走() {
        var l = learner([night("2026-09-20", at: home)], now: t("2026-09-22 12:00"))
        #expect(l.samples.count == 1)
        l.prune(now: t("2026-10-12 12:00"))
        #expect(l.samples.isEmpty)
    }

    @Test func 八十米内当同一个地方() {
        let now = t("2026-10-12 12:00")
        let near = learner([night("2026-10-10", at: home), night("2026-10-11", at: offset(home, east: 50))], now: now)
        #expect(near.clusters(now: now, calendar: cal).count == 1)
        let far = learner([night("2026-10-10", at: home), night("2026-10-11", at: offset(home, east: 200))], now: now)
        #expect(far.clusters(now: now, calendar: cal).count == 2)
    }

    @Test func 一晚未够() {
        let now = t("2026-10-11 12:00")
        let l = learner([night("2026-10-10", at: home)], now: now)
        #expect(l.verdict(home: home, picked: true, now: now, calendar: cal) == .learning(nights: 1))
        #expect(HomeLearner().verdict(home: home, picked: true, now: now, calendar: cal) == .learning(nights: 0))
    }

    @Test func 两晚喺揀咗嘅屋企就确认() {
        let now = t("2026-10-12 12:00")
        let l = learner([night("2026-10-10", at: offset(home, east: 30)), night("2026-10-11", at: offset(home, east: 40))], now: now)
        guard case .confirmed(let n, let d) = l.verdict(home: home, picked: true, now: now, calendar: cal) else {
            Issue.record("应该确认"); return
        }
        #expect(n == 2)
        #expect(d < 60)
    }

    @Test func 连续两晚喺三百米外就问係咪搬咗屋() {
        let now = t("2026-10-12 12:00")
        let l = learner([night("2026-10-10", at: shenzhen), night("2026-10-11", at: shenzhen)], now: now)
        guard case .moved(let p, let n, let d) = l.verdict(home: home, picked: true, now: now, calendar: cal) else {
            Issue.record("应该问搬屋"); return
        }
        #expect(n == 2)
        #expect(d > 10_000)
        #expect(HomeLearner.distance(p, shenzhen) < 20)
    }

    @Test func 住咗两个礼拜再搬都认到() {
        let now = t("2026-10-14 12:00")
        var s: [NightSample] = []
        for d in 1...10 { s.append(night(String(format: "2026-10-%02d", d), at: home)) }
        s.append(night("2026-10-12", at: shenzhen))
        s.append(night("2026-10-13", at: shenzhen))
        let l = learner(s, now: now)
        guard case .moved(_, let n, _) = l.verdict(home: home, picked: true, now: now, calendar: cal) else {
            Issue.record("最近连续两晚喺新地方，应该问"); return
        }
        #expect(n == 2)
    }

    @Test func 唔连续嘅两晚唔问() {
        let now = t("2026-10-12 12:00")
        // Away on the 9th and 11th but home on the 10th is not two consecutive nights.
        let l = learner([night("2026-10-09", at: shenzhen), night("2026-10-10", at: home), night("2026-10-11", at: shenzhen)], now: now)
        let v = l.verdict(home: home, picked: true, now: now, calendar: cal)
        if case .moved = v { Issue.record("唔连续唔应该问：\(v)") }
        // Do not prompt after the latest night was at home.
        let back = learner([night("2026-10-09", at: shenzhen), night("2026-10-10", at: shenzhen), night("2026-10-11", at: home)], now: now)
        if case .moved = back.verdict(home: home, picked: true, now: now, calendar: cal) { Issue.record("已经返咗屋企") }
    }

    @Test func 一百五到三百米之间唔问() {
        let now = t("2026-10-12 12:00")
        let p = offset(home, east: 220)
        let l = learner([night("2026-10-10", at: p), night("2026-10-11", at: p)], now: now)
        guard case .unsure(_, let d) = l.verdict(home: home, picked: true, now: now, calendar: cal) else {
            Issue.record("150–300 m 应该係未确认"); return
        }
        #expect(abs(d - 220) < 5)
    }

    @Test func 未揀屋企就建议() {
        let now = t("2026-10-12 12:00")
        let l = learner([night("2026-10-10", at: shenzhen), night("2026-10-11", at: shenzhen)], now: now)
        guard case .suggest(_, 2, nil) = l.verdict(home: nil, picked: false, now: now, calendar: cal) else {
            Issue.record("冇屋企应该建议"); return
        }
        // With a sample-selected home, picked=false confirms nearby evidence or suggests a distant location.
        guard case .suggest(_, 2, let d?) = l.verdict(home: home, picked: false, now: now, calendar: cal), d > 10_000 else {
            Issue.record("示例屋邨应该建议"); return
        }
        let atHome = learner([night("2026-10-10", at: home), night("2026-10-11", at: home)], now: now)
        guard case .confirmed = atHome.verdict(home: home, picked: false, now: now, calendar: cal) else {
            Issue.record("真係住喺示例屋邨就确认"); return
        }
    }

    @Test func 每晚主要喺边() {
        let now = t("2026-10-12 12:00")
        let l = learner([night("2026-10-10", at: home), night("2026-10-11", at: shenzhen)], now: now)
        let n = l.nights(now: now, calendar: cal)
        #expect(n.map(\.night) == ["2026-10-11", "2026-10-10"], "最近嘅排先")
        #expect(HomeLearner.distance(n[0].center, shenzhen) < 20)
        #expect(abs(n[1].hours - 7.5) < 0.01, "22:30–06:00")
    }
}

struct TriggerRuleTests {
    let t0 = SunShadeTests.hk("2026-10-10 09:00")

    @Test func 离开屋企就等开始行路() {
        #expect(TriggerRules.response(to: .leftHome, recording: false, enabled: true) == .watch)
        #expect(TriggerRules.response(to: .leftHome, recording: true, enabled: true) == .none)
        #expect(TriggerRules.response(to: .leftHome, recording: false, enabled: false) == .none, "演示模式 / 未完成首次使用")
        #expect(TriggerRules.response(to: .visitDeparture(fromHome: 60), recording: false, enabled: true) == .watch)
        #expect(TriggerRules.response(to: .visitDeparture(fromHome: 900), recording: false, enabled: true) == .none, "离开嘅唔係屋企")
        #expect(TriggerRules.response(to: .visitDeparture(fromHome: nil), recording: false, enabled: true) == .none)
    }

    @Test func 返到屋企就收尾或者补记() {
        #expect(TriggerRules.response(to: .arrivedHome, recording: true, enabled: true) == .finish)
        #expect(TriggerRules.response(to: .arrivedHome, recording: false, enabled: true) == .catchUp)
        #expect(TriggerRules.response(to: .visitArrival(fromHome: 80), recording: true, enabled: true) == .finish)
        #expect(TriggerRules.response(to: .visitArrival(fromHome: 80), recording: false, enabled: true) == .catchUp)
        #expect(TriggerRules.response(to: .visitArrival(fromHome: 2000), recording: true, enabled: true) == .none, "到咗第二度唔係返屋企")
        #expect(TriggerRules.response(to: .arrivedHome, recording: true, enabled: false) == .none)
    }

    @Test func 大范围移动只喺附近先等() {
        #expect(TriggerRules.response(to: .significantChange(fromHome: 800), recording: false, enabled: true) == .watch)
        #expect(TriggerRules.response(to: .significantChange(fromHome: 5000), recording: false, enabled: true) == .none, "多数係坐车")
        #expect(TriggerRules.response(to: .significantChange(fromHome: 100), recording: false, enabled: true) == .none, "仲喺屋企")
        #expect(TriggerRules.response(to: .significantChange(fromHome: nil), recording: false, enabled: true) == .none)
        #expect(TriggerRules.response(to: .significantChange(fromHome: 800), recording: true, enabled: true) == .none)
    }

    @Test func 等开始行路几耐() {
        func keep(_ s: Double, moving: Bool, recording: Bool = false) -> Bool {
            TriggerRules.keepWatching(since: t0, now: t0.addingTimeInterval(s), recording: recording, moving: moving)
        }
        #expect(keep(120, moving: false))
        #expect(!keep(6 * 60, moving: false), "5 分钟冇行路就熄")
        #expect(keep(6 * 60, moving: true), "行紧路但未开始：等多阵")
        #expect(!keep(16 * 60, moving: true), "最多 15 分钟")
        #expect(!keep(30, moving: true, recording: true), "开始咗就交俾散步")
    }

    @Test func 由屋企行出去放宽出门距离() {
        #expect(TriggerRules.maxStart(leftHomeAt: nil, now: t0) == LiveWalkGate.maxStart)
        #expect(TriggerRules.maxStart(leftHomeAt: t0, now: t0.addingTimeInterval(600)) == TriggerRules.relaxedStart)
        #expect(TriggerRules.maxStart(leftHomeAt: t0, now: t0.addingTimeInterval(4 * 3600)) == LiveWalkGate.maxStart, "3 个钟之后照旧")
        // A delayed departure wake at 600 m still starts detection.
        var gate = LiveWalkGate()
        _ = gate.decide(fromHome: 600, acc: 10, at: t0, recording: false, moving: true)
        #expect(gate.decide(fromHome: 610, acc: 10, at: t0.addingTimeInterval(10), recording: false, moving: true) == .none)
        var relaxed = LiveWalkGate()
        _ = relaxed.decide(fromHome: 600, acc: 10, at: t0, recording: false, moving: true, maxStart: TriggerRules.relaxedStart)
        #expect(relaxed.decide(fromHome: 610, acc: 10, at: t0.addingTimeInterval(10), recording: false, moving: true,
                               maxStart: TriggerRules.relaxedStart) == .start)
    }

    @Test func 定位纪录只留五十件() {
        var log = LocationLog()
        for i in 0..<60 { log.add(LocationEvent(at: t0.addingTimeInterval(Double(i)), kind: .note, detail: "\(i)", background: false)) }
        #expect(log.events.count == LocationLog.cap)
        #expect(log.events.first?.detail == "10")
        #expect(log.events.last?.detail == "59")
        #expect(LocationEvent(at: t0, kind: .leftHome, detail: "", background: true).isWake)
        #expect(!LocationEvent(at: t0, kind: .walkEnd, detail: "", background: true).isWake)
    }

    @Test func 场景坐标换返经纬度() {
        let m = MapModel(tile: TileKey(ix: 0, iy: 0), center: GeoPoint(lat: 22.5044, lon: 114.1563), size: 200, buildings: [], roads: [],
                         areas: [], pois: [], trees: [], fetchedAt: Date(), source: "test", rotation: 0.37)
        let g = GeoPoint(lat: 22.5051, lon: 114.1572)
        let back = m.geoPoint(m.scenePoint(g))
        #expect(HomeLearner.distance(back, g) < 0.01)
        #expect(AppStore.parseGeo("22.5431, 114.0579") == GeoPoint(lat: 22.5431, lon: 114.0579))
        #expect(AppStore.parseGeo("abc") == nil)
    }
}
