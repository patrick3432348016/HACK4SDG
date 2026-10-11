import Foundation

// 组员 B 嘅 AssistantClient（MobilityAssistant/AssistantClient.swift）抄入嚟。保留：唔跟转址、HTTPS 规则（HTTP 只准 Debug）、
// 错误信封、ID 校验、每次请求先攞 token。成员 A 改动：去掉 public；加 uploadContext（POST /v1/assistant/context）；
// 请求超时由 40 秒改 12 秒（App 等唔到就退返手机模板，唔好令长者干等）；冇用到嘅录音转写 / 云端播报接口删咗
//（录音用手机自己嘅粤语识别，播报用 Speaker）。

private final class RejectAssistantRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Pass A's current login token through this closure; never put vendor keys in an app.
actor AssistantClient {
    typealias TokenProvider = @Sendable () async throws -> String
    private let baseURL: URL
    private let tokenProvider: TokenProvider
    private let session: URLSession

    init(baseURL: URL, session: URLSession? = nil, allowInsecureDevelopmentHTTP: Bool = false,
         tokenProvider: @escaping TokenProvider) throws {
        guard baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil else {
            throw AssistantAPIError(code: "INVALID_URL", message: "服务地址无效。")
        }
        var insecureAllowed = false
        #if DEBUG
        insecureAllowed = allowInsecureDevelopmentHTTP && baseURL.scheme == "http"
        #endif
        guard baseURL.scheme == "https" || insecureAllowed else {
            throw AssistantAPIError(code: "HTTPS_REQUIRED", message: "正式连接必须使用 HTTPS。")
        }
        self.baseURL = baseURL; self.tokenProvider = tokenProvider
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration, delegate: RejectAssistantRedirects(), delegateQueue: nil)
        }
    }

    private func request(_ path: String, method: String = "POST", body: Data? = nil,
                         contentType: String = "application/json", query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer " + (try await tokenProvider()), forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AssistantAPIError(code: "INVALID_RESPONSE", message: "服务响应无效。")
        }
        guard (200..<300).contains(response.statusCode) else {
            if let envelope = try? AssistantCoding.decoder().decode(AssistantErrorEnvelope.self, from: data) {
                throw AssistantAPIError(code: envelope.error.code, message: envelope.error.message, requestId: envelope.error.requestId)
            }
            throw AssistantAPIError(code: "HTTP_\(response.statusCode)", message: "服务暂时不可用，请稍后重试。")
        }
        return data
    }

    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func reply(_ data: Data) throws -> AssistantReply {
        do { return try AssistantCoding.decoder().decode(AssistantReply.self, from: data) }
        catch { throw AssistantAPIError(code: "INVALID_RESPONSE", message: "结果格式不兼容，请检查服务端版本。") }
    }
    private func validID(_ value: String) throws -> String {
        guard value.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else {
            throw AssistantAPIError(code: "INVALID_ID", message: "操作标识无效。")
        }
        return value
    }

    func capabilities() async throws -> AssistantCapabilities {
        try await AssistantCoding.decoder().decode(AssistantCapabilities.self, from: request("v1/capabilities", method: "GET"))
    }
    func turn(text: String, locale: AssistantLocale, conversationID: String?) async throws -> AssistantReply {
        var body: [String: Any] = ["text": text, "locale": locale.rawValue]
        if let conversationID { body["conversation_id"] = try validID(conversationID) }
        return try await reply(request("v1/assistant/turn", body: json(body)))
    }
    func choose(conversationID: String, kind: String, value: String) async throws -> AssistantReply {
        guard ["contact", "place"].contains(kind) else { throw AssistantAPIError(code: "INVALID_CHOICE", message: "选项类型无效。") }
        return try await reply(request("v1/conversations/\(validID(conversationID))/choice", body: json(["kind": kind, "value": value])))
    }
    func confirm(draftID: String) async throws -> AssistantReply {
        try await reply(request("v1/drafts/\(validID(draftID))/confirm"))
    }
    func cancel(draftID: String) async throws -> AssistantReply {
        try await reply(request("v1/drafts/\(validID(draftID))/cancel"))
    }
    func reconcile(draftID: String) async throws -> AssistantReply {
        try await reply(request("v1/drafts/\(validID(draftID))/reconcile"))
    }
    /// 成员 A 加：上传而家嘅地标、步行分钟、遮荫（冇坐标）。返回服务器记低嘅版本。
    func uploadContext(_ body: AssistantContextUpload) async throws -> String {
        struct R: Decodable { let version: String }
        let data = try await request("v1/assistant/context", body: JSONEncoder().encode(body))
        return try JSONDecoder().decode(R.self, from: data).version
    }
}
