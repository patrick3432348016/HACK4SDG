import AVFoundation
import CryptoKit
import Foundation

// Stream WAV / mono PCM16 from the voice server and cache completed utterances for immediate offline replay.
// TTSRoute chooses the path; Speaker owns system fallback and queue semantics.

// MARK: - Pure, unit-tested voice routing

enum TTSRoute: Equatable {
    /// Device system voice through AVSpeechSynthesizer.
    case system
    /// Replay a previously cached server utterance immediately without networking.
    case cached(URL)
    /// Stream from the Mac server, falling back after 6 seconds without audio.
    case server(URL)

    /// language: current spoken language.
    /// server: available model-ready server, or nil.
    /// cached: local audio file for this utterance.
    /// scripted: automated demos require timing alignment and do not wait for uncached server audio.
    /// mandarin: server supports Mandarin, as Doubao Xiaohe does but GPT-SoVITS does not.
    /// english: /v1/voice advertises en-US. Prefer server Xiaohe in all three languages, then device voices.
    static func decide(language: SpokenLanguage, server: URL?, cached: URL?, scripted: Bool, mandarin: Bool = false, english: Bool = false) -> TTSRoute {
        let serverSpeaks = switch language {
        case .cantonese: true
        case .mandarin: mandarin
        case .english: english
        }
        guard serverSpeaks else { return .system }
        if let cached { return .cached(cached) }
        if scripted { return .system }
        if let server { return .server(server) }
        return .system
    }

    /// Maximum wait for first server audio, in seconds.
    static let firstAudioTimeout: TimeInterval = 6
    /// Maximum silence between data chunks after playback begins, in seconds.
    static let stallTimeout: TimeInterval = 10

    /// Map speech speed to server range 0.7–1.3. Doubao offsets B's baseline speech_rate -15 by (speed - 1) * 100.
    /// Slow/normal/fast become -40/-15/+10; 10-17 testing found the previous 0.9/1.1 difference too subtle.
    static func speed(_ pace: SpeechPace) -> Double {
        switch pace {
        case .slow: return 0.75
        case .normal: return 1.0
        case .fast: return 1.25
        }
    }
}

// MARK: - Pure, unit-tested streaming WAV parser

/// Convert chunks into sample-rate metadata and PCM16 samples; ignore streaming length values such as 0xFFFFFFFF.
struct StreamingWAVParser {
    private(set) var sampleRate: Int?
    private(set) var channels = 1
    private var buffer = Data()
    private var headerDone = false
    private(set) var failed = false

    /// Return whole playable samples and retain an odd trailing byte for the next chunk.
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

    /// Return PCM start after finding data, nil if incomplete, or fail for non-PCM16 WAV.
    private mutating func parseHeader() -> Int? {
        let b = [UInt8](buffer)
        // Reject a non-RIFF prefix immediately, including JSON error replies.
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

// MARK: - Device cache

/// Caches/voice-cache/*.wav keyed by voice version, speed and text; retain at most 300 utterances, evicting oldest first.
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

// MARK: - Playback

/// Stream one utterance at a time; stop() immediately interrupts for microphone use, replacement or disabled output.
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

    /// Buffer this many seconds before playback because near-real-time synthesis can otherwise stutter.
    static let preroll: Double = 0.8
    /// Seconds from request start to first audio for debug-state and logs.
    private(set) var lastFirstAudio: TimeInterval?
    private var requestedAt = Date()

    var isActive: Bool { completion != nil }
    /// Continuous capture shares this voice-processing engine so output echo is suppressed and users can interrupt.
    private(set) var capturing = false

    override init() {
        super.init()
        engine.attach(node)
    }

    // MARK: Capture for Doubao streaming recognition, added 2026-10-12

    /// Start microphone and deliver 16 kHz mono PCM16 to onPCM on the audio thread; shared playback enables echo cancellation.
    func startCapture(_ onPCM: @escaping @Sendable (Data) -> Void) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true)
        engine.stop()
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: target) else {
            try? input.setVoiceProcessingEnabled(false)
            throw NSError(domain: "ServerSpeechPlayer", code: 1)
        }
        converter.downmix = true
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.tapBlock(converter: converter, target: target, onPCM: onPCM))
        if connectedRate == nil {
            // Connect the playback path before first engine start because voice processing requires both input and output.
            let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
            engine.connect(node, to: engine.mainMixerNode, format: f)
            connectedRate = 24000
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            try? input.setVoiceProcessingEnabled(false)
            throw error
        }
        capturing = true
    }

    /// Stop capture and playback, then restore a playback-only audio session.
    func stopCapture() {
        guard capturing else { return }
        stop()
        capturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    /// Convert to 16 kHz PCM16 on the audio thread, outside MainActor-isolated closures.
    nonisolated private static func tapBlock(converter: AVAudioConverter, target: AVAudioFormat,
                                             onPCM: @escaping @Sendable (Data) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, out.frameLength > 0, let ch = out.int16ChannelData?[0] else { return }
            onPCM(Data(bytes: ch, count: Int(out.frameLength) * 2))
        }
    }

    /// Request and stream an utterance; cacheKey saves it after completion.
    func stream(text: String, server: URL, speed: Double, token: String?, cacheKey: String?, locale: String = "zh-HK",
                done: @escaping (Outcome) -> Void) {
        stop()
        generation += 1
        let gen = generation
        begin(done: done, cacheKey: cacheKey)
        var req = URLRequest(url: server.appendingPathComponent("v1/speech/synthesize"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/wav", forHTTPHeaderField: "Accept")
        // Send authentication tokens only over HTTPS; LAN HTTP does not require login.
        if let token, server.scheme == "https" { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "locale": locale, "speed": speed])
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

    /// Play a cached device utterance.
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
        if !capturing { engine.stop() }   // Keep the engine running during continuous capture.
        playing = false
        if outcome == .finished, let key = cacheKey, let rate = parser.sampleRate, !pcm.isEmpty {
            let data = pcm
            Task.detached(priority: .utility) { SpeechAudioCache.store(data, sampleRate: rate, key: key) }
        }
        done?(outcome)
    }

    // MARK: Receive data transferred to the main thread by StreamDelegate

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

    /// Begin after preroll; then enqueue roughly 0.15-second chunks.
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

/// URLSession callbacks run off-main; dispatch playback handling to the main thread.
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

// MARK: - Warmup

/// On connection, synthesize common phrases behind immediate speech requests so later playback starts quickly.
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

    /// First pass queues synthesis without waiting and downloads ready audio for offline / scripted use.
    /// Retry after 90 seconds to collect phrases not ready in the first pass.
    /// English common phrases must exactly match L.t's third argument to hit the cache.
    static let commonEnglish = [
        "Didn't catch that. Please say it again, or pick a sentence.",
        "Sorry, I didn't understand. Please say it again, or pick a sentence.",
        "Day off cancelled.",
        "Found them!",
        "Who do you want to invite? Pick a neighbour.",
        "Cancelled. Nothing was done.",
        "Hello, I'm the StreetWalk voice assistant. Tap the mic and talk to me.",
    ]

    /// Choose phrases, locale and cache key as Speaker.speak does: original voiceID for Cantonese, language suffix otherwise.
    static func run(server: URL, speed: Double, voiceID: String, language: SpokenLanguage) {
        switch language {
        case .cantonese: run(server: server, speed: speed, voiceID: voiceID, phrases: common, locale: language.bcp47)
        case .english: run(server: server, speed: speed, voiceID: "\(voiceID)/\(language.rawValue)", phrases: commonEnglish, locale: language.bcp47)
        case .mandarin: break
        }
    }

    static func run(server: URL, speed: Double, voiceID: String, phrases: [String] = common, locale: String = "zh-HK") {
        Task.detached(priority: .utility) {
            for round in 0..<2 {
                if round == 1 { try? await Task.sleep(for: .seconds(90)) }
                var missing = 0
                for text in phrases {
                    let key = SpeechAudioCache.key(text: text, voiceID: voiceID, speed: speed)
                    if SpeechAudioCache.file(for: key) != nil { continue }
                    guard let code = await post(server, text: text, speed: speed, prefetch: true, locale: locale)?.code else { return }
                    guard code == 200, let (_, data) = await post(server, text: text, speed: speed, prefetch: false, locale: locale), !data.isEmpty else {
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

    private static func post(_ server: URL, text: String, speed: Double, prefetch: Bool, locale: String) async -> (code: Int, data: Data)? {
        var req = URLRequest(url: server.appendingPathComponent("v1/speech/synthesize"))
        req.httpMethod = "POST"
        req.timeoutInterval = prefetch ? 5 : 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "locale": locale, "speed": speed, "prefetch": prefetch])
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }
}
