import Foundation

// Supabase Realtime（Phoenix 协议 vsn 1.0.0，JSON 物件）。只用 Foundation（URLSessionWebSocketTask）。
// 2026-10-10 对住正式后端实测（scratchpad probe + tools/backendtest）：
//   连线：wss://<project>/realtime/v1/websocket?apikey=<publishable key>&vsn=1.0.0
//   加入：{"topic":"realtime:<名>","event":"phx_join","payload":{"config":{broadcast,presence,postgres_changes,private},"access_token":<JWT>},"ref","join_ref"}
//   心跳：{"topic":"phoenix","event":"heartbeat","payload":{},"ref"} 每 25 秒；换 token：event "access_token"。
//   表变动：event "postgres_changes"，payload.data = {type, table, record, old_record}。INSERT / UPDATE 按 RLS 过滤；
//   DELETE 唔过滤（所有订阅者都收到，只有主键）——所以出门状态回家时改成 null，唔删行（见 SupabaseCommunityService）。
//   私有频道（private: true）：pair:<小uuid>:<大uuid> 只放行两个互为街坊嘅人，第三者加入会收到 Unauthorized。

struct PostgresChangeSpec: Sendable {
    var event = "*"
    var schema = "public"
    var table: String
    var filter: String?

    var json: JSONValue {
        var o: [String: JSONValue] = ["event": .string(event), "schema": .string(schema), "table": .string(table)]
        if let filter { o["filter"] = .string(filter) }
        return .object(o)
    }
}

struct PostgresChange: Sendable {
    var type: String            // INSERT / UPDATE / DELETE
    var table: String
    var record: JSONValue?
    var oldRecord: JSONValue?
}

@MainActor
final class RealtimeChannel {
    /// 频道名（唔带 "realtime:" 前缀），例如 "pair:<a>:<b>"。私有频道嘅 RLS 用呢个名（realtime.topic()）。
    let name: String
    var topic: String { "realtime:" + name }
    let isPrivate: Bool
    fileprivate let config: JSONValue
    fileprivate(set) var joined = false
    fileprivate var joinRef: String?
    /// 加入被拒（例如私有频道无权限）：唔再自动重试，等下次重新连线。
    fileprivate(set) var refusedReason: String?
    fileprivate weak var client: RealtimeClient?

    var onPostgresChange: ((PostgresChange) -> Void)?
    var onBroadcast: ((_ event: String, _ payload: JSONValue) -> Void)?
    /// 加入结果：成功 / 被拒（附原因）。重新连线后会再叫一次。
    var onJoin: ((_ ok: Bool, _ reason: String?) -> Void)?

    fileprivate init(name: String, config: JSONValue, isPrivate: Bool) {
        self.name = name
        self.config = config
        self.isPrivate = isPrivate
    }

    /// 发一个 broadcast（未加入时丢弃；位置之类即时数据唔使补发）。
    func broadcast(_ event: String, _ payload: JSONValue) {
        guard joined, let client else { return }
        client.push(topic: topic, event: "broadcast",
                    payload: .object(["type": .string("broadcast"), "event": .string(event), "payload": payload]), joinRef: joinRef)
    }
}

@MainActor
final class RealtimeClient {
    enum State: Equatable { case disconnected, connecting, connected }
    private(set) var state: State = .disconnected { didSet { if state != oldValue { onStateChange?(state) } } }
    var onStateChange: ((State) -> Void)?

    private let url: URL
    private let tokenProvider: () async -> String?
    private let log: Bool
    private let urlSession = URLSession(configuration: .default)
    private var socket: URLSessionWebSocketTask?
    private var channels: [String: RealtimeChannel] = [:]
    private var ref = 0
    private var heartbeat: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var pendingHeartbeat: String?
    private var wantConnected = false
    private var attempts = 0
    static let heartbeatInterval: Duration = .seconds(25)

    init(baseURL: URL, apiKey: String, log: Bool = false, tokenProvider: @escaping () async -> String?) {
        var c = URLComponents(url: baseURL.appendingPathComponent("/realtime/v1/websocket"), resolvingAgainstBaseURL: false)!
        c.scheme = baseURL.scheme == "http" ? "ws" : "wss"
        c.queryItems = [URLQueryItem(name: "apikey", value: apiKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        url = c.url!
        self.log = log
        self.tokenProvider = tokenProvider
    }

    // MARK: - 连线

    func connect() {
        wantConnected = true
        guard socket == nil else { return }
        open()
    }

    func disconnect() {
        wantConnected = false
        reconnect?.cancel(); reconnect = nil
        close()
    }

    private func open() {
        reconnect?.cancel(); reconnect = nil
        let s = urlSession.webSocketTask(with: url)
        socket = s
        state = .connecting
        pendingHeartbeat = nil
        s.resume()
        if log { print("[realtime] open") }
        Task { await self.receiveLoop(s) }
        for ch in channels.values { join(ch) }
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard let self, !Task.isCancelled else { return }
                self.beat()
            }
        }
    }

    private func close() {
        heartbeat?.cancel(); heartbeat = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        for ch in channels.values { ch.joined = false; ch.joinRef = nil }
        state = .disconnected
    }

    private func beat() {
        guard socket != nil else { return }
        // 上一次心跳冇回覆：条线已经断咗（例如退后台再返嚟），重新连。
        if pendingHeartbeat != nil { dropped("heartbeat timeout"); return }
        let r = nextRef()
        pendingHeartbeat = r
        send(["topic": .string("phoenix"), "event": .string("heartbeat"), "payload": .object([:]), "ref": .string(r)])
    }

    private func dropped(_ why: String) {
        if log { print("[realtime] dropped: \(why)") }
        close()
        guard wantConnected else { return }
        let delays: [Double] = [1, 2, 5, 10, 20, 30]
        let d = delays[min(attempts, delays.count - 1)]
        attempts += 1
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(d))
            guard let self, !Task.isCancelled, self.wantConnected, self.socket == nil else { return }
            self.open()
        }
    }

    private func receiveLoop(_ s: URLSessionWebSocketTask) async {
        while true {
            do {
                let msg = try await s.receive()
                guard socket === s else { return }
                switch msg {
                case .string(let t): handle(Data(t.utf8))
                case .data(let d): handle(d)
                @unknown default: break
                }
            } catch {
                if socket === s { dropped(error.localizedDescription) }
                return
            }
        }
    }

    // MARK: - 频道

    /// 开一个频道（已连线就即刻加入；断线重连会自动再加入）。同名频道会取代旧嘅。
    func channel(_ name: String, postgresChanges: [PostgresChangeSpec] = [], isPrivate: Bool = false,
                 receiveOwnBroadcasts: Bool = false) -> RealtimeChannel {
        if let old = channels[name] { remove(old) }
        let config: JSONValue = .object([
            "broadcast": .object(["self": .bool(receiveOwnBroadcasts), "ack": .bool(false)]),
            "presence": .object(["key": .string("")]),
            "postgres_changes": .array(postgresChanges.map(\.json)),
            "private": .bool(isPrivate),
        ])
        let ch = RealtimeChannel(name: name, config: config, isPrivate: isPrivate)
        ch.client = self
        channels[name] = ch
        if socket != nil { join(ch) }
        return ch
    }

    func remove(_ ch: RealtimeChannel) {
        guard channels[ch.name] === ch else { return }
        channels[ch.name] = nil
        if ch.joined { push(topic: ch.topic, event: "phx_leave", payload: .object([:]), joinRef: ch.joinRef) }
        ch.joined = false
        ch.client = nil
    }

    private func join(_ ch: RealtimeChannel) {
        let r = nextRef()
        ch.joinRef = r
        ch.joined = false
        ch.refusedReason = nil
        Task { [weak self] in
            guard let self else { return }
            let token = await self.tokenProvider()
            guard ch.joinRef == r, self.channels[ch.name] === ch, self.socket != nil else { return }
            var payload: [String: JSONValue] = ["config": ch.config]
            if let token { payload["access_token"] = .string(token) }
            self.send(["topic": .string(ch.topic), "event": .string("phx_join"), "payload": .object(payload),
                       "ref": .string(r), "join_ref": .string(r)])
        }
    }

    /// 换咗 access token（续期）：通知所有已加入嘅频道，唔使断线。
    func updateToken(_ token: String?) {
        guard let token else { return }
        for ch in channels.values where ch.joined {
            push(topic: ch.topic, event: "access_token", payload: .object(["access_token": .string(token)]), joinRef: ch.joinRef)
        }
    }

    fileprivate func push(topic: String, event: String, payload: JSONValue, joinRef: String?) {
        var m: [String: JSONValue] = ["topic": .string(topic), "event": .string(event), "payload": payload, "ref": .string(nextRef())]
        if let joinRef { m["join_ref"] = .string(joinRef) }
        send(m)
    }

    private func nextRef() -> String { ref += 1; return String(ref) }

    private func send(_ m: [String: JSONValue]) {
        guard let s = socket, let data = try? BackendCoding.encoder.encode(JSONValue.object(m)) else { return }
        // 用 completion 版本：按调用次序送出。
        s.send(.string(String(decoding: data, as: UTF8.self))) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, self.socket === s else { return }
                self.dropped("send: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 收消息

    private func handle(_ data: Data) {
        guard let m = try? BackendCoding.decoder.decode(JSONValue.self, from: data),
              let topic = m["topic"]?.string, let event = m["event"]?.string else { return }
        let payload = m["payload"] ?? .null
        let ref = m["ref"]?.string
        if topic == "phoenix" {
            if event == "phx_reply", ref != nil, ref == pendingHeartbeat { pendingHeartbeat = nil }
            return
        }
        guard let ch = channels.values.first(where: { $0.topic == topic }) else { return }
        switch event {
        case "phx_reply":
            guard ref != nil, ref == ch.joinRef else { return }
            if payload["status"]?.string == "ok" {
                ch.joined = true
                attempts = 0
                state = .connected
                if log { print("[realtime] joined \(ch.name)") }
                ch.onJoin?(true, nil)
            } else {
                let reason = payload["response"]?["reason"]?.string ?? "join refused"
                ch.refusedReason = reason
                if log { print("[realtime] join \(ch.name) refused: \(reason)") }
                ch.onJoin?(false, reason)
            }
        case "postgres_changes":
            guard let d = payload["data"], let type = d["type"]?.string, let table = d["table"]?.string else { return }
            ch.onPostgresChange?(PostgresChange(type: type, table: table, record: d["record"], oldRecord: d["old_record"]))
        case "broadcast":
            guard let e = payload["event"]?.string else { return }
            ch.onBroadcast?(e, payload["payload"] ?? .null)
        case "system":
            if payload["status"]?.string == "error", log { print("[realtime] system error \(ch.name): \(payload)") }
        case "phx_error", "phx_close":
            // 频道喺服务器嗰边断咗（例如 token 过期）：2 秒后再加入。
            ch.joined = false
            if log { print("[realtime] \(event) \(ch.name)") }
            let name = ch.name
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, let c = self.channels[name], c === ch, !c.joined, self.socket != nil else { return }
                self.join(c)
            }
        default:
            break
        }
    }
}
