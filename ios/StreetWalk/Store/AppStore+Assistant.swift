import Foundation

// 组员 B 嘅语音助手（Mac 语音服务器上，tools/voice_server.sh）接入原有嘅语音卡（2026-10-11）。
//
// 流程：手机识别（粤语，免费）→ 手机模板先听一次（TemplateAI）→ 约人 / 听唔明嘅句子交俾服务器（B 嘅流程：问时间、
// 问最多行几耐、揀地点、复述 → 撳「好」先写入 Supabase）→ 我哋原有嘅「我聽到」卡显示每一步（每步都有掣）。
// 服务器连唔到 / 8 秒都未答 / 演示模式：照旧用手机模板（TemplateAI），行为同之前一样。
// 冇撳「好」永远唔会写入（B 嘅确认卡 + 幂等规则）。
extension AppStore {
    /// 语音助手而家用唔用得：关咗演示模式、已登录真后端、搵到开咗 Supabase 模式嘅语音服务器。
    var assistantURL: URL? {
        guard !demoMode, supabase?.myID != nil else { return nil }
        return VoiceServer.shared.assistantURL
    }

    /// 准备好 AssistantSession（服务器 / 用户变咗就重新开始）。
    @discardableResult
    func configureAssistant() -> Bool {
        guard let url = assistantURL, let s = supabase, let uid = s.myID else { return false }
        let api = s.api
        assistant.configure(baseURL: url, userID: uid) {
            guard let t = try await api.accessToken() else { throw AssistantAPIError(code: "NOT_SIGNED_IN", message: L.t("未登入。", "未登录。", "Not signed in.")) }
            return t
        }
        return true
    }

    /// handle() 用：交俾服务器就返回 true（结果之后出卡）；唔交返回 false（照旧用手机模板）。
    func handleWithAssistant(_ text: String, local: VoiceIntent, fallback: @escaping () -> Void) -> Bool {
        guard AssistantFlow.shouldAsk(local), configureAssistant() else { return false }
        let gen = UUID()
        assistantGen = gen
        // 同一个对话入面讲过嘅句子串埋显示（「約阿芳聽日四點，最多行十五分鐘」）
        let heard = assistant.conversationID == nil ? text : [assistant.heard, text].filter { !$0.isEmpty }.joined(separator: Self.utteranceSeparator)
        assistant.heard = heard
        voiceCard = thinkingCard(heard: heard)
        let upload = assistantContextUpload()
        Task { @MainActor in
            do {
                // B 嗰套：豆包理解约 3–4 秒，问天气再加天文台（最多 6 秒）
                let reply = try await Self.withTimeout(12) { [assistant] in
                    // 地点资料上传失败都照问：最多系揀唔到地点，B 会如实讲
                    try? await assistant.upload(upload)
                    return try await assistant.turn(text)
                }
                guard self.assistantGen == gen else { return }
                VoiceServer.shared.noteSuccess()
                if AssistantFlow.shouldFallBack(reply, local: local) {
                    self.voiceCard = nil
                    fallback()
                    return
                }
                self.showAssistant(reply, heard: heard)
            } catch {
                guard self.assistantGen == gen else { return }
                print("[assistant] turn failed: \(error) → 手機模板")
                Self.debugEvent("assistant turn failed: \(error)")
                if let e = error as? AssistantAPIError, e.code == "ACTION_UNRESOLVED" {
                    self.showAssistantUncertain(heard: heard)
                    return
                }
                if !(error is AssistantAPIError) { VoiceServer.shared.noteFailure() }
                self.voiceCard = nil
                fallback()
            }
        }
        return true
    }

    private func thinkingCard(heard: String, title: String = L.t("等等，幫你睇睇⋯", "稍等，帮你看看⋯", "One moment, checking…")) -> VoiceCard {
        VoiceCard(heard: heard, title: title, detail: nil, needsConfirm: false, intent: .unknown,
                  assistant: AssistantCard(kind: .thinking, title: title, spoken: "", conversationID: ""))
    }

    var assistantLookup: AssistantFlow.Lookup {
        AssistantFlow.Lookup(
            contactName: { [weak self] id in self?.resident(id)?.name },
            placeName: { [weak self] id in self?.landmark(id)?.name },
            placeDetail: { [weak self] id, at in self?.assistantPlaceDetail(id, at: at) },
            timeLabel: { [weak self] d in self?.dayTimeLabel(d) ?? "" },
            dayLabel: { [weak self] d in self?.dayLabel(d) ?? "" })
    }

    /// 地点按钮下面嘅一行：你行几耐、嗰陣有冇遮、有冇櫈。
    func assistantPlaceDetail(_ id: String, at: Date?) -> String? {
        guard let l = landmark(id) else { return nil }
        let mins = Self.walkMinutes(l.pos.distance(to: scene.homeTarget))
        return L.t("你行 \(Int(mins.rounded())) 分鐘；", "你走 \(Int(mins.rounded())) 分钟；", "\(Int(mins.rounded())) min walk for you; ") + reason(for: l, at: at ?? now)
    }

    /// 显示服务器嘅一步（问、揀、复述、结果）。
    func showAssistant(_ reply: AssistantReply, heard: String) {
        var card = AssistantFlow.card(reply, lookup: assistantLookup)
        if card.kind == .info && reply.status == .info {
            // 今日一句、天气、B 嘅固定句之类：照讲 B 嘅内容（转繁体）
            voiceCard = VoiceCard(heard: heard, title: card.title, detail: card.detail, needsConfirm: false, intent: .unknown, assistant: card)
            say(card.spoken)
            // 天气：留住对话，紧接住问「咁聽日呢」B 会参考上一句（其他资讯答完就开新对话）
            if AssistantFlow.policy(reply) != "weather" { assistant.reset() }
            return
        }
        // 约人讲咗行几耐（「散步一個鐘」）：B 嘅确认卡冇呢样，手机自己讲埋（完成后写入约会理由）
        if card.kind == .confirm, card.action?.kind == "invite", let walk = TemplateAI.parseDuration(heard) {
            let how = TemplateAI.walkPhrase(walk)
            if L.isEn {
                // 英文：「Walk with Mrs Chan tomorrow 3 pm for 40 minutes」
                card.title += " " + how
                card.spoken += " " + how
            } else {
                let base = L.t("一齊行", "一起走", "")
                if card.title.hasSuffix(base) { card.title = String(card.title.dropLast(base.count)) + how } else { card.title += "，" + how }
                card.spoken += "，" + how
            }
        }
        voiceCard = VoiceCard(heard: heard, title: card.title, detail: card.detail, needsConfirm: card.kind == .confirm,
                              intent: .unknown, assistant: card)
        switch card.kind {
        case .confirm:
            if let p = card.action?.placeID, landmark(p) != nil { scene.highlightLandmark(p); focus(onLandmark: p) }
            let s = card.spoken.trimmingCharacters(in: CharacterSet(charactersIn: "。？?！! "))
            say(Self.confirmPrompt(s), prompt: true)   // 讲「好」或者撳掣都得（普通话掣写「好的」）
            listenForAnswer(.confirm)
        case .choosePlace:
            if let p = card.options.first?.id, landmark(p) != nil { scene.highlightLandmark(p) }
            say(card.spoken, prompt: true)
        case .notUnderstood:
            // 字已经认到：复述 + 例句，唔好话「冇聽明白」（见 showNotUnderstood）
            assistant.reset()
            showNotUnderstood(heard)
            return
        default:
            say(card.spoken, prompt: card.waitsForUser)
            // 问紧几时 / 行几耐：手机识别讲完就再开咪，直接答就得
            if card.kind == .ask { listenForAnswer(.retry) }
        }
        if card.endsConversation { assistant.reset() }
    }

    private func showAssistantUncertain(heard: String) {
        let card = AssistantCard(kind: .uncertain, title: L.t("上次嘅操作未知做咗未", "上次的操作不知道做了没有", "Not sure if the last action went through"), detail: L.t("撳「查結果」，唔好再做多次。", "按「查结果」，不要重复操作。", "Tap \"Check result\". Don't do it again."),
                                 spoken: L.t("上次嘅操作未知做咗未，撳查結果。", "上次的操作不知道做了没有，按查结果。", "Not sure if the last action went through. Tap check result."), conversationID: assistant.conversationID ?? "",
                                 draftID: assistant.unresolvedDraftID)
        voiceCard = VoiceCard(heard: heard, title: card.title, detail: card.detail, needsConfirm: false, intent: .unknown, assistant: card)
        say(card.spoken, prompt: true)
    }

    /// 揀咗联系人 / 地点。
    func assistantChoose(_ option: AssistantCard.Option) {
        guard let card = voiceCard, let a = card.assistant, a.kind == .chooseContact || a.kind == .choosePlace else { return }
        let kind = a.kind == .chooseContact ? "contact" : "place"
        Haptics.select()
        let gen = UUID()
        assistantGen = gen
        if kind == "place", landmark(option.id) != nil { scene.highlightLandmark(option.id) }
        voiceCard = thinkingCard(heard: card.heard, title: L.t("揀咗\(option.label)⋯", "选了\(option.label)⋯", "Picked \(option.label)…"))
        Task { @MainActor in
            do {
                let reply = try await assistant.choose(kind: kind, value: option.id)
                guard self.assistantGen == gen else { return }
                self.showAssistant(reply, heard: card.heard)
            } catch {
                guard self.assistantGen == gen else { return }
                self.assistantFailed(error, restoring: card)
            }
        }
    }

    /// 建议说法（例如「最多行十五分鐘」）：等于讲咗嗰句，继续同一个对话。
    func assistantChip(_ phrase: String) { handle(phrase) }

    /// 复述卡撳「好」：B 嘅确认（送出前先记低 draft id）。
    func assistantConfirm(_ card: VoiceCard) {
        guard let a = card.assistant, let draft = a.draftID else { voiceCard = nil; return }
        let gen = UUID()
        assistantGen = gen
        voiceCard = thinkingCard(heard: card.heard, title: L.t("幫緊你⋯", "正在帮你⋯", "Working on it…"))
        Task { @MainActor in
            do {
                let reply = try await assistant.confirm(draftID: draft)
                guard self.assistantGen == gen else { return }
                if reply.status == .completed {
                    self.applyAssistantCompletion(a.action, reply: reply, heard: card.heard)
                } else {
                    self.scene.highlightLandmark(nil)
                    self.showAssistant(reply, heard: card.heard)
                }
            } catch {
                guard self.assistantGen == gen else { return }
                // 送咗出去但冇收到答覆：唔知做咗未，唔准再撳一次「好」，只可以查结果（B 嘅规则）
                self.pendingAssistantAction = a.action
                self.showAssistantUncertain(heard: card.heard)
            }
        }
    }

    /// 复述卡撳「唔係」：取消服务器上嘅确认卡（未提交，唔会写入）。
    func assistantReject(_ card: VoiceCard) {
        assistantGen = UUID()
        scene.highlightLandmark(nil)
        if let draft = card.assistant?.draftID, card.assistant?.kind == .confirm {
            Task { @MainActor in _ = try? await self.assistant.cancel(draftID: draft); self.assistant.reset() }
        } else {
            assistant.reset()
        }
    }

    /// 「查結果」：只查，唔会再做一次。
    func assistantReconcile() {
        guard let card = voiceCard else { return }
        let action = card.assistant?.action ?? pendingAssistantAction
        voiceCard = thinkingCard(heard: card.heard, title: L.t("查緊⋯", "正在查⋯", "Checking…"))
        Task { @MainActor in
            do {
                guard let reply = try await assistant.reconcile() else { self.voiceCard = nil; return }
                if reply.status == .completed {
                    self.applyAssistantCompletion(action, reply: reply, heard: card.heard)
                } else {
                    self.showAssistant(reply, heard: card.heard)
                }
            } catch {
                self.voiceCard = card
                self.toast(L.t("連唔到語音伺服器，遲啲再查。", "连不上语音服务器，稍后再查。", "Can't reach the voice server. Check again later."))
            }
        }
    }

    /// 服务器做好咗：手机同步（约会加入列表、请假、网名），讲俾用户知。
    func applyAssistantCompletion(_ action: AssistantCard.Action?, reply: AssistantReply, heard: String) {
        pendingAssistantAction = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
        let receipt = reply.data["receipt_id"]?.string ?? reply.data["receiptId"]?.string
        var name: String?, when: String?, place: String?
        switch action?.kind {
        case "invite":
            if let a = action, let pid = a.contactID, let at = a.startsAt {
                let lm = a.placeID ?? ""
                name = resident(pid)?.name
                when = dayTimeLabel(at)
                place = landmark(lm)?.name
                let id = receipt.flatMap(UUID.init(uuidString:)) ?? UUID()
                if !appointments.contains(where: { $0.id == id }) {
                    let walk = TemplateAI.parseDuration(heard).map(Self.walkNote) ?? ""
                    let reasonText = (landmark(lm).map { reason(for: $0, at: at) } ?? "") + walk
                    let appt = Appointment(id: id, partnerID: pid, date: at, landmarkID: lm, reason: reasonText, status: .waiting)
                    appointments.insert(appt, at: 0)
                    supabase?.adoptServerInvite(appt)
                }
            }
            supabase?.scheduleRefresh([.meetups], delay: 0.5)
        case "leave":
            if let d = action?.date.flatMap(AssistantFlow.parseDay) {
                leaveDays.insert(LocalStore.dayKey(d))
                refreshMe()
            }
        case "rename":
            if let n = action?.newName, let clean = CommunityProfile.cleanNickname(n) {
                nickname = clean
                if let i = residents.firstIndex(where: \.isMe) { residents[i].nickname = clean }
            }
        default: break
        }
        let title = AssistantFlow.doneTitle(action, contactName: name, timeLabel: when, place: place)
        let card = AssistantCard(kind: .done, title: title, spoken: title, conversationID: "")
        voiceCard = VoiceCard(heard: heard, title: title, detail: nil, needsConfirm: false, intent: .unknown, assistant: card)
        say(title)
        Haptics.success()
        assistant.reset()
    }

    private func assistantFailed(_ error: Error, restoring card: VoiceCard) {
        if let e = error as? AssistantAPIError, ["SESSION_NOT_FOUND", "CONTACT_CHANGED", "INVALID_CHOICE", "PLACE_CHANGED"].contains(e.code) {
            voiceCard = nil
            assistant.reset()
            toast(e.code == "CONTACT_CHANGED" ? L.t("街坊名單有變，請再講一次。", "邻居名单有变，请再说一次。", "Your neighbour list changed. Please say it again.") : L.t("資料有變，請再講一次。", "资料有变，请再说一次。", "Details changed. Please say it again."))
            return
        }
        voiceCard = card
        toast(L.t("連唔到語音伺服器，請再試。", "连不上语音服务器，请再试。", "Can't reach the voice server. Please try again."))
    }

    /// 连上语音服务器：上次「未知」嘅操作即刻查一次（B 嘅规则：用原来嘅 id 查，唔会再做）。
    func assistantConnected() {
        guard configureAssistant(), assistant.unresolvedDraftID != nil else { return }
        Task { @MainActor in
            guard let reply = try? await assistant.reconcile() else { return }
            if reply.status == .completed {
                supabase?.scheduleRefresh([.meetups], delay: 0)
                toast(L.t("上次嘅操作已經做好。", "上次的操作已经完成。", "The last action is done."))
            }
        }
    }

    // MARK: - 上传俾服务器嘅地点资料（冇坐标）

    nonisolated static func walkMinutes(_ metres: Double) -> Double { max(1, (metres / 65 * 10).rounded() / 10) }

    /// 地标（名、有冇櫈）、你同每个街坊行过去几耐、之后三日每半个钟嘅遮荫（日落后冇）。坐标、屋企位置唔会上传。
    func assistantContextUpload() -> AssistantContextUpload {
        let home = scene.homeTarget
        let neighbours = residents.filter { $0.isNeighbor && !$0.isMe }
        let start = Self.hk.startOfDay(for: now)
        let iso = ISO8601DateFormatter()
        iso.timeZone = SolarPosition.hongKong
        iso.formatOptions = [.withInternetDateTime]
        let places = landmarks.filter { !$0.id.hasPrefix(LandmarkIndex.syntheticPrefix) }.map { l -> AssistantContextUpload.Place in
            var contact: [String: Double] = [:]
            for r in neighbours {
                let p = landmark(r.homeLandmarkID)?.pos ?? home
                contact[r.id] = Self.walkMinutes(l.pos.distance(to: p))
            }
            var slots: [AssistantContextUpload.Slot] = []
            if let shade {
                for day in 0..<3 {
                    for k in 0..<30 {
                        let a = start.addingTimeInterval(Double(day) * 86400 + 6 * 3600 + Double(k) * 1800)
                        // 用时段开始嗰刻（约会多数约喺整点 / 半点；同手机复述卡讲嘅「嗰陣有冇遮」一致）
                        guard shade.isSunUp(at: a) else { continue }
                        let f = (shade.shade(landmarkID: l.id, at: a) * 100).rounded() / 100
                        slots.append(.init(start: iso.string(from: a), end: iso.string(from: a.addingTimeInterval(1800)), fraction: min(1, max(0, f))))
                    }
                }
            }
            return .init(id: l.id, name: l.name, publish_name: originalLandmarkNames[l.id] ?? l.name, has_seat: l.hasSeat,
                         self_walk_minutes: Self.walkMinutes(l.pos.distance(to: home)), contact_walk_minutes: contact, shade: slots)
        }
        return AssistantContextUpload(places: places,
                                      walk_source: "手機估算：直線距離 ÷ 每分鐘 65 米；街坊屋企位置唔知時當住喺你附近",
                                      shade_source: "街坊行手機遮蔭估算（按樓宇影子，集合點）")
    }

    /// 等最多 seconds 秒；超时抛错（之后照用手机模板）。
    nonisolated static func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await op() }
            g.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AssistantAPIError(code: "TIMEOUT", message: L.t("語音伺服器太慢。", "语音服务器太慢。", "The voice server is too slow."))
            }
            let first = try await g.next()!
            g.cancelAll()
            return first
        }
    }
}
