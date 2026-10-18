import AVFoundation
import Foundation

// B's continuous-conversation stack adopted on 2026-10-12 at the user's request.
//
// One microphone tap starts a conversation without tapping for every sentence:
// - Recognition: phone audio → Mac → Doubao streaming ASR; endpointing produces text through VoiceEar.
// - Understanding: local safety/weather and app-specific intents such as finding, rescheduling, cancellation, reports, and landmark renaming,
//     then B's policy/model/confirmation flow through /v1/assistant/turn, using the same handle path as one-shot speech.
// - Speech: Xiaohe shares the capture engine with echo cancellation; speaking interrupts playback.
// Actions affecting others still require tapping confirmation: a spoken affirmative does not press the button, while a spoken refusal withdraws the draft.
// Tap again, finish, 45-second silence, ten-minute limit, or backgrounding stops capture. Without the Mac, fall back to Listener.
extension AppStore {
    /// Silence timeout in seconds.
    static let conversationIdle: TimeInterval = 45
    /// Wait briefly for a continuation after an utterance; B merges adjacent clauses within 0.35 s.
    static let utteranceJoin: Duration = .milliseconds(450)

    /// Whether the discovered Mac server supports Doubao recognition.
    var canConverse: Bool { VoiceServer.shared.earURL != nil }

    /// Start continuous conversation; false means permission/connection/capture failure and permits local recognition fallback.
    func startConversation() async -> Bool {
        guard let url = VoiceServer.shared.earURL else { return false }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: break
        case .undetermined: guard await AVAudioApplication.requestRecordPermission() else { return false }
        default: return false
        }
        // HTTPS tunnel requires authentication; direct LAN recognition does not send a plaintext token unnecessarily.
        let token: String? = url.scheme == "wss" ? (try? await supabase?.api.accessToken()) ?? nil : nil
        let ok = await ear.open(url, token: token, locale: L.isCmn ? "zh-CN" : "zh-HK") { [weak self] e in self?.earEvent(e) }
        guard ok else { return false }
        hush()
        #if DEBUG
        if let files = LaunchArgs.value("-earFeed") {
            // Simulator feeds 16-kHz mono PCM16 WAV recordings as speech, with seven-second response gaps.
            feedEar(files.split(separator: ",").map(String.init))
            beginConversation()
            return true
        }
        #endif
        do {
            try speaker.startCapture { [sender = ear.sender] pcm in sender.feed(pcm) }
        } catch {
            ear.close()
            return false
        }
        beginConversation()
        return true
    }

    private func beginConversation() {
        conversing = true
        listening = true
        heardPartial = ""
        listener.transcript = ""
        earPending = []
        lastEarActivity = Date()
        Haptics.light()
        earIdle?.cancel()
        earIdle = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.conversing else { return }
                if self.speaker.isSpeaking || self.voiceCard?.assistant?.kind == .thinking { self.lastEarActivity = Date() }
                if Date().timeIntervalSince(self.lastEarActivity) > Self.conversationIdle {
                    self.endConversation(toast: L.t("冇聲，收咗咪。想講再撳咪。", "没声音，关了麦克风。想说再按麦克风。"))
                    return
                }
            }
        }
    }

    /// Stop capture on microphone tap, finish, silence, error, or backgrounding.
    func endConversation(toast message: String? = nil) {
        guard conversing else { return }
        conversing = false
        listening = false
        earFlush?.cancel()
        earIdle?.cancel()
        earFeed?.cancel()
        earPending = []
        heardPartial = ""
        listener.transcript = ""
        ear.close()
        speaker.stopCapture()
        if let message { toast(message) }
    }

    /// Recognition text callback on the main thread.
    func earEvent(_ e: VoiceEar.Event) {
        guard conversing else { return }
        switch e {
        case .partial(let raw):
            let text = AssistantFlow.hant(raw)
            guard !isEcho(text) else { return }
            lastEarActivity = Date()
            show(partial: (earPending + [text]).joined(separator: "，"))
            // Barge-in: stop speech when new recognized user content begins.
            if speaker.isSpeaking && text.count >= 2 { hush() }
        case .final(let raw):
            let text = AssistantFlow.hant(raw)
            guard !isEcho(text) else { show(partial: earPending.joined(separator: "，")); return }
            lastEarActivity = Date()
            earPending.append(text)
            show(partial: earPending.joined(separator: "，"))
            earFlush?.cancel()
            earFlush = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.utteranceJoin)
                guard let self, !Task.isCancelled, self.conversing, !self.earPending.isEmpty else { return }
                let all = self.earPending.joined(separator: "，")
                self.earPending = []
                self.show(partial: "")
                self.conversationTurn(all)
            }
        case .failed(let message):
            endConversation(toast: message)
        }
    }

    private func show(partial: String) {
        heardPartial = partial
        listener.transcript = partial
    }

    /// Process a finished utterance through handle, with special affirmative/refusal handling while a recap card awaits a tap.
    /// Route emergency and medical utterances through handle rather than treating them as confirmation or refusal.
    func conversationTurn(_ text: String) {
        if let card = voiceCard, card.needsConfirm, TemplateAI.safety(text) == nil {
            switch Self.yesNo(text) {
            case .yes?:
                say(L.t("請撳「好」確認。", "请按「好的」确认。"), prompt: true)   // Use the same label as the recap card button.
                return
            case .no?:
                rejectVoice()
                say(L.t("好，唔做。", "好，不做。"))
                return
            case nil: break
            }
        }
        handle(text)
    }

    enum YesNo { case yes, no }

    /// Treat only short utterances as confirmation to avoid approving a new request containing yes-like wording. Pure logic covered by tests.
    nonisolated static func yesNo(_ text: String) -> YesNo? {
        let t = text.filter { !$0.isPunctuation && !$0.isWhitespace }
        guard (1...6).contains(t.count) else { return nil }
        // Match negatives before their embedded affirmative words.
        let no = ["唔好", "唔係", "唔要", "取消", "唔使", "不要", "不是", "不用", "算啦", "算了",
                  "不好", "不對", "不对", "不可以", "不行", "不確認", "不确认", "唔得", "唔可以", "唔啱", "唔確認"]
        if no.contains(where: t.contains) { return .no }
        let yes = ["好", "係", "啱", "可以", "確認", "确认", "得", "OK", "ok", "是", "对", "對"]
        // A negative immediately before approval/confirmation wording remains a rejection.
        if yes.contains(where: { w in ["唔", "不", "冇", "沒", "没", "未", "別", "别"].contains { t.contains($0 + w) } }) { return .no }
        // Only short affirmative phrases approve; a longer invitation request is new input.
        guard t.count <= 3 else { return nil }
        if yes.contains(where: t.contains) { return .yes }
        return nil
    }

    // MARK: - Echo protection

    /// Ignore recognized content matching the app's recent speech when loudspeaker audio leaks past echo cancellation.
    func isEcho(_ heard: String) -> Bool {
        let now = Date()
        recentSpoken.removeAll { now.timeIntervalSince($0.at) > 20 }
        return Self.looksLikeEcho(heard, spoken: recentSpoken.map(\.text))
    }

    /// Pure tested comparison: most of a recognized phrase of at least two characters appears in recent spoken text.
    nonisolated static func looksLikeEcho(_ heard: String, spoken: [String]) -> Bool {
        let h = normalize(heard)
        guard h.count >= 2 else { return false }
        for s in spoken.map(normalize) where !s.isEmpty {
            if s.contains(h) { return true }
            let chars = Set(s)
            let hits = h.filter(chars.contains).count
            if h.count >= 4 && Double(hits) / Double(h.count) >= 0.8 { return true }
        }
        return false
    }

    nonisolated static func normalize(_ s: String) -> String {
        let t = s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s
        return t.filter { !$0.isPunctuation && !$0.isWhitespace && !$0.isSymbol }
    }

    // MARK: - Simulator input

    #if DEBUG
    /// -earFeed streams WAV files in real time, separated by -earGap seconds (default seven), then silence to keep the connection alive.
    private func feedEar(_ files: [String]) {
        let sender = ear.sender
        let gapFrames = Int((LaunchArgs.value("-earGap").flatMap(Double.init) ?? 7) * 5)
        earFeed = Task.detached(priority: .userInitiated) {
            let silence = Data(count: EarSender.frameBytes)
            for f in files {
                guard let d = try? Data(contentsOf: URL(fileURLWithPath: f)), d.count > 44 else { continue }
                let pcm = d.dropFirst(44)
                var i = pcm.startIndex
                while i < pcm.endIndex, !Task.isCancelled {
                    let end = min(i + EarSender.frameBytes, pcm.endIndex)
                    var frame = Data(pcm[i..<end])
                    if frame.count < EarSender.frameBytes { frame.append(Data(count: EarSender.frameBytes - frame.count)) }
                    sender.feed(frame)
                    i = end
                    try? await Task.sleep(for: .milliseconds(200))
                }
                for _ in 0..<gapFrames where !Task.isCancelled {
                    sender.feed(silence)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            while !Task.isCancelled {
                sender.feed(silence)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    #endif
}
