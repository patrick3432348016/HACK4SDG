import Foundation

/// 未送出嘅写入（离线、服务器暂时唔得时排队，之后再试）。存喺 Application Support/StreetWalk/outbox.json，重启都唔会冇。
/// path / query / body 入面嘅 `__ME__` 喺送出时先换成自己嘅用户 id（未登录时都可以排队）。
struct OutboxOp: Codable, Equatable, Identifiable, Sendable {
    static let me = "__ME__"

    var id = UUID()
    /// 同一个 key 只留最新一个（例如 "profile"、"outing"、"remind:<id>"）：旧嘅未送就作废。
    var key: String?
    var method: String
    var path: String
    var query: String?
    var body: Data?
    var prefer: String?
    var created = Date()
    /// 过咗呢个时间未送出就唔送（例如「我喺涼亭」呢类即时说话）。
    var expires: Date?
    /// 大嘅先送：个人资料要喺其他写入之前（其他表都引用 profiles）。
    var priority = 0

    func resolved(me: String) -> (path: String, query: String?, body: Data?) {
        func r(_ s: String) -> String { s.replacingOccurrences(of: Self.me, with: me) }
        return (r(path), query.map(r), body.map { Data(r(String(decoding: $0, as: UTF8.self)).utf8) })
    }
}

struct Outbox: Codable, Equatable, Sendable {
    var ops: [OutboxOp] = []
    /// 最多留几多个（离线好耐都唔会无限变大；旧嘅先丢）。
    static let limit = 300

    var isEmpty: Bool { ops.isEmpty }

    mutating func add(_ op: OutboxOp) {
        if let k = op.key, let i = ops.firstIndex(where: { $0.key == k }) {
            ops[i] = op
        } else {
            ops.append(op)
        }
        if ops.count > Self.limit { ops.removeFirst(ops.count - Self.limit) }
    }

    /// 下一个要送嘅：先丢过期嘅；priority 大嘅先，同级按先后。
    mutating func next(now: Date = Date()) -> OutboxOp? {
        ops.removeAll { $0.expires.map { $0 < now } ?? false }
        guard let top = ops.map(\.priority).max() else { return nil }
        return ops.first { $0.priority == top }
    }

    mutating func remove(_ id: UUID) { ops.removeAll { $0.id == id } }
    mutating func remove(key: String) { ops.removeAll { $0.key == key } }
    func contains(key: String) -> Bool { ops.contains { $0.key == key } }

    static func load(_ url: URL) -> Outbox {
        guard let d = try? Data(contentsOf: url), let o = try? JSONDecoder().decode(Outbox.self, from: d) else { return Outbox() }
        return o
    }

    func save(_ url: URL) {
        guard let d = try? JSONEncoder().encode(self) else { return }
        try? d.write(to: url, options: .atomic)
    }
}
