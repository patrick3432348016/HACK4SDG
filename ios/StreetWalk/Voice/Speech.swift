import AVFoundation
import Speech

@MainActor
final class Speaker: ObservableObject {
    private var synth = AVSpeechSynthesizer()
    @Published var lastSpoken = ""
    /// 设定页「試聽」讲紧（个掣变「正在播放…」，撳咗一定有反应）。
    /// 2026-10-17 用户测试：有声但个掣冇变。以前靠各条播放路线嘅完成回调收返，旧一句嘅回调会提早收咗新一次试听；
    /// 而家由 trackPreview 自己睇住：开始讲 → 讲完（或者被打断 / 6 秒都冇声）先变返。
    @Published private(set) var previewing = false
    /// 边个掣喺试听（"current" = 「聲音」主掣、"assistant" = 「試聽助手把聲」、其他 = 系统声音 id）。
    @Published private(set) var previewKey: String?
    private var previewGen = 0
    /// 系统声音嘅开始 / 讲完回调（试听状态、冇出声自动重试）。
    private lazy var observer: SynthObserver = {
        let o = SynthObserver()
        o.owner = self
        return o
    }()
    /// 而家呢批句子（play() 一次）：最后一句讲完 = 讲完；有冇真系开始讲。
    private var batchLast: ObjectIdentifier?
    private var batchStarted = false
    private var playGeneration = 0
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
    /// 连续对话收紧音（ServerSpeechPlayer 嘅 engine）：唔好改音频会话，否则咪会断。
    var capturing: Bool { serverPlayer.capturing }
    func startCapture(_ onPCM: @escaping @Sendable (Data) -> Void) throws { try serverPlayer.startCapture(onPCM) }
    func stopCapture() { serverPlayer.stopCapture() }
    func stop() {
        speakGeneration += 1
        playGeneration += 1
        endPreview()
        serverPlayer.stop()
        synth.stopSpeaking(at: .immediate)
    }

    /// 播报一句：粤语有 Mac 服务器（或者手机存咗呢句）就用真人声，否则 / 太慢（6 秒）就用系统声音。
    /// 开关由 Announcer 管（关咗唔会叫到呢度，除非用户亲手撳「再聽一次」）。
    func speak(_ text: String) {
        speakGeneration += 1
        endPreview()   // 新嘅播报取代试听
        lastSpoken = text
        settings.ensureScanned()
        let language = settings.language
        let speed = TTSRoute.speed(settings.pace)
        // 普通话同粤语同一把声（豆包小何）：缓存要分开（粤语照旧 key，同预热一致）
        let voiceID = server?.voiceID.map { language == .cantonese ? $0 : "\($0)/\(language.rawValue)" }
        let key = voiceID.map { SpeechAudioCache.key(text: text, voiceID: $0, speed: speed) }
        let cached = key.flatMap { SpeechAudioCache.file(for: $0) }
        let route = TTSRoute.decide(language: language, server: server?.speechURL, cached: cached, scripted: Self.scripted,
                                    mandarin: server?.speaksMandarin ?? false, english: server?.speaksEnglish ?? false)
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
        serverPlayer.stream(text: text, server: url, speed: speed, token: token, cacheKey: key,
                            locale: language.bcp47) { [weak self] outcome in
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

    /// 每句讲之前都设好：.playback 喺静音模式（响铃 / 静音掣拨咗静音）都会出声；.spokenAudio + 压低其他声音。
    /// 连续对话收紧音（playAndRecord，同样唔受静音掣影响）就唔好郁，否则咪会断。
    func activateSession() {
        guard !capturing else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback || session.mode != .spokenAudio {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            }
            try session.setActive(true)
        } catch {
            // 啱啱收完咪，会话未放手：放咗再开一次
            print("[voice] audio session: \(error) → retry")
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
        }
    }

    private func playSystem(_ text: String, language: SpokenLanguage) {
        play(text, voice: settings.active, language: language)
    }

    /// 设定页「聲音」嗰粒主「試聽」：同真播报行同一条路——连到 Mac 语音服务器就用豆包小何把声，连唔到先用系统声音
    /// （用户 10-16：试听都要係豆包把声，唔好又係系统声）。返回 false = 媒体音量係 0。
    /// text：试听句子（nil = 语言嘅试听句）；key：边个掣（见 previewKey）。
    @discardableResult
    func previewCurrent(language: SpokenLanguage, text: String? = nil, key: String = "current") -> Bool {
        guard server?.speechURL != nil else { return preview(settings.active, language: language, text: text, key: key) }
        speak(text ?? language.sample)
        trackPreview(key)
        return AVAudioSession.sharedInstance().outputVolume > 0.02
    }

    /// 设定页「試聽」：用指定嘅声音讲试听句子（唔理开关）。讲紧期间 previewing = true。
    /// 返回 false = 媒体音量係 0（静音掣唔影响，但音量调到最细就听唔到），叫人按音量加。
    @discardableResult
    func preview(_ v: VoiceInfo?, language: SpokenLanguage, text: String? = nil, key: String? = nil) -> Bool {
        endPreview()
        play(text ?? language.sample, voice: v, language: language)
        trackPreview(key ?? v?.id ?? "current")
        return AVAudioSession.sharedInstance().outputVolume > 0.02
    }

    /// 试听开始：个掣即刻变「正在播放…」，睇住真系讲紧（系统声音 / 服务器声 / 手机缓存都系 isSpeaking），
    /// 开始咗又静咗 0.45 秒 = 讲完；6 秒都未开始（冇声）、20 秒上限都变返。stop() / 新播报会即刻变返。
    private func trackPreview(_ key: String) {
        previewGen += 1
        let gen = previewGen
        previewKey = key
        previewing = true
        AppStore.debugEvent("preview start \(key)")
        Task { @MainActor [weak self] in
            let start = Date()
            var started = false, quiet = 0
            while Date().timeIntervalSince(start) < 20 {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.previewGen == gen else { return }
                if self.isSpeaking { started = true; quiet = 0 } else { quiet += 1 }
                if started && quiet >= 3 { break }
                if !started && Date().timeIntervalSince(start) > 6 { break }
            }
            guard let self, self.previewGen == gen else { return }
            self.endPreview()
        }
    }

    private func endPreview() {
        previewGen += 1
        if previewing { previewing = false; AppStore.debugEvent("preview end") }
        if previewKey != nil { previewKey = nil }
    }

    private func play(_ text: String, voice v: VoiceInfo?, language: SpokenLanguage) {
        serverPlayer.stop()
        activateSession()
        synth.stopSpeaking(at: .immediate)
        // 一定要指明边把声（只写语言会拎到最低档；普通话只会揀 zh-CN 声，见 VoicePicker）。
        let voice = v.flatMap(systemVoice) ?? fallback(language)
        let pace = settings.pace
        // 每句一个 utterance、句同句之间停一停：清楚靠停顿，唔靠放慢音节（放慢会逐个字读，见 SpeechPace）。
        let make: () -> [AVSpeechUtterance] = {
            SpeechPace.sentences(text).map { sentence in
                let u = AVSpeechUtterance(string: sentence)
                u.voice = voice
                // 唔跟「辅助使用」入面嘅朗读设定（语速、声音由我哋设定页管）。
                u.prefersAssistiveTechnologySettings = false
                u.rate = pace.rate
                u.pitchMultiplier = 1.0
                u.postUtteranceDelay = pace.pauseAfterSentence
                return u
            }
        }
        enqueue(make())
        // 真机试过：啱啱 stopSpeaking 即刻 speak，合成器有时成批唔讲（冇声、冇回调）。1.5 秒都未开始就换个新合成器再讲一次。
        playGeneration += 1
        let gen = playGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, self.playGeneration == gen, !self.batchStarted else { return }
            AppStore.debugEvent("tts system: no start after 1.5s → new synthesizer")
            self.synth.delegate = nil
            self.synth.stopSpeaking(at: .immediate)
            self.synth = AVSpeechSynthesizer()
            self.activateSession()
            self.enqueue(make())
        }
    }

    private func enqueue(_ utterances: [AVSpeechUtterance]) {
        synth.delegate = observer
        batchLast = utterances.last.map(ObjectIdentifier.init)
        batchStarted = false
        utterances.forEach(synth.speak)
    }

    fileprivate func synthStarted(_ id: ObjectIdentifier) {
        batchStarted = true
    }

    fileprivate func synthEnded(_ id: ObjectIdentifier) {}

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

/// AVSpeechSynthesizer 回调（背景线程）→ 主线程交返 Speaker。
private final class SynthObserver: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    weak var owner: Speaker?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.owner?.synthStarted(id) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.owner?.synthEnded(id) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.owner?.synthEnded(id) }
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

    /// 卡出咗之后自动开咪听答案（2026-10-17 用户测试）：复述卡等「好 / 不要」、帮助卡等用户再讲一次。
    /// 张卡照显示（唔转「聽緊」卡）；冇人讲就静静鸡收咪。nil = 用户自己撳咪。stop() 会清走。
    enum Answer: Equatable { case confirm, retry }
    var answering: Answer?
    /// 讲完停一停（有字之后 endPause 冇新字），或者一直冇讲嘢（start 嘅 idle 秒）就叫一次：当讲完，唔使撳「講完」。
    /// 每次 start 前设；stop() 会清走（首次使用「試一次」有自己嘅计时）。
    var onSilence: (() -> Void)?
    static let endPause: Duration = .seconds(2)
    private var silence: Task<Void, Never>?
    /// 自动开咪嘅一次请求（新卡 / 撳咗掣就作废）。
    private(set) var answerGen = 0
    func nextAnswerGen() -> Int { answerGen += 1; return answerGen }

    private func armSilence(_ d: Duration) {
        silence?.cancel()
        guard onSilence != nil else { return }
        silence = Task { @MainActor [weak self] in
            try? await Task.sleep(for: d)
            guard let self, !Task.isCancelled, self.isListening else { return }
            self.onSilence?()
        }
    }

    func requestAuth() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                self.available = status == .authorized && (self.recognizer?.isAvailable ?? false)
            }
        }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    /// idle：一直冇讲嘢几耐就当讲完（要设 onSilence）。
    func start(idle: Double = 15) throws {
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

        committed = ""
        lastPartial = ""
        task = recognizer?.recognitionTask(with: req) { result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self.received(text) }
        }
        isListening = true
        armSilence(.seconds(idle))
    }

    /// 停顿之后 iOS 有时会由头再认（新一段字唔包含之前嗰段）：前面嗰段留低，接埋；空字唔好盖走已经认到嘅字。
    private var committed = ""
    private var lastPartial = ""

    private func received(_ text: String) {
        guard isListening else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // 新一段明显短咗、开头唔同、又唔系旧嗰段嘅一截（识别改紧字）：当係停顿后由头再认
        if lastPartial.count >= 4, t.count * 2 <= lastPartial.count, t.first != lastPartial.first, !lastPartial.contains(t) {
            committed = Self.joined(committed: committed, latest: lastPartial)
        }
        lastPartial = t
        transcript = Self.joined(committed: committed, latest: t)
        armSilence(Self.endPause)
    }

    /// 前面认好嘅一段 + 最新一段（2026-10-17 用户测试：「帮我约我的帮我帮我约」字叠埋）。纯逻辑，有单元测试。
    /// - 用户由头再讲（新一段同旧段开头两个字一样）或者新一段已经包含旧段：只要新嗰段；
    /// - 旧段尾同新段头重叠：只留一次；
    /// - 紧接重复嘅词（「帮我帮我约」）收埋。
    nonisolated static func joined(committed: String, latest: String) -> String {
        var c = committed
        if c.count >= 2, latest.hasPrefix(String(c.prefix(2))) || latest.contains(c) {
            c = ""
        } else if let k = overlap(c, latest) {
            c.removeLast(k)
        }
        return collapseRepeats(c + latest)
    }

    /// a 尾同 b 头重叠几多个字（最少 2 个）。
    nonisolated static func overlap(_ a: String, _ b: String) -> Int? {
        let x = Array(a), y = Array(b)
        guard min(x.count, y.count) >= 2 else { return nil }
        for k in stride(from: min(x.count, y.count), through: 2, by: -1) where x.suffix(k).elementsEqual(y.prefix(k)) { return k }
        return nil
    }

    /// 紧接重复嘅 2–6 个字只留一次（「帮我帮我约」→「帮我约」、「好的好的」→「好的」）。一个字嘅叠字（「慢慢」）唔郁。
    nonisolated static func collapseRepeats(_ s: String) -> String {
        // 英文按字收（「invite invite Mrs Chan」→「invite Mrs Chan」）；按字母收会整坏「banana」之类
        if EnglishText.isEnglish(s) { return collapseRepeatedWords(s) }
        var c = Array(s)
        var i = 0
        while i < c.count {
            var removed = false
            for n in stride(from: min(6, (c.count - i) / 2), through: 2, by: -1)
            where c[i..<i + n].elementsEqual(c[i + n..<i + 2 * n]) && c[i..<i + n].contains(where: { !$0.isPunctuation && !$0.isWhitespace }) {
                c.removeSubrange(i + n..<i + 2 * n)
                removed = true
                break
            }
            if !removed { i += 1 }
        }
        return String(c)
    }

    /// 紧接重复嘅 1–3 个英文字只留一次。
    nonisolated static func collapseRepeatedWords(_ s: String) -> String {
        var w = s.split(separator: " ").map(String.init)
        func key(_ x: String) -> String { x.lowercased().filter { $0.isLetter || $0.isNumber } }
        var i = 0
        while i < w.count {
            var removed = false
            for n in stride(from: min(3, (w.count - i) / 2), through: 1, by: -1)
            where (0..<n).allSatisfy({ key(w[i + $0]) == key(w[i + n + $0]) && !key(w[i + $0]).isEmpty }) {
                w.removeSubrange(i + n..<i + 2 * n)
                removed = true
                break
            }
            if !removed { i += 1 }
        }
        return w.joined(separator: " ")
    }

    @discardableResult
    func stop() -> String {
        silence?.cancel()
        silence = nil
        onSilence = nil
        answering = nil
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
