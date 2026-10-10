import Foundation
import Testing
@testable import StreetWalk

// 真后端：服务器 JSON ↔ App 资料嘅对应、圈成员合并、约会对比、连续天数、写入排队。
// 唔打网络；打正式后端嘅集成测试喺 ios/tools/backendtest.sh（会留低测试用户）。

struct BackendJSONTests {
    @Test func 时间格式_微秒_Z_纯日期都读得() throws {
        let a = try #require(BackendTime.parse("2026-10-10T07:30:45.749549+00:00"))
        let b = try #require(BackendTime.parse("2026-10-10T07:30:45.757Z"))
        let c = try #require(BackendTime.parse("2026-10-10T07:30:44+00:00"))
        #expect(abs(a.timeIntervalSince(c) - 1.749549) < 0.001)
        #expect(abs(b.timeIntervalSince(c) - 1.757) < 0.001)
        #expect(BackendTime.parse("2026-10-10") != nil)
        #expect(BackendTime.parse("唔系时间") == nil)
        #expect(BackendTime.parse(BackendTime.format(a)).map { abs($0.timeIntervalSince(a)) < 0.002 } == true, "写出去再读返一样")
    }

    /// 实测 Realtime / PostgREST 返回嘅样子（2026-10-10 probe）。
    @Test func 读服务器返回嘅行() throws {
        let board = """
        [{"id":"E5729A1E-a741-487b-af54-6197884c97a2","nickname":"探針乙","avatar":{"age":"elder","skin":1,"color":1,"mobility":"cane"},
          "streak":3,"month_steps":12000,"is_me":false,"is_neighbor":true,"daily_line":null}]
        """
        let b = try BackendCoding.decoder.decode([BoardRow].self, from: Data(board.utf8))
        #expect(b.first?.avatar?.mobility == "cane" && b.first?.month_steps == 12000 && b.first?.daily_line == nil)

        let nb = """
        [{"id":"e5729a1e-a741-487b-af54-6197884c97a2","nickname":"探針乙","avatar":{"age":"elder","skin":1,"color":1,"mobility":"walk"},
          "block":"4座","floor":12,"streak":3,"since":"2026-10-10T07:30:40.1+00:00","send_remind":true,"receive_remind":false,
          "out_at":"涼亭","out_since":"2026-10-10T07:30:44.184+00:00","daily_line":"12 樓今日行到涼亭"}]
        """
        let n = try BackendCoding.decoder.decode([NeighborRow].self, from: Data(nb.utf8))
        #expect(n.first?.floor == 12 && n.first?.out_at == "涼亭" && n.first?.out_since != nil && n.first?.receive_remind == false)

        let sig = """
        {"id":7,"kind":"find_ask","payload":{"landmark":"涼亭","ask":"abc"},"to_user":"00dd8445-4fb1-4e14-8215-d053b0290b83",
         "from_user":"e5729a1e-a741-487b-af54-6197884c97a2","created_at":"2026-10-10T07:30:54.847041+00:00"}
        """
        let s = try BackendCoding.decoder.decode(JSONValue.self, from: Data(sig.utf8)).decode(SignalRow.self)
        #expect(s.id == 7 && s.payload["ask"]?.string == "abc" && s.payload["landmark"]?.string == "涼亭")

        let m = """
        {"id":"5D9C1E4A-0000-4000-8000-000000000001","inviter":"a","invitee":"b","at":"2099-01-01T10:00:00+00:00",
         "landmark_name":"涼亭","reason":"有樓遮","status":"accepted","updated_by":"b","updated_at":"2026-10-10T08:00:00.123456+00:00"}
        """
        let row = try BackendCoding.decoder.decode(MeetupRow.self, from: Data(m.utf8))
        #expect(row.status == "accepted" && row.updated_by == "b")
    }

    @Test func 写出去嘅资料_可选栏明确写null() throws {
        let p = ProfileUpsert(id: "x", nickname: "阿明", avatar: AvatarJSON(mobility: "walk", color: 6, skin: 1, age: "elder"),
                              tile_x: 0, tile_y: -1, community_name: nil, block: nil, floor: nil, streak: 3, streak_day: "2026-10-10")
        let o = try JSONSerialization.jsonObject(with: BackendCoding.encoder.encode(p)) as? [String: Any]
        #expect(o?["block"] is NSNull && o?["floor"] is NSNull && o?["community_name"] is NSNull, "upsert 唔写 = 唔改，所以要写 null")
        #expect(o?["tile_y"] as? Int == -1)

        let home = OutingUpsert(user_id: "x", landmark_name: nil, started_at: nil, updated_at: Date())
        let h = try JSONSerialization.jsonObject(with: BackendCoding.encoder.encode(home)) as? [String: Any]
        #expect(h?["landmark_name"] is NSNull, "回家：改成 null（唔删行）")
        #expect(h?["started_at"] == nil, "途中 / 回家唔改开始时间")

        let n: JSONValue = .object(["eta": .number(5), "x": .number(1.5)])
        let txt = String(decoding: try BackendCoding.encoder.encode(n), as: UTF8.self)
        #expect(txt.contains("\"eta\":5") && txt.contains("1.5"), "整数唔好写成 5.0")
    }

    @Test func 网名规则() {
        #expect(CommunityProfile.cleanNickname("  陳太 ") == "陳太")
        #expect(CommunityProfile.cleanNickname("   ") == nil)
        #expect(CommunityProfile.cleanNickname(String(repeating: "好", count: 20)) != nil)
        #expect(CommunityProfile.cleanNickname(String(repeating: "好", count: 21)) == nil, "同服务器 1–20 字一致")
    }
}

struct BackendMergeTests {
    let lm = [Landmark(id: "pav", name: "涼亭", kind: .shelter, pos: Vec2(x: 10, y: 0), hasSeat: true),
              Landmark(id: "bus", name: "巴士站", kind: .busStop, pos: Vec2(x: -10, y: 0), hasSeat: false)]

    func board(_ id: String, _ nick: String, streak: Int = 2, me: Bool = false, neighbor: Bool = false, line: String? = nil) -> BoardRow {
        BoardRow(id: id, nickname: nick, avatar: AvatarJSON(mobility: "wheelchair", color: 3, skin: 2, age: "young"), streak: streak,
                 month_steps: 100, is_me: me, is_neighbor: neighbor, daily_line: line)
    }

    func neighbor(_ id: String, _ nick: String, out: String? = nil, since: Date? = Date()) -> NeighborRow {
        NeighborRow(id: id, nickname: nick, avatar: AvatarJSON(mobility: "cane", color: 1, skin: 0, age: "elder"), block: "皇滙樓", floor: 12,
                    streak: 5, since: Date(), send_remind: true, receive_remind: false, out_at: out, out_since: out == nil ? nil : since,
                    daily_line: "12 樓今日行到涼亭")
    }

    @Test func 排行榜加街坊合并_非街坊冇座数楼层() {
        let index = LandmarkIndex(landmarks: lm, originals: ["pav": "涼亭", "bus": "巴士站"])
        let rs = BackendMapping.residents(board: [board("me", "我", me: true), board("a", "阿芳", line: "唔应该见到"), board("b", "阿明", neighbor: true)],
                                          neighbors: [neighbor("b", "阿明", out: "涼亭"), neighbor("c", "搬咗走嘅街坊")],
                                          myID: "me", landmarks: index, now: Date())
        #expect(rs.map(\.id) == ["a", "b", "c"], "唔包括我；街坊唔喺附近格子都要有")
        let a = rs[0], b = rs[1], c = rs[2]
        #expect(!a.isNeighbor && a.floor == 0 && a.blockName == nil && a.todayLine.isEmpty, "非街坊：冇楼层、座数、今日一句")
        #expect(a.listName == "阿芳" && a.mobility == .wheelchair && a.skinTone == 2 && a.ageGroup == .young && a.streakDays == 2 && !a.isDemo)
        #expect(b.isNeighbor && b.floor == 12 && b.listName == "阿明 · 皇滙樓 12 樓" && b.todayLine == "12 樓今日行到涼亭")
        #expect(b.isOut && b.atLandmarkID == "pav" && b.receiveRemind == false, "出门地标名对返本机地标")
        #expect(c.isNeighbor && c.streakDays == 5)
    }

    @Test func 出门太耐当返咗屋企_地图外面嘅地标只有名() {
        let index = LandmarkIndex(landmarks: lm, originals: [:])
        let old = BackendMapping.residents(board: [], neighbors: [neighbor("b", "阿明", out: "涼亭", since: Date().addingTimeInterval(-4 * 3600))],
                                           myID: "me", landmarks: index, now: Date())
        #expect(old.first?.isOut == false, "超过 3 个钟冇更新：唔当佢仲喺外面")
        let far = BackendMapping.residents(board: [], neighbors: [neighbor("b", "阿明", out: "天水圍公園")], myID: "me", landmarks: index, now: Date())
        #expect(far.first?.atLandmarkID == "lmname:天水圍公園")
        #expect(LandmarkIndex.syntheticName(far.first?.atLandmarkID) == "天水圍公園")
    }

    @Test func 地标名对应_用原名上传_改咗名都对得上() {
        var renamed = lm
        renamed[0].name = "大樹下"
        let index = LandmarkIndex(landmarks: renamed, originals: ["pav": "涼亭", "bus": "巴士站"])
        #expect(index.publishName("pav") == "涼亭", "上传原名，对方先对得上")
        #expect(index.id(forName: "涼亭") == "pav")
        #expect(index.id(forName: "大樹下") == "pav")
        #expect(index.id(forName: "邊度") == "lmname:邊度")
        #expect(index.publishName("lmname:邊度") == "邊度")
        #expect(index.id(forName: nil) == nil && index.id(forName: "") == nil)
    }

    @Test func 配上嘅对方变成街坊() {
        let row = LinkRow(id: "ABC", nickname: "阿芳", avatar: AvatarJSON(mobility: "stroller", color: 2, skin: 3, age: "adult"), block: nil, floor: 7)
        let peer = BackendMapping.peer(row)
        #expect(peer.id == "abc" && peer.mobility == .stroller && peer.floor == 7)
        let r = BackendMapping.resident(peer)
        #expect(r.isNeighbor && r.listName == "阿芳 · 7 樓" && r.colorIndex == 2 && r.skinTone == 3)
        #expect(BackendMapping.look(AvatarJSON(mobility: "飛", color: 99, skin: -3, age: nil)) == (.walk, Palette.people.count - 1, 0, .adult), "坏数据唔会崩")
    }
}

struct BackendMeetupTests {
    let me = "me"
    func row(status: String, by: String, at: Date = Date().addingTimeInterval(3600), place: String? = "涼亭", stamp: Double = 0) -> MeetupRow {
        MeetupRow(id: "5d9c1e4a-0000-4000-8000-000000000001", inviter: "you", invitee: me, at: at, landmark_name: place, reason: "有櫈",
                  status: status, updated_by: by, updated_at: Date(timeIntervalSince1970: 1_000 + stamp))
    }

    @Test func 对方约我_应承_改约_取消() {
        let now = Date()
        #expect(BackendMapping.meetupChange(row(status: "waiting", by: "you"), seen: nil, me: me, now: now) == .invited)
        #expect(BackendMapping.meetupChange(row(status: "waiting", by: "you", at: now.addingTimeInterval(-7200)), seen: nil, me: me, now: now) == nil, "过咗期嘅唔约")
        let mine = row(status: "waiting", by: me)
        #expect(BackendMapping.meetupChange(mine, seen: nil, me: me, now: now) == nil, "自己改嘅唔出事件")
        #expect(BackendMapping.meetupChange(row(status: "accepted", by: "you", stamp: 1), seen: mine, me: me, now: now) == .answered(true))
        #expect(BackendMapping.meetupChange(row(status: "declined", by: "you", stamp: 1), seen: mine, me: me, now: now) == .answered(false))
        #expect(BackendMapping.meetupChange(row(status: "cancelled", by: "you", stamp: 1), seen: mine, me: me, now: now) == .cancelled)
        #expect(BackendMapping.meetupChange(row(status: "waiting", by: "you", place: "巴士站", stamp: 1), seen: mine, me: me, now: now) == .changed)
        let accepted = row(status: "accepted", by: "you", stamp: 1)
        #expect(BackendMapping.meetupChange(accepted, seen: accepted, me: me, now: now) == nil, "冇变唔重复")
    }

    @Test func 约会行变返App嘅约会() throws {
        let index = LandmarkIndex(landmarks: [Landmark(id: "pav", name: "涼亭", kind: .shelter, pos: .zero, hasSeat: true)], originals: [:])
        let a = try #require(BackendMapping.appointment(row(status: "waiting", by: "you"), me: me, landmarks: index))
        #expect(a.partnerID == "you" && a.landmarkID == "pav" && a.status == .waiting && a.fromPartner, "对方嘅约：等我确认")
        let d = try #require(BackendMapping.appointment(row(status: "declined", by: "you"), me: me, landmarks: index))
        #expect(d.status == .cancelled)
        #expect(BackendMapping.serverStatus(.expired) == "expired")
        #expect(BackendMapping.reportKind(BackendMapping.serverKind(.noSeat)) == .noSeat)
    }
}

@MainActor
struct BackendStreakTests {
    @Test func 连续天数计到边日_请假顺延() {
        let today = AppStore.today(at: 10)
        func key(_ d: Int) -> String { LocalStore.dayKey(today.addingTimeInterval(Double(d) * 86400)) }
        // 今日行咗：今日
        #expect(BackendMapping.streakDay(today: today, streak: 3, walkedOrLeave: { $0 == key(0) }, leave: { _ in false }) == key(0))
        // 今日未行：琴日（服务器两日内照显示）
        #expect(BackendMapping.streakDay(today: today, streak: 3, walkedOrLeave: { _ in false }, leave: { _ in false }) == key(-1))
        // 今日起请 3 日假：顺延到第 3 日，排行榜唔会中途变 0
        let leaves: Set<String> = [key(0), key(1), key(2)]
        #expect(BackendMapping.streakDay(today: today, streak: 3, walkedOrLeave: { leaves.contains($0) }, leave: { leaves.contains($0) }) == key(2))
        #expect(BackendMapping.streakDay(today: today, streak: 0, walkedOrLeave: { _ in false }, leave: { _ in false }) == key(0))
    }
}

struct BackendOutboxTests {
    @Test func 同key只留最新_资料优先_过期唔送() {
        var box = Outbox()
        box.add(OutboxOp(key: "walk:1", method: "POST", path: "/w"))
        box.add(OutboxOp(key: "outing", method: "POST", path: "/o", body: Data("1".utf8)))
        box.add(OutboxOp(key: "outing", method: "POST", path: "/o", body: Data("2".utf8)))
        box.add(OutboxOp(method: "POST", path: "/s", expires: Date().addingTimeInterval(-1)))
        box.add(OutboxOp(key: "profile", method: "POST", path: "/p", priority: 10))
        #expect(box.ops.count == 4)
        #expect(box.next()?.key == "profile")
        #expect(box.ops.count == 3, "过期嘅即刻丢")
        box.remove(key: "profile")
        #expect(box.next()?.key == "walk:1", "同级按先后")
        #expect(box.ops.first { $0.key == "outing" }?.body == Data("2".utf8))
        let op = OutboxOp(method: "DELETE", path: "/rest/v1/neighbors", query: "owner=eq.__ME__&other=eq.x", body: Data("{\"u\":\"__ME__\"}".utf8))
        let r = op.resolved(me: "abc")
        #expect(r.query == "owner=eq.abc&other=eq.x" && r.body == Data("{\"u\":\"abc\"}".utf8))
    }

    @Test func 存盘读返() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString).json")
        var box = Outbox()
        box.add(OutboxOp(key: "profile", method: "POST", path: "/p", priority: 10))
        box.save(url)
        #expect(Outbox.load(url) == box)
        try? FileManager.default.removeItem(at: url)
        #expect(Outbox.load(url).isEmpty, "冇文件 = 空")
    }
}
