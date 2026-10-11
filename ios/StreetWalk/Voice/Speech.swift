import AVFoundation
import Speech

@MainActor
final class Speaker: ObservableObject {
    private let synth = AVSpeechSynthesizer()
    @Published var lastSpoken = ""
    /// 讲边种语言、用边把声、几快、开唔开（设定页「聲音」）。测试可以换。
    var settings: VoiceSettings = .shared
    /// 声音对象只查一次（有些模拟器每次查都会卡住主线程）。
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    /// Mac 语音服务器（粤语真人声）。nil = 唔用（单元测试）。见 Voice/VoiceServer.swift、ServerSpeech.swift。
    var server: VoiceServer?
    /// 登录 token（只经 HTTPS 送；局域网唔使）。
    var token: (() async -> String?)?
    private lazy var serverPlayer = ServerSpeechPlayer()
    /// 而家呢句点讲（debug-state、测试）。
    private(set) var lastRoute: TTSRoute = .system
    /// 自动演示脚本：冇缓存就唔等服务器（画面同声音要对得准）。
    static let scripted = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-script") }

    /// 每次 speak / stop 加一：等 token 嗰阵被打断就唔再开始。
    private var speakGeneration = 0
    var isSpeaking: Bool { synth.isSpeaking || serverPlayer.isActive }
    func stop() {
        speakGeneration += 1
        serverPlayer.stop()
        synth.stopSpeaking(at: .immediate)
    }

    /// 播报一句：粤语有 Mac 服务器（或者手机存咗呢句）就用真人声，否则 / 太慢（6 秒）就用系统声音。
    /// 开关由 Announcer 管（关咗唔会叫到呢度，除非用户亲手撳「再聽一次」）。
    func speak(_ text: String) {
        speakGeneration += 1
        lastSpoken = text
        settings.ensureScanned()
        let language = settings.language
        let speed = TTSRoute.speed(settings.pace)
        let voiceID = server?.voiceID
        let key = voiceID.map { SpeechAudioCache.key(text: text, voiceID: $0, speed: speed) }
        let cached = key.flatMap { SpeechAudioCache.file(for: $0) }
        let route = TTSRoute.decide(language: language, server: server?.speechURL, cached: cached, scripted: Self.scripted)
        lastRoute = route
        switch route {
        case .system:
            AppStore.debugEvent("tts system: \(text)")
            playSystem(text, language: language)
        case .cached(let file):
            activateSession()
            synth.stopSpeaking(at: .immediate)
            AppStore.debugEvent("tts phone-cache: \(text)")
            serverPlayer.play(file: file) { [weak self] outcome in
                if outcome == .failedBeforeAudio { self?.playSystem(text, language: language) }
            }
        case .server(let url):
            activateSession()
            synth.stopSpeaking(at: .immediate)
            let gen = speakGeneration
            if url.scheme == "https", let token {
                // 隧道（公网 HTTPS）要登录：攞 token 期间被 stop / 换咗句就唔好再开始
                Task { @MainActor [weak self] in
                    let t = await token()
                    guard let self, self.speakGeneration == gen else { return }
                    self.startStream(text, url: url, speed: speed, token: t, key: key, language: language)
                }
            } else {
                startStream(text, url: url, speed: speed, token: nil, key: key, language: language)
            }
        }
    }

    private func startStream(_ text: String, url: URL, speed: Double, token: String?, key: String?, language: SpokenLanguage) {
        let started = Date()
        serverPlayer.stream(text: text, server: url, speed: speed, token: token, cacheKey: key) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .failedBeforeAudio:
                print("[voice] server failed after \(String(format: "%.1f", Date().timeIntervalSince(started)))s → system voice")
                AppStore.debugEvent("tts fallback after \(String(format: "%.1f", Date().timeIntervalSince(started)))s → system: \(text)")
                self.server?.noteFailure()
                self.playSystem(text, language: language)
            case .finished:
                self.server?.noteSuccess()
                if let t = self.serverPlayer.lastFirstAudio {
                    print("[voice] server first audio \(String(format: "%.2f", t))s")
                    AppStore.debugEvent("tts server first-audio \(String(format: "%.2f", t))s total \(String(format: "%.1f", Date().timeIntervalSince(started)))s: \(text)")
                }
            case .stopped: break
            }
        }
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func playSystem(_ text: String, language: SpokenLanguage) {
        play(text, voice: settings.active, language: language)
    }

    /// 设定页「試聽」：用指定嘅声音讲试听句子（唔理开关）。
    func preview(_ v: VoiceInfo?, language: SpokenLanguage) {
        play(language.sample, voice: v, language: language)
    }

    private func play(_ text: String, voice v: VoiceInfo?, language: SpokenLanguage) {
        serverPlayer.stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synth.stopSpeaking(at: .immediate)
        // 一定要指明边把声（只写语言会拎到最低档；普通话只会揀 zh-CN 声，见 VoicePicker）。
        let voice = v.flatMap(systemVoice) ?? fallback(language)
        let pace = settings.pace
        // 每句一个 utterance、句同句之间停一停：清楚靠停顿，唔靠放慢音节（放慢会逐个字读，见 SpeechPace）。
        for sentence in SpeechPace.sentences(text) {
            let u = AVSpeechUtterance(string: sentence)
            u.voice = voice
            // 唔跟「辅助使用」入面嘅朗读设定（语速、声音由我哋设定页管）。
            u.prefersAssistiveTechnologySettings = false
            u.rate = pace.rate
            u.pitchMultiplier = 1.0
            u.postUtteranceDelay = pace.pauseAfterSentence
            synth.speak(u)
        }
    }

    private func systemVoice(_ v: VoiceInfo) -> AVSpeechSynthesisVoice? {
        if let c = voiceCache[v.id] { return c }
        let s = AVSpeechSynthesisVoice(identifier: v.id)
        voiceCache[v.id] = s
        return s
    }

    /// 揀唔到（未装 / 假声音）：用系统按语言俾嘅声。
    private func fallback(_ l: SpokenLanguage) -> AVSpeechSynthesisVoice? {
        let key = "lang:" + l.bcp47
        if let c = voiceCache[key] { return c }
        let s = AVSpeechSynthesisVoice(language: l.bcp47)
        voiceCache[key] = s
        return s
    }
}

@MainActor
final class Listener: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var available = false

    /// 跟界面语言：粤语 zh-HK、普通话 zh-CN（每次开始听先揀，切换语言即时生效）。
    private var recognizers: [AppLang: SFSpeechRecognizer] = [:]
    private var recognizer: SFSpeechRecognizer? {
        let l = L.lang
        if let r = recognizers[l] { return r }
        let r = SFSpeechRecognizer(locale: Locale(identifier: l.locale))
        recognizers[l] = r
        return r
    }
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestAuth() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                self.available = status == .authorized && (self.recognizer?.isAvailable ?? false)
            }
        }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    func start() throws {
        transcript = ""
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw NSError(domain: "Listener", code: 1) }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer?.recognitionTask(with: req) { result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self.transcript = text }
        }
        isListening = true
    }

    @discardableResult
    func stop() -> String {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        return transcript
    }
}
