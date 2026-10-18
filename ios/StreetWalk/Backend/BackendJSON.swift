import Foundation

// Backend JSON/time helpers using Foundation only; also compiled by tools/backendtest.

/// Arbitrary JSON values for Realtime messages and signals.payload.
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
            // Do not encode integers as 1.0; Postgres integer columns reject them.
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

    /// Decode JSON into a Decodable type, such as a Realtime record row.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try BackendCoding.decoder.decode(T.self, from: BackendCoding.encoder.encode(self))
    }

    static func from<T: Encodable>(_ v: T) throws -> JSONValue {
        try BackendCoding.decoder.decode(JSONValue.self, from: BackendCoding.encoder.encode(v))
    }
}

/// Postgres timestamps support fractional seconds, timezone offsets/Z, and date-only values.
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

    /// Support any fractional precision by parsing the fraction separately; ISO8601DateFormatter accepts only three digits.
    static func parse(_ s: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        var str = s.trimmingCharacters(in: .whitespaces)
        if str.count == 10, str.dropFirst(4).first == "-" {      // Treat a date-only value as midnight UTC.
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
