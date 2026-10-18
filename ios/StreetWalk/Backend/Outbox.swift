import Foundation

/// Persistent pending writes for offline/transient failures, stored in Application Support/StreetWalk/outbox.json across restarts.
/// Replace __ME__ in path/query/body with the authenticated ID at send time, allowing queueing before login.
struct OutboxOp: Codable, Equatable, Identifiable, Sendable {
    static let me = "__ME__"

    var id = UUID()
    /// Keep only the newest pending write per key, such as profile, outing, or remind:<id>.
    var key: String?
    var method: String
    var path: String
    var query: String?
    var body: Data?
    var prefer: String?
    var created = Date()
    /// Drop unsent time-sensitive messages after this deadline.
    var expires: Date?
    /// Higher priority sends first; profile writes must precede rows that reference profiles.
    var priority = 0

    func resolved(me: String) -> (path: String, query: String?, body: Data?) {
        func r(_ s: String) -> String { s.replacingOccurrences(of: Self.me, with: me) }
        return (r(path), query.map(r), body.map { Data(r(String(decoding: $0, as: UTF8.self)).utf8) })
    }
}

struct Outbox: Codable, Equatable, Sendable {
    var ops: [OutboxOp] = []
    /// Bound queue size during long offline periods; discard oldest entries first.
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

    /// Next write: discard expired entries, then order by descending priority and FIFO within a priority.
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
