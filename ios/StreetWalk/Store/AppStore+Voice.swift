import SwiftUI
import AVFoundation
import Speech

// 语音
extension AppStore {
    // MARK: - 播报

    /// 所有播报都经呢度：排队唔互相截断、读屏开着改用公告、聆听中先收起、过期唔讲（见 Announcer）。
    /// prompt：要用户回应嘅句子（复述确认、问题），优先讲、唔会被挤走。
    /// force：用户亲手要求（「再聽一次」），设定入面「語音播報」关咗都读。
    func say(_ s: String, prompt: Bool = false, force: Bool = false) {
        // 连续对话：一路收音一路可以讲（回声消除），唔使收起；记低讲过咩（回声保险）
        if conversing { recentSpoken.append((s, Date())) }
        announcer.say(s, kind: prompt ? .prompt : .info, force: force, via: speaker, holding: listening && !conversing)
    }

    /// 「再聽一次」：停低而家讲紧嘅，即刻由头讲（排队嘅话，长句讲紧时再撳会排到过期、静静鸡唔讲）。
    func sayAgain(_ s: String) {
        guard !listening || conversing else { say(s, force: true); return }
        announcer.hold(speaker)
        _ = announcer.release()
        say(s, prompt: true, force: true)
    }

    /// 聆听结束：讲返聆听期间收起嘅提示（排喺对用户嗰句嘅回应之后；排得太耐嘅资讯句唔再讲）。
    func flushHeldSpeech(_ held: [Announcer.Line]) {
        held.forEach { announcer.enqueue($0, via: speaker, holding: listening && !conversing) }
    }

    // MARK: - 语音

    func micTapped() {
        if conversing { endConversation(); return }
        if listening { stopListening(); return }
        guard !micStarting else { return }
        // 复述卡仲等紧确认：当係「唔係」（收返高亮、撤回提议），唔好静静鸡丢咗。
        if voiceCard?.needsConfirm == true { rejectVoice() } else { voiceCard = nil }
        micStarting = true
        Task { @MainActor in
            defer { micStarting = false }
            // Mac 语音服务器有 B 嘅豆包识别：连续对话（AppStore+Conversation）；开唔到先用手机识别
            if canConverse, await startConversation() { return }
            // 第一次按咪：等用户答完权限框先开始听，唔系第一句会冇咗（A47）。
            let auth = await ensureVoiceAuth()
            guard auth.granted else {
                toast(L.t("未開咪或者語音識別權限。可以揀一句，或者去設定開。", "没开麦克风或语音识别权限。可以选一句，或者去设置打开。"))
                phrasePicker = true
                return
            }
            // 啱啱弹完权限框：等音频会话定落嚟先开咪（模拟器上即刻开录音引擎试过超时崩溃，见复核 A47）。
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

    /// 语音识别同麦克风权限：未问过就等用户答。granted：两样都允许；prompted：今次弹过权限框。
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

    /// 改名卡真係喺度先算改名中：揀中嗰个地标、冇约人 / 找人 / 出门提醒 / 碰一碰盖住。
    /// renaming 本身会留低（例如撳咗「改名」就去约人），唔好用佢判断（复核 A02）。
    var renamingNow: String? {
        guard let id = renaming, selection == .landmark(id), proposal == nil, find == nil,
              remindPromptFor == nil, bumpStage == .idle else { return nil }
        return id
    }

    var suggestedPhrases: [String] {
        // 改名中：建议几个新名，撳一个 = 讲咗个新名（之后照样复述确认）。
        if let id = renamingNow, let lm = landmark(id) { return ai.alternativeNames(for: lm) }
        // 只用街坊的名字（非街坊唔出名）；未有街坊就唔出约人嘅句子。
        let name = neighbors.first?.name
        if find != nil { return [L.t("我喺\(landmark(find?.landmarkID)?.name ?? "涼亭")", "我在\(landmark(find?.landmarkID)?.name ?? "涼亭")")] }
        if walk != nil { return [L.t("呢度好曬", "这里太晒"), L.t("呢度冇櫈", "这里没有凳子")] + (name.map { [L.t("過去搵\($0)", "去找\($0)"), L.t("約\($0)聽日朝早一齊行", "约\($0)明天早上一起走")] } ?? []) }
        if let a = targetAppointment(partnerID: nil), let p = resident(a.partnerID),
           let other = landmarks.filter({ $0.id != a.landmarkID }).max(by: { $0.name.count < $1.name.count }) {
            // 建议一个同而家唔同嘅钟点（约咗四点就建议五点）。
            let alt = Self.hk.component(.hour, from: a.date) == 16 ? "五" : "四"
            return [L.t("改做下晝\(alt)點", "改到下午\(alt)点"), L.t("改去\(other.name)", "改到\(other.name)"), L.t("取消同\(p.name)嘅約", "取消和\(p.name)的约会"), L.t("今日請假", "今天请假")]
        }
        // 反映只喺散步时讲（F10）；唔散步时唔建议。
        return (name.map { [L.t("約\($0)聽日下晝三點一齊行", "约\($0)明天下午三点一起走")] } ?? []) + [L.t("今日請假", "今天请假"), L.t("\(landmarks.first?.name ?? "涼亭")改名做大樹底", "\(landmarks.first?.name ?? "涼亭")改名叫大樹底")]
    }

    func handle(_ text: String) {
        phrasePicker = false
        // 连续对话：继续听，唔使收起播报
        guard !conversing else { routeHeard(text); return }
        if listening { _ = listener.stop() }
        listening = false
        let held = announcer.release()
        defer { flushHeldSpeech(held) }
        routeHeard(text)
    }

    /// 听到 / 揀咗一句之后：手机模板先认，约人同听唔明嘅交俾组员 B 嘅助手。
    private func routeHeard(_ text: String) {
        // 只俾 AI 睇我同街坊（非街坊连名都唔传，A03）。讲非街坊个名 = 听唔明，唔会讲出佢住几楼。
        let known = residents.filter { $0.isMe || $0.isNeighbor }
        let ctx = AIContext(residents: known, landmarks: landmarks, now: now, walking: walk != nil, finding: find != nil)
        var intent = ai.parseVoice(text, context: ctx)
        // 地标卡撳咗「講新名」：成句当新名（A02）。
        if let id = renamingNow {
            switch intent {
            case .rename, .leave, .report: break
            default:
                guard let name = Self.spokenName(text) else { toast(L.t("聽唔清個新名，講短啲（十個字以內）。", "没听清新名字，说短一点（十个字以内）。")); return }
                intent = .rename(landmarkID: id, newName: name)
            }
        }
        // 约人 / 听唔明：有 Mac 语音服务器就交俾组员 B 嘅助手（AppStore+Assistant）；冇就照旧用手机模板。
        let heard = intent
        if renamingNow == nil, handleWithAssistant(text, local: heard, fallback: { [weak self] in self?.handleLocally(text, heard) }) { return }
        handleLocally(text, heard)
    }

    /// 手机模板（TemplateAI）嘅流程：离线、演示模式、服务器连唔到时都系呢个。
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
            // 按原句判断日子（「聽日請假」「請三日假」）；已经请咗就唔再出卡（免得「撤回」撤咗之前请嘅假）。
            let r = LeaveRequest.parse(text, today: now)
            guard !leaveKeys(r).allSatisfy(leaveDays.contains) else { toast(L.t("你已經\(leaveTitle(r))喇。", "你已经\(leaveTitle(r))了。")); return }
            let title = requestLeave(fromVoice: text)
            voiceCard = VoiceCard(heard: text, title: title, detail: L.t("連續日數會保留", "连续天数会保留"), needsConfirm: false, intent: intent)
        case .rename(let id, let name):
            // 改名全圈生效（F3）：影响别人，先复述，撳「好」先改（A02）。
            let old = landmark(id)?.name ?? ""
            guard name != old else { toast(L.t("而家已經叫\(name)。", "现在已经叫\(name)了。")); return }
            showConfirm(VoiceCard(heard: text, title: L.t("\(old)改名做\(name)？", "\(old)改名叫\(name)？"), detail: renameNote, needsConfirm: true, intent: intent))
        case .report(let kind):
            // F10：反映喺散步时讲，挂喺最近嘅地标（A18）。
            guard walk != nil else { toast(L.t("散步時講「呢度好曬」「呢度冇櫈」，我會記喺附近嘅地標。", "散步时说「这里太晒」「这里没有凳子」，我会记在附近的地标。")); return }
            let rid = report(kind, rawText: text)
            voiceCard = VoiceCard(heard: text, title: L.t("記低：呢度\(kind.label)", "记下：这里\(kind.label)"), detail: reportNote, needsConfirm: false, intent: intent, reportID: rid)
        case .broadcast(let raw):
            // 复述同真正播出去嘅係同一句（A11）。
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
            say(L.t("唔好意思，我未聽明白。可以再講一次，或者揀一句。", "不好意思，我没听明白。可以再说一次，或者选一句。"), prompt: true)
            phrasePicker = true
        }
    }

    /// 要撳「好」嘅复述卡：画面同语音一齐出（§4），讲埋点样确认。
    private func showConfirm(_ card: VoiceCard, spoken: String? = nil) {
        voiceCard = card
        let s = (spoken ?? card.title).trimmingCharacters(in: CharacterSet(charactersIn: "。？?！! "))
        say(L.t("\(s)。啱就撳「好」。", "\(s)。没问题就按「好」。"), prompt: true)
    }

    /// 改名、反映嘅说明：未接伺服器时唔好讲成已经同步咗（A69）。
    var renameNote: String { community.sharesLandmarkNames ? L.t("同圈街坊都會見到", "同圈邻居都会看到") : L.t("暫時只喺你部手機", "暂时只在你的手机上") }
    var reportNote: String { community.hasServer ? L.t("月尾匿名交俾屋邨管理（夠 10 人先會出）", "月底匿名交给屋苑管理（满 10 人才会出）") : L.t("暫時只喺你部手機", "暂时只在你的手机上") }

    /// 改名中只讲新名：去掉「改名做」「叫」之类同标点；太长（超过 10 个字）当听错。
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

    /// 播送嘅句子：去掉头尾空格同标点。
    static func cleanBroadcast(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    func confirmVoice() {
        guard let card = voiceCard else { return }
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
