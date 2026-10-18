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

    /// 停低兼清空播报（换标签、开关设定、引导换页、关卡、取消、退后台）。连续对话照听，唔会收咪。
    func hush() {
        announcer.interrupt(speaker)
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
        // 复述卡仲等紧确认：张卡留住，开咪听「好 / 不要」（2026-10-17 用户测试：讲「不要」冇反应）；讲第二句就当新请求。
        let answer: Listener.Answer? = voiceCard?.needsConfirm == true ? .confirm : nil
        if answer == nil { voiceCard = nil }
        _ = listener.nextAnswerGen()   // 等紧自动开咪嘅作废
        micStarting = true
        Task { @MainActor in
            defer { micStarting = false }
            // Mac 语音服务器有 B 嘅豆包识别：连续对话（AppStore+Conversation）；开唔到先用手机识别
            if canConverse, await startConversation() { return }
            // 第一次按咪：等用户答完权限框先开始听，唔系第一句会冇咗（A47）。
            let auth = await ensureVoiceAuth()
            guard auth.granted else {
                toast(L.t("未開咪或者語音識別權限。可以揀一句，或者去設定開。", "没开麦克风或语音识别权限。可以选一句，或者去设置打开。", "No mic or speech permission. Pick a sentence, or turn it on in Settings."))
                phrasePicker = true
                return
            }
            // 啱啱弹完权限框：等音频会话定落嚟先开咪（模拟器上即刻开录音引擎试过超时崩溃，见复核 A47）。
            if auth.prompted { try? await Task.sleep(for: .milliseconds(400)) }
            guard AVAudioSession.sharedInstance().isInputAvailable else {
                toast(L.t("而家用唔到咪，可以揀一句。", "现在用不了麦克风，可以选一句。", "The mic isn't available now. Pick a sentence."))
                phrasePicker = true
                return
            }
            announcer.hold(speaker)
            do {
                // 讲完停 1.5 秒就自动当讲完（唔使撳「講完」；2026-10-17 用户测试：讲完冇反应，以为认唔到，再讲一次字就叠埋）
                listener.answering = answer
                listener.onSilence = { [weak self] in self?.listenerSilent() }
                try listener.start(idle: answer == nil ? 15 : 8)
                listening = true
                Haptics.light()
            } catch {
                listener.answering = nil
                listener.onSilence = nil
                listening = false
                flushHeldSpeech(announcer.release())
                toast(L.t("而家用唔到咪，可以揀一句。", "现在用不了麦克风，可以选一句。", "The mic isn't available now. Pick a sentence."))
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
        let answering = listener.answering != nil
        let text = listener.stop()
        listening = false
        if text.isEmpty {
            let held = announcer.release()
            // 自动开咪等答案（复述卡 / 帮助卡）冇人讲：静静鸡收咪，张卡同掣照留
            if !answering {
                say(L.t("聽唔清楚。可以再講一次，或者揀一句。", "没听清楚。可以再说一次，或者选一句。", "Didn't catch that. Please say it again, or pick a sentence."), prompt: true)
                phrasePicker = true
            }
            flushHeldSpeech(held)
        } else {
            handle(text)
        }
    }

    /// 手机识别：讲完停咗一阵 / 一直冇讲嘢（Listener.onSilence）。
    func listenerSilent() {
        guard listening, !conversing else { return }
        stopListening()
    }

    // MARK: - 卡出咗之后自动再听一次（手机识别；连续对话本身一直听紧）

    /// 复述卡（等「好 / 不要」）、帮助卡（例句）、助手问问题：提示讲完就自动开咪听一次，唔使再撳咪（2026-10-17 用户测试）。
    /// 只喺已经俾咗咪同语音识别权限、冇开读屏、喺主画面前台时先开；8 秒冇人讲就静静鸡收咪（张卡同掣照留）。
    func listenForAnswer(_ kind: Listener.Answer) {
        guard !conversing, let id = voiceCard?.id, Self.autoListenAllowed else { return }
        let gen = listener.nextAnswerGen()
        Task { @MainActor [weak self] in
            let start = Date()
            var quiet = 0
            // 等提示讲完（最多 25 秒）：连续两次睇到冇讲紧、冇排紧先开（播报会抢咪，仲会录埋入去）
            while Date().timeIntervalSince(start) < 25 {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.listener.answerGen == gen else { return }
                quiet = self.speaker.isSpeaking || !self.announcer.queued.isEmpty ? 0 : quiet + 1
                if quiet >= 2 && Date().timeIntervalSince(start) > 0.6 { break }
            }
            guard let self, self.listener.answerGen == gen, self.voiceCard?.id == id, !self.listening, !self.conversing, !self.micStarting,
                  self.phase == .main, !self.showSettings, UIApplication.shared.applicationState == .active,
                  AVAudioSession.sharedInstance().isInputAvailable else { return }
            self.announcer.hold(self.speaker)
            self.listener.answering = kind
            self.listener.onSilence = { [weak self] in self?.listenerSilent() }
            do {
                try self.listener.start(idle: 8)
                self.listening = true
            } catch {
                self.listener.answering = nil
                self.listener.onSilence = nil
                self.flushHeldSpeech(self.announcer.release())
                return
            }
            // 张卡收咗 / 换咗（撳「收起」、自动收）：咪都收埋，唔好变成一张空白「聽緊」卡
            while self.listening, self.listener.answering != nil, self.listener.answerGen == gen {
                try? await Task.sleep(for: .milliseconds(300))
                if self.voiceCard?.id != id { self.stopAnswerListening(); return }
            }
        }
    }

    /// 自动开咪：已经俾咗权限（唔会自己弹权限框）、冇开读屏、唔系自动演示。
    static var autoListenAllowed: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVAudioApplication.shared.recordPermission == .granted
            && !UIAccessibility.isVoiceOverRunning && !Speaker.scripted
    }

    /// 撳咗卡上嘅掣 / 张卡换咗：自动开咗嘅咪收埋（唔处理听到嘅字）。
    func stopAnswerListening() {
        _ = listener.nextAnswerGen()
        guard listening, !conversing, listener.answering != nil else { return }
        _ = listener.stop()
        listening = false
        flushHeldSpeech(announcer.release())
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
        if find != nil { return [L.t("我喺\(landmark(find?.landmarkID)?.name ?? "涼亭")", "我在\(landmark(find?.landmarkID)?.name ?? "涼亭")", "I'm at \(landmark(find?.landmarkID)?.name ?? "the pavilion")")] }
        // 散步中：三种反映 + 一句同街坊有关（有街坊喺外面就去找，冇就约聽日）或者问天气，一共 4 句
        // （10-18 真机：冇街坊时只剩「太晒 / 没凳子」两句）
        if walk != nil {
            let out = residents.first(where: { $0.isNeighbor && !$0.isMe && $0.isOut })
            let social = out.map { L.t("過去搵\($0.name)", "去找\($0.name)", "Go find \($0.name)") }
                ?? name.map { L.t("約\($0)聽日朝早一齊行", "约\($0)明天早上一起走", "Invite \($0) tomorrow morning") }
                ?? L.t("今日天氣點", "今天天气怎么样", "What's the weather today?")
            return [L.t("呢度好曬", "这里太晒", "Too sunny here"), L.t("呢度冇櫈", "这里没有凳子", "No seats here"),
                    L.t("呢度難行", "这里路难走", "Hard to walk here"), social]
        }
        if let a = targetAppointment(partnerID: nil), let p = resident(a.partnerID),
           let other = landmarks.filter({ $0.id != a.landmarkID }).max(by: { $0.name.count < $1.name.count }) {
            // 建议一个同而家唔同嘅钟点（约咗四点就建议五点）。
            let five = Self.hk.component(.hour, from: a.date) == 16
            let alt = five ? "五" : "四", altEn = five ? "5" : "4"
            return [L.t("改做下晝\(alt)點", "改到下午\(alt)点", "Change to \(altEn) pm"), L.t("改去\(other.name)", "改到\(other.name)", "Move to \(other.name)"), L.t("取消同\(p.name)嘅約", "取消和\(p.name)的约会", "Cancel walk with \(p.name)"), L.t("今日請假", "今天请假", "Day off today")]
        }
        // 反映只喺散步时讲（F10）；唔散步时唔建议。改地标名好少用、仲会以为改咗地名（UX 报告 33），唔建议；
        // 问天气：手机自己答天文台嗰句（showWeatherAnswer，唔交服务器）。
        let weather = [L.t("今日天氣點", "今天天气怎么样", "What's the weather today?")]
        let find = residents.first(where: { $0.isNeighbor && !$0.isMe && $0.isOut }).map { [L.t("過去搵\($0.name)", "去找\($0.name)", "Go find \($0.name)")] } ?? []
        return (name.map { [L.t("約\($0)聽日下晝三點一齊行", "约\($0)明天下午三点一起走", "Invite \($0) tomorrow at 3 pm")] } ?? []) + weather + find + [L.t("今日請假", "今天请假", "Day off today")]
    }

    func handle(_ text: String) {
        let text = Listener.collapseRepeats(text)   // 口吃 / 识别重复嘅词（「帮我帮我约」）收埋
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
        // 安全先行（两种语言、有冇 Mac 服务器都一样）：求救叫打 999；问食咩藥 / 睇咩醫生叫问医生（B 嘅规则只喺粤语服务器有）。
        if let s = TemplateAI.safety(text) { showSafety(s, heard: text); return }
        // 复述卡等紧确认：讲「好 / 可以 / 行」= 撳「好」，讲「不要 / 算了 / 取消」= 撳「唔係」（2026-10-17 用户测试）
        if answerConfirm(text) { return }
        // 只俾 AI 睇我同街坊（非街坊连名都唔传，A03）。讲非街坊个名 = 听唔明，唔会讲出佢住几楼。
        let known = residents.filter { $0.isMe || $0.isNeighbor }
        let ctx = AIContext(residents: known, landmarks: landmarks, now: now, walking: walk != nil, finding: find != nil)
        var intent = ai.parseVoice(text, context: ctx)
        // 问天气：普通话（B 嘅服务器普通话唔答天气）或者连唔到 Mac 时手机自己答（天文台）；粤语有服务器就照旧交俾 B（分区、逐个钟、「咁聽日呢」都答到）。
        if renamingNow == nil, intent == .unknown, TemplateAI.asksWeather(text),
           VoiceSettings.shared.language != .cantonese || !VoiceServer.shared.status.isConnected { showWeatherAnswer(text); return }
        // 地标卡撳咗「講新名」：成句当新名（A02）。
        if let id = renamingNow {
            switch intent {
            case .rename, .leave, .report: break
            default:
                guard let name = Self.spokenName(text) else { toast(L.t("聽唔清個新名，講短啲（十個字以內）。", "没听清新名字，说短一点（十个字以内）。", "Didn't catch the new name. Say a shorter one.")); return }
                intent = .rename(landmarkID: id, newName: name)
            }
        }
        // 约人 / 听唔明：有 Mac 语音服务器就交俾组员 B 嘅助手（AppStore+Assistant）；冇就照旧用手机模板。
        let heard = intent
        if renamingNow == nil, handleWithAssistant(text, local: heard, fallback: { [weak self] in self?.handleLocally(text, heard) }) { return }
        handleLocally(text, heard)
    }

    /// 对住等紧确认嘅复述卡讲嘢：「好」类 → 确认；「唔好」类 → 撤回；好短又听唔明（多数系听错咗「好」）→ 张卡留住、再问一次。
    /// 返回 true = 已经处理。长句当新请求：手机自己嘅复述卡先撤回（同以前撳咪一样）；助手嘅卡唔撤（B 嘅对话可以接住改）。
    func answerConfirm(_ text: String) -> Bool {
        guard let card = voiceCard, card.needsConfirm else { return false }
        switch Self.yesNo(text) {
        case .yes?:
            confirmVoice()
            return true
        case .no?:
            rejectVoice()
            say(L.t("好，唔做。", "好，不做了。", "OK, not doing it."))
            return true
        case nil:
            let t = text.filter { !$0.isPunctuation && !$0.isWhitespace }
            // 改名中两个字可能系新名；「請假」之类系新请求（英文：一两个字）
            let english = EnglishText.isEnglish(text)
            let short = english ? EnglishText.words(text).count <= 2 : t.count <= 2
            if short, renamingNow == nil, !TemplateAI.asksLeave(english ? text : TemplateAI.toHant(t)), TemplateAI.topic(english ? text : t) == nil {
                say(L.t("想做就講「好」，唔要就講「唔好」，或者撳掣。", "要的话说「好」，不要就说「不要」，也可以按按钮。", "Say \"yes\" to go ahead, or \"no\" to stop. Or tap a button."), prompt: true)
                listenForAnswer(.confirm)
                return true
            }
            if card.assistant == nil { rejectVoice() }
            return false
        }
    }

    /// 手机模板（TemplateAI）嘅流程：离线、演示模式、服务器连唔到时都系呢个。
    func handleLocally(_ text: String, _ intent: VoiceIntent) {
        switch intent {
        case .invite(let id, let day, let hour):
            guard let p = resident(id), p.isNeighbor else { toast(L.t("你講嘅人仲未係你街坊。見到面碰一碰，先可以約。", "你说的人还不是你的邻居。见面碰一碰，才可以约。", "That person isn't your neighbour yet. Tap phones when you meet, then you can invite them.")); return }
            proposeMeetup(with: id, day: day, hour: hour, announce: false)
            // 讲咗分钟（「三點十五」）、行几耐（「走四十分鐘」）：复述卡讲埋（理由加「一齊行…」，对方都见到）
            let walk = applySpokenTime(text, day: day, hour: hour)
            if let prop = proposal?.options.first {
                let place = landmark(prop.landmarkID)?.name ?? ""
                let how = walk.map(TemplateAI.walkPhrase) ?? L.t("一齊行", "一起走", "")
                let title = L.t("約\(p.name)\(dayTimeLabel(prop.date))\(how)", "约\(p.name)\(dayTimeLabel(prop.date))\(how)",
                                "Walk with \(p.name) \(dayTimeLabel(prop.date))" + (how.isEmpty ? "" : " " + how))
                let why = walk.map { prop.reason.replacingOccurrences(of: Self.walkNote($0), with: "") } ?? prop.reason
                showConfirm(VoiceCard(heard: text, title: title, detail: L.t("地點：\(place)\n\(why)", "地点：\(place)\n\(why)", "Place: \(place)\n\(why)"), needsConfirm: true, intent: intent),
                            spoken: L.t("\(title)，喺\(place)，\(why)", "\(title)，在\(place)，\(why)", "\(title), at \(place). \(why)"))
            }
        case .goFind(let id):
            guard let p = resident(id), p.isNeighbor, p.isOut else { toast(L.t("而家冇街坊喺外面。", "现在没有邻居在外面。", "No neighbours are out now.")); return }
            showConfirm(VoiceCard(heard: text, title: L.t("過去搵\(p.name)", "去找\(p.name)", "Find \(p.name)"), detail: L.t("會先問\(p.name)方唔方便", "会先问\(p.name)方不方便", "We'll ask \(p.name) first if it's OK"), needsConfirm: true, intent: intent),
                        spoken: L.t("過去搵\(p.name)，會先問佢方唔方便", "去找\(p.name)，会先问对方方不方便", "Find \(p.name). We'll ask them first if it's OK"))
        case .leave:
            // 按原句判断日子（「聽日請假」「請三日假」）；已经请咗就唔再出卡（免得「撤回」撤咗之前请嘅假）。
            let r = LeaveRequest.parse(Self.leaveText(text), today: now)
            guard !leaveKeys(r).allSatisfy(leaveDays.contains) else { toast(L.t("你已經\(leaveTitle(r))喇。", "你已经\(leaveTitle(r))了。", "Already set: \(leaveTitle(r)).")); return }
            let title = requestLeave(fromVoice: Self.leaveText(text))
            voiceCard = VoiceCard(heard: text, title: title, detail: L.t("連續日數會保留", "连续天数会保留", "Your streak is kept"), needsConfirm: false, intent: intent)
        case .rename(let id, let name):
            // 改名全圈生效（F3）：影响别人，先复述，撳「好」先改（A02）。
            let old = landmark(id)?.name ?? ""
            guard name != old else { toast(L.t("而家已經叫\(name)。", "现在已经叫\(name)了。", "It's already called \(name).")); return }
            showConfirm(VoiceCard(heard: text, title: L.t("\(old)改名做\(name)？", "\(old)改名叫\(name)？", "Rename \(old) to \(name)?"), detail: renameNote, needsConfirm: true, intent: intent))
        case .report(let kind):
            // F10：反映喺散步时讲，挂喺最近嘅地标（A18）。
            guard walk != nil else { toast(L.t("散步時講「呢度好曬」「呢度冇櫈」，我會記喺附近嘅地標。", "散步时说「这里太晒」「这里没有凳子」，我会记在附近的地标。", "While walking, say \"Too sunny here\" or \"No seats here\". I'll note it at the nearest landmark.")); return }
            let rid = report(kind, rawText: text)
            voiceCard = VoiceCard(heard: text, title: L.t("記低：呢度\(kind.label)", "记下：这里\(kind.label)", "Noted: \(kind.label) here"), detail: reportNote, needsConfirm: false, intent: intent, reportID: rid)
        case .broadcast(let raw):
            // 复述同真正播出去嘅係同一句（A11）。
            let msg = Self.cleanBroadcast(raw)
            let name = find.flatMap { resident($0.partnerID)?.name } ?? L.t("對方", "对方", "them")
            showConfirm(VoiceCard(heard: text, title: L.t("播俾\(name)聽", "播给\(name)听", "Send to \(name)"), detail: msg, needsConfirm: true, intent: .broadcast(msg)),
                        spoken: L.t("播俾\(name)聽：\(msg)", "播给\(name)听：\(msg)", "Send to \(name): \(msg)"))
        case .changeMeetup(let pid, let day, let hour, let lmID):
            guard let a = targetAppointment(partnerID: pid) else { toast(L.t("而家冇約會可以改。", "现在没有约会可以改。", "No walk plan to change.")); return }
            let c = changed(a, day: day, hour: hour, minute: hour == nil ? 0 : TemplateAI.spokenMinute(text), landmarkID: lmID)
            guard c.date > now else { toast(L.t("嗰個時間已經過咗，揀過第二個。", "那个时间已经过了，换一个吧。", "That time has passed. Pick another.")); return }
            guard c.date != a.date || c.landmarkID != a.landmarkID else { toast(L.t("時間地點都冇變，照舊。", "时间地点都没变，照旧。", "Same time and place. No change.")); return }
            let name = resident(a.partnerID)?.name ?? L.t("街坊", "邻居", "your neighbour")
            let place = landmark(c.landmarkID)?.name ?? ""
            showConfirm(VoiceCard(heard: text, title: L.t("改約\(name)：\(dayTimeLabel(c.date)) · \(place)", "改约\(name)：\(dayTimeLabel(c.date)) · \(place)", "Change walk with \(name): \(dayTimeLabel(c.date)) · \(place)"),
                                  detail: L.t("會再問\(name)確認\n\(c.reason)", "会再问\(name)确认\n\(c.reason)", "We'll ask \(name) again\n\(c.reason)"), needsConfirm: true, intent: intent, appointmentID: a.id),
                        spoken: L.t("改約\(name)：\(dayTimeLabel(c.date))，喺\(place)，會再問\(name)確認", "改约\(name)：\(dayTimeLabel(c.date))，在\(place)，会再问\(name)确认", "Change walk with \(name) to \(dayTimeLabel(c.date)), at \(place). We'll ask \(name) again"))
            scene.highlightLandmark(c.landmarkID)
        case .cancelMeetup(let pid):
            guard let a = targetAppointment(partnerID: pid) else { toast(L.t("而家冇約會可以取消。", "现在没有约会可以取消。", "No walk plan to cancel.")); return }
            let name = resident(a.partnerID)?.name ?? L.t("街坊", "邻居", "your neighbour")
            showConfirm(VoiceCard(heard: text, title: L.t("取消同\(name)\(dayTimeLabel(a.date))嘅約", "取消和\(name)\(dayTimeLabel(a.date))的约", "Cancel walk with \(name), \(dayTimeLabel(a.date))"), detail: L.t("會話俾\(name)知", "会告诉\(name)", "We'll tell \(name)"), needsConfirm: true, intent: intent, appointmentID: a.id))
        case .unknown:
            showNotUnderstood(text)
        }
    }

    /// 听到咗字但唔知做乜（手机模板 / Mac 助手都认唔到）：唔好话「冇聽清楚」（用户睇到字已经认咗）。
    /// 复述听到嘅句子，讲清楚点解做唔到，再俾两三句撳得嘅例句（撳 = 讲咗嗰句）。
    /// 问天气：冇 Mac 服务器都答（天文台嗰句，同「今日」页一样）。
    func showNotUnderstood(_ text: String) {
        phrasePicker = false
        if TemplateAI.asksWeather(text) { showWeatherAnswer(text); return }
        let title: String
        switch TemplateAI.topic(text) {
        case .invite? where neighbors.isEmpty, .find? where neighbors.isEmpty:
            title = L.t("你仲未有街坊。見到面喺「街坊」頁碰一碰，之後就約得、搵得。", "你还没有邻居。见面时在「街坊」页碰一碰，之后就能约、能找。", "No neighbours yet. When you meet, tap phones on the Neighbours page. Then you can invite and find them.")
        case .invite?:
            title = L.t("想約邊個、幾時？講埋個名同時間，例如：", "想约谁、什么时候？请说出名字和时间，比如：", "Who and when? Say a name and a time.")
        case .find?:
            title = L.t("想搵邊個？講埋個名，例如：", "想找谁？请说出名字，比如：", "Find who? Say a name.")
        case .report? where walk == nil:
            title = L.t("散步嗰陣講「呢度冇櫈」「呢度好曬」，我會記喺附近嘅地標。", "散步时说「这里没有凳子」「这里太晒」，我会记在附近的地标。", "While walking, say \"No seats here\" or \"Too sunny here\". I'll note it at the nearest landmark.")
        default:
            title = L.t("呢句我未識做。可以噉講：", "这句我还不会做。可以这样说：", "I can't do that yet. You can say:")
        }
        let chips = voiceExamples
        voiceCard = VoiceCard(heard: text, title: title, detail: nil, needsConfirm: false, intent: .unknown,
                              assistant: AssistantCard(kind: .notUnderstood, title: title, spoken: title, chips: chips, conversationID: ""))
        let example = chips.first.map { L.t("例如「\($0)」。", "比如「\($0)」。", "For example: \"\($0)\".") } ?? ""
        // 标题本身以「例如：」结尾就唔好再讲多次「例如」（以前讲成「比如，比如『…』」）
        let lead = String(title.dropLast())
        let spoken = L.isEn ? title + (chips.first.map { title.hasSuffix(":") ? " \"\($0)\"." : " For example: \"\($0)\"." } ?? "")
            : !title.hasSuffix("：") ? title
            : lead.hasSuffix("例如") || lead.hasSuffix("比如") ? lead + (chips.first.map { "「\($0)」。" } ?? "。")
            : lead + "，" + example
        say(spoken, prompt: true)
        // 手机识别：讲完就再开咪，用户直接再讲一次就得，唔使撳例句（2026-10-17 用户测试）
        listenForAnswer(.retry)
    }

    /// 问天气：手机答天文台嗰句（同「今日」页一样）；问聽日就加埋天文台嘅聽日降雨机会。
    func showWeatherAnswer(_ text: String) {
        phrasePicker = false
        refreshWeatherTip()   // 用而家嘅界面语言重出（唔好用转语言之前定咗嘅句子）
        var answer = tryAnswer
        if TemplateAI.parseDay(TemplateAI.toHant(text)) == 1, !hko.demoOverride, let psr = hko.report?.tomorrowPSR, !psr.isEmpty {
            answer = Self.oneSentence([answer, L.t("天文台話聽日降雨機會\(psr)", "天文台说明天降雨概率\(psr)", "The Observatory says the chance of rain tomorrow is \(HKOReport.psrEnglish(psr))")])
        }
        voiceCard = VoiceCard(heard: text, title: answer, detail: nil, needsConfirm: false, intent: .unknown,
                              assistant: AssistantCard(kind: .info, title: answer, spoken: answer, conversationID: ""))
        say(answer)
    }

    /// 求救 / 问医疗（TemplateAI.safety）：唔做任何 App 动作，出卡兼即刻讲。等紧确认嘅复述卡先撤回。
    func showSafety(_ s: TemplateAI.Safety, heard text: String) {
        phrasePicker = false
        if voiceCard?.needsConfirm == true { rejectVoice() }
        assistantGen = UUID()   // 服务器仲答紧上一句：答返嚟都唔好盖住呢张卡
        assistant.reset()
        hush()
        let title: String, detail: String?
        switch s {
        case .emergency:
            title = L.t("有危險請即刻打 999 求助，或者叫身邊嘅人幫手。", "有危险请马上打 999 求助，或者叫身边的人帮忙。", "If you are in danger, call 999 now, or ask someone nearby for help.")
            detail = L.t("呢個 App 唔會自動幫你打電話。", "这个 App 不会自动帮你打电话。", "This app will not call for you.")
        case .medical:
            title = L.t("呢個我幫唔到，請問醫生或者藥劑師。", "这个我帮不了，请问医生或药剂师。", "I can't help with this. Please ask a doctor or pharmacist.")
            detail = nil
        }
        voiceCard = VoiceCard(heard: text, title: title, detail: detail, needsConfirm: false, intent: .unknown,
                              assistant: AssistantCard(kind: .info, title: title, detail: detail, spoken: title, conversationID: ""),
                              sticky: s == .emergency)
        say(title, prompt: true)
    }

    /// 撳得嘅例句：只出而家真係做得到嘅（有街坊先出约人 / 找人；散步先出反映；天气手机都答到）。
    var voiceExamples: [String] {
        var out: [String] = []
        if let n = neighbors.first {
            out.append(L.t("約\(n.name)聽日下晝三點一齊行", "约\(n.name)明天下午三点一起走", "Invite \(n.name) tomorrow at 3 pm"))
            if let o = neighbors.first(where: { $0.isOut }) { out.append(L.t("過去搵\(o.name)", "去找\(o.name)", "Go find \(o.name)")) }
        }
        if walk != nil { out.append(L.t("呢度冇櫈", "这里没有凳子", "No seats here")) }
        out.append(L.t("今日天氣點", "今天天气怎么样", "What's the weather today?"))
        if out.count < 3 { out.append(L.t("今日請假", "今天请假", "Day off today")) }
        return Array(out.prefix(3))
    }

    /// 要撳「好」嘅复述卡：画面同语音一齐出（§4），讲埋点样确认（同个掣一样：粤语「好」、普通话「好的」）。
    private func showConfirm(_ card: VoiceCard, spoken: String? = nil) {
        voiceCard = card
        let s = (spoken ?? card.title).trimmingCharacters(in: CharacterSet(charactersIn: "。？?！! "))
        say(Self.confirmPrompt(s), prompt: true)
        listenForAnswer(.confirm)
    }

    /// 复述卡讲完点样确认：讲「好」或者撳掣（2026-10-17 起讲「好 / 不要」都得）。
    static func confirmPrompt(_ s: String) -> String {
        L.t("\(s)。啱就講「好」或者撳「好」。", "\(s)。没问题就说「好」，或者按「好的」。", "\(s). If that's right, say \"OK\" or tap OK.")
    }

    /// 理由后面加嘅「，一齊行四十分鐘」（同 setCustomProposal 一样写入理由，对方都见到）。
    static func walkNote(_ minutes: Int) -> String {
        L.t("，", "，", ", walk together ") + TemplateAI.walkPhrase(minutes)
    }

    /// 请假句：英文先转成中文写法（LeaveRequest.parse 认中文），中文原样。
    static func leaveText(_ text: String) -> String {
        EnglishText.isEnglish(text) ? EnglishText.leaveText(text) : text
    }

    /// 约人讲咗分钟（「三點十五」）同行几耐（「走四十分鐘」）：改第一个提议嘅时间、全部提议嘅理由。
    /// 返回行几耐（分钟）；冇讲返回 nil。
    @discardableResult
    func applySpokenTime(_ text: String, day: Int, hour: Int?) -> Int? {
        guard var p = proposal, !p.options.isEmpty else { return nil }
        let walk = TemplateAI.parseDuration(text)
        if let h = hour, let m = TemplateAI.parseClock(text)?.minute, m > 0 {
            // 同 candidateTimes 一样：今日嗰个钟已经过咗就聽日
            var date = Self.today(at: Double(h) + Double(m) / 60, dayOffset: day)
            if date <= now { date = date.addingTimeInterval(86400) }
            p.options[0] = honestReason(MeetProposal(date: date, landmarkID: p.options[0].landmarkID, reason: p.options[0].reason))
        }
        if let walk {
            p.options = p.options.map { MeetProposal(date: $0.date, landmarkID: $0.landmarkID, reason: $0.reason + Self.walkNote(walk)) }
        }
        proposal = p
        return walk
    }

    /// 改名、反映嘅说明：未接伺服器时唔好讲成已经同步咗（A69）。
    var renameNote: String { community.sharesLandmarkNames ? L.t("同圈街坊都會見到", "同圈邻居都会看到", "Neighbours in your circle will see it") : L.t("暫時只喺你部手機", "暂时只在你的手机上", "Only on your phone for now") }
    var reportNote: String { community.hasServer ? L.t("同一個地方多位街坊都反映，我哋會匿名整理好轉告社區", "同一个地方多位邻居都反映，我们会匿名整理好转告社区", "When several neighbours report the same place, we'll pass it on to the community anonymously") : L.t("暫時只喺你部手機", "暂时只在你的手机上", "Only on your phone for now") }

    /// 改名中只讲新名：去掉「改名做」「叫」之类同标点；太长（超过 10 个字）当听错。
    static func spokenName(_ text: String) -> String? {
        let strip = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        if EnglishText.isEnglish(text) {
            // 英文：「call it Chess Corner」「rename it to …」→ 新名（最多 24 个字母）
            var s = text.trimmingCharacters(in: strip)
            for p in ["rename it to ", "change it to ", "call it ", "name it ", "rename to ", "it's called ", "call "] where s.lowercased().hasPrefix(p) {
                s.removeFirst(p.count)
                break
            }
            s = s.trimmingCharacters(in: strip)
            return (1...24).contains(s.count) ? s : nil
        }
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
        stopAnswerListening()
        hush()   // 撳咗「好」：唔好再叫人撳「好」，之后讲结果
        if card.assistant != nil { assistantConfirm(card); return }
        voiceCard = nil
        switch card.intent {
        case .invite: confirmProposal()
        case .goFind(let id): goFind(id)
        case .broadcast(let msg): broadcastHere(msg)
        case .rename(let id, let name): rename(id, to: name)
        case .changeMeetup(_, let day, let hour, let lmID):
            scene.highlightLandmark(nil)
            if let id = card.appointmentID { changeMeetup(id, day: day, hour: hour, minute: hour == nil ? 0 : TemplateAI.spokenMinute(card.heard), landmarkID: lmID) }
        case .cancelMeetup:
            if let id = card.appointmentID, appointments.contains(where: { $0.id == id && $0.isOpen }) { cancelMeetup(id) }
            else { toast(L.t("呢個約會已經冇咗。", "这个约会已经没有了。", "This walk plan is gone.")) }
        default: break
        }
    }

    func rejectVoice() {
        guard let card = voiceCard else { return }
        stopAnswerListening()
        hush()   // 撳咗「唔係 / 取消」：「撳好就約」唔好再讲落去
        voiceCard = nil
        if card.assistant != nil { assistantReject(card); return }
        switch card.intent {
        case .invite: cancelProposal()
        case .leave:
            cancelLeave(fromVoice: Self.leaveText(card.heard))
            say(L.t("撤回咗請假。", "已撤回请假。", "Day off cancelled."))
        case .report: if let id = card.reportID { retractReport(id) }
        case .changeMeetup: scene.highlightLandmark(nil)
        default: break
        }
    }
}
