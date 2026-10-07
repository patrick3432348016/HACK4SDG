import SwiftUI

// 语音
extension AppStore {
    // MARK: - 语音

    func micTapped() {
        if listening { stopListening(); return }
        if !askedSpeechAuth {
            // 第一次按咪才请求麦克风和语音识别权限。
            askedSpeechAuth = true
            listener.requestAuth()
        }
        // 复述卡仲等紧确认：当係「唔係」（收返高亮、撤回提议），唔好静静鸡丢咗。
        if voiceCard?.needsConfirm == true { rejectVoice() } else { voiceCard = nil }
        do {
            try listener.start()
            listening = true
            Haptics.light()
        } catch {
            listening = false
            phrasePicker = true
        }
    }

    func stopListening() {
        let text = listener.stop()
        listening = false
        if text.isEmpty { phrasePicker = true } else { handle(text) }
    }

    var suggestedPhrases: [String] {
        // 只用街坊的名字（非街坊唔出名）；未有街坊就唔出约人嘅句子。
        let name = neighbors.first?.name
        if find != nil { return ["我喺\(landmark(find?.landmarkID)?.name ?? "涼亭")"] }
        if walk != nil { return ["呢度好曬", "呢度冇櫈"] + (name.map { ["過去搵\($0)", "約\($0)聽日朝早一齊行"] } ?? []) }
        if let a = targetAppointment(partnerID: nil), let p = resident(a.partnerID),
           let other = landmarks.filter({ $0.id != a.landmarkID }).max(by: { $0.name.count < $1.name.count }) {
            return ["改做下晝四點", "改去\(other.name)", "取消同\(p.name)嘅約", "今日請假"]
        }
        return (name.map { ["約\($0)聽日下晝三點一齊行"] } ?? []) + ["今日請假", "\(landmarks.first?.name ?? "涼亭")改名做大樹底", "呢度好曬"]
    }

    func handle(_ text: String) {
        phrasePicker = false
        if listening { _ = listener.stop() }
        listening = false
        let ctx = AIContext(residents: residents, landmarks: landmarks, now: now, walking: walk != nil, finding: find != nil)
        let intent = ai.parseVoice(text, context: ctx)
        switch intent {
        case .invite(let id, let day, let hour):
            guard let p = resident(id) else { return }
            guard p.isNeighbor else { toast("你同\(p.floorLabel)仲未係街坊。見到面碰一碰，先可以約。"); return }
            proposeMeetup(with: id, day: day, hour: hour)
            if let prop = proposal?.options.first {
                voiceCard = VoiceCard(heard: text, title: "約\(p.name)\(dayTimeLabel(prop.date))一齊行",
                                      detail: "地點：\(landmark(prop.landmarkID)?.name ?? "")\n\(prop.reason)", needsConfirm: true, intent: intent)
            }
        case .goFind(let id):
            guard let p = resident(id), p.isNeighbor, p.isOut else { toast("而家冇街坊喺外面。"); return }
            voiceCard = VoiceCard(heard: text, title: "過去搵\(p.name)", detail: "會先問\(p.name)方唔方便", needsConfirm: true, intent: intent)
        case .leave:
            voiceCard = VoiceCard(heard: text, title: "今日請假", detail: "連續日數會保留", needsConfirm: false, intent: intent)
            if !me.onLeave { toggleLeave() }
        case .rename(let id, let name):
            let old = landmark(id)?.name ?? ""
            voiceCard = VoiceCard(heard: text, title: "\(old)改名做\(name)", detail: "同圈街坊都會見到", needsConfirm: false, intent: intent)
            rename(id, to: name)
        case .report(let kind):
            voiceCard = VoiceCard(heard: text, title: "記低：呢度\(kind.rawValue)", detail: "月尾匿名交俾屋邨管理", needsConfirm: false, intent: intent)
            report(kind)
        case .broadcast:
            voiceCard = VoiceCard(heard: text, title: "播俾對方聽", detail: text, needsConfirm: true, intent: intent)
        case .changeMeetup(let pid, let day, let hour, let lmID):
            guard let a = targetAppointment(partnerID: pid) else { toast("而家冇約會可以改。"); return }
            let c = changed(a, day: day, hour: hour, landmarkID: lmID)
            guard c.date > now else { toast("嗰個時間已經過咗，揀過第二個。"); return }
            let name = resident(a.partnerID)?.name ?? "街坊"
            voiceCard = VoiceCard(heard: text, title: "改約\(name)：\(dayTimeLabel(c.date)) · \(landmark(c.landmarkID)?.name ?? "")",
                                  detail: "會再問\(name)確認\n\(c.reason)", needsConfirm: true, intent: intent, appointmentID: a.id)
            scene.highlightLandmark(c.landmarkID)
        case .cancelMeetup(let pid):
            guard let a = targetAppointment(partnerID: pid) else { toast("而家冇約會可以取消。"); return }
            let name = resident(a.partnerID)?.name ?? "街坊"
            voiceCard = VoiceCard(heard: text, title: "取消同\(name)\(dayTimeLabel(a.date))嘅約", detail: "會話俾\(name)知", needsConfirm: true, intent: intent, appointmentID: a.id)
        case .unknown:
            speaker.speak("唔好意思，我未聽明白。可以揀一句。")
            phrasePicker = true
        }
    }

    func confirmVoice() {
        guard let card = voiceCard else { return }
        voiceCard = nil
        switch card.intent {
        case .invite: confirmProposal()
        case .goFind(let id): goFind(id)
        case .broadcast: broadcastHere()
        case .changeMeetup(_, let day, let hour, let lmID):
            scene.highlightLandmark(nil)
            if let id = card.appointmentID { changeMeetup(id, day: day, hour: hour, landmarkID: lmID) }
        case .cancelMeetup:
            if let id = card.appointmentID, appointments.contains(where: { $0.id == id && $0.isOpen }) { cancelMeetup(id) }
            else { toast("呢個約會已經冇咗。") }
        default: break
        }
    }

    func rejectVoice() {
        guard let card = voiceCard else { return }
        voiceCard = nil
        switch card.intent {
        case .invite: cancelProposal()
        case .leave: if me.onLeave { toggleLeave() }
        case .report: undoLastReport()
        case .changeMeetup: scene.highlightLandmark(nil)
        default: break
        }
    }
}
