import Foundation

// 后端用的小工具：任意 JSON、时间格式。只用 Foundation（tools/backendtest 命令行测试都编译呢个文件）。

/// 任意 JSON 值（Realtime 消息、signals.payload 用）。
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            // 整数唔好写成 1.0（Postgres int 栏会拒绝）
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var int: Int? { if case .number(let n) = self { return Int(n) }; if case .string(let s) = self { return Int(s) }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; if case .string(let s) = self { return Double(s) }; return nil }
    var isNull: Bool { self == .null }

    /// 将 JSON 值解成某个 Decodable（Realtime 的 record → 行）。
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try BackendCoding.decoder.decode(T.self, from: BackendCoding.encoder.encode(self))
    }

    static func from<T: Encodable>(_ v: T) throws -> JSONValue {
        try BackendCoding.decoder.decode(JSONValue.self, from: BackendCoding.encoder.encode(v))
    }
}

/// Postgres 时间："2026-10-10T07:30:45.749549+00:00"、"2026-10-10T07:30:45.757Z"、"2026-10-10"（date 栏）。
enum BackendTime {
    nonisolated(unsafe) private static let internet: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let lock = NSLock()

    /// 小数位几多都得（ISO8601DateFormatter 只认 3 位，所以先拆出小数再加返）。
    static func parse(_ s: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        var str = s.trimmingCharacters(in: .whitespaces)
        if str.count == 10, str.dropFirst(4).first == "-" {      // 纯日期：当 UTC 零点
            return internet.date(from: str + "T00:00:00Z")
        }
        str = str.replacingOccurrences(of: " ", with: "T")
        var frac = 0.0
        if let dot = str.firstIndex(of: ".") {
            var end = str.index(after: dot)
            while end < str.endIndex, str[end].isNumber { end = str.index(after: end) }
            frac = Double("0" + str[dot..<end]) ?? 0
            str.removeSubrange(dot..<end)
        }
        if str.hasSuffix("+00") { str += ":00" }
        guard let d = internet.date(from: str) else { return nil }
        return d.addingTimeInterval(frac)
    }

    static func format(_ d: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return fractional.string(from: d)
    }
}

enum BackendCoding {
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = BackendTime.parse(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad timestamp \(s)")
            }
            return date
        }
        return d
    }
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(BackendTime.format(date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
