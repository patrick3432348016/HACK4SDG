import Foundation

// B's Mac voice assistant integrates with the existing cards (2026-10-11); start through tools/voice_server.sh.
//
// Original flow: phone recognition → TemplateAI → server for invitations/unknown requests, with time and walking-limit clarification,
// place choice and read-back, then explicit confirmation before Supabase writing. Existing cards provide buttons for each step.
// Use TemplateAI in demo mode or after server failure/timeout; inspect the current timeout constant rather than this historical flow description.
// Never write before explicit confirmation; preserve B's draft and idempotency rules.
extension AppStore {
    /// Assistant availability requires normal mode, real-backend login, and a discovered voice server in Supabase mode.
    var assistantURL: URL? {
        guard !demoMode, supabase?.myID != nil else { return nil }
        return VoiceServer.shared.assistantURL
    }

    /// Prepare AssistantSession; reset when server/user identity changes.
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

    /// handle() returns true when delegated to the server for an eventual card; false retains the local-template flow.
    func handleWithAssistant(_ text: String, local: VoiceIntent, fallback: @escaping () -> Void) -> Bool {
        guard AssistantFlow.shouldAsk(local), configureAssistant() else { return false }
        let gen = UUID()
        assistantGen = gen
        // Combine the current conversation's utterances for the read-back display.
        let heard = assistant.conversationID == nil ? text : [assistant.heard, text].filter { !$0.isEmpty }.joined(separator: Self.utteranceSeparator)
        assistant.heard = heard
        voiceCard = thinkingCard(heard: heard)
        let upload = assistantContextUpload()
        Task { @MainActor in
            do {
                // Doubao understanding typically took 3–4 seconds; weather may add an Observatory request up to six seconds.
                let reply = try await Self.withTimeout(12) { [assistant] in
                    // Continue after context-upload failure; the server can explicitly report that no place can be selected.
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

    /// Place-button subtitle: your walking time, expected shade, and seating.
    func assistantPlaceDetail(_ id: String, at: Date?) -> String? {
        guard let l = landmark(id) else { return nil }
        let mins = Self.walkMinutes(l.pos.distance(to: scene.homeTarget))
        return L.t("你行 \(Int(mins.rounded())) 分鐘，", "你走 \(Int(mins.rounded())) 分钟，", "\(Int(mins.rounded())) min walk for you, ") + reason(for: l, at: at ?? now)
    }

    /// Render the server's clarification, choice, confirmation, or result step.
    func showAssistant(_ reply: AssistantReply, heard: String) {
        var card = AssistantFlow.card(reply, lookup: assistantLookup)
        if card.kind == .info && reply.status == .info {
            // For daily descriptions, weather, and fixed policy responses, use B's text with appropriate script conversion.
            voiceCard = VoiceCard(heard: heard, title: card.title, detail: card.detail, needsConfirm: false, intent: .unknown, assistant: card)
            say(card.spoken)
            // Keep weather context for an immediate follow-up about tomorrow; other completed informational answers start a fresh conversation.
            if AssistantFlow.policy(reply) != "weather" { assistant.reset() }
            return
        }
        // Preserve spoken walk duration locally when B's draft lacks it; include it in confirmation and the completed meetup reason.
        if card.kind == .confirm, card.action?.kind == "invite", let walk = TemplateAI.parseDuration(heard) {
            let how = TemplateAI.walkPhrase(walk)
            if L.isEn {
                // English example: Walk with Mrs Chan tomorrow 3 pm for 40 minutes.
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
            say(Self.confirmPrompt(s), prompt: true)   // Allow spoken approval or the localized confirmation button.
            listenForAnswer(.confirm)
        case .choosePlace:
            if let p = card.options.first?.id, landmark(p) != nil { scene.highlightLandmark(p) }
            say(card.spoken, prompt: true)
        case .notUnderstood:
            // If text was recognized, read it back and offer examples rather than claiming no speech was heard (showNotUnderstood).
            assistant.reset()
            showNotUnderstood(heard)
            return
        default:
            say(card.spoken, prompt: card.waitsForUser)
            // While clarifying time/duration, reopen the phone microphone after recognition so the user can answer directly.
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

    /// Contact/place choice selected.
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

    /// A suggested phrase is submitted as an utterance in the same conversation.
    func assistantChip(_ phrase: String) { handle(phrase) }

    /// Confirmation calls B's confirm flow after persisting the draft ID.
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
                // After sending without receiving a result, allow only reconciliation, never another blind confirmation.
                self.pendingAssistantAction = a.action
                self.showAssistantUncertain(heard: card.heard)
            }
        }
    }

    /// Rejection cancels the unsubmitted server draft without a business write.
    func assistantReject(_ card: VoiceCard) {
        assistantGen = UUID()
        scene.highlightLandmark(nil)
        if let draft = card.assistant?.draftID, card.assistant?.kind == .confirm {
            Task { @MainActor in _ = try? await self.assistant.cancel(draftID: draft); self.assistant.reset() }
        } else {
            assistant.reset()
        }
    }

    /// Reconcile only; do not execute the action again.
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

    /// After server completion, synchronize the local meetup/leave/nickname and explain the outcome.
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

    /// On reconnection, query a previously uncertain operation using its original ID without repeating it.
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

    // MARK: - Uploading place context without coordinates

    nonisolated static func walkMinutes(_ metres: Double) -> Double { max(1, (metres / 65 * 10).rounded() / 10) }

    /// Upload landmark names/seating, both walking times, and half-hour daylight shade for the next three days; exclude coordinates/home location.
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
                        // Sample at interval start, matching common whole/half-hour meetup times and local confirmation wording.
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

    /// Wait at most seconds; throw on timeout so the caller can use the local template.
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
