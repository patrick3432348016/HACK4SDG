import Foundation

// Live Supabase integration creates two anonymous test users; retain printed IDs for authorized cleanup.
// Usage: ios/tools/backendtest.sh compiles Foundation-only Backend files plus this test file.
// Tests anonymous login/refresh, profiles, community_board, link_neighbor, postgres_changes, private pair channels and outbox.

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
    // Use a random remote grid so the board contains only these two test accounts.
    let tile = Int.random(in: 10_000...1_000_000)
    let a = SupabaseAPI(baseURL: base, apiKey: key, store: storeA, log: verbose)
    let b = SupabaseAPI(baseURL: base, apiKey: key, store: storeB, log: verbose)
    do {
        let sa = try await a.signInAnonymously(), sb = try await b.signInAnonymously()
        check("Anonymous sign-in creates two distinct users", !sa.userID.isEmpty && !sb.userID.isEmpty && sa.userID != sb.userID)
        let again = try await a.signInAnonymously()
        check("Repeated sign-in reuses the existing user", again.userID == sa.userID)

        for (api, id, nick) in [(a, sa.userID, "測試客甲"), (b, sb.userID, "測試客乙")] {
            let p = ProfileUpsert(id: id, nickname: nick, avatar: AvatarJSON(mobility: "cane", color: 2, skin: 3, age: "elder"),
                                  tile_x: tile, tile_y: tile, community_name: "測試邨", block: "1座", floor: 9, streak: 4,
                                  streak_day: "2099-01-01")
            try await api.upsert("profiles", p, onConflict: "id")
        }
        // Upsert again to change floor and clear building; optional nulls must actually clear values.
        try await a.upsert("profiles", ProfileUpsert(id: sa.userID, nickname: "測試客甲", avatar: AvatarJSON(mobility: "cane", color: 2, skin: 3, age: "elder"),
                                                     tile_x: tile, tile_y: tile, community_name: "測試邨", block: nil, floor: 10, streak: 5,
                                                     streak_day: "2099-01-01"), onConflict: "id")
        let mine: [ProfileUpsert] = try await a.select("profiles", query: "select=id,nickname,avatar,tile_x,tile_y,community_name,block,floor,streak,streak_day,lang")
        check("Profile upsert merges updates and clears nullable fields", mine.first?.floor == 10 && mine.first?.block == nil && mine.first?.avatar.skin == 3, "\(mine)")

        let board: [BoardRow] = try await a.rpc("community_board")
        check("Board contains both users with nicknames and avatars", board.count == 2 && board.contains { $0.nickname == "測試客乙" && $0.avatar?.mobility == "cane" }, "\(board)")
        check("Board identifies the current user", board.first { $0.id == sa.userID }?.is_me == true)

        // A subscribes to outings/signals; B's outing must arrive at A.
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
        check("Realtime joins the channel", await waitFor(10) { joined })
        try? await Task.sleep(for: .seconds(1.5))   // Allow time for the postgres_changes subscription to become active.

        let code = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let l1: [LinkRow] = try await a.rpc("link_neighbor", ["p_code": .string(code)])
        let l2: [LinkRow] = try await b.rpc("link_neighbor", ["p_code": .string(code)])
        let l3: [LinkRow] = try await a.rpc("link_neighbor", ["p_code": .string(code)])
        check("Pairing waits for B, then returns A to B and B to A", l1.isEmpty && l2.first?.id == sa.userID && l3.first?.id == sb.userID && l3.first?.floor == 9,
              "\(l1) \(l2) \(l3)")

        try await b.upsert("outings", OutingUpsert(user_id: sb.userID, landmark_name: "測試涼亭", started_at: Date(), updated_at: Date()), onConflict: "user_id")
        check("Realtime receives neighbor outing INSERT/UPDATE", await waitFor(8) { changes.contains { $0.table == "outings" && $0.record?["landmark_name"]?.string == "測試涼亭" } },
              "\(changes)")
        let nb: [NeighborRow] = try await a.rpc("my_neighbors")
        check("my_neighbors returns B, floor, and outing landmark", nb.first?.id == sb.userID && nb.first?.floor == 9 && nb.first?.out_at == "測試涼亭" && nb.first?.out_since != nil, "\(nb)")

        try await b.upsert("outings", OutingUpsert(user_id: sb.userID, landmark_name: nil, started_at: nil, updated_at: Date()), onConflict: "user_id")
        check("A receives the return-home UPDATE with a null landmark", await waitFor(8) { changes.contains { $0.type == "UPDATE" && $0.record?["landmark_name"]?.isNull == true } })
        let nb2: [NeighborRow] = try await a.rpc("my_neighbors")
        check("out_at is null after returning home", nb2.first?.out_at == nil, "\(nb2)")

        let sig = SignalInsert(from_user: sb.userID, to_user: sa.userID, kind: "find_ask",
                               payload: .object(["ask": .string("t1"), "landmark": .string("測試涼亭")]))
        _ = try await b.request("POST", "/rest/v1/signals", body: try BackendCoding.encoder.encode(sig), prefer: "return=minimal")
        check("Realtime receives the signal", await waitFor(8) { changes.contains { $0.table == "signals" && $0.record?["payload"]?["ask"]?.string == "t1" } })
        let sigs: [SignalRow] = try await a.select("signals", query: "select=*&to_user=eq.\(sa.userID)&order=id.asc")
        check("Signal query and payload decoding succeed", sigs.last?.payload["landmark"]?.string == "測試涼亭" && sigs.last?.created_at != nil, "\(sigs)")

        // A and B broadcast over the private pair channel.
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
        check("Both peers join the private pair channel", await waitFor(10) { pjA && pjB })
        pb.broadcast("loc", .object(["x": .number(1.5)]))
        check("Pair channel receives the broadcast", await waitFor(6) { got.contains { $0["x"]?.int == 1 } }, "\(got)")

        // A client initialized with an expired session refreshes on its first request.
        let s = storeA.load()!
        let expired = MemorySessionStore(BackendSession(accessToken: s.accessToken, refreshToken: s.refreshToken, expiresAt: Date().addingTimeInterval(-10), userID: s.userID))
        let a2 = SupabaseAPI(baseURL: base, apiKey: key, store: expired, log: verbose)
        let me2: [ProfileUpsert] = try await a2.select("profiles", query: "select=id,nickname,avatar,tile_x,tile_y,community_name,block,floor,streak,streak_day,lang")
        check("Expired session refreshes automatically", me2.first?.id == sa.userID && expired.load()?.isFresh() == true && expired.load()?.refreshToken != s.refreshToken)

        // Outbox substitutes __ME__ with user ID and retains only the latest payload per key.
        var box = Outbox()
        box.add(OutboxOp(key: "remind:x", method: "PATCH", path: "/rest/v1/neighbors", query: "owner=eq.__ME__", body: Data("{\"a\":1}".utf8)))
        box.add(OutboxOp(key: "remind:x", method: "PATCH", path: "/rest/v1/neighbors", query: "owner=eq.__ME__", body: Data("{\"a\":2}".utf8)))
        box.add(OutboxOp(key: "profile", method: "POST", path: "/rest/v1/profiles", priority: 10))
        check("Outbox merges matching keys and prioritizes the profile", box.ops.count == 2 && box.next()?.key == "profile")
        check("Outbox substitutes __ME__", box.ops[0].resolved(me: "abc").query == "owner=eq.abc")

        // Cleanup removes my own neighbor row.
        _ = try await a.request("DELETE", "/rest/v1/neighbors", query: "owner=eq.\(sa.userID)&other=eq.\(sb.userID)")
        let nb3: [NeighborRow] = try await b.rpc("my_neighbors")
        check("B no longer lists A after unlinking", nb3.isEmpty)
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
