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

    var isSpeaking: Bool { synth.isSpeaking }
    func stop() { synth.stopSpeaking(at: .immediate) }

    /// 播报一句：用设定入面而家嘅语言同声音。开关由 Announcer 管（关咗唔会叫到呢度，除非用户亲手撳「再聽一次」）。
    func speak(_ text: String) {
        lastSpoken = text
        settings.ensureScanned()
        play(text, voice: settings.active, language: settings.language)
    }

    /// 设定页「試聽」：用指定嘅声音讲试听句子（唔理开关）。
    func preview(_ v: VoiceInfo?, language: SpokenLanguage) {
        play(language.sample, voice: v, language: language)
    }

    private func play(_ text: String, voice v: VoiceInfo?, language: SpokenLanguage) {
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

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-HK"))
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
