import AVFoundation
import CryptoKit
import Foundation

// Mac 语音服务器嘅真人声播放：边收边播（WAV / PCM16 单声道），播过嘅句子存喺手机（离线都即刻播到）。
// 走边条路由 TTSRoute 决定；Speaker 负责后备（系统声音）同排队语义。

// MARK: - 揀边把声（纯逻辑，有单元测试）

enum TTSRoute: Equatable {
    /// 手机系统声音（AVSpeechSynthesizer）。
    case system
    /// 手机已经存咗呢句（之前由服务器播过）：即刻播，唔使网络。
    case cached(URL)
    /// 问 Mac 服务器（边收边播；6 秒都未有声就转系统声音）。
    case server(URL)

    /// - language：而家播报语言（服务器只有粤语）
    /// - server：可以用嘅服务器（模型准备好）；nil = 冇
    /// - cached：手机缓存入面呢句嘅档案
    /// - scripted：自动演示脚本（-script…）：画面同声音要对得准，冇缓存就唔等服务器
    static func decide(language: SpokenLanguage, server: URL?, cached: URL?, scripted: Bool) -> TTSRoute {
        guard language == .cantonese else { return .system }
        if let cached { return .cached(cached) }
        if scripted { return .system }
        if let server { return .server(server) }
        return .system
    }

    /// 服务器几耐都未出声就放弃（秒）。
    static let firstAudioTimeout: TimeInterval = 6
    /// 开始咗之后几耐冇新数据当断线（秒）。
    static let stallTimeout: TimeInterval = 10

    /// 设定「語速」→ 服务器 speed_factor。
    static func speed(_ pace: SpeechPace) -> Double {
        switch pace {
        case .slow: return 0.9
        case .normal: return 1.0
        case .fast: return 1.1
        }
    }
}

// MARK: - 解析流式 WAV（纯逻辑，有单元测试）

/// 一段段收到嘅字节 → 头（采样率）+ PCM16 样本。头入面嘅长度可能系 0xFFFFFFFF（流式），唔理佢。
struct StreamingWAVParser {
    private(set) var sampleRate: Int?
    private(set) var channels = 1
    private var buffer = Data()
    private var headerDone = false
    private(set) var failed = false

    /// 喂入新字节，返回可以播嘅样本（整数个；单数字节留低等下一段）。
    mutating func feed(_ data: Data) -> [Int16] {
        guard !failed else { return [] }
        buffer.append(data)
        if !headerDone {
            guard let start = parseHeader() else { return [] }
            buffer.removeFirst(start)
            headerDone = true
        }
        let usable = buffer.count - buffer.count % 2
        guard usable > 0 else { return [] }
        var out = [Int16](repeating: 0, count: usable / 2)
        buffer.prefix(usable).withUnsafeBytes { raw in
            for i in 0..<out.count { out[i] = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self)) }
        }
        buffer.removeFirst(usable)
        return out
    }

    /// 搵到 "data" 块就返回 PCM 开始位置；未够字节返回 nil；唔系 PCM16 WAV 就标记失败。
    private mutating func parseHeader() -> Int? {
        let b = [UInt8](buffer)
        // 一开头唔系 "RIFF"（例如服务器答咗 JSON 错误）：即刻当失败
        if !b.prefix(4).elementsEqual("RIFF".utf8.prefix(min(4, b.count))) { failed = true; return nil }
        guard b.count >= 12 else { return nil }
        guard b[0..<4].elementsEqual("RIFF".utf8), b[8..<12].elementsEqual("WAVE".utf8) else { failed = true; return nil }
        var i = 12
        while i + 8 <= b.count {
            let id = String(decoding: b[i..<i + 4], as: UTF8.self)
            let size = Int(UInt32(b[i + 4]) | UInt32(b[i + 5]) << 8 | UInt32(b[i + 6]) << 16 | UInt32(b[i + 7]) << 24)
            if id == "fmt " {
                guard i + 8 + 16 <= b.count else { return nil }
                let f = i + 8
                let format = Int(b[f]) | Int(b[f + 1]) << 8
                channels = Int(b[f + 2]) | Int(b[f + 3]) << 8
                sampleRate = Int(UInt32(b[f + 4]) | UInt32(b[f + 5]) << 8 | UInt32(b[f + 6]) << 16 | UInt32(b[f + 7]) << 24)
                let bits = Int(b[f + 14]) | Int(b[f + 15]) << 8
                guard format == 1, bits == 16, channels == 1, (8000...48000).contains(sampleRate ?? 0) else { failed = true; return nil }
                i = f + size
            } else if id == "data" {
                if sampleRate == nil { failed = true; return nil }
                return i + 8
            } else {
                i += 8 + size
            }
        }
        return nil
    }
}

// MARK: - 手机上嘅缓存

/// 播过嘅句子（Caches/voice-cache/*.wav）。key = 声音版本 + 语速 + 文字。最多留 300 句（旧嘅先删）。
enum SpeechAudioCache {
    static let limit = 300

    static var directory: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("voice-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func key(text: String, voiceID: String, speed: Double) -> String {
        let raw = "\(voiceID)\n\(String(format: "%.2f", speed))\n\(text)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func file(for key: String, in dir: URL = directory) -> URL? {
        let u = dir.appendingPathComponent(key + ".wav")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    static func store(_ pcm: Data, sampleRate: Int, key: String, in dir: URL = directory) {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: "RIFF".utf8); u32(36 + pcm.count); d.append(contentsOf: "WAVEfmt ".utf8)
        u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append(contentsOf: "data".utf8); u32(pcm.count)
        d.append(pcm)
        try? d.write(to: dir.appendingPathComponent(key + ".wav"), options: .atomic)
        trim(dir)
    }

    static func trim(_ dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > limit else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        for f in sorted.prefix(files.count - limit) { try? fm.removeItem(at: f) }
    }
}

// MARK: - 播放

/// 边收边播。一次一句；stop() 即刻停（开咪、下一句、播报关）。
@MainActor
final class ServerSpeechPlayer: NSObject {
    enum Outcome { case finished, failedBeforeAudio, stopped }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var connectedRate: Double?
    private var parser = StreamingWAVParser()
    private var pcm = Data()
    private var pendingSamples: [Int16] = []
    private var scheduled = 0
    private var streamEnded = false
    private var playing = false
    private var gotAudio = false
    private var lastData = Date()
    private var generation = 0
    private var task: URLSessionDataTask?
    private var watchdog: Task<Void, Never>?
    private var completion: ((Outcome) -> Void)?
    private var cacheKey: String?
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        return URLSession(configuration: cfg, delegate: StreamDelegate(owner: self), delegateQueue: nil)
    }()

    /// 播之前收集够几多秒先开始（生成速度大约等于实时，太早开始会断断续续）。
    static let preroll: Double = 0.8
    /// 由开始请求到第一段声音几耐（秒），测量用（debug-state、日志）。
    private(set) var lastFirstAudio: TimeInterval?
    private var requestedAt = Date()

    var isActive: Bool { completion != nil }

    override init() {
        super.init()
        engine.attach(node)
    }

    /// 问服务器要一句，边收边播。cacheKey：播完就存手机。
    func stream(text: String, server: URL, speed: Double, token: String?, cacheKey: String?, done: @escaping (Outcome) -> Void) {
        stop()
        generation += 1
        let gen = generation
        begin(done: done, cacheKey: cacheKey)
        var req = URLRequest(url: server.appendingPathComponent("v1/speech/synthesize"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/wav", forHTTPHeaderField: "Accept")
        // 登录 token 只经 HTTPS 送（局域网 HTTP 唔使登录）
        if let token, server.scheme == "https" { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "locale": "zh-HK", "speed": speed])
        let t = session.dataTask(with: req)
        t.taskDescription = String(gen)
        task = t
        t.resume()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.generation == gen, self.isActive else { return }
                let idle = Date().timeIntervalSince(self.gotAudio ? self.lastData : self.requestedAt)
                if !self.gotAudio && idle > TTSRoute.firstAudioTimeout { self.finish(.failedBeforeAudio); return }
                if self.gotAudio && !self.streamEnded && idle > TTSRoute.stallTimeout { self.endOfStream(gen, ok: true); return }
            }
        }
    }

    /// 播手机存咗嘅一句。
    func play(file: URL, done: @escaping (Outcome) -> Void) {
        stop()
        generation += 1
        begin(done: done, cacheKey: nil)
        guard let data = try? Data(contentsOf: file) else { finish(.failedBeforeAudio); return }
        receive(data, gen: generation)
        endOfStream(generation, ok: true)
    }

    func stop() {
        guard isActive else { return }
        finish(.stopped)
    }

    private func begin(done: @escaping (Outcome) -> Void, cacheKey: String?) {
        completion = done
        self.cacheKey = cacheKey
        parser = StreamingWAVParser()
        pcm = Data()
        pendingSamples = []
        scheduled = 0
        streamEnded = false
        playing = false
        gotAudio = false
        requestedAt = Date()
        lastData = Date()
    }

    private func finish(_ outcome: Outcome) {
        let done = completion
        completion = nil
        generation += 1
        task?.cancel()
        task = nil
        watchdog?.cancel()
        watchdog = nil
        node.stop()
        engine.stop()
        playing = false
        if outcome == .finished, let key = cacheKey, let rate = parser.sampleRate, !pcm.isEmpty {
            let data = pcm
            Task.detached(priority: .utility) { SpeechAudioCache.store(data, sampleRate: rate, key: key) }
        }
        done?(outcome)
    }

    // MARK: 收数据（由 StreamDelegate 转返主线程）

    fileprivate func receive(_ data: Data, gen: Int) {
        guard gen == generation, isActive else { return }
        let samples = parser.feed(data)
        if parser.failed { finish(gotAudio ? .finished : .failedBeforeAudio); return }
        guard !samples.isEmpty else { return }
        if !gotAudio {
            gotAudio = true
            lastFirstAudio = Date().timeIntervalSince(requestedAt)
        }
        lastData = Date()
        samples.withUnsafeBufferPointer { pcm.append(Data(buffer: $0)) }
        pendingSamples += samples
        pump()
    }

    fileprivate func endOfStream(_ gen: Int, ok: Bool) {
        guard gen == generation, isActive else { return }
        if !gotAudio { finish(.failedBeforeAudio); return }
        streamEnded = true
        pump()
        if scheduled == 0 && pendingSamples.isEmpty { finish(.finished) }
    }

    /// 够 preroll 就开始播；之后每收到约 0.15 秒就排一段。
    private func pump() {
        guard let rate = parser.sampleRate else { return }
        let minimum = playing ? Int(Double(rate) * 0.15) : Int(Double(rate) * Self.preroll)
        guard pendingSamples.count >= minimum || (streamEnded && !pendingSamples.isEmpty) else { return }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false)!
        if connectedRate != Double(rate) {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            connectedRate = Double(rate)
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pendingSamples.count)),
              let ch = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(pendingSamples.count)
        for (i, s) in pendingSamples.enumerated() { ch[i] = Float(s) / 32768 }
        pendingSamples = []
        if !engine.isRunning {
            do { try engine.start() } catch { finish(gotAudio ? .finished : .failedBeforeAudio); return }
        }
        scheduled += 1
        let gen = generation
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, gen == self.generation, self.isActive else { return }
                self.scheduled -= 1
                if self.streamEnded && self.scheduled == 0 && self.pendingSamples.isEmpty { self.finish(.finished) }
            }
        }
        if !playing {
            playing = true
            node.play()
        }
    }
}

/// URLSession 回调喺背景线程：转返主线程交俾播放器。
private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var owner: ServerSpeechPlayer?
    init(owner: ServerSpeechPlayer) { self.owner = owner }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let ok = (response as? HTTPURLResponse)?.statusCode == 200
        completionHandler(ok ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let gen = Int(dataTask.taskDescription ?? "") ?? -1
        Task { @MainActor [weak self] in self?.owner?.receive(data, gen: gen) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let gen = Int(task.taskDescription ?? "") ?? -1
        Task { @MainActor [weak self] in self?.owner?.endOfStream(gen, ok: error == nil) }
    }
}

// MARK: - 预热

/// 连上服务器时叫佢先合成常用句子（排喺当场要讲嘅句子后面，唔会阻住）。之后呢啲句子一讲即出声。
enum VoicePrewarm {
    static let common = [
        "聽唔清楚。可以再講一次，或者揀一句。",
        "唔好意思，我未聽明白。可以再講一次，或者揀一句。",
        "撤回咗請假。",
        "撤回咗今日嘅請假。",
        "見到喇！",
        "偵測到你出咗門，開始記錄，唔使撳任何掣。",
        "將手機貼近對方手機。",
        "搵到對方部手機，慢慢貼近啲。",
        "開唔開出門提醒？開咗之後，佢出門你會知，你出門佢都會知。",
        "約邊個？揀一個街坊。",
        "取消咗，冇做任何嘢。",
        "你好，我係街坊行嘅廣東話聲，由你部 Mac 讀出嚟。",
    ]

    /// 第一轮：叫服务器排队合成（唔等）；已经合成好嘅就下载落手机（之后离线、演示脚本都用到真人声）。
    /// 90 秒后再行一轮，攞返第一轮未合成好嗰啲。
    static func run(server: URL, speed: Double, voiceID: String, phrases: [String] = common) {
        Task.detached(priority: .utility) {
            for round in 0..<2 {
                if round == 1 { try? await Task.sleep(for: .seconds(90)) }
                var missing = 0
                for text in phrases {
                    let key = SpeechAudioCache.key(text: text, voiceID: voiceID, speed: speed)
                    if SpeechAudioCache.file(for: key) != nil { continue }
                    guard let code = await post(server, text: text, speed: speed, prefetch: true)?.code else { return }
                    guard code == 200, let (_, data) = await post(server, text: text, speed: speed, prefetch: false), !data.isEmpty else {
                        missing += 1
                        continue
                    }
                    var parser = StreamingWAVParser()
                    let samples = parser.feed(data)
                    guard let rate = parser.sampleRate, !samples.isEmpty else { continue }
                    SpeechAudioCache.store(samples.withUnsafeBufferPointer { Data(buffer: $0) }, sampleRate: rate, key: key)
                }
                if missing == 0 { return }
            }
        }
    }

    private static func post(_ server: URL, text: String, speed: Double, prefetch: Bool) async -> (code: Int, data: Data)? {
        var req = URLRequest(url: server.appendingPathComponent("v1/speech/synthesize"))
        req.httpMethod = "POST"
        req.timeoutInterval = prefetch ? 5 : 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "locale": "zh-HK", "speed": speed, "prefetch": prefetch])
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }
}
