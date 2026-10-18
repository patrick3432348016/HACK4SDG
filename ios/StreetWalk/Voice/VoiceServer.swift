import Foundation
import Network
import Observation

/// Voice server combines B's Doubao recognition, understanding and Xiaohe speech with App business services.
/// Doubao is default since 2026-10-12; --voice=sovits selects the legacy Cantonese-only synthesis path without recognition.
///
/// Discovery order: manual Settings URL, then same-Wi-Fi Bonjour _jiefongvoice._tcp with URL TXT record,
/// then simulator localhost at http://127.0.0.1:8765. Probe /v1/voice and use the first available candidate.
/// Unavailable servers fall back to system speech and limited TemplateAI understanding; arbitrary natural-language capability is not equivalent.
@MainActor
@Observable
final class VoiceServer {
    static let shared = VoiceServer()
    nonisolated static let defaultPort = 8765
    static let serviceType = "_jiefongvoice._tcp"

    enum Status: Equatable {
        /// Not found or discovery not started.
        case searching
        /// Server found but model loading, roughly 20 seconds; temporarily use system speech.
        case warming(URL)
        case connected(URL, voiceID: String, assistant: Bool)
        /// Known address is unreachable, for example sleeping server or different Wi-Fi.
        case unreachable(URL?)

        var url: URL? {
            switch self {
            case .warming(let u), .connected(let u, _, _): return u
            case .unreachable(let u): return u
            case .searching: return nil
            }
        }
        /// Settings display text.
        var label: String {
            switch self {
            case .connected: return L.t("已連線", "已连接", "Connected")
            case .warming: return L.t("準備緊（載入聲音）", "准备中（加载声音）", "Getting ready (loading voice)")
            case .searching, .unreachable: return L.t("未連線", "未连接", "Offline")
            }
        }
        var isConnected: Bool { if case .connected = self { return true }; return false }
    }

    /// Response from /v1/voice.
    struct Info: Decodable, Equatable {
        var service: String
        var tts: String?
        var voice_id: String?
        var status: String
        var assistant: String?
        /// Advertised synthesis locales; use the response rather than assuming all providers support every language.
        var locales: [String]?
        /// Whether /v1/voice/ear supports Doubao streaming recognition for continuous conversation.
        var ear: Bool?
    }

    private(set) var status: Status = .searching
    /// Manual Settings address; empty selects discovery.
    var manualURL: String {
        didSet {
            defaults.set(manualURL, forKey: Self.manualKey)
            recheckSoon()
        }
    }
    /// Bonjour-discovered address.
    private(set) var discovered: [URL] = []
    /// Capabilities of the connected server from /v1/voice.
    private(set) var info: Info?

    /// Model-ready server available for synthesis.
    var speechURL: URL? { if case .connected(let u, let v, _) = status, !v.isEmpty { return u }; return nil }
    var voiceID: String? { if case .connected(_, let v, _) = status, !v.isEmpty { return v }; return nil }
    /// Server with Supabase business mode enabled for assistant requests.
    var assistantURL: URL? { if case .connected(let u, _, true) = status { return u }; return nil }
    /// Mandarin synthesis capability; Doubao supports it, legacy GPT-SoVITS does not.
    var speaksMandarin: Bool { speechURL != nil && (info?.locales ?? []).contains("zh-CN") }
    /// English synthesis capability advertised as en-US.
    var speaksEnglish: Bool { speechURL != nil && (info?.locales ?? []).contains("en-US") }
    /// Map HTTP/HTTPS to WS/WSS for Doubao streaming recognition.
    var earURL: URL? {
        guard case .connected(let u, _, _) = status, info?.ear == true,
              var c = URLComponents(url: u.appendingPathComponent("v1/voice/ear"), resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = c.scheme == "https" ? "wss" : "ws"
        return c.url
    }

    /// Consecutive synthesis failures trigger disconnection and rediscovery.
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    /// Connection-change callback for warmup and Settings.
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

    // MARK: - Discovery

    /// Call once after launch; unit tests omit it to avoid network access.
    func start() {
        guard !started, !LaunchArgs.has("-noVoiceServer") else { return }
        started = true
        startBrowsing()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.check()
                // Probe connected servers every minute, otherwise retry every 10 seconds during startup / loading.
                let wait: Double = self.status.isConnected ? 60 : 10
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func recheckSoon() {
        guard started else { return }
        Task { await check() }
    }

    /// Two consecutive speech or assistant failures mark disconnected and trigger immediate discovery.
    func noteFailure() {
        failures += 1
        if failures >= 2 {
            failures = 0
            if let u = status.url { status = .unreachable(u) }
            recheckSoon()
        }
    }

    func noteSuccess() { failures = 0 }

    /// Probe each candidate's /v1/voice endpoint.
    func check() async {
        let list = Self.candidates(manual: manualURL, discovered: discovered, simulator: Self.isSimulator)
        for url in list {
            guard let info = await probe(url) else { continue }
            self.info = info
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

    // MARK: - Pure, unit-tested logic

    /// Deduplicated candidate order: manual, Bonjour, then simulator localhost.
    nonisolated static func candidates(manual: String, discovered: [URL], simulator: Bool) -> [URL] {
        var out: [URL] = []
        if let m = normalize(manual) { out.append(m) }
        out += discovered
        if simulator, let local = URL(string: "http://127.0.0.1:\(defaultPort)") { out.append(local) }
        var seen = Set<String>()
        return out.filter { seen.insert($0.absoluteString).inserted }
    }

    /// Normalize Settings input: add http:// if absent and port 8765 without an explicit port unless HTTPS; invalid/empty yields nil.
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
            // While loading or with an empty voiceID, use system output even if assistant service is available.
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
