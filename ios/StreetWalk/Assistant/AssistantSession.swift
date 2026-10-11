import Foundation

/// 组员 B 嘅 AssistantViewModel 规则搬入嚟（冇用佢嘅界面，界面用我哋原有嘅复述卡）：
/// - 撳「好」之前先记低 draft id（UserDefaults，按服务器 + 登录用户分开），超时 / 闪退之后用同一个 id 查结果，唔会盲目再做一次；
/// - 结果「未知」（uncertain）时唔准开新请求，只可以「查結果」；
/// - 换用户 / 换服务器 = 换 identityScope，唔会读到人哋嘅待查操作；
/// - 会话过期（SESSION_NOT_FOUND）或者联系人变咗（CONTACT_CHANGED）就重新开始。
@MainActor
final class AssistantSession {
    private(set) var conversationID: String?
    private(set) var lastReply: AssistantReply?
    private(set) var unresolvedDraftID: String?
    /// 今次对话讲过嘅句子（复述卡「我聽到」用）。
    var heard = ""
    private var client: AssistantClient?
    private var scope = ""
    private let defaults: UserDefaults
    /// 上传过嘅地点资料（一样就唔再传）。
    private var uploadedContext: (scope: String, body: AssistantContextUpload, at: Date)?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var recoveryKey: String { "MobilityAssistant.pending." + scope }

    /// 用边个服务器、边个用户。变咗就重新开始（旧对话唔再用）。
    func configure(baseURL: URL, userID: String, session: URLSession? = nil, token: @escaping AssistantClient.TokenProvider) {
        let newScope = "supabase:\(userID):\(baseURL.absoluteString)"
        guard newScope != scope || client == nil else { return }
        scope = newScope
        client = try? AssistantClient(baseURL: baseURL, session: session, allowInsecureDevelopmentHTTP: true, tokenProvider: token)
        conversationID = nil
        lastReply = nil
        unresolvedDraftID = defaults.string(forKey: recoveryKey)
    }

    var isConfigured: Bool { client != nil }

    func reset() {
        heard = ""
        guard unresolvedDraftID == nil else { return }
        conversationID = nil
        lastReply = nil
    }

    private func use() throws -> AssistantClient {
        guard let client else { throw AssistantAPIError(code: "NOT_CONFIGURED", message: "未連到語音伺服器。") }
        return client
    }

    func upload(_ body: AssistantContextUpload, now: Date = Date()) async throws {
        if let u = uploadedContext, u.scope == scope, u.body == body, now.timeIntervalSince(u.at) < 600 { return }
        _ = try await use().uploadContext(body)
        uploadedContext = (scope, body, now)
    }

    func turn(_ text: String) async throws -> AssistantReply {
        guard unresolvedDraftID == nil else {
            throw AssistantAPIError(code: "ACTION_UNRESOLVED", message: "上次操作結果未知，請先查結果。")
        }
        return try await run { try await $0.turn(text: text, locale: .cantonese, conversationID: self.conversationID) }
    }

    func choose(kind: String, value: String) async throws -> AssistantReply {
        guard let id = conversationID else { throw AssistantAPIError(code: "SESSION_NOT_FOUND", message: "對話已經完咗。") }
        return try await run { try await $0.choose(conversationID: id, kind: kind, value: value) }
    }

    func confirm(draftID: String) async throws -> AssistantReply {
        // 送出之前先记低：超时 / 闪退之后唔可以盲目再做一次（B 嘅规则）。
        remember(draftID)
        return try await run { try await $0.confirm(draftID: draftID) }
    }

    func cancel(draftID: String) async throws -> AssistantReply {
        try await run { try await $0.cancel(draftID: draftID) }
    }

    func reconcile() async throws -> AssistantReply? {
        guard let id = unresolvedDraftID ?? lastReply?.draftId else { return nil }
        return try await run { try await $0.reconcile(draftID: id) }
    }

    private func run(_ op: (AssistantClient) async throws -> AssistantReply) async throws -> AssistantReply {
        do {
            let r = try await op(use())
            accept(r)
            return r
        } catch let e as AssistantAPIError where e.code == "SESSION_NOT_FOUND" || e.code == "CONTACT_CHANGED" {
            conversationID = nil
            lastReply = nil
            throw e
        }
    }

    private func accept(_ r: AssistantReply) {
        lastReply = r
        conversationID = r.conversationId
        if r.status == .uncertain { remember(r.draftId) } else { remember(nil) }
        if [.completed, .cancelled].contains(r.status) { conversationID = nil; heard = "" }
    }

    private func remember(_ id: String?) {
        unresolvedDraftID = id
        if let id { defaults.set(id, forKey: recoveryKey) } else { defaults.removeObject(forKey: recoveryKey) }
    }
}
