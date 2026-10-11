import Foundation

// 组员 B 嘅语音助手（MobilityAssistant Swift 包，Sources/MobilityAssistant/Models.swift）抄入嚟用，冇改佢嘅字段同状态。
// 成员 A 改动（2026-10-11）：
// - 唔用 Swift 包（免改 pbxproj），直接放喺 App 入面；去掉 public。
// - JSONValue 改名 AssistantJSON（App 入面已经有一个 JSONValue，见 Backend/BackendJSON.swift）。
// - AssistantReply 加 command（B 服务器本来就有回传，App 要用嚟出粤语复述卡）。

enum AssistantLocale: String, CaseIterable, Codable, Sendable {
    case cantonese = "zh-HK"
    case mandarin = "zh-CN"
    var label: String { self == .cantonese ? "粵語" : "普通话" }
}

struct AssistantCapabilities: Decodable, Sendable {
    let mode: String
    let speech: Bool
    let languageModel: Bool
    let interpretation: String
    let business: String
    let maxAudioSeconds: Int
}

struct AssistantChoice: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let detail: String
}

enum ReplyStatus: String, Decodable, Sendable {
    case needsInput = "needs_input", chooseContact = "choose_contact", choosePlace = "choose_place"
    case needsConfirmation = "needs_confirmation", completed, cancelled, uncertain, info
}

enum AssistantJSON: Decodable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: AssistantJSON]), array([AssistantJSON]), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([String: AssistantJSON].self) { self = .object(v) }
        else { self = .array(try value.decode([AssistantJSON].self)) }
    }
    var display: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.formatted()
        case .bool(let b): return b ? "是" : "否"
        default: return ""
        }
    }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var number: Double? { if case .number(let n) = self { return n }; return nil }
    subscript(key: String) -> AssistantJSON? { if case .object(let o) = self { return o[key] }; return nil }
}

/// B 服务器解析出嚟嘅指令（Command 模型）。冇讲到嘅字段系 nil。
struct AssistantCommand: Decodable, Sendable, Equatable {
    var intent: String = "help"
    var contactQuery: String?
    var startsAt: String?
    var leaveDate: String?
    var newName: String?
    var landmarkQuery: String?
    var preferShade: Bool?
    var maxWalkMinutes: Int?
}

struct AssistantReply: Decodable, Sendable, Equatable {
    let conversationId: String
    let status: ReplyStatus
    let message: String
    let speechText: String
    var command: AssistantCommand? = nil
    let choices: [AssistantChoice]
    let draftId: String?
    let data: [String: AssistantJSON]
    let demo: Bool
}

struct AssistantAPIError: Error, LocalizedError, Sendable {
    let code: String
    let message: String
    let requestId: String?
    var errorDescription: String? { message }
    init(code: String, message: String, requestId: String? = nil) {
        self.code = code; self.message = message; self.requestId = requestId
    }
}

struct AssistantErrorEnvelope: Decodable {
    struct Body: Decodable { let code: String; let message: String; let requestId: String? }
    let error: Body
}

enum AssistantCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

// MARK: - 成员 A 加：上传俾服务器嘅地点 / 步行 / 遮荫（冇坐标）

struct AssistantContextUpload: Encodable, Equatable {
    struct Slot: Encodable, Equatable {
        var start: String
        var end: String
        var fraction: Double
    }
    struct Place: Encodable, Equatable {
        var id: String
        var name: String
        var publish_name: String?
        var has_seat: Bool
        var self_walk_minutes: Double?
        var contact_walk_minutes: [String: Double]
        var shade: [Slot]
    }
    var places: [Place]
    var walk_source: String
    var shade_source: String
}
