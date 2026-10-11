import Foundation

// 后端客户端集成测试（打正式 Supabase；会留低两个匿名测试用户，最后一行印出 id，测完喺 SQL Editor 删）。
// 用法：ios/tools/backendtest.sh   （编译 StreetWalk/Backend 入面只用 Foundation 嘅文件 + 呢个文件）
// 测：匿名登录、续期、profiles upsert、community_board、link_neighbor、Realtime postgres_changes、私有 pair 频道、outbox。

let base = URL(string: "https://oajsqhpqsgqnvkgsdjtv.supabase.co")!
let key = "sb_publishable_BgcZ-r4jFWml1kILSiEgWg_HVoL4g3c"
let verbose = CommandLine.arguments.contains("-v")

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1; print("PASS \(name)") } else { failed += 1; print("FAIL \(name)  -> \(detail())") }
}

@MainActor
func waitFor(_ seconds: Double, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if cond() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return cond()
}

@MainActor
func run() async {
    let storeA = MemorySessionStore(), storeB = MemorySessionStore()
    // 每次用一个远离真人嘅随机格子：排行榜只会有呢两个测试用户
    let tile = Int.random(in: 10_000...1_000_000)
    let a = SupabaseAPI(baseURL: base, apiKey: key, store: storeA, log: verbose)
    let b = SupabaseAPI(baseURL: base, apiKey: key, store: storeB, log: verbose)
    do {
        let sa = try await a.signInAnonymously(), sb = try await b.signInAnonymously()
        check("匿名登录两个用户", !sa.userID.isEmpty && !sb.userID.isEmpty && sa.userID != sb.userID)
        let again = try await a.signInAnonymously()
        check("已登录再叫唔会开新用户", again.userID == sa.userID)

        for (api, id, nick) in [(a, sa.userID, "測試客甲"), (b, sb.userID, "測試客乙")] {
            let p = ProfileUpsert(id: id, nickname: nick, avatar: AvatarJSON(mobility: "cane", color: 2, skin: 3, age: "elder"),
                                  tile_x: tile, tile_y: tile, community_name: "測試邨", block: "1座", floor: 9, streak: 4,
                                  streak_day: "2099-01-01")
            try await api.upsert("profiles", p, onConflict: "id")
        }
        // 再 upsert 一次（改楼层、清座数）：可选栏写 null 要真系清走
        try await a.upsert("profiles", ProfileUpsert(id: sa.userID, nickname: "測試客甲", avatar: AvatarJSON(mobility: "cane", color: 2, skin: 3, age: "elder"),
                                                     tile_x: tile, tile_y: tile, community_name: "測試邨", block: nil, floor: 10, streak: 5,
                                                     streak_day: "2099-01-01"), onConflict: "id")
        let mine: [ProfileUpsert] = try await a.select("profiles", query: "select=id,nickname,avatar,tile_x,tile_y,community_name,block,floor,streak,streak_day,lang")
        check("profiles upsert 合并更新、null 清栏", mine.first?.floor == 10 && mine.first?.block == nil && mine.first?.avatar.skin == 3, "\(mine)")

        let board: [BoardRow] = try await a.rpc("community_board")
        check("排行榜有两人、有网名同小人", board.count == 2 && board.contains { $0.nickname == "測試客乙" && $0.avatar?.mobility == "cane" }, "\(board)")
        check("排行榜标记自己", board.first { $0.id == sa.userID }?.is_me == true)

        // Realtime：甲订阅 outings / signals；乙出门 → 甲要收到
        let rtA = RealtimeClient(baseURL: base, apiKey: key, log: verbose) { try? await a.accessToken() }
        var changes: [PostgresChange] = []
        var joined = false
        let ch = rtA.channel("sw-test-\(sa.userID.prefix(8))", postgresChanges: [
            PostgresChangeSpec(table: "outings"),
            PostgresChangeSpec(event: "INSERT", table: "signals", filter: "to_user=eq.\(sa.userID)"),
        ])
        ch.onJoin = { ok, _ in joined = ok }
        ch.onPostgresChange = { changes.append($0) }
        rtA.connect()
        check("Realtime 加入频道", await waitFor(10) { joined })
        try? await Task.sleep(for: .seconds(1.5))   // postgres_changes 订阅生效要一阵

        let code = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let l1: [LinkRow] = try await a.rpc("link_neighbor", ["p_code": .string(code)])
        let l2: [LinkRow] = try await b.rpc("link_neighbor", ["p_code": .string(code)])
        let l3: [LinkRow] = try await a.rpc("link_neighbor", ["p_code": .string(code)])
        check("配对：甲先交码未配上，乙交码配上返回甲，甲再问返回乙", l1.isEmpty && l2.first?.id == sa.userID && l3.first?.id == sb.userID && l3.first?.floor == 9,
              "\(l1) \(l2) \(l3)")

        try await b.upsert("outings", OutingUpsert(user_id: sb.userID, landmark_name: "測試涼亭", started_at: Date(), updated_at: Date()), onConflict: "user_id")
        check("Realtime 收到街坊出门（INSERT/UPDATE）", await waitFor(8) { changes.contains { $0.table == "outings" && $0.record?["landmark_name"]?.string == "測試涼亭" } },
              "\(changes)")
        let nb: [NeighborRow] = try await a.rpc("my_neighbors")
        check("my_neighbors 有乙、楼层、出门地标", nb.first?.id == sb.userID && nb.first?.floor == 9 && nb.first?.out_at == "測試涼亭" && nb.first?.out_since != nil, "\(nb)")

        try await b.upsert("outings", OutingUpsert(user_id: sb.userID, landmark_name: nil, started_at: nil, updated_at: Date()), onConflict: "user_id")
        check("回家：改成 null（UPDATE）甲都收到", await waitFor(8) { changes.contains { $0.type == "UPDATE" && $0.record?["landmark_name"]?.isNull == true } })
        let nb2: [NeighborRow] = try await a.rpc("my_neighbors")
        check("回家后 out_at 系 null", nb2.first?.out_at == nil, "\(nb2)")

        let sig = SignalInsert(from_user: sb.userID, to_user: sa.userID, kind: "find_ask",
                               payload: .object(["ask": .string("t1"), "landmark": .string("測試涼亭")]))
        _ = try await b.request("POST", "/rest/v1/signals", body: try BackendCoding.encoder.encode(sig), prefer: "return=minimal")
        check("Realtime 收到信号", await waitFor(8) { changes.contains { $0.table == "signals" && $0.record?["payload"]?["ask"]?.string == "t1" } })
        let sigs: [SignalRow] = try await a.select("signals", query: "select=*&to_user=eq.\(sa.userID)&order=id.asc")
        check("signals 查得返、payload 解得返", sigs.last?.payload["landmark"]?.string == "測試涼亭" && sigs.last?.created_at != nil, "\(sigs)")

        // 私有 pair 频道：甲乙互相 broadcast
        let (lo, hi) = sa.userID < sb.userID ? (sa.userID, sb.userID) : (sb.userID, sa.userID)
        let rtB = RealtimeClient(baseURL: base, apiKey: key, log: verbose) { try? await b.accessToken() }
        var pjA = false, pjB = false
        var got: [JSONValue] = []
        let pa = rtA.channel("pair:\(lo):\(hi)", isPrivate: true)
        let pb = rtB.channel("pair:\(lo):\(hi)", isPrivate: true)
        pa.onJoin = { ok, _ in pjA = ok }
        pb.onJoin = { ok, _ in pjB = ok }
        pa.onBroadcast = { e, p in if e == "loc" { got.append(p) } }
        rtB.connect()
        check("私有 pair 频道两边加入", await waitFor(10) { pjA && pjB })
        pb.broadcast("loc", .object(["x": .number(1.5)]))
        check("pair 频道收到 broadcast", await waitFor(6) { got.contains { $0["x"]?.int == 1 } }, "\(got)")

        // 续期：用过期嘅 session 开一个新客户端，第一个请求自动续期
        let s = storeA.load()!
        let expired = MemorySessionStore(BackendSession(accessToken: s.accessToken, refreshToken: s.refreshToken, expiresAt: Date().addingTimeInterval(-10), userID: s.userID))
        let a2 = SupabaseAPI(baseURL: base, apiKey: key, store: expired, log: verbose)
        let me2: [ProfileUpsert] = try await a2.select("profiles", query: "select=id,nickname,avatar,tile_x,tile_y,community_name,block,floor,streak,streak_day,lang")
        check("过期 token 自动续期", me2.first?.id == sa.userID && expired.load()?.isFresh() == true && expired.load()?.refreshToken != s.refreshToken)

        // outbox：__ME__ 换成用户 id；同 key 只留最新
        var box = Outbox()
        box.add(OutboxOp(key: "remind:x", method: "PATCH", path: "/rest/v1/neighbors", query: "owner=eq.__ME__", body: Data("{\"a\":1}".utf8)))
        box.add(OutboxOp(key: "remind:x", method: "PATCH", path: "/rest/v1/neighbors", query: "owner=eq.__ME__", body: Data("{\"a\":2}".utf8)))
        box.add(OutboxOp(key: "profile", method: "POST", path: "/rest/v1/profiles", priority: 10))
        check("outbox 同 key 合并、资料优先", box.ops.count == 2 && box.next()?.key == "profile")
        check("outbox __ME__ 替换", box.ops[0].resolved(me: "abc").query == "owner=eq.abc")

        // 清理：解除街坊（DELETE 自己那行）
        _ = try await a.request("DELETE", "/rest/v1/neighbors", query: "owner=eq.\(sa.userID)&other=eq.\(sb.userID)")
        let nb3: [NeighborRow] = try await b.rpc("my_neighbors")
        check("解除后乙名单冇甲", nb3.isEmpty)
        rtA.disconnect(); rtB.disconnect()
        print("\n\(passed)/\(passed + failed) passed")
        print("TEST_USERS \(sa.userID) \(sb.userID)")
    } catch {
        print("ERROR \(error)")
        failed += 1
    }
}

await run()
exit(failed == 0 ? 0 : 1)
