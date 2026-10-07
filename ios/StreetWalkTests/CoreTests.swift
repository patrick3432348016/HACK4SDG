import Foundation
import Testing
@testable import StreetWalk

// 核心逻辑单元测试：地图解析与风格化、地标、太阳与遮荫、寻路、语音意图、连续天数、持久化编码、示範数据。
// 运行：cd ios && xcodebuild test -project StreetWalk.xcodeproj -scheme StreetWalk -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'

@MainActor
struct MapTests {
    let full = MapService.fallback()

    @Test func 解析皇后山邨() {
        #expect(full.placeName == "皇后山邨")
        #expect(full.buildings.count > 20)
        #expect(full.roads.count > 50)
        #expect(full.buildings.allSatisfy { $0.outline.allSatisfy { abs($0.x) <= full.half + 0.01 && abs($0.y) <= full.half + 0.01 } })
    }

    @Test func 风格化底座做减法() {
        let home = full.buildings.filter { $0.kind == .residential }.min { $0.centroid.length < $1.centroid.length }!
        let m = full.simplified(around: home.centroid, home: home.id)
        #expect(m.size == MapModel.dioramaSize)
        #expect(m.buildings.count <= 6)
        #expect(m.buildings.contains { $0.id == home.id }, "我屋企一定保留")
        #expect(m.buildings.allSatisfy { $0.outline.count == 4 }, "楼都是规整长方体")
        #expect(m.areas.count <= 3)
    }

    @Test func 地标三到四个且分得开() {
        let picked = LandmarkDeriver.pick(LandmarkDeriver.candidates(in: full))
        #expect((3...4).contains(picked.count))
        for i in picked.indices { for j in picked.indices where j > i { #expect(picked[i].pos.distance(to: picked[j].pos) >= 30) } }
    }

    @Test func 寻路唔穿楼() {
        let home = full.buildings.filter { $0.kind == .residential }.min { $0.centroid.length < $1.centroid.length }!
        let m = full.simplified(around: home.centroid, home: home.id)
        let grid = PathGrid(map: m)
        let a = grid.nearestWalkable(Vec2(x: -80, y: -80)), b = grid.nearestWalkable(Vec2(x: 80, y: 80))
        let path = grid.path(from: a, to: b)
        #expect(path.count >= 2)
        #expect(grid.length(of: path) >= a.distance(to: b) - 1)
        #expect(path.filter { m.isInsideBuilding($0) }.count <= 1)
    }
}

struct SunShadeTests {
    static func hk(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = SolarPosition.hongKong
        return f.date(from: s)!
    }

    @Test func 太阳位置() {
        let jun = SolarPosition.at(Self.hk("2026-06-21 12:25"), lat: 22.5044, lon: 114.1563)
        #expect(abs(jun.elevation - 89) < 1.5)
        let dec = SolarPosition.at(Self.hk("2026-12-21 12:21"), lat: 22.5044, lon: 114.1563)
        #expect(abs(dec.elevation - 44) < 1.5)
        #expect(abs(dec.azimuth - 180) < 3)
    }

    @Test func 楼影遮荫() {
        let box = Building(id: 1, name: nil, outline: [Vec2(x: -10, y: -20), Vec2(x: 10, y: -20), Vec2(x: 10, y: -10), Vec2(x: -10, y: -10)],
                           minHeight: 0, height: 30, levels: 10, kind: .other)
        let m = MapModel(tile: TileKey(ix: 0, iy: 0), center: GeoPoint(lat: 22.5044, lon: 114.1563), size: 200, buildings: [box],
                         roads: [], areas: [], pois: [], trees: [], fetchedAt: Date(), source: "t")
        let calc = ShadeCalculator(map: m)
        let dec = SolarPosition.at(Self.hk("2026-12-21 12:21"), lat: 22.5044, lon: 114.1563)
        #expect(calc.isShaded(Vec2(x: 0, y: 0), sun: dec), "冬至正午，南面的楼挡住太阳")
        #expect(!calc.isShaded(Vec2(x: 0, y: -40), sun: dec), "楼的南边晒到")
        #expect(calc.shade(at: .zero, sun: SolarPosition(elevation: -5, azimuth: 270)) == 1, "日落后当全阴")
    }
}

struct VoiceTests {
    let ai = TemplateAI()
    let chan = { var r = Resident(id: "chan", name: "陳太", floor: 8, colorIndex: 0, mobility: .walk, streakDays: 3, todayLine: ""); r.isNeighbor = true; return r }()
    let me = Resident(id: "me", name: "你", floor: 12, colorIndex: 6, mobility: .walk, streakDays: 1, todayLine: "", isMe: true)
    let lms = [Landmark(id: "shelter-1", name: "涼亭", kind: .shelter, pos: .zero, hasSeat: true),
               Landmark(id: "park-0", name: "公園櫈仔", kind: .park, pos: Vec2(x: 40, y: 0), hasSeat: true)]
    func ctx(finding: Bool = false) -> AIContext { AIContext(residents: [chan, me], landmarks: lms, now: Date(), walking: false, finding: finding) }

    @Test func 约人带日子同钟数() {
        #expect(ai.parseVoice("約陳太聽日下晝三點一齊行", context: ctx()) == .invite(partnerID: "chan", day: 1, hour: 15))
        #expect(ai.parseVoice("約8樓後日朝早一齊行", context: ctx()) == .invite(partnerID: "chan", day: 2, hour: 8))
    }

    @Test func 讲钟数() {
        #expect(ai.parseHour("下晝三點") == 15)
        #expect(ai.parseHour("朝早8點") == 8)
        #expect(ai.parseHour("十一點") == 11)
        #expect(ai.parseHour("夜晚七點") == 19)
    }

    @Test func 请假改名反映() {
        #expect(ai.parseVoice("今日請假", context: ctx()) == .leave)
        #expect(ai.parseVoice("涼亭改名做大樹底", context: ctx()) == .rename(landmarkID: "shelter-1", newName: "大樹底"))
        #expect(ai.parseVoice("呢度好曬", context: ctx()) == .report(.sunny))
        #expect(ai.parseVoice("呢度冇櫈", context: ctx()) == .report(.noSeat))
    }

    @Test func 改约同取消() {
        #expect(ai.parseVoice("改做下晝五點", context: ctx()) == .changeMeetup(partnerID: nil, day: nil, hour: 17, landmarkID: nil))
        #expect(ai.parseVoice("改去涼亭", context: ctx()) == .changeMeetup(partnerID: nil, day: nil, hour: nil, landmarkID: "shelter-1"))
        #expect(ai.parseVoice("同陳太嘅約改到聽日朝早", context: ctx()) == .changeMeetup(partnerID: "chan", day: 1, hour: 8, landmarkID: nil))
        #expect(ai.parseVoice("取消同陳太嘅約", context: ctx()) == .cancelMeetup(partnerID: "chan"))
        #expect(ai.parseVoice("改到明日朝早", context: ctx()) == .changeMeetup(partnerID: nil, day: 1, hour: 8, landmarkID: nil))
    }

    @Test func 改约地点揀最长嘅名() {
        let lms2 = lms + [Landmark(id: "park-1", name: "公園", kind: .park, pos: Vec2(x: 80, y: 0), hasSeat: true)]
        let c = AIContext(residents: [chan, me], landmarks: lms2, now: Date(), walking: false, finding: false)
        #expect(ai.parseVoice("改去公園櫈仔", context: c) == .changeMeetup(partnerID: nil, day: nil, hour: nil, landmarkID: "park-0"))
    }

    @Test func 找人时播位置() {
        #expect(ai.parseVoice("我喺涼亭", context: ctx(finding: true)) == .broadcast("我喺涼亭"))
        #expect(ai.parseVoice("過去搵陳太", context: ctx()) == .goFind(partnerID: "chan"))
    }

    @Test func 听唔明() {
        #expect(ai.parseVoice("今日天氣幾好", context: ctx()) == .unknown)
    }
}

struct StoreTests {
    let today = SunShadeTests.hk("2026-10-07 10:00")
    func key(_ daysAgo: Int) -> String { LocalStore.dayKey(today.addingTimeInterval(-Double(daysAgo) * 86400)) }

    @Test func 连续天数() {
        var log: [String: DayLog] = [:]
        for d in 1...4 { log[key(d)] = DayLog(minutes: 30, walks: 1) }
        #expect(LocalStore.streak(log, leaves: [], today: today, includeDemo: true) == 4, "今日未行：由昨日数起")
        log[key(0)] = DayLog(minutes: 20, walks: 1)
        #expect(LocalStore.streak(log, leaves: [], today: today, includeDemo: true) == 5)
        log[key(2)] = nil
        #expect(LocalStore.streak(log, leaves: [], today: today, includeDemo: true) == 2, "中间断咗")
        #expect(LocalStore.streak(log, leaves: [key(2)], today: today, includeDemo: true) == 5, "请假唔会断")
    }

    @Test func 示範纪录可以唔计() {
        var log: [String: DayLog] = [:]
        for d in 0...5 { log[key(d)] = DayLog(minutes: 30, walks: 1, demo: true) }
        #expect(LocalStore.streak(log, leaves: [], today: today, includeDemo: true) == 6)
        #expect(LocalStore.streak(log, leaves: [], today: today, includeDemo: false) == 0)
    }

    @Test func 日期键用香港时区() {
        // UTC 16:30 = 香港翌日 00:30
        let utc = ISO8601DateFormatter().date(from: "2026-10-06T16:30:00Z")!
        #expect(LocalStore.dayKey(utc) == "2026-10-07")
    }

    @Test func 保存格式来回一致() throws {
        var s = SavedState()
        s.mapKey = "0_0|123"
        s.neighbors["chan"] = NeighborLink(since: Date(timeIntervalSince1970: 1_790_000_000), send: true, receive: false)
        s.appointments = [Appointment(partnerID: "chan", date: Date(timeIntervalSince1970: 1_790_100_000), landmarkID: "park-0", reason: "有櫈", status: .accepted)]
        s.reports = [Report(kind: .noSeat, pos: Vec2(x: 1, y: 2), landmarkID: "park-0", date: Date(timeIntervalSince1970: 1_790_000_000), followUp: "加櫈")]
        s.landmarkNames = ["park-0": "大樹底"]
        s.walkLog = [key(0): DayLog(minutes: 30, walks: 1, landmarks: ["park-0"])]
        s.leaveDays = [key(1)]
        let back = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}

@MainActor
struct CommunityTests {
    let lms = [Landmark(id: "a", name: "涼亭", kind: .shelter, pos: .zero, hasSeat: true),
               Landmark(id: "b", name: "公園", kind: .park, pos: Vec2(x: 50, y: 0), hasSeat: true),
               Landmark(id: "c", name: "巴士站", kind: .busStop, pos: Vec2(x: 0, y: 60), hasSeat: false)]

    @Test func 示範街坊只喺演示模式出现() {
        let demo = LocalCommunityService(demoEnabled: true)
        let members = demo.circleMembers(blocks: ["皇滙樓"], landmarks: lms)
        #expect(members.count == 6)
        #expect(members.allSatisfy { $0.isDemo && !$0.isNeighbor })
        let real = LocalCommunityService(demoEnabled: false)
        #expect(real.circleMembers(blocks: [], landmarks: lms).isEmpty)
        #expect(real.passersToday(at: lms[0]) == nil)
        #expect(real.othersReports(landmarks: lms).isEmpty)
        #expect(!real.monthlyStats(myWalks: 3, myMeetups: 1, estateHomes: 5000).isDemo)
    }

    @Test func 月报只出十人以上() {
        let demo = LocalCommunityService(demoEnabled: true)
        let reports = demo.othersReports(landmarks: lms)
        let r = TemplateAI().monthlyReport(placeName: "皇后山邨", reports: reports, landmarks: lms,
                                          stats: demo.monthlyStats(myWalks: 0, myMeetups: 0, estateHomes: 4000))
        #expect(r.items.allSatisfy { $0.count >= TemplateAI.minReporters })
        #expect(r.items.first?.place == "涼亭")
        #expect(r.title.contains("皇后山邨"))
    }
}
