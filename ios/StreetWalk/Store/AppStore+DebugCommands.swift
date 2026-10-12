import Foundation

#if DEBUG
// 开发用（只喺 Debug 版、启动参数 -debugCommands）：两部模拟器做端到端测试时，唔使撳屏幕都可以驱动 App。
// 将指令写入 App 容器嘅 Documents/debug-commands.txt（一行一个），App 每秒读一次、执行完删走；
// 状态写去 Documents/debug-state.txt（文字），方便对照截图。
//   xcrun simctl get_app_container <UDID> hk.hack4sdg.streetwalk data  → 容器路径
// 指令：tab today|board|neighbors · walk · home · find <网名> · go · endfind · answer yes|no
//      invite <网名> [日 0/1/2] [钟点] · accept · decline · depart · remind on|off · unlink <网名>
//      say <一句> · banner off · refresh · settings on|off · link <一次性码>（两部机用同一个码 = 碰咗一碰）
//      bgrefresh（App 喺后台时叫 backgroundRefresh，睇 debug-events.txt 有冇「notify」）
//      语音助手（Mac 语音服务器）：voice <一句>（等于讲咗）· vpick <第几个>（揀人 / 地点）· vchip <第几个> · vok（撳「好」）
//      · vno（撳「唔係」）· vcheck（即刻重新搵语音服务器）· speak <一句>（播报，测真人声）· mic（撳咪：连续对话开始 / 收咪）
extension AppStore {
    private static var debugCommandsStarted = false

    /// 记一行去 Documents/debug-events.txt（-debugCommands 先记）：例如后台出咗边啲本地通知。
    nonisolated static func debugEvent(_ s: String) {
        guard LaunchArgs.has("-debugCommands") else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("debug-events.txt")
        let line = "\(BackendTime.format(Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    private var debugDir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    func startDebugCommandsIfNeeded() {
        guard LaunchArgs.has("-debugCommands"), !Self.debugCommandsStarted else { return }
        Self.debugCommandsStarted = true
        let inbox = debugDir.appendingPathComponent("debug-commands.txt")
        try? FileManager.default.removeItem(at: inbox)
        Task { @MainActor in
            var last = ""
            var tick = 0
            var seenBanner: UUID?
            var seenToast: String?
            try? FileManager.default.removeItem(at: self.debugDir.appendingPathComponent("debug-events.txt"))
            func note(_ s: String) { Self.debugEvent(s) }
            while true {
                try? await Task.sleep(for: .milliseconds(500))
                tick += 1
                // 横幅、提示、找人卡出现过就记低（横幅 8 秒、提示 3.5 秒就收）
                if let b = self.banner, b.id != seenBanner { seenBanner = b.id; note("banner \(b.text)") }
                if let t = self.toast, t != seenToast { seenToast = t; note("toast \(t)") }
                if self.toast == nil { seenToast = nil }
                if let text = try? String(contentsOf: inbox, encoding: .utf8), !text.isEmpty {
                    try? FileManager.default.removeItem(at: inbox)
                    for line in text.split(separator: "\n") { self.runDebugCommand(String(line)) }
                }
                let state = self.debugState()
                if state != last || tick % 10 == 0 {
                    last = state
                    try? state.write(to: self.debugDir.appendingPathComponent("debug-state.txt"), atomically: true, encoding: .utf8)
                }
            }
        }
    }

    private func debugResident(_ name: String) -> Resident? {
        residents.first { !$0.isMe && $0.name == name } ?? residents.first { !$0.isMe && $0.name.hasPrefix(name) }
    }

    func runDebugCommand(_ raw: String) {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard let cmd = parts.first else { return }
        let arg = parts.dropFirst().joined(separator: " ")
        print("[debugCmd] \(raw)")
        switch cmd {
        case "tab": tab = arg == "board" ? .board : arg == "neighbors" ? .neighbors : .today
        case "walk": startWalk()
        case "home": finishWalk()
        case "find": if let r = debugResident(arg) { goFind(r.id) }
        case "go": startGoing()
        case "endfind", "stopshare": endFind()
        case "met": liveMetTapped()
        case "answer": answerIncomingFind(arg == "yes")
        case "invite":
            guard let r = debugResident(parts.count > 1 ? parts[1] : "") else { return }
            let day = parts.count > 2 ? Int(parts[2]) : nil
            let hour = parts.count > 3 ? Int(parts[3]) : nil
            proposeMeetup(with: r.id, day: day, hour: hour, announce: false)
            confirmProposal()
        case "accept": if let a = invitations.first { acceptInvitation(a.id) }
        case "decline": if let a = invitations.first { declineInvitation(a.id) }
        case "depart": if let a = appointments.first(where: { $0.status == .accepted }) { departForAppointment(a) }
        case "remind": if let id = remindPromptFor { createNeighbor(id, remind: arg != "off") }
        case "unlink": if let r = debugResident(arg) { unlinkNeighbor(r.id) }
        case "say": broadcastHere(arg.isEmpty ? nil : arg)
        case "banner": banner = nil
        case "refresh": supabase?.scheduleRefresh(Set(SupabaseCommunityService.Part.allCases), delay: 0)
        case "link": if !arg.isEmpty { debugLink(code: arg) }
        case "settings": showSettings = arg != "off"
        case "bgrefresh": Task { await self.backgroundRefresh() }   // 模拟器排唔到 BGAppRefreshTask：App 喺后台时用呢个试
        case "voice": if !arg.isEmpty { handle(arg) }
        case "vpick":
            if let a = voiceCard?.assistant, let i = Int(arg), a.options.indices.contains(i - 1) { assistantChoose(a.options[i - 1]) }
        case "vchip":
            if let a = voiceCard?.assistant, let i = Int(arg), a.chips.indices.contains(i - 1) { assistantChip(a.chips[i - 1]) }
        case "vok": confirmVoice()
        case "vno": rejectVoice()
        case "vcheck": VoiceServer.shared.recheckSoon()
        case "speak": if !arg.isEmpty { say(arg, force: true) }
        case "mic": micTapped()   // 等于撳咪（连续对话：开始 / 收咪）
        default: break
        }
    }

    func debugState() -> String {
        var out: [String] = []
        let id = supabase?.myID ?? "-"
        out.append("phase=\(phase) tab=\(tab) demo=\(demoMode) backend=\(supabase.map { "\($0.status)" } ?? "local") me=\(id) nickname=\(nickname)")
        out.append("residents:")
        for r in residents where !r.isMe {
            out.append("  \(r.id.prefix(8)) \(r.name) neighbor=\(r.isNeighbor) list=\(r.listName) streak=\(r.streakDays) out=\(r.isOut ? placeName(r.atLandmarkID) ?? "?" : "-") send=\(r.sendRemind) recv=\(r.receiveRemind) line=\(r.todayLine)")
        }
        out.append("appointments:")
        for a in appointments {
            out.append("  \(a.id.uuidString.prefix(8)) \(resident(a.partnerID)?.name ?? a.partnerID.prefix(8).description) \(a.status) fromPartner=\(a.fromPartner) \(dayTimeLabel(a.date)) @\(placeName(a.landmarkID) ?? "?")")
        }
        out.append("incomingFind=\(incomingFind.map { "\(resident($0.fromID)?.name ?? "?") @\(placeName($0.landmarkID) ?? "?")" } ?? "-")")
        out.append("find=\(find.map { "\(resident($0.partnerID)?.name ?? "?") \($0.stage) agreed=\(partnerAgreed) partnerOut=\($0.partnerOut)" } ?? "-")")
        if let f = find, f.live {
            let lf = liveFind
            out.append("live=mode:\(f.liveMode) stage:\(f.stage) dist:\(Int(f.distance))m eta:\(f.etaMinutes) arrow:\(Int(f.bearing)) precise:\(f.precise) headingPoor:\(f.headingPoor) stale:\(f.partnerStale) joined:\(lf?.channelJoined ?? false) refused:\(lf?.channelRefused ?? "-") sent:\(lf?.sentCount ?? 0) recv:\(lf?.receivedCount ?? 0) ni:\(lf.map { "\($0.niState)" } ?? "-") me:\(lf?.myFix.map { "\($0.geo.lat),\($0.geo.lon)" } ?? "-") partner:\(lf?.partnerFix.map { "\($0.geo.lat),\($0.geo.lon)" } ?? "-")")
        } else {
            out.append("live=-")
        }
        out.append("walk=\(walk.map { "\($0.minutes)min" } ?? "-") bump=\(bumpStage) remindPrompt=\(remindPromptFor ?? "-")")
        out.append("banner=\(banner?.text ?? "-")")
        out.append("toast=\(toast ?? "-")")
        out.append("card=\(uiActiveCard.map { "\($0)" } ?? "-")")
        out.append("voiceServer=\(VoiceServer.shared.status.label) url=\(VoiceServer.shared.status.url?.absoluteString ?? "-") voice=\(VoiceServer.shared.voiceID ?? "-") assistant=\(assistantURL != nil) route=\(speaker.lastRoute)")
        out.append("conversing=\(conversing) ear=\(VoiceServer.shared.earURL?.absoluteString ?? "-") heard=\(heardPartial) lastSpoken=\(speaker.lastSpoken)")
        if let c = voiceCard {
            out.append("voiceCard=\(c.title) | \(c.detail ?? "") confirm=\(c.needsConfirm) assistant=\(c.assistant.map { "\($0.kind) options=\($0.options.map(\.label)) chips=\($0.chips)" } ?? "-")")
        } else {
            out.append("voiceCard=-")
        }
        return out.joined(separator: "\n") + "\n"
    }
}
#else
extension AppStore {
    func startDebugCommandsIfNeeded() {}
    nonisolated static func debugEvent(_ s: String) {}
}
#endif
