import AVFoundation
import Speech

@MainActor
final class Speaker: ObservableObject {
    private var synth = AVSpeechSynthesizer()
    @Published var lastSpoken = ""
    /// Track Settings preview playback so the button visibly responds immediately.
    /// 10-17 testing found audible previews without button changes because an older completion callback cleared a newer preview.
    /// trackPreview now observes start and completion, interruption or a 6-second no-audio timeout itself.
    @Published private(set) var previewing = false
    /// Preview button key: current, assistant, or a system voice ID.
    @Published private(set) var previewKey: String?
    private var previewGen = 0
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
    /// 10-18 crash logs showed synth.isSpeaking waiting on a TextToSpeech lock and blocking the main thread until termination.
    /// Track speaking locally from callbacks; clear on final completion, cancellation or stop, and treat a 3-second non-start as idle.
    var isSpeaking: Bool { synthSpeaking || serverPlayer.isActive }
    private var synthActive = false
    private var synthQueuedAt = Date.distantPast
    private var synthSpeaking: Bool { synthActive && (batchStarted || Date().timeIntervalSince(synthQueuedAt) < 3) }
    private func haltSynth() {
        synthActive = false
        synth.stopSpeaking(at: .immediate)
    }
    /// Do not alter the audio session while ServerSpeechPlayer captures continuous input, or the microphone disconnects.
    var capturing: Bool { serverPlayer.capturing }
    func startCapture(_ onPCM: @escaping @Sendable (Data) -> Void) throws { try serverPlayer.startCapture(onPCM) }
    func stopCapture() { serverPlayer.stopCapture() }
    func stop() {
        speakGeneration += 1
        playGeneration += 1
        endPreview()
        serverPlayer.stop()
        haltSynth()
    }

    /// Prefer available server or cached speech for supported languages; fall back to system output after a 6-second delay.
    /// Announcer owns the enable switch; explicit replay may still call here while disabled.
    func speak(_ text: String) {
        speakGeneration += 1
        endPreview()   // New speech supersedes a preview.
        lastSpoken = text
        settings.ensureScanned()
        let language = settings.language
        let text = Self.pronounced(text, language: language)
        let speed = TTSRoute.speed(settings.pace)
        // Doubao Xiaohe serves Cantonese and Mandarin; separate cache keys while retaining the original Cantonese warmup key.
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
            haltSynth()
            AppStore.debugEvent("tts phone-cache: \(text)")
            serverPlayer.play(file: file) { [weak self] outcome in
                if outcome == .failedBeforeAudio { self?.playSystem(text, language: language) }
            }
        case .server(let url):
            activateSession()
            haltSynth()
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
    /// text overrides the language's preview sentence; key identifies the button, as in previewKey.
    @discardableResult
    func previewCurrent(language: SpokenLanguage, text: String? = nil, key: String = "current") -> Bool {
        guard server?.speechURL != nil else { return preview(settings.active, language: language, text: text, key: key) }
        speak(text ?? language.sample)
        trackPreview(key)
        return AVAudioSession.sharedInstance().outputVolume > 0.02
    }

    /// Preview the specified voice regardless of the enable switch; previewing remains true while speaking.
    /// False means media volume is zero; suggest volume-up, since the silent switch is irrelevant.
    @discardableResult
    func preview(_ v: VoiceInfo?, language: SpokenLanguage, text: String? = nil, key: String? = nil) -> Bool {
        endPreview()
        play(text ?? language.sample, voice: v, language: language)
        trackPreview(key ?? v?.id ?? "current")
        return AVAudioSession.sharedInstance().outputVolume > 0.02
    }

    /// Set the button to playing immediately and observe actual server, cache or system output.
    /// Finish after 0.45 seconds idle following speech, 6 seconds without a start, or a 20-second limit; stop/new speech clears immediately.
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

    /// 10-18: Mandarin mispronounced the final character of the App name; substitute its xing homophone only in synthesis input.
    /// Keep visible text unchanged and leave Cantonese/English untouched; server app.tts_text applies the same pronunciation correction.
    nonisolated static func pronounced(_ text: String, language: SpokenLanguage) -> String {
        language == .mandarin ? text.replacingOccurrences(of: "街坊行", with: "街坊形") : text
    }

    private func play(_ text: String, voice v: VoiceInfo?, language: SpokenLanguage) {
        let text = Self.pronounced(text, language: language)
        serverPlayer.stop()
        activateSession()
        haltSynth()
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
            self.haltSynth()
            self.synth = AVSpeechSynthesizer()
            self.activateSession()
            self.enqueue(make())
        }
    }

    private func enqueue(_ utterances: [AVSpeechUtterance]) {
        synth.delegate = observer
        batchLast = utterances.last.map(ObjectIdentifier.init)
        batchStarted = false
        synthActive = true
        synthQueuedAt = Date()
        utterances.forEach(synth.speak)
    }

    fileprivate func synthStarted(_ id: ObjectIdentifier) {
        batchStarted = true
    }

    fileprivate func synthEnded(_ id: ObjectIdentifier) {
        if id == batchLast { synthActive = false }
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

    /// 2026-10-17: automatically listen after recap or help cards for confirmation/cancellation or a retry.
    /// Keep the card visible and stop silently without input; nil means a manual microphone start. stop() clears it.
    enum Answer: Equatable { case confirm, retry }
    var answering: Answer?
    /// Invoke once after endPause without new words, or the idle timeout without speech, removing the need to tap Done.
    /// Set before each start; stop clears it. Onboarding trial owns a separate timer.
    var onSilence: (() -> Void)?
    /// 10-18: reduce end pause from 2 to 1.5 seconds after slow-response device feedback.
    static let endPause: Duration = .milliseconds(1500)
    private var silence: Task<Void, Never>?
    /// Automatic listening request invalidated by a new card or button action.
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

    /// idle is the no-speech timeout, requiring onSilence.
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

    /// iOS may restart recognition after a pause; preserve the previous segment and do not overwrite recognized text with empty output.
    private var committed = ""
    private var lastPartial = ""

    private func received(_ text: String) {
        guard isListening else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // A markedly shorter segment with a different start, not a revision substring, indicates recognition restarting after a pause.
        if lastPartial.count >= 4, t.count * 2 <= lastPartial.count, t.first != lastPartial.first, !lastPartial.contains(t) {
            committed = Self.joined(committed: committed, latest: lastPartial)
        }
        lastPartial = t
        transcript = Self.joined(committed: committed, latest: t)
        armSilence(Self.endPause)
    }

    /// Pure, unit-tested merge of prior and latest segments, addressing repeated text in 2026-10-17 tests.
    /// If the user restarts with the same first two characters or the new segment already contains the old, keep only the new segment.
    /// Deduplicate overlap between the old suffix and new prefix.
    /// Collapse adjacent repeated phrases.
    nonisolated static func joined(committed: String, latest: String) -> String {
        var c = committed
        if c.count >= 2, latest.hasPrefix(String(c.prefix(2))) || latest.contains(c) {
            c = ""
        } else if let k = overlap(c, latest) {
            c.removeLast(k)
        }
        return collapseRepeats(c + latest)
    }

    /// Length of suffix/prefix overlap between a and b, at least two characters.
    nonisolated static func overlap(_ a: String, _ b: String) -> Int? {
        let x = Array(a), y = Array(b)
        guard min(x.count, y.count) >= 2 else { return nil }
        for k in stride(from: min(x.count, y.count), through: 2, by: -1) where x.suffix(k).elementsEqual(y.prefix(k)) { return k }
        return nil
    }

    /// Collapse repeated 2–6-character phrases but preserve single-character reduplication.
    nonisolated static func collapseRepeats(_ s: String) -> String {
        // Deduplicate English by words, not letters, to avoid corrupting words such as banana.
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

    /// Collapse adjacent repeats of 1–3 English words.
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
