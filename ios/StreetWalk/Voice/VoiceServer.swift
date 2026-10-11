import Foundation
import Network
import Observation

/// Mac 语音服务器（tools/voice_server.sh）：粤语真人声（GPT-SoVITS）+ 组员 B 嘅语音助手。
///
/// 点搵：① 设定 → 聲音 →「語音伺服器」亲手填嘅地址；② 同一个 Wi-Fi 用 Bonjour（_jiefongvoice._tcp，TXT 带 url）自动搵；
/// ③ 模拟器再试本机 http://127.0.0.1:8765。逐个问 GET /v1/voice，第一个答到就用。
/// 连唔到 / 未开：播报用系统声音，语音助手用手机入面嘅模板（TemplateAI），功能唔会少。
@MainActor
@Observable
final class VoiceServer {
    static let shared = VoiceServer()
    nonisolated static let defaultPort = 8765
    static let serviceType = "_jiefongvoice._tcp"

    enum Status: Equatable {
        /// 未搵到（或者未开始搵）。
        case searching
        /// 搵到，声音模型载入中（约 20 秒）：播报暂时用系统声音。
        case warming(URL)
        case connected(URL, voiceID: String, assistant: Bool)
        /// 地址有，但问唔到（Mac 瞓咗 / 未开 / 唔同 Wi-Fi）。
        case unreachable(URL?)

        var url: URL? {
            switch self {
            case .warming(let u), .connected(let u, _, _): return u
            case .unreachable(let u): return u
            case .searching: return nil
            }
        }
        /// 设定页显示。
        var label: String {
            switch self {
            case .connected: return L.t("已連線", "已连接")
            case .warming: return L.t("準備緊（載入聲音）", "准备中（加载声音）")
            case .searching, .unreachable: return L.t("未連線", "未连接")
            }
        }
        var isConnected: Bool { if case .connected = self { return true }; return false }
    }

    /// 服务器 /v1/voice 嘅答覆。
    struct Info: Decodable, Equatable {
        var service: String
        var tts: String?
        var voice_id: String?
        var status: String
        var assistant: String?
    }

    private(set) var status: Status = .searching
    /// 设定页亲手填嘅地址（空 = 自动搵）。
    var manualURL: String {
        didSet {
            defaults.set(manualURL, forKey: Self.manualKey)
            recheckSoon()
        }
    }
    /// Bonjour 搵到嘅地址。
    private(set) var discovered: [URL] = []

    /// 播报用：而家可以用嘅服务器（模型准备好）。
    var speechURL: URL? { if case .connected(let u, let v, _) = status, !v.isEmpty { return u }; return nil }
    var voiceID: String? { if case .connected(_, let v, _) = status, !v.isEmpty { return v }; return nil }
    /// 语音助手用：服务器开咗 Supabase 业务模式。
    var assistantURL: URL? { if case .connected(let u, _, true) = status { return u }; return nil }

    /// 连续播报失败几多次（超过就当连唔到，重新搵）。
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    /// 接通 / 断线时通知（预热句子、设定页）。
    @ObservationIgnored var onConnected: ((URL) -> Void)?

    static let manualKey = "voice.serverURL"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        manualURL = LaunchArgs.value("-voiceServer") ?? defaults.string(forKey: Self.manualKey) ?? ""
        #else
        manualURL = defaults.string(forKey: Self.manualKey) ?? ""
        #endif
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 4
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    // MARK: - 开始搵

    /// App 启动后叫一次（单元测试唔叫，唔会连网络）。
    func start() {
        guard !started, !LaunchArgs.has("-noVoiceServer") else { return }
        started = true
        startBrowsing()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.check()
                // 连住：每分钟睇一次；未连：10 秒再试（服务器啱啱开、模型载入中）
                let wait: Double = self.status.isConnected ? 60 : 10
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func recheckSoon() {
        guard started else { return }
        Task { await check() }
    }

    /// 播报 / 助手请求失败：连续两次就当断咗，即刻重新搵。
    func noteFailure() {
        failures += 1
        if failures >= 2 {
            failures = 0
            if let u = status.url { status = .unreachable(u) }
            recheckSoon()
        }
    }

    func noteSuccess() { failures = 0 }

    /// 逐个候选地址问一次 /v1/voice。
    func check() async {
        let list = Self.candidates(manual: manualURL, discovered: discovered, simulator: Self.isSimulator)
        for url in list {
            guard let info = await probe(url) else { continue }
            let next = Self.status(for: url, info: info)
            let wasConnected = status.isConnected
            status = next
            if case .connected = next, !wasConnected {
                failures = 0
                onConnected?(url)
            }
            return
        }
        status = list.isEmpty ? .searching : .unreachable(Self.normalize(manualURL) ?? list.first)
    }

    private func probe(_ base: URL) async -> Info? {
        var req = URLRequest(url: base.appendingPathComponent("v1/voice"))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let info = try? JSONDecoder().decode(Info.self, from: data), info.service == "jiefong-voice" else { return nil }
        return info
    }

    // MARK: - 纯逻辑（有单元测试）

    /// 候选次序：亲手填 > Bonjour 搵到 > （模拟器）本机。去重。
    nonisolated static func candidates(manual: String, discovered: [URL], simulator: Bool) -> [URL] {
        var out: [URL] = []
        if let m = normalize(manual) { out.append(m) }
        out += discovered
        if simulator, let local = URL(string: "http://127.0.0.1:\(defaultPort)") { out.append(local) }
        var seen = Set<String>()
        return out.filter { seen.insert($0.absoluteString).inserted }
    }

    /// 设定页填嘅地址 → URL：冇写 http 就补 http://，冇写端口（又唔系 https）就补 8765。空 / 唔啱 → nil。
    nonisolated static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard var c = URLComponents(string: s), let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = c.host, !host.isEmpty else { return nil }
        if scheme == "http" && c.port == nil { c.port = defaultPort }
        c.path = ""
        c.query = nil
        c.fragment = nil
        return c.url
    }

    static func status(for url: URL, info: Info) -> Status {
        guard info.status == "ready", let v = info.voice_id else {
            // 模型载入中 / 冇声音（只有助手，voiceID 空）：播报暂时用系统声音
            if info.status == "loading" { return .warming(url) }
            return .connected(url, voiceID: "", assistant: info.assistant == "supabase")
        }
        return .connected(url, voiceID: v, assistant: info.assistant == "supabase")
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    // MARK: - Bonjour

    private func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let urls = results.compactMap { r -> URL? in
                if case .bonjour(let txt) = r.metadata, let s = txt["url"] { return VoiceServer.normalize(s) }
                return nil
            }
            Task { @MainActor in
                guard let self else { return }
                let changed = urls != self.discovered
                self.discovered = urls
                if changed && !self.status.isConnected { await self.check() }
            }
        }
        b.start(queue: .main)
        browser = b
    }
}
