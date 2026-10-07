import SwiftUI

// F7 约人
extension AppStore {
    // MARK: - F7 约人

    func proposeMeetup(with partnerID: String, day: Int? = nil, hour: Int? = nil) {
        guard let p = resident(partnerID), let shade else { return }
        guard p.isNeighbor else { toast("你同\(p.floorLabel)仲未係街坊。見到面碰一碰，先可以約。"); return }
        var options: [MeetProposal] = []
        let nowH = Calendar.current.component(.hour, from: now)
        let candidates: [(Int, Int)] = {
            if let day, let hour { return [(day, hour), (day, hour + 1), (day + 1, 8)] }
            if let day { return [(day, 8), (day, 16), (day, 18)] }
            var c: [(Int, Int)] = []
            for h in [8, 16, 17, 18] where h > nowH + 1 { c.append((0, h)) }
            c += [(1, 8), (1, 17)]
            return c
        }()
        for (d, h) in candidates {
            if let prop = ai.pickMeetupSpot(me: me, partner: p, date: Self.today(at: Double(h), dayOffset: d), landmarks: landmarks, shade: shade) {
                options.append(prop)
            }
        }
        guard !options.isEmpty else { return }
        proposal = (partnerID, options, 0)
        scene.highlightLandmark(options[0].landmarkID)
        focus(onLandmark: options[0].landmarkID)
    }

    func nextProposalTime() {
        guard var p = proposal else { return }
        p.index = (p.index + 1) % p.options.count
        proposal = p
        scene.highlightLandmark(p.options[p.index].landmarkID)
        Haptics.select()
    }

    func nextProposalPlace() {
        guard var p = proposal, let partner = resident(p.partnerID) else { return }
        let cur = p.options[p.index]
        let others = landmarks.filter { $0.id != cur.landmarkID }.sorted { (shade?.shade(landmarkID: $0.id, at: cur.date) ?? 0) > (shade?.shade(landmarkID: $1.id, at: cur.date) ?? 0) }
        guard let next = others.first(where: { $0.hasSeat }) ?? others.first, let shade else { return }
        let s = shade.shade(landmarkID: next.id, at: cur.date)
        _ = partner
        p.options[p.index] = MeetProposal(date: cur.date, landmarkID: next.id, reason: (s >= 0.5 ? "嗰陣有樹蔭" : "嗰陣有啲曬") + (next.hasSeat ? "、有櫈" : ""))
        proposal = p
        scene.highlightLandmark(next.id)
        focus(onLandmark: next.id)
        Haptics.select()
    }

    func confirmProposal() {
        guard let p = proposal else { return }
        let opt = p.options[p.index]
        let a = Appointment(partnerID: p.partnerID, date: opt.date, landmarkID: opt.landmarkID, reason: opt.reason, status: .waiting)
        appointments.insert(a, at: 0)
        proposal = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
        let name = resident(p.partnerID)?.name ?? ""
        speaker.speak("幫你約咗\(name)\(dayTimeLabel(opt.date))，喺\(landmark(opt.landmarkID)?.name ?? "")附近。等緊\(name)確認。")
        Haptics.success()
        let id = a.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            self.partnerAccepts(id)
        }
    }

    func partnerAccepts(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].status == .waiting else { return }
        appointments[i].status = .accepted
        let a = appointments[i]
        let name = resident(a.partnerID)?.name ?? ""
        let text = "\(name)應承咗：\(dayTimeLabel(a.date))，喺\(landmark(a.landmarkID)?.name ?? "")附近見。"
        showBanner(BannerItem(symbol: "checkmark.circle.fill", text: text))
        speaker.speak(text)
        Haptics.success()
    }

    func cancelProposal() {
        proposal = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
    }

    /// 演示：陈太约你。
    func partnerInvites(_ id: String = "chan") {
        guard let p = resident(id), p.isNeighbor, let shade else {
            toast("要先同陳太碰一碰做街坊，佢先可以約你。")
            return
        }
        let h = Calendar.current.component(.hour, from: now) < 15 ? 16 : 8
        let day = h == 8 ? 1 : 0
        guard let opt = ai.pickMeetupSpot(me: me, partner: p, date: Self.today(at: Double(h), dayOffset: day), landmarks: landmarks, shade: shade) else { return }
        appointments.insert(Appointment(partnerID: id, date: opt.date, landmarkID: opt.landmarkID, reason: opt.reason, status: .waiting, fromPartner: true), at: 0)
        let text = "\(p.name)約你\(dayTimeLabel(opt.date))喺\(landmark(opt.landmarkID)?.name ?? "")一齊行。"
        showBanner(BannerItem(symbol: "envelope.fill", text: text, action: .openNeighbors, actionTitle: "睇吓"))
        speaker.speak(text)
    }

    func acceptInvitation(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[i].status = .accepted
        speaker.speak("約好咗。")
        Haptics.success()
    }

    func rescheduleInvitation(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[i].date = appointments[i].date.addingTimeInterval(3600)
        Haptics.select()
    }

    var todaysAppointments: [Appointment] {
        let cal = Calendar.current
        return appointments.filter { cal.isDate($0.date, inSameDayAs: now) && $0.status != .done && !($0.fromPartner && $0.status == .waiting) }
    }
    var invitations: [Appointment] { appointments.filter { $0.fromPartner && $0.status == .waiting } }
    var upcomingAppointments: [Appointment] {
        let cal = Calendar.current
        return appointments.filter { !cal.isDate($0.date, inSameDayAs: now) && $0.status != .done && !($0.fromPartner && $0.status == .waiting) }
    }

    func dayTimeLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let day = cal.isDate(d, inSameDayAs: now) ? "今日" : cal.isDate(d, inSameDayAs: now.addingTimeInterval(86400)) ? "聽日" : "後日"
        return day + TemplateAI.hourLabel(cal.component(.hour, from: d))
    }
}
