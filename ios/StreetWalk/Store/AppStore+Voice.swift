import SwiftUI
import AVFoundation
import Speech

// Voice interaction.
extension AppStore {
    // MARK: - Speech output

    /// Route all speech through Announcer for queuing, VoiceOver announcements, listening deferral and expiry.
    /// prompt marks response-required messages with priority and protection from displacement.
    /// force honors explicit replay requests even when spoken announcements are disabled in Settings.
    func say(_ s: String, prompt: Bool = false, force: Bool = false) {
        // Continuous conversation may speak while capturing with echo cancellation; remember output for the echo guard.
        if conversing { recentSpoken.append((s, Date())) }
        announcer.say(s, kind: prompt ? .prompt : .info, force: force, via: speaker, holding: listening && !conversing)
    }

    /// Stop and clear announcements on navigation, card changes, cancellation or backgrounding; continuous capture remains active where applicable.
    func hush() {
        announcer.interrupt(speaker)
    }

    /// Replay stops current speech and restarts immediately, avoiding queued requests expiring during long sentences.
    func sayAgain(_ s: String) {
        guard !listening || conversing else { say(s, force: true); return }
        announcer.hold(speaker)
        _ = announcer.release()
        say(s, prompt: true, force: true)
    }

    /// After listening, flush deferred prompts behind the response; discard stale informational messages.
    func flushHeldSpeech(_ held: [Announcer.Line]) {
        held.forEach { announcer.enqueue($0, via: speaker, holding: listening && !conversing) }
    }

    // MARK: - Voice input

    func micTapped() {
        if conversing { endConversation(); return }
        if listening { stopListening(); return }
        guard !micStarting else { return }
        // If a recap card awaits confirmation, withdraw its proposal and highlight instead of silently discarding the state.
        if voiceCard?.needsConfirm == true { rejectVoice() } else { voiceCard = nil }
        micStarting = true
        Task { @MainActor in
            defer { micStarting = false }
            // Use B's Doubao recognition through the Mac server for continuous conversation; fall back to device recognition if unavailable.
            if canConverse, await startConversation() { return }
            // A47: wait for first-use permission responses before listening, preserving the first utterance.
            let auth = await ensureVoiceAuth()
            guard auth.granted else {
                toast(L.t("未開咪或者語音識別權限。可以揀一句，或者去設定開。", "没开麦克风或语音识别权限。可以选一句，或者去设置打开。"))
                phrasePicker = true
                return
            }
            // After permission prompts, let the audio session settle; immediately starting the engine caused simulator timeout crashes (A47 review).
            if auth.prompted { try? await Task.sleep(for: .milliseconds(400)) }
            guard AVAudioSession.sharedInstance().isInputAvailable else {
                toast(L.t("而家用唔到咪，可以揀一句。", "现在用不了麦克风，可以选一句。"))
                phrasePicker = true
                return
            }
            announcer.hold(speaker)
            do {
                try listener.start()
                listening = true
                Haptics.light()
            } catch {
                listening = false
                flushHeldSpeech(announcer.release())
                toast(L.t("而家用唔到咪，可以揀一句。", "现在用不了麦克风，可以选一句。"))
                phrasePicker = true
            }
        }
    }

    /// Await microphone and speech authorization when undetermined. granted means both allowed; prompted means dialogs appeared this time.
    func ensureVoiceAuth() async -> (granted: Bool, prompted: Bool) {
        var prompted = false
        var speech = SFSpeechRecognizer.authorizationStatus()
        if speech == .notDetermined {
            prompted = true
            speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        }
        guard speech == .authorized else { return (false, prompted) }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return (true, prompted)
        case .undetermined: return (await AVAudioApplication.requestRecordPermission(), true)
        default: return (false, prompted)
        }
    }

    func stopListening() {
        if conversing { endConversation(); return }
        let text = listener.stop()
        listening = false
        if text.isEmpty {
            let held = announcer.release()
            say(L.t("聽唔清楚。可以再講一次，或者揀一句。", "没听清楚。可以再说一次，或者选一句。"), prompt: true)
            phrasePicker = true
            flushHeldSpeech(held)
        } else {
            handle(text)
        }
    }

    /// Renaming is active only when its selected landmark card is visible and not covered by invitation, finding, outing or bump UI.
    /// The renaming flag alone can outlive its visible card, so do not rely on it (A02 review).
    var renamingNow: String? {
        guard let id = renaming, selection == .landmark(id), proposal == nil, find == nil,
              remindPromptFor == nil, bumpStage == .idle else { return nil }
        return id
    }

    var suggestedPhrases: [String] {
        // During rename, offer suggested names; tapping one follows the same recap-confirmation path as speech.
        if let id = renamingNow, let lm = landmark(id) { return ai.alternativeNames(for: lm) }
        // Use only neighbors' names; omit invitation examples when no neighbors exist.
        let name = neighbors.first?.name
        if find != nil { return [L.t("我喺\(landmark(find?.landmarkID)?.name ?? "涼亭")", "我在\(landmark(find?.landmarkID)?.name ?? "涼亭")")] }
        if walk != nil { return [L.t("呢度好曬", "这里太晒"), L.t("呢度冇櫈", "这里没有凳子")] + (name.map { [L.t("過去搵\($0)", "去找\($0)"), L.t("約\($0)聽日朝早一齊行", "约\($0)明天早上一起走")] } ?? []) }
        if let a = targetAppointment(partnerID: nil), let p = resident(a.partnerID),
           let other = landmarks.filter({ $0.id != a.landmarkID }).max(by: { $0.name.count < $1.name.count }) {
            // Suggest a time different from the current meeting, such as five instead of four.
            let alt = Self.hk.component(.hour, from: a.date) == 16 ? "五" : "四"
            return [L.t("改做下晝\(alt)點", "改到下午\(alt)点"), L.t("改去\(other.name)", "改到\(other.name)"), L.t("取消同\(p.name)嘅約", "取消和\(p.name)的约会"), L.t("今日請假", "今天请假")]
        }
        // F10: offer reports only during walks. Omit rarely used rename suggestions that confused users about changing official place names (UX 33).
        // Weather examples use the local HKO response through showWeatherAnswer.
        let weather = [L.t("今日天氣點", "今天天气怎么样")]
        let find = residents.first(where: { $0.isNeighbor && !$0.isMe && $0.isOut }).map { [L.t("過去搵\($0.name)", "去找\($0.name)")] } ?? []
        return (name.map { [L.t("約\($0)聽日下晝三點一齊行", "约\($0)明天下午三点一起走")] } ?? []) + weather + find + [L.t("今日請假", "今天请假")]
    }

    func handle(_ text: String) {
        phrasePicker = false
        // Continuous conversation keeps listening without deferring speech.
        guard !conversing else { routeHeard(text); return }
        if listening { _ = listener.stop() }
        listening = false
        let held = announcer.release()
        defer { flushHeldSpeech(held) }
        routeHeard(text)
    }

    /// After input or an example tap, try device templates first; route invitations and unknown requests to B's assistant.
    private func routeHeard(_ text: String) {
        // Apply the local emergency and medical-response safety rules before App actions, regardless of server availability or language.
        if let s = TemplateAI.safety(text) { showSafety(s, heard: text); return }
        // A03: AI context includes only me and neighbors, excluding even non-neighbor names and floors.
        let known = residents.filter { $0.isMe || $0.isNeighbor }
        let ctx = AIContext(residents: known, landmarks: landmarks, now: now, walking: walk != nil, finding: find != nil)
        var intent = ai.parseVoice(text, context: ctx)
        // Use local HKO weather when the server path is unavailable or unsupported; the Cantonese server supports district, hourly and follow-up questions.
        if renamingNow == nil, intent == .unknown, TemplateAI.asksWeather(text),
           VoiceSettings.shared.language == .mandarin || !VoiceServer.shared.status.isConnected { showWeatherAnswer(text); return }
        // A02: after explicit rename input activation, treat the whole utterance as the new name.
        if let id = renamingNow {
            switch intent {
            case .rename, .leave, .report: break
            default:
                guard let name = Self.spokenName(text) else { toast(L.t("聽唔清個新名，講短啲（十個字以內）。", "没听清新名字，说短一点（十个字以内）。")); return }
                intent = .rename(landmarkID: id, newName: name)
            }
        }
        // Route invitations and unknown input to B when the voice server is available, otherwise use local templates.
        let heard = intent
        if renamingNow == nil, handleWithAssistant(text, local: heard, fallback: { [weak self] in self?.handleLocally(text, heard) }) { return }
        handleLocally(text, heard)
    }

    /// TemplateAI flow for offline use, demos and unavailable servers.
    func handleLocally(_ text: String, _ intent: VoiceIntent) {
        switch intent {
        case .invite(let id, let day, let hour):
            guard let p = resident(id), p.isNeighbor else { toast(L.t("你講嘅人仲未係你街坊。見到面碰一碰，先可以約。", "你说的人还不是你的邻居。见面碰一碰，才可以约。")); return }
            proposeMeetup(with: id, day: day, hour: hour, announce: false)
            if let prop = proposal?.options.first {
                let place = landmark(prop.landmarkID)?.name ?? ""
                let title = L.t("約\(p.name)\(dayTimeLabel(prop.date))一齊行", "约\(p.name)\(dayTimeLabel(prop.date))一起走")
                showConfirm(VoiceCard(heard: text, title: title, detail: L.t("地點：\(place)\n\(prop.reason)", "地点：\(place)\n\(prop.reason)"), needsConfirm: true, intent: intent),
                            spoken: L.t("\(title)，喺\(place)，\(prop.reason)", "\(title)，在\(place)，\(prop.reason)"))
            }
        case .goFind(let id):
            guard let p = resident(id), p.isNeighbor, p.isOut else { toast(L.t("而家冇街坊喺外面。", "现在没有邻居在外面。")); return }
            showConfirm(VoiceCard(heard: text, title: L.t("過去搵\(p.name)", "去找\(p.name)"), detail: L.t("會先問\(p.name)方唔方便", "会先问\(p.name)方不方便"), needsConfirm: true, intent: intent),
                        spoken: L.t("過去搵\(p.name)，會先問佢方唔方便", "去找\(p.name)，会先问对方方不方便"))
        case .leave:
            // Parse leave dates / duration from the original utterance; avoid duplicate cards that could withdraw previously granted leave.
            let r = LeaveRequest.parse(text, today: now)
            guard !leaveKeys(r).allSatisfy(leaveDays.contains) else { toast(L.t("你已經\(leaveTitle(r))喇。", "你已经\(leaveTitle(r))了。")); return }
            let title = requestLeave(fromVoice: text)
            voiceCard = VoiceCard(heard: text, title: title, detail: L.t("連續日數會保留", "连续天数会保留"), needsConfirm: false, intent: intent)
        case .rename(let id, let name):
            // F3 / A02: shared landmark renaming affects others and requires spoken recap and explicit confirmation.
            let old = landmark(id)?.name ?? ""
            guard name != old else { toast(L.t("而家已經叫\(name)。", "现在已经叫\(name)了。")); return }
            showConfirm(VoiceCard(heard: text, title: L.t("\(old)改名做\(name)？", "\(old)改名叫\(name)？"), detail: renameNote, needsConfirm: true, intent: intent))
        case .report(let kind):
            // F10 / A18: walking reports attach to the nearest landmark.
            guard walk != nil else { toast(L.t("散步時講「呢度好曬」「呢度冇櫈」，我會記喺附近嘅地標。", "散步时说「这里太晒」「这里没有凳子」，我会记在附近的地标。")); return }
            let rid = report(kind, rawText: text)
            voiceCard = VoiceCard(heard: text, title: L.t("記低：呢度\(kind.label)", "记下：这里\(kind.label)"), detail: reportNote, needsConfirm: false, intent: intent, reportID: rid)
        case .broadcast(let raw):
            // A11: the displayed recap matches the spoken sentence.
            let msg = Self.cleanBroadcast(raw)
            let name = find.flatMap { resident($0.partnerID)?.name } ?? L.t("對方", "对方")
            showConfirm(VoiceCard(heard: text, title: L.t("播俾\(name)聽", "播给\(name)听"), detail: msg, needsConfirm: true, intent: .broadcast(msg)),
                        spoken: L.t("播俾\(name)聽：\(msg)", "播给\(name)听：\(msg)"))
        case .changeMeetup(let pid, let day, let hour, let lmID):
            guard let a = targetAppointment(partnerID: pid) else { toast(L.t("而家冇約會可以改。", "现在没有约会可以改。")); return }
            let c = changed(a, day: day, hour: hour, landmarkID: lmID)
            guard c.date > now else { toast(L.t("嗰個時間已經過咗，揀過第二個。", "那个时间已经过了，换一个吧。")); return }
            guard c.date != a.date || c.landmarkID != a.landmarkID else { toast(L.t("時間地點都冇變，照舊。", "时间地点都没变，照旧。")); return }
            let name = resident(a.partnerID)?.name ?? L.t("街坊", "邻居")
            let place = landmark(c.landmarkID)?.name ?? ""
            showConfirm(VoiceCard(heard: text, title: L.t("改約\(name)：\(dayTimeLabel(c.date)) · \(place)", "改约\(name)：\(dayTimeLabel(c.date)) · \(place)"),
                                  detail: L.t("會再問\(name)確認\n\(c.reason)", "会再问\(name)确认\n\(c.reason)"), needsConfirm: true, intent: intent, appointmentID: a.id),
                        spoken: L.t("改約\(name)：\(dayTimeLabel(c.date))，喺\(place)，會再問\(name)確認", "改约\(name)：\(dayTimeLabel(c.date))，在\(place)，会再问\(name)确认"))
            scene.highlightLandmark(c.landmarkID)
        case .cancelMeetup(let pid):
            guard let a = targetAppointment(partnerID: pid) else { toast(L.t("而家冇約會可以取消。", "现在没有约会可以取消。")); return }
            let name = resident(a.partnerID)?.name ?? L.t("街坊", "邻居")
            showConfirm(VoiceCard(heard: text, title: L.t("取消同\(name)\(dayTimeLabel(a.date))嘅約", "取消和\(name)\(dayTimeLabel(a.date))的约"), detail: L.t("會話俾\(name)知", "会告诉\(name)"), needsConfirm: true, intent: intent, appointmentID: a.id))
        case .unknown:
            showNotUnderstood(text)
        }
    }

    /// If recognition produced text but neither parser understands it, do not claim the speech was inaudible.
    /// Repeat the transcript, explain the limitation and offer two or three tappable actionable examples.
    /// Answer weather locally with Today's HKO sentence even without the Mac server.
    func showNotUnderstood(_ text: String) {
        phrasePicker = false
        if TemplateAI.asksWeather(text) { showWeatherAnswer(text); return }
        let title: String
        switch TemplateAI.topic(text) {
        case .invite? where neighbors.isEmpty, .find? where neighbors.isEmpty:
            title = L.t("你仲未有街坊。見到面喺「街坊」頁碰一碰，之後就約得、搵得。", "你还没有邻居。见面时在「街坊」页碰一碰，之后就能约、能找。")
        case .invite?:
            title = L.t("想約邊個、幾時？講埋個名同時間，例如：", "想约谁、什么时候？说上名字和时间，比如：")
        case .find?:
            title = L.t("想搵邊個？講埋個名，例如：", "想找谁？说上名字，比如：")
        case .report? where walk == nil:
            title = L.t("散步嗰陣講「呢度冇櫈」「呢度好曬」，我會記喺附近嘅地標。", "散步时说「这里没有凳子」「这里太晒」，我会记在附近的地标。")
        default:
            title = L.t("呢句我未識做。可以噉講：", "这句我还不会做。可以这样说：")
        }
        let chips = voiceExamples
        voiceCard = VoiceCard(heard: text, title: title, detail: nil, needsConfirm: false, intent: .unknown,
                              assistant: AssistantCard(kind: .notUnderstood, title: title, spoken: title, chips: chips, conversationID: ""))
        let example = chips.first.map { L.t("例如「\($0)」。", "比如「\($0)」。") } ?? ""
        say(title.hasSuffix("：") ? String(title.dropLast()) + "，" + example : title, prompt: true)
    }

    /// Local weather matches Today; tomorrow questions add HKO's next-day rain probability.
    func showWeatherAnswer(_ text: String) {
        phrasePicker = false
        var answer = tryAnswer
        if TemplateAI.parseDay(TemplateAI.toHant(text)) == 1, !hko.demoOverride, let psr = hko.report?.tomorrowPSR, !psr.isEmpty {
            answer = Self.oneSentence([answer, L.t("天文台話聽日降雨機會\(psr)", "天文台说明天降雨概率\(psr)")])
        }
        voiceCard = VoiceCard(heard: text, title: answer, detail: nil, needsConfirm: false, intent: .unknown,
                              assistant: AssistantCard(kind: .info, title: answer, spoken: answer, conversationID: ""))
        say(answer)
    }

    /// TemplateAI.safety shows and immediately speaks safety guidance without executing App actions; withdraw pending recaps first.
    func showSafety(_ s: TemplateAI.Safety, heard text: String) {
        phrasePicker = false
        if voiceCard?.needsConfirm == true { rejectVoice() }
        assistantGen = UUID()   // Prevent an outstanding earlier server reply from replacing the safety card.
        assistant.reset()
        hush()
        let title: String, detail: String?
        switch s {
        case .emergency:
            title = L.t("有危險請即刻打 999 求助，或者叫身邊嘅人幫手。", "有危险请马上打 999 求助，或者叫身边的人帮忙。")
            detail = L.t("呢個 App 唔會自動幫你打電話。", "这个 App 不会自动帮你打电话。")
        case .medical:
            title = L.t("呢個我幫唔到，請問醫生或者藥劑師。", "这个我帮不了，请问医生或药剂师。")
            detail = nil
        }
        voiceCard = VoiceCard(heard: text, title: title, detail: detail, needsConfirm: false, intent: .unknown,
                              assistant: AssistantCard(kind: .info, title: title, detail: detail, spoken: title, conversationID: ""),
                              sticky: s == .emergency)
        say(title, prompt: true)
    }

    /// Offer only currently feasible examples: neighbors for inviting / finding, active walks for reports, local weather always available.
    var voiceExamples: [String] {
        var out: [String] = []
        if let n = neighbors.first {
            out.append(L.t("約\(n.name)聽日下晝三點一齊行", "约\(n.name)明天下午三点一起走"))
            if let o = neighbors.first(where: { $0.isOut }) { out.append(L.t("過去搵\(o.name)", "去找\(o.name)")) }
        }
        if walk != nil { out.append(L.t("呢度冇櫈", "这里没有凳子")) }
        out.append(L.t("今日天氣點", "今天天气怎么样"))
        if out.count < 3 { out.append(L.t("今日請假", "今天请假")) }
        return Array(out.prefix(3))
    }

    /// Section 4: show and speak confirmation recaps together, using the same localized confirmation wording as the button.
    private func showConfirm(_ card: VoiceCard, spoken: String? = nil) {
        voiceCard = card
        let s = (spoken ?? card.title).trimmingCharacters(in: CharacterSet(charactersIn: "。？?！! "))
        say(L.t("\(s)。啱就撳「好」。", "\(s)。没问题就按「好的」。"), prompt: true)
    }

    /// A69: rename/report explanations must not claim synchronization without a server connection.
    var renameNote: String { community.sharesLandmarkNames ? L.t("同圈街坊都會見到", "同圈邻居都会看到") : L.t("暫時只喺你部手機", "暂时只在你的手机上") }
    var reportNote: String { community.hasServer ? L.t("月尾匿名交俾屋邨管理（夠 10 人先會出）", "月底匿名交给屋苑管理（满 10 人才会出）") : L.t("暫時只喺你部手機", "暂时只在你的手机上") }

    /// Strip rename prefixes and punctuation; reject names longer than 10 Chinese characters as likely recognition errors.
    static func spokenName(_ text: String) -> String? {
        let strip = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        var s = text.trimmingCharacters(in: strip).replacingOccurrences(of: " ", with: "")
        for p in ["改名做", "改名叫", "改名為", "改名为", "改做", "改成", "改为", "就叫", "叫做", "叫"] where s.hasPrefix(p) {
            s.removeFirst(p.count)
            break
        }
        s = s.trimmingCharacters(in: strip)
        return (1...10).contains(s.count) ? s : nil
    }

    /// Trim whitespace and punctuation around the spoken sentence.
    static func cleanBroadcast(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    func confirmVoice() {
        guard let card = voiceCard else { return }
        hush()   // After confirmation, stop asking for confirmation and announce the result.
        if card.assistant != nil { assistantConfirm(card); return }
        voiceCard = nil
        switch card.intent {
        case .invite: confirmProposal()
        case .goFind(let id): goFind(id)
        case .broadcast(let msg): broadcastHere(msg)
        case .rename(let id, let name): rename(id, to: name)
        case .changeMeetup(_, let day, let hour, let lmID):
            scene.highlightLandmark(nil)
            if let id = card.appointmentID { changeMeetup(id, day: day, hour: hour, landmarkID: lmID) }
        case .cancelMeetup:
            if let id = card.appointmentID, appointments.contains(where: { $0.id == id && $0.isOpen }) { cancelMeetup(id) }
            else { toast(L.t("呢個約會已經冇咗。", "这个约会已经没有了。")) }
        default: break
        }
    }

    func rejectVoice() {
        guard let card = voiceCard else { return }
        hush()   // After cancellation, stop the pending invitation-confirmation prompt.
        voiceCard = nil
        if card.assistant != nil { assistantReject(card); return }
        switch card.intent {
        case .invite: cancelProposal()
        case .leave:
            cancelLeave(fromVoice: card.heard)
            say(L.t("撤回咗請假。", "已撤回请假。"))
        case .report: if let id = card.reportID { retractReport(id) }
        case .changeMeetup: scene.highlightLandmark(nil)
        default: break
        }
    }
}
