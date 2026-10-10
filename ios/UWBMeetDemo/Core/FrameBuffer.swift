import Foundation

/// Length-prefixed records over TCP. Supports fragmented headers and coalesced records.
struct FrameBuffer {
    static let maximum = 65_536
    enum Failure: Error { case invalidLength }
    private var buffer = Data()

    static func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximum else { throw Failure.invalidLength }
        let n = UInt32(payload.count)
        var result = Data([UInt8((n >> 24) & 255), UInt8((n >> 16) & 255),
                           UInt8((n >> 8) & 255), UInt8(n & 255)])
        result.append(payload)
        return result
    }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var records: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= Self.maximum else { throw Failure.invalidLength }
            guard buffer.count >= length + 4 else { break }
            records.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(length + 4))
        }
        return records
    }
}

