import Foundation
import Security

// Supabase 的最小客户端（唔用第三方包）：匿名登录 + 续期、PostgREST、RPC。只用 Foundation + Security。
// 用法见 supabase/tests/rls_test.py：每个请求带 apikey（publishable key）同 Authorization: Bearer <access_token>。

/// 登录状态（匿名用户）。access_token 一个钟过期，用 refresh_token 换新（每个 refresh_token 只用一次）。
struct BackendSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String

    /// 过期前 90 秒就续期。
    func isFresh(at now: Date = Date()) -> Bool { expiresAt.timeIntervalSince(now) > 90 }
}

enum BackendError: Error, Equatable, CustomStringConvertible {
    /// 冇网络 / 超时 / 服务器暂时唔得（5xx、429）：可以迟啲再试。
    case offline(String)
    /// 服务器拒绝（4xx）：再试都冇用（例如权限、格式）。
    case rejected(Int, String)
    /// 未登录（仲未同意 / 未建资料）。
    case notSignedIn

    var isRetryable: Bool { if case .offline = self { return true }; return false }
    var description: String {
        switch self {
        case .offline(let s): return "offline(\(s))"
        case .rejected(let c, let s): return "rejected(\(c), \(s.prefix(200)))"
        case .notSignedIn: return "notSignedIn"
        }
    }
}

/// 保存登录状态的地方：App 用钥匙圈（锁屏后台都读得到），命令行测试用内存。
protocol SessionStore: Sendable {
    func load() -> BackendSession?
    func save(_ s: BackendSession?)
}

struct KeychainSessionStore: SessionStore {
    var service = "hk.hack4sdg.streetwalk.backend"
    var account = "session"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> BackendSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(BackendSession.self, from: data)
    }

    func save(_ s: BackendSession?) {
        SecItemDelete(query as CFDictionary)
        guard let s, let data = try? JSONEncoder().encode(s) else { return }
        var q = query
        q[kSecValueData as String] = data
        // 第一次解锁之后背景都读得到（BGAppRefresh、定位唤醒时要用）。
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

final class MemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: BackendSession?
    init(_ s: BackendSession? = nil) { value = s }
    func load() -> BackendSession? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ s: BackendSession?) { lock.lock(); value = s; lock.unlock() }
}

/// HTTP 层。actor：续期只会同时做一次（refresh_token 用一次就作废，两个请求同时续期会令登录失效）。
actor SupabaseAPI {
    let baseURL: URL
    let apiKey: String
    private let store: SessionStore
    private let http: URLSession
    private var session: BackendSession?
    private var refreshing: Task<BackendSession, Error>?
    /// 每次换咗 token（登录、续期、登出）都通知（Realtime 要跟住换）。
    private var tokenListener: (@Sendable (String?) -> Void)?
    /// 打 log（开发用：-logBackend）。
    nonisolated let log: Bool

    init(baseURL: URL, apiKey: String, store: SessionStore, log: Bool = false) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.store = store
        self.log = log
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        http = URLSession(configuration: cfg)
        session = store.load()
    }

    func setTokenListener(_ f: (@Sendable (String?) -> Void)?) { tokenListener = f }

    var userID: String? { session?.userID }
    var isSignedIn: Bool { session != nil }

    /// 而家有效嘅 access token（快过期就先续期）。未登录返回 nil。
    func accessToken() async throws -> String? {
        guard let s = session else { return nil }
        if s.isFresh() { return s.accessToken }
        return try await refresh().accessToken
    }

    /// 匿名登录（只喺用户同意、完成首次使用之后先叫）。已经登录就直接返回。
    @discardableResult
    func signInAnonymously() async throws -> BackendSession {
        if let s = session { return s }
        let data = try await send(method: "POST", path: "/auth/v1/signup", body: Data("{}".utf8), auth: nil, prefer: nil)
        let s = try Self.parseSession(data)
        setSession(s)
        return s
    }

    func signOut() {
        refreshing?.cancel()
        refreshing = nil
        setSession(nil)
    }

    private func setSession(_ s: BackendSession?) {
        session = s
        store.save(s)
        tokenListener?(s?.accessToken)
    }

    private func refresh() async throws -> BackendSession {
        if let t = refreshing { return try await t.value }
        guard let s = session else { throw BackendError.notSignedIn }
        let t = Task { () throws -> BackendSession in
            let body = try JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
            return try Self.parseSession(try await self.send(method: "POST", path: "/auth/v1/token", query: "grant_type=refresh_token",
                                                              body: body, auth: nil, prefer: nil))
        }
        refreshing = t
        defer { refreshing = nil }
        do {
            let new = try await t.value
            setSession(new)
            return new
        } catch BackendError.rejected(let code, let msg) where code == 400 || code == 401 || code == 403 {
            // refresh_token 作废（用户俾人删咗）：登出，下次重新匿名登录。
            if log { print("[backend] refresh rejected \(code) \(msg) → sign out") }
            if session?.refreshToken == s.refreshToken { setSession(nil) }
            throw BackendError.notSignedIn
        }
    }

    static func parseSession(_ data: Data) throws -> BackendSession {
        struct R: Decodable {
            struct U: Decodable { let id: String }
            let access_token: String
            let refresh_token: String
            let expires_in: Double?
            let expires_at: Double?
            let user: U
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        let exp = r.expires_at.map { Date(timeIntervalSince1970: $0) } ?? Date().addingTimeInterval(r.expires_in ?? 3600)
        return BackendSession(accessToken: r.access_token, refreshToken: r.refresh_token, expiresAt: exp, userID: r.user.id.lowercased())
    }

    // MARK: - 请求

    /// 已登录请求：带 token；401 就续期再试一次。
    func request(_ method: String, _ path: String, query: String? = nil, body: Data? = nil, prefer: String? = nil) async throws -> Data {
        guard let token = try await accessToken() else { throw BackendError.notSignedIn }
        do {
            return try await send(method: method, path: path, query: query, body: body, auth: token, prefer: prefer)
        } catch BackendError.rejected(401, _) {
            let t = try await refresh().accessToken
            return try await send(method: method, path: path, query: query, body: body, auth: t, prefer: prefer)
        }
    }

    func rpc<T: Decodable>(_ fn: String, _ args: [String: JSONValue] = [:], as: T.Type = T.self) async throws -> T {
        let data = try await request("POST", "/rest/v1/rpc/\(fn)", body: try BackendCoding.encoder.encode(args))
        return try decode(T.self, data)
    }

    func select<T: Decodable>(_ table: String, query: String, as: T.Type = T.self) async throws -> T {
        try decode(T.self, try await request("GET", "/rest/v1/\(table)", query: query))
    }

    /// upsert（插入，有冲突就合并更新）：只更新 body 入面有嘅栏。
    func upsert<B: Encodable>(_ table: String, _ body: B, onConflict: String) async throws {
        _ = try await request("POST", "/rest/v1/\(table)", query: "on_conflict=\(onConflict)",
                              body: try BackendCoding.encoder.encode(body), prefer: "resolution=merge-duplicates,return=minimal")
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try BackendCoding.decoder.decode(T.self, from: data) }
        catch { throw BackendError.rejected(0, "decode \(T.self): \(error) body=\(String(decoding: data.prefix(300), as: UTF8.self))") }
    }

    private func send(method: String, path: String, query: String? = nil, body: Data?, auth: String?, prefer: String?) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let query { comps.percentEncodedQuery = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth { req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await http.data(for: req)
        } catch {
            if log { print("[backend] \(method) \(path) ✗ \(error.localizedDescription)") }
            throw BackendError.offline(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if log { print("[backend] \(method) \(path)\(query.map { "?" + $0.prefix(80) } ?? "") → \(code)") }
        switch code {
        case 200..<300: return data
        case 408, 429, 500...599: throw BackendError.offline("HTTP \(code)")
        default: throw BackendError.rejected(code, String(decoding: data.prefix(500), as: UTF8.self))
        }
    }
}

/// PostgREST 查询参数要编码（uuid、日期入面有 : + 等字符）。
enum PG {
    static func q(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
