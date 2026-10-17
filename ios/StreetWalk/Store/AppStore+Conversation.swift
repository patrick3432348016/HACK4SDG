import AVFoundation
import Foundation

// 组员 B 嗰套嘅连续对话（2026-10-12，用户：「直接换成 B 的，用它的那套」）。
//
// 撳一下咪 = 开始倾，唔使每句再撳：
// - 耳：手机收音 → Mac 语音服务器 → 豆包流式识别，讲完一句（豆包判定停顿）自动出字（VoiceEar）；
// - 脑：手机先认求救 / 问医疗 / 问天气（两种语言都喺手机答），同 App 自己做嘅指令（找人、改约、取消约、反映、地标改名…，
//   TemplateAI）；其余交 B 嘅豆包理解（/v1/assistant/turn：B 嘅范围规则、约人确认卡），同撳咪讲一句完全一样（handle）；
// - 嘴：小何（同收音共用一部 engine，开咗回声消除）：用户一开口就停（插嘴，B 嘅做法）。
// 复述卡等紧确认时讲「好 / 可以 / 行」= 撳「好」，讲「不要 / 算了 / 取消」= 撳「唔係」（2026-10-17 用户测试要求；
// 以前要亲手撳「好」）。否定先认，「不好」「唔得」唔会当「好」。
// 再撳咪 / 「傾完」/ 45 秒冇人讲嘢 / 十分钟上限 / App 退后台 → 收咪。连唔到 Mac → 照旧用手机识别（Listener）。
extension AppStore {
    /// 冇人讲嘢几耐就收咪（秒）。
    static let conversationIdle: TimeInterval = 45
    /// 一句讲完之后等几耐睇下有冇下半句（B：0.35 秒合并相邻分句）。
    static let utteranceJoin: Duration = .milliseconds(450)

    /// Mac 语音服务器有豆包识别。
    var canConverse: Bool { VoiceServer.shared.earURL != nil }

    /// 开始连续对话。false = 开唔到（冇咪权限 / 连唔到 / 收唔到音），叫嘅人照旧用手机识别。
    func startConversation() async -> Bool {
        guard let url = VoiceServer.shared.earURL else { return false }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: break
        case .undetermined: guard await AVAudioApplication.requestRecordPermission() else { return false }
        default: return false
        }
        // 经 https 隧道要登录；局域网直连唔使（唔好将 token 明文送过 Wi-Fi）
        let token: String? = url.scheme == "wss" ? (try? await supabase?.api.accessToken()) ?? nil : nil
        let ok = await ear.open(url, token: token, locale: L.lang.locale) { [weak self] e in self?.earEvent(e) }
        guard ok else { return false }
        hush()
        #if DEBUG
        if let files = LaunchArgs.value("-earFeed") {
            // 模拟器测试：用录好嘅 WAV（16 kHz 单声道 PCM16）当系用户讲，每段之间停 7 秒等回答
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
                    self.endConversation(toast: L.t("冇聲，收咗咪。想講再撳咪。", "没声音，关了麦克风。想说再按麦克风。", "No sound, so the mic is off. Tap the mic to speak again."))
                    return
                }
            }
        }
    }

    /// 收咪（撳咪、「傾完」、冇声、出错、退后台）。
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

    /// 识别通道嘅一句字（主线程）。
    func earEvent(_ e: VoiceEar.Event) {
        guard conversing else { return }
        switch e {
        case .partial(let raw):
            let text = AssistantFlow.hant(raw)
            guard !isEcho(text) else { return }
            lastEarActivity = Date()
            show(partial: (earPending + [text]).joined(separator: Self.utteranceSeparator))
            // 插嘴：用户开口就停播报（B：识别到新语句即停旧播报）
            if speaker.isSpeaking && text.count >= 2 { hush() }
        case .final(let raw):
            // 口吃 / 重复嘅词收埋（「帮我帮我约」）；同上一句一模一样嘅唔再叠（2026-10-17 用户测试：字叠埋）
            let text = Listener.collapseRepeats(AssistantFlow.hant(raw))
            guard !isEcho(text) else { show(partial: earPending.joined(separator: Self.utteranceSeparator)); return }
            lastEarActivity = Date()
            if earPending.last != text { earPending.append(text) }
            show(partial: earPending.joined(separator: Self.utteranceSeparator))
            earFlush?.cancel()
            earFlush = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.utteranceJoin)
                guard let self, !Task.isCancelled, self.conversing, !self.earPending.isEmpty else { return }
                let all = self.earPending.joined(separator: Self.utteranceSeparator)
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

    /// 一句讲完：同撳咪讲一句一样处理（handle）。复述卡等紧确认时嘅「好 / 唔好」喺 routeHeard（answerConfirm）处理，
    /// 手机识别同连续对话一样；求救 / 问医疗唔当「好 / 唔好」（安全先行）。
    func conversationTurn(_ text: String) {
        handle(text)
    }

    enum YesNo { case yes, no }

    /// 连续对话几段字串埋：中文用「，」、英文用「, 」。
    static var utteranceSeparator: String { L.t("，", "，", ", ") }

    /// 对住复述卡讲嘅「好 / 唔好」（成句好短先算，免得「好想約阿芳」当咗「好」）。纯逻辑，有单元测试。
    nonisolated static func yesNo(_ text: String) -> YesNo? {
        // 英文：yes / ok / sure / sounds good；no / don't / cancel / not now（否定优先）
        if EnglishText.isEnglish(text) { return EnglishText.yesNo(text) }
        let t = text.filter { !$0.isPunctuation && !$0.isWhitespace }
        guard (1...6).contains(t.count) else { return nil }
        // 先认否定：「不好」「不对」「不可以」「唔得」「唔可以」都含「好 / 對 / 可以 / 得」，唔可以当「好」。
        let no = ["唔好", "唔係", "唔要", "取消", "唔使", "不要", "不是", "不用", "算啦", "算了", "算吧", "算數", "算数", "罷了", "罢了",
                  "不好", "不對", "不对", "不可以", "不行", "不確認", "不确认", "唔得", "唔可以", "唔啱", "唔確認",
                  "不約", "不约", "唔約", "不去", "唔去", "冇需要", "沒需要", "没需要"]
        if no.contains(where: t.contains) { return .no }
        // 「沒問題」含「沒」，唔好当否定
        if ["沒問題", "没问题", "冇問題", "冇问题"].contains(where: t.contains) { return .yes }
        let yes = ["好", "係", "啱", "可以", "確認", "确认", "得", "OK", "ok", "Ok", "是", "对", "對", "行"]
        // 否定字紧接「好 / 係 / 得…」（「唔OK」「沒確認」）都系否定
        if yes.contains(where: { w in ["唔", "不", "冇", "沒", "没", "未", "別", "别"].contains { t.contains($0 + w) } }) { return .no }
        // 「好」类只认好短嘅（「好呀」「係呀」「可以呀」）；「好想約阿芳」系新请求
        guard t.count <= 3 else { return nil }
        if yes.contains(where: t.contains) { return .yes }
        return nil
    }

    // MARK: - 回声保险

    /// 手机播报漏咗入咪（外放大声、回声消除未收晒）：认得系自己啱啱讲过嘅字就唔当用户讲。
    func isEcho(_ heard: String) -> Bool {
        let now = Date()
        recentSpoken.removeAll { now.timeIntervalSince($0.at) > 20 }
        return Self.looksLikeEcho(heard, spoken: recentSpoken.map(\.text))
    }

    /// 纯逻辑（有单元测试）：听到嘅字（≥ 2 个）大部分喺最近讲过嘅句子入面出现过。
    nonisolated static func looksLikeEcho(_ heard: String, spoken: [String]) -> Bool {
        // 英文按字（word）比：字母人人都有，按字母比会将用户讲嘅嘢都当回声；一两个字（「yes」「no」）永远唔当回声
        if EnglishText.isEnglish(heard) {
            let h = EnglishText.words(heard)
            guard h.count >= 3 else { return false }
            for s in spoken where EnglishText.isEnglish(s) {
                let sw = EnglishText.words(s)
                if (" " + sw.joined(separator: " ") + " ").contains(" " + h.joined(separator: " ") + " ") { return true }
                let set = Set(sw)
                if h.count >= 4 && Double(h.filter(set.contains).count) / Double(h.count) >= 0.8 { return true }
            }
            return false
        }
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

    // MARK: - 模拟器测试

    #if DEBUG
    /// -earFeed a.wav,b.wav：当系用户讲（实时速度送），每段之后停 -earGap 秒（默认 7）；送完继续送静音保持连线。
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
