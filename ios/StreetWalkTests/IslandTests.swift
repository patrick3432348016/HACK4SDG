import CoreGraphics
import Foundation
import Testing
@testable import StreetWalk

// Island tests cover measured/fallback geometry, layouts, priority, meeting windows, rounded distance and labels.

struct IslandGeometryTests {
    @Test func 已知机型用实测位置() {
        // iPhone 17 Pro simulator measurement: x=138.33, y=14, width=125.33, height=36.67.
        let p = IslandGeometry.make(screen: CGSize(width: 402, height: 874), safeTop: 62)
        let i = try! #require(p.island)
        #expect(abs(i.minX - 138.33) < 0.1 && i.minY == 14 && abs(i.width - 125.33) < 0.1 && abs(i.height - 36.67) < 0.1)
        // iPhone 15 simulator measurement: x=134, y=11.33, width=125, height=36.67.
        let f = IslandGeometry.make(screen: CGSize(width: 393, height: 852), safeTop: 59)
        let j = try! #require(f.island)
        #expect(abs(j.minX - 134) < 0.1 && abs(j.minY - 11.33) < 0.1 && j.width == 125)
    }

    @Test func 新机型按安全区估() {
        // Unmeasured iPhone Air 420 x 912 uses centered fallback at safe-area top minus 48.
        let a = IslandGeometry.make(screen: CGSize(width: 420, height: 912), safeTop: 68)
        let i = try! #require(a.island)
        #expect(i.minY == 20)
        #expect(abs(i.midX - 210) < 0.01, "居中")
        #expect(i.height > 30 && i.height < 40)
    }

    @Test func 刘海同冇刘海冇岛() {
        #expect(!IslandGeometry.make(screen: CGSize(width: 390, height: 844), safeTop: 47).hasIsland, "iPhone 14 / 16e 刘海")
        #expect(!IslandGeometry.make(screen: CGSize(width: 375, height: 812), safeTop: 44).hasIsland, "iPhone X / 11 Pro")
        #expect(!IslandGeometry.make(screen: CGSize(width: 375, height: 667), safeTop: 20).hasIsland, "iPhone SE")
        #expect(!IslandGeometry.make(screen: CGSize(width: 1024, height: 1366), safeTop: 24, isPhone: false).hasIsland, "iPad")
        #expect(!IslandGeometry.make(screen: CGSize(width: 874, height: 402), safeTop: 0).hasIsland, "横屏")
    }

    @Test func 横幅由岛顶开始冇岛就喺状态栏下面() {
        let p = IslandGeometry.make(screen: CGSize(width: 402, height: 874), safeTop: 62)
        let b = p.bannerFrame(height: 160)
        let i = p.island!
        #expect(b.minY <= i.minY && b.minY >= i.minY - 6, "由岛顶附近开始")
        #expect(b.contains(i), "展开后包住个岛")
        #expect(p.bannerTextTop(height: 160) > i.maxY - b.minY, "正文喺岛下面")
        let n = IslandGeometry.make(screen: CGSize(width: 390, height: 844), safeTop: 47)
        #expect(n.bannerFrame(height: 160).minY > 47, "刘海机：状态栏下面")
    }

    @Test func 两侧胶囊包住个岛唔出界() {
        let p = IslandGeometry.make(screen: CGSize(width: 393, height: 852), safeTop: 59)
        let i = p.island!
        let c = try! #require(p.compactFrame(leading: 40, trailing: 120))
        #expect(c.minX == i.minX - 40 && c.minY == i.minY && c.height == i.height)
        #expect(c.maxX <= 393 - IslandGeometry.edge, "右边太长就收窄，唔出屏幕")
        let clock = try! #require(p.clockCenter(leading: 40))
        #expect(clock.x < c.minX - 20, "时间喺左边胶囊外面")
        #expect(IslandGeometry.make(screen: CGSize(width: 390, height: 844), safeTop: 47).compactFrame(leading: 40, trailing: 60) == nil)
    }
}

struct IslandStatusTests {
    @Test func 优先次序找人约会散步() {
        let walk = IslandStatus(kind: .walk, minutes: 12)
        let meet = IslandStatus(kind: .meet, minutes: 15)
        let find = IslandStatus(kind: .find, minutes: 2, meters: 35)
        #expect(IslandStatus.ordered([walk, meet, find]).map(\.kind) == [.find, .meet, .walk])
        #expect(IslandStatus.ordered([walk, meet]).first?.kind == .meet)
        #expect(IslandStatus.ordered([walk, IslandStatus(kind: .meet, minutes: 5), meet]).filter { $0.kind == .meet }.first?.minutes == 5, "同一类只留第一个")
        #expect(IslandStatus.ordered([]).isEmpty)
    }

    @Test func 约会三十分钟前开始过咗十分钟收() {
        #expect(IslandStatus.meetMinutes(left: 31 * 60) == nil)
        #expect(IslandStatus.meetMinutes(left: 30 * 60) == 30)
        #expect(IslandStatus.meetMinutes(left: 14 * 60 + 20) == 15, "向上取整")
        #expect(IslandStatus.meetMinutes(left: 0) == 0)
        #expect(IslandStatus.meetMinutes(left: -9 * 60) == 0, "过咗时间：夠鐘")
        #expect(IslandStatus.meetMinutes(left: -10 * 60) == nil)
    }

    @Test func 距离取整同字() {
        #expect(IslandStatus.roundMeters(33) == 35)
        #expect(IslandStatus.roundMeters(-3) == 0)
        #expect(IslandStatus.roundMeters(234) == 230)
        #expect(IslandStatus.roundMeters(1260) == 1300)
        #expect(IslandStatus.metersText(35) == "35 米")
        #expect(IslandStatus.metersText(1300) == "1.3 公里")
    }

    @Test func 岛两侧同锁屏嘅字() {
        let walk = IslandStatus(kind: .walk, minutes: 12, places: 3)
        #expect(walk.short == "12 分" && walk.title == "行緊 12 分鐘" && walk.detail == "經過咗 3 個地方")
        let meet = IslandStatus(kind: .meet, minutes: 15, name: "陳太", place: "涼亭")
        #expect(meet.short == "15 分鐘後" && meet.compact == "15 分")
        #expect(meet.title == "15 分鐘後約咗陳太" && meet.detail == "喺涼亭見")
        #expect(IslandStatus(kind: .meet, minutes: 0, name: "陳太").short == "夠鐘喇")
        let find = IslandStatus(kind: .find, minutes: 2, meters: 35, bearing: 40, name: "陳太", place: "涼亭")
        #expect(find.short == "35 米" && find.title == "搵緊陳太" && find.findLine == "喺涼亭 · 大約 2 分鐘到")
        var done = walk
        done.finished = true
        #expect(done.title == "散步完成" && done.detail.contains("12 分鐘"))
    }

    @Test func 实时活动内容可以存取() throws {
        let s = IslandStatus(kind: .meet, minutes: 15, name: "陳太", place: "涼亭", target: Date(timeIntervalSince1970: 1_800_000_000), demo: true)
        let back = try JSONDecoder().decode(IslandStatus.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}

@MainActor
struct IslandStoreTests {
    let lms = [Landmark(id: "shelter-1", name: "涼亭", kind: .shelter, pos: .zero, hasSeat: true)]
    var chan: Resident { var r = Resident(id: "chan", name: "陳太", floor: 8, colorIndex: 0, mobility: .walk, streakDays: 3, todayLine: ""); r.isNeighbor = true; return r }
    let me = Resident(id: "me", name: "你", floor: 12, colorIndex: 6, mobility: .walk, streakDays: 1, todayLine: "", isMe: true)

    func makeStore() -> AppStore {
        let s = AppStore()
        s.restoring = true
        s.clockTask?.cancel()
        s.announcer.voiceOverRunning = { false }
        s.demoHour = 15
        s.landmarks = lms
        s.residents = [chan, me]
        s.appointments = []
        s.reports = []
        return s
    }

    @Test func 散步同约会快到() {
        let s = makeStore()
        #expect(s.islandStatuses.isEmpty, "冇嘢进行紧")
        s.walk = WalkSession(start: Date(), minutes: 12, passed: ["shelter-1"])
        #expect(s.islandStatuses.map(\.kind) == [.walk])
        #expect(s.islandStatuses.first?.places == 1)
        // At 15:00, a 15:20 meeting with Mrs Chan takes priority.
        s.appointments = [Appointment(partnerID: "chan", date: AppStore.today(at: 15 + 20.0 / 60), landmarkID: "shelter-1", reason: "", status: .accepted)]
        let first = try! #require(s.islandStatuses.first)
        #expect(first.kind == .meet && first.minutes == 20 && first.name == "陳太" && first.place == "涼亭")
        #expect(first.target == nil, "演示拨咗时间：唔俾实时活动自己倒数")
        #expect(s.islandStatuses.count == 2)
    }

    @Test func 未应承同太远嘅约会唔显示() {
        let s = makeStore()
        s.appointments = [
            Appointment(partnerID: "chan", date: AppStore.today(at: 15.25), landmarkID: "shelter-1", reason: "", status: .waiting),
            Appointment(partnerID: "chan", date: AppStore.today(at: 16), landmarkID: "shelter-1", reason: "", status: .accepted),
        ]
        #expect(s.islandStatuses.isEmpty)
    }

    @Test func 出发搵人就由找人接手() {
        let s = makeStore()
        let a = Appointment(partnerID: "chan", date: AppStore.today(at: 15.25), landmarkID: "shelter-1", reason: "", status: .accepted)
        s.appointments = [a]
        s.findAppointment = a.id
        s.find = FindSession(partnerID: "chan", landmarkID: "shelter-1", spontaneous: false, stage: .going, distance: 233, etaMinutes: 4, bearing: 30)
        let st = s.islandStatuses
        #expect(st.map(\.kind) == [.find], "同一个约会唔会再出倒数")
        #expect(st.first?.meters == 230 && st.first?.bearing == 30)
        s.find?.stage = .asking
        #expect(s.islandStatuses.isEmpty, "问紧对方：未有距离")
    }

    @Test func 散步中找完人唔闪退() {
        // 10-18 device crash: endFind read walk while mutating it, triggering an exclusivity abort.
        let s = makeStore()
        s.walk = WalkSession(start: Date(), minutes: 12)
        s.find = FindSession(partnerID: "chan", landmarkID: "shelter-1", spontaneous: true, stage: .met)
        s.endFind()
        #expect(s.find == nil)
        #expect(s.walk != nil, "找完人继续散步")
    }

    @Test func 撳散步展开讲行咗几耐() {
        let s = makeStore()
        s.walk = WalkSession(start: Date(), minutes: 12)
        s.islandTapped()
        #expect(s.banner?.text.hasPrefix("行緊 12 分鐘") == true)
        #expect(s.banner?.action == BannerItem.Action.none)
        s.appointments = [Appointment(partnerID: "chan", date: AppStore.today(at: 15.25), landmarkID: "shelter-1", reason: "", status: .accepted)]
        s.islandTapped()
        #expect(s.banner?.actionTitle == "出發")
    }
}
