import AVFoundation
import Speech

@MainActor
final class Speaker: ObservableObject {
    private var synth = AVSpeechSynthesizer()
    @Published var lastSpoken = ""
    /// Track Settings preview playback so the button visibly responds immediately.
    @Published private(set) var previewing = false
    /// System speech start/finish callbacks drive preview state and silent-start retry.
    private lazy var observer: SynthObserver = {
        let o = SynthObserver()
        o.owner = self
        return o
    }()
    /// Track each play() batch: whether speech started and when its final utterance finishes.
    private var batchLast: ObjectIdentifier?
    private var batchStarted = false
    private var playGeneration = 0
    /// Configurable language, voice, speed and enabled state; replaceable in tests.
    var settings: VoiceSettings = .shared
    /// Query available voices once because repeated simulator queries can block the main thread.
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    /// Optional voice server, nil in unit tests; see VoiceServer.swift and ServerSpeech.swift.
    var server: VoiceServer?
    /// Authentication token sent only through HTTPS, not needed on LAN.
    var token: (() async -> String?)?
    private lazy var serverPlayer = ServerSpeechPlayer()
    /// Current utterance route for debug-state and tests.
    private(set) var lastRoute: TTSRoute = .system
    /// Automated scripts use cache or system speech instead of waiting for the server.
    static let scripted = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-script") }

    /// Increment on speak/stop so an interrupted token lookup cannot restart obsolete speech.
    private var speakGeneration = 0
    var isSpeaking: Bool { synth.isSpeaking || serverPlayer.isActive }
    /// Do not alter the audio session while ServerSpeechPlayer captures continuous input, or the microphone disconnects.
    var capturing: Bool { serverPlayer.capturing }
    func startCapture(_ onPCM: @escaping @Sendable (Data) -> Void) throws { try serverPlayer.startCapture(onPCM) }
    func stopCapture() { serverPlayer.stopCapture() }
    func stop() {
        speakGeneration += 1
        playGeneration += 1
        previewing = false
        serverPlayer.stop()
        synth.stopSpeaking(at: .immediate)
    }

    /// Prefer available server or cached speech for supported languages; fall back to system output after a 6-second delay.
    /// Announcer owns the enable switch; explicit replay may still call here while disabled.
    func speak(_ text: String) {
        speakGeneration += 1
        previewing = false
        lastSpoken = text
        settings.ensureScanned()
        let language = settings.language
        let speed = TTSRoute.speed(settings.pace)
        // Doubao Xiaohe serves Cantonese and Mandarin; separate cache keys while retaining the original Cantonese warmup key.
        let voiceID = server?.voiceID.map { language == .cantonese ? $0 : "\($0)/\(language.rawValue)" }
        let key = voiceID.map { SpeechAudioCache.key(text: text, voiceID: $0, speed: speed) }
        let cached = key.flatMap { SpeechAudioCache.file(for: $0) }
        let route = TTSRoute.decide(language: language, server: server?.speechURL, cached: cached, scripted: Self.scripted,
                                    mandarin: server?.speaksMandarin ?? false)
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
                if outcome == .failedBeforeAudio { self?.playSystem(text, language: language) } else { self?.previewing = false }
            }
        case .server(let url):
            activateSession()
            synth.stopSpeaking(at: .immediate)
            let gen = speakGeneration
            if url.scheme == "https", let token {
                // Public HTTPS tunnels require authentication; discard token results if speech was stopped or replaced meanwhile.
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
                            locale: language == .mandarin ? "zh-CN" : "zh-HK") { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .failedBeforeAudio:
                print("[voice] server failed after \(String(format: "%.1f", Date().timeIntervalSince(started)))s → system voice")
                AppStore.debugEvent("tts fallback after \(String(format: "%.1f", Date().timeIntervalSince(started)))s → system: \(text)")
                self.server?.noteFailure()
                self.playSystem(text, language: language)
            case .finished:
                self.previewing = false
                self.server?.noteSuccess()
                if let t = self.serverPlayer.lastFirstAudio {
                    print("[voice] server first audio \(String(format: "%.2f", t))s")
                    AppStore.debugEvent("tts server first-audio \(String(format: "%.2f", t))s total \(String(format: "%.1f", Date().timeIntervalSince(started)))s: \(text)")
                }
            case .stopped: self.previewing = false
            }
        }
    }

    /// Use playback mode so the silent switch does not suppress speech, with spokenAudio and ducking.
    /// Do not modify playAndRecord during continuous capture; it also ignores the silent switch.
    func activateSession() {
        guard !capturing else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback || session.mode != .spokenAudio {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            }
            try session.setActive(true)
        } catch {
            // If microphone shutdown has not released the session yet, retry after release.
            print("[voice] audio session: \(error) → retry")
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
        }
    }

    private func playSystem(_ text: String, language: SpokenLanguage) {
        play(text, voice: settings.active, language: language)
    }

    /// Settings' primary preview follows actual routing: Doubao Xiaohe when connected, otherwise system voice.
    /// 10-16 user requirement: preview must use the assistant voice too. False indicates zero media volume.
    @discardableResult
    func previewCurrent(language: SpokenLanguage) -> Bool {
        guard server?.speechURL != nil else { return preview(settings.active, language: language) }
        speak(language.sample)
        previewing = true
        let gen = speakGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            if let self, self.speakGeneration == gen { self.previewing = false }
        }
        return AVAudioSession.sharedInstance().outputVolume > 0.02
    }

    /// Preview the specified voice regardless of the enable switch; previewing remains true while speaking.
    /// False means media volume is zero; suggest volume-up, since the silent switch is irrelevant.
    @discardableResult
    func preview(_ v: VoiceInfo?, language: SpokenLanguage) -> Bool {
        play(language.sample, voice: v, language: language)
        previewing = true
        // Do not leave the playing indicator active indefinitely if a completion callback never arrives.
        let gen = playGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            if let self, self.playGeneration == gen { self.previewing = false }
        }
        return AVAudioSession.sharedInstance().outputVolume > 0.02
    }

    private func play(_ text: String, voice v: VoiceInfo?, language: SpokenLanguage) {
        serverPlayer.stop()
        activateSession()
        synth.stopSpeaking(at: .immediate)
        previewing = false
        // Specify a voice explicitly; language alone may select the lowest tier. Mandarin selects only compatible voices via VoicePicker.
        let voice = v.flatMap(systemVoice) ?? fallback(language)
        let pace = settings.pace
        // Use one utterance per sentence with pauses for clarity, rather than slowing every syllable; see SpeechPace.
        let make: () -> [AVSpeechUtterance] = {
            SpeechPace.sentences(text).map { sentence in
                let u = AVSpeechUtterance(string: sentence)
                u.voice = voice
                // App Settings owns speed and voice instead of inheriting system spoken-content settings.
                u.prefersAssistiveTechnologySettings = false
                u.rate = pace.rate
                u.pitchMultiplier = 1.0
                u.postUtteranceDelay = pace.pauseAfterSentence
                return u
            }
        }
        enqueue(make())
        // Device testing found immediate speak after stop could produce no sound/callbacks; replace the synthesizer and retry once after 1.5 seconds.
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
            let wasPreviewing = self.previewing
            self.enqueue(make())
            self.previewing = wasPreviewing
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

    fileprivate func synthEnded(_ id: ObjectIdentifier) {
        if id == batchLast { previewing = false }
    }

    private func systemVoice(_ v: VoiceInfo) -> AVSpeechSynthesisVoice? {
        if let c = voiceCache[v.id] { return c }
        let s = AVSpeechSynthesisVoice(identifier: v.id)
        voiceCache[v.id] = s
        return s
    }

    /// If the requested voice is missing or invalid, use the system language fallback.
    private func fallback(_ l: SpokenLanguage) -> AVSpeechSynthesisVoice? {
        let key = "lang:" + l.bcp47
        if let c = voiceCache[key] { return c }
        let s = AVSpeechSynthesisVoice(language: l.bcp47)
        voiceCache[key] = s
        return s
    }
}

/// Forward AVSpeechSynthesizer callbacks from background threads to Speaker on main.
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

    /// Select recognition locale from the current UI language at each start so switching applies immediately.
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

        committed = ""
        lastPartial = ""
        task = recognizer?.recognitionTask(with: req) { result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self.received(text) }
        }
        isListening = true
    }

    /// iOS may restart recognition after a pause; preserve the previous segment and do not overwrite recognized text with empty output.
    private var committed = ""
    private var lastPartial = ""

    private func received(_ text: String) {
        guard isListening else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if lastPartial.count >= 4, t.count * 2 <= lastPartial.count, t.first != lastPartial.first {
            committed += lastPartial
        }
        lastPartial = t
        transcript = committed + t
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
