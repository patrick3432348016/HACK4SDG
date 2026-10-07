import SwiftUI

// F7 约人：提议 → 对方确认 → 改时间 / 改地点 / 取消 → 出发前提醒 → 过期
extension AppStore {
    // MARK: - 提议

    func proposeMeetup(with partnerID: String, day: Int? = nil, hour: Int? = nil) {
        guard let p = resident(partnerID), let shade else { return }
        guard p.isNeighbor else { toast("你同\(p.floorLabel)仲未係街坊。見到面碰一碰，先可以約。"); return }
        var options: [MeetProposal] = []
        for (d, h) in candidateTimes(day: day, hour: hour) {
            if let prop = ai.pickMeetupSpot(me: me, partner: p, date: Self.today(at: Double(h), dayOffset: d), landmarks: landmarks, shade: shade) {
                options.append(prop)
            }
        }
        guard !options.isEmpty else { return }
        proposal = Proposal(partnerID: partnerID, options: options, index: 0)
        scene.highlightLandmark(options[0].landmarkID)
        focus(onLandmark: options[0].landmarkID)
    }

    /// 候选时间：讲咗就用讲嘅；冇讲就由而家之后嘅朝早 / 下晝 / 傍晚揀。
    func candidateTimes(day: Int?, hour: Int?) -> [(Int, Int)] {
        let nowH = Self.hk.component(.hour, from: now)
        // 今日已经过咗嘅钟点唔提：讲咗"今日三點"而家已经四点，就改去聽日同一个钟。
        if var day, let hour {
            if day == 0 && hour <= nowH { day = 1 }
            return [(day, hour), (day, min(hour + 1, 21)), (day + 1, 8)]
        }
        if let day {
            let hours = [8, 16, 18].filter { day > 0 || $0 > nowH + 1 }
            return hours.isEmpty ? [(day + 1, 8), (day + 1, 16)] : hours.map { (day, $0) }
        }
        var c: [(Int, Int)] = []
        for h in [8, 16, 17, 18] where h > nowH + 1 { c.append((0, h)) }
        c += [(1, 8), (1, 17)]
        return c
    }

    func nextProposalTime() {
        guard var p = proposal else { return }
        p.index = (p.index + 1) % p.options.count
        proposal = p
        scene.highlightLandmark(p.options[p.index].landmarkID)
        Haptics.select()
    }

    func nextProposalPlace() {
        guard var p = proposal, let shade else { return }
        let cur = p.options[p.index]
        // 下一个：遮荫多、有櫈的优先；轮流换，不会停在同一个。
        let ranked = landmarks.sorted {
            let a = ($0.hasSeat ? 1 : 0, shade.shade(landmarkID: $0.id, at: cur.date)), b = ($1.hasSeat ? 1 : 0, shade.shade(landmarkID: $1.id, at: cur.date))
            return a != b ? a > b : $0.id < $1.id
        }
        guard let i = ranked.firstIndex(where: { $0.id == cur.landmarkID }) ?? ranked.indices.first, ranked.count > 1 else { return }
        let next = ranked[(i + 1) % ranked.count]
        p.options[p.index] = MeetProposal(date: cur.date, landmarkID: next.id, reason: reason(for: next, at: cur.date))
        proposal = p
        scene.highlightLandmark(next.id)
        focus(onLandmark: next.id)
        Haptics.select()
    }

    /// 地点理由：遮荫按画面上的楼大约计（唔计树荫）。
    func reason(for l: Landmark, at d: Date) -> String {
        let s = shade?.shade(landmarkID: l.id, at: d) ?? 0
        return (s >= 0.5 ? "嗰陣有樓遮住" : "嗰陣會曬") + (l.hasSeat ? "、有櫈" : "")
    }

    func confirmProposal() {
        guard let p = proposal else { return }
        guard let partner = resident(p.partnerID), partner.isNeighbor else {
            cancelProposal(); toast("你同佢已經唔係街坊，約唔到。"); return
        }
        let opt = p.options[p.index]
        if let id = p.editing {
            guard let a = appointments.first(where: { $0.id == id }), a.isOpen else {
                cancelProposal(); toast("呢個約會已經冇咗。"); return
            }
            if a.date == opt.date && a.landmarkID == opt.landmarkID { cancelProposal(); speaker.speak("冇改到，照舊。"); return }
        }
        let name = resident(p.partnerID)?.name ?? ""
        let place = landmark(opt.landmarkID)?.name ?? ""
        if let id = p.editing, let i = appointments.firstIndex(where: { $0.id == id }) {
            // 改约：时间 / 地点换咗，要对方再确认一次。
            appointments[i].date = opt.date
            appointments[i].landmarkID = opt.landmarkID
            appointments[i].reason = opt.reason
            appointments[i].status = .waiting
            appointments[i].fromPartner = false
            appointments[i].reminded = false
            community.updateMeetup(appointments[i])
            speaker.speak("改咗：\(dayTimeLabel(opt.date))，喺\(place)附近。等緊\(name)確認。")
        } else {
            let a = Appointment(partnerID: p.partnerID, date: opt.date, landmarkID: opt.landmarkID, reason: opt.reason, status: .waiting)
            appointments.insert(a, at: 0)
            community.sendInvite(a)
            speaker.speak("幫你約咗\(name)\(dayTimeLabel(opt.date))，喺\(place)附近。等緊\(name)確認。")
        }
        proposal = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
        Haptics.success()
    }

    func cancelProposal() {
        proposal = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
    }

    // MARK: - 改约、取消

    /// 打开一个已有约会来改：当前时间地点排第一，其余是候选时间。
    func startEditing(_ id: UUID) {
        guard let a = appointments.first(where: { $0.id == id }), let p = resident(a.partnerID), let shade else { return }
        var options = [MeetProposal(date: a.date, landmarkID: a.landmarkID, reason: a.reason)]
        for (d, h) in candidateTimes(day: nil, hour: nil) {
            let date = Self.today(at: Double(h), dayOffset: d)
            guard abs(date.timeIntervalSince(a.date)) > 1800 else { continue }
            if let prop = ai.pickMeetupSpot(me: me, partner: p, date: date, landmarks: landmarks, shade: shade) { options.append(prop) }
        }
        proposal = Proposal(partnerID: a.partnerID, options: options, index: 0, editing: id)
        scene.highlightLandmark(a.landmarkID)
        focus(onLandmark: a.landmarkID)
    }

    /// 直接改（语音"改做下晝 4 點""改去涼亭"复述确认后）。
    func changeMeetup(_ id: UUID, day: Int?, hour: Int?, landmarkID: String?) {
        guard let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].isOpen else { toast("呢個約會已經冇咗。"); return }
        var a = changed(appointments[i], day: day, hour: hour, landmarkID: landmarkID)
        guard a.date > now else { toast("嗰個時間已經過咗，揀過第二個。"); return }
        a.status = .waiting
        a.fromPartner = false
        a.reminded = false
        appointments[i] = a
        community.updateMeetup(a)
        let name = resident(a.partnerID)?.name ?? ""
        speaker.speak("改咗：\(dayTimeLabel(a.date))，喺\(landmark(a.landmarkID)?.name ?? "")附近。等緊\(name)確認。")
        Haptics.success()
    }

    /// 改咗之后嘅样子（未保存）：冇讲嘅部分保留原来的。
    func changed(_ a: Appointment, day: Int?, hour: Int?, landmarkID: String?) -> Appointment {
        var a = a
        let cal = Self.hk
        if hour != nil || day != nil {
            let base = day.map { cal.startOfDay(for: now).addingTimeInterval(Double($0) * 86400) } ?? cal.startOfDay(for: a.date)
            a.date = base.addingTimeInterval(Double(hour ?? cal.component(.hour, from: a.date)) * 3600)
            // 冇讲日子、只讲钟点，而嗰个钟今日已经过咗：当係聽日。
            if day == nil, a.date <= now { a.date = a.date.addingTimeInterval(86400) }
        }
        if let landmarkID { a.landmarkID = landmarkID }
        if let l = landmark(a.landmarkID) { a.reason = reason(for: l, at: a.date) }
        return a
    }

    func cancelMeetup(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[i].status = .cancelled
        community.updateMeetup(appointments[i])
        if proposal?.editing == id { cancelProposal() }
        let name = resident(appointments[i].partnerID)?.name ?? ""
        speaker.speak("取消咗同\(name)嘅約，已經話咗俾\(name)知。")
        Haptics.light()
    }

    /// 语音改约、取消时要改边一个：指名就揀佢，否则揀最近嘅未完成约会。
    func targetAppointment(partnerID: String?) -> Appointment? {
        appointments.filter { $0.isOpen && (partnerID == nil || $0.partnerID == partnerID) && $0.date > now.addingTimeInterval(-3600) }
            .min { $0.date < $1.date }
    }

    // MARK: - 对方的回覆、对方约我

    func partnerAnswered(_ id: UUID, accepted: Bool) {
        guard let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].status == .waiting else { return }
        let a = appointments[i]
        let name = resident(a.partnerID)?.name ?? ""
        if accepted {
            appointments[i].status = .accepted
            let text = "\(name)應承咗：\(dayTimeLabel(a.date))，喺\(landmark(a.landmarkID)?.name ?? "")附近見。"
            showBanner(BannerItem(symbol: "checkmark.circle.fill", text: text))
            speaker.speak(text)
            Haptics.success()
        } else {
            appointments[i].status = .cancelled
            let text = "\(name)話\(dayTimeLabel(a.date))唔得。換個時間再約？"
            showBanner(BannerItem(symbol: "calendar.badge.exclamationmark", text: text, action: .invite(a.partnerID), actionTitle: "再約"))
            speaker.speak(text)
        }
    }

    /// 演示：陈太约你（经 CommunityService 送回来）。
    func partnerInvites(_ id: String = "chan") {
        guard let p = resident(id), p.isNeighbor, let shade else {
            toast("要先同陳太碰一碰做街坊，佢先可以約你。")
            return
        }
        let h = Self.hk.component(.hour, from: now) < 15 ? 16 : 8
        let day = h == 8 ? 1 : 0
        guard let opt = ai.pickMeetupSpot(me: me, partner: p, date: Self.today(at: Double(h), dayOffset: day), landmarks: landmarks, shade: shade) else { return }
        localCommunity?.simulateInvite(Appointment(partnerID: id, date: opt.date, landmarkID: opt.landmarkID, reason: opt.reason, status: .waiting, fromPartner: true))
    }

    func invitedBy(_ a: Appointment) {
        guard let p = resident(a.partnerID), p.isNeighbor else { return }
        appointments.insert(a, at: 0)
        let text = "\(p.name)約你\(dayTimeLabel(a.date))喺\(landmark(a.landmarkID)?.name ?? "")一齊行。"
        showBanner(BannerItem(symbol: "envelope.fill", text: text, action: .openNeighbors, actionTitle: "睇吓"))
        speaker.speak(text)
    }

    /// 对方只需一次确认（规格 F7）：我按「好」。
    func acceptInvitation(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[i].status = .accepted
        community.respond(to: appointments[i], accept: true)
        let a = appointments[i]
        speaker.speak("約好咗：\(dayTimeLabel(a.date))，喺\(landmark(a.landmarkID)?.name ?? "")附近見\(resident(a.partnerID)?.name ?? "")。")
        Haptics.success()
    }

    func declineInvitation(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[i].status = .cancelled
        community.respond(to: appointments[i], accept: false)
        speaker.speak("已經話咗俾\(resident(appointments[i].partnerID)?.name ?? "佢")知，今次唔去。")
        Haptics.light()
    }

    /// 别人约我、我想换时间：打开改约卡，按「好」就变成我反提议，等对方确认。
    func rescheduleInvitation(_ id: UUID) { startEditing(id) }

    // MARK: - 出发前提醒、过期

    /// 每 30 秒、拉时间滑杆、装好地图时检查一次。
    func checkAppointments() {
        for i in appointments.indices where appointments[i].isOpen {
            let a = appointments[i]
            let left = a.date.timeIntervalSince(now)
            if a.status == .accepted, !a.reminded, left > 0, left <= 30 * 60, find == nil {
                appointments[i].reminded = true
                let name = resident(a.partnerID)?.name ?? ""
                let text = "\(Int((left / 60).rounded())) 分鐘後約咗\(name)喺\(landmark(a.landmarkID)?.name ?? "")。"
                showBanner(BannerItem(symbol: "bell.fill", text: text, action: .depart(a.id), actionTitle: "出發"))
                speaker.speak(text)
            } else if left < -3600, findAppointment != a.id {
                // 过咗约定时间一个钟都冇碰头：收埋，唔再提。
                appointments[i].status = .expired
                toast("同\(resident(a.partnerID)?.name ?? "街坊")\(dayTimeLabel(a.date))嘅約過咗時間，收埋咗。")
            }
        }
    }

    func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.checkAppointments()
            }
        }
    }

    // MARK: - 列表

    var todaysAppointments: [Appointment] {
        let cal = Self.hk
        return appointments.filter { cal.isDate($0.date, inSameDayAs: now) && $0.isOpen && !($0.fromPartner && $0.status == .waiting) }
            .sorted { $0.date < $1.date }
    }
    var invitations: [Appointment] { appointments.filter { $0.fromPartner && $0.status == .waiting } }
    var upcomingAppointments: [Appointment] {
        let cal = Self.hk
        return appointments.filter { !cal.isDate($0.date, inSameDayAs: now) && $0.date > now && $0.isOpen && !($0.fromPartner && $0.status == .waiting) }
            .sorted { $0.date < $1.date }
    }

    func dayTimeLabel(_ d: Date) -> String {
        let cal = Self.hk
        let day = cal.isDate(d, inSameDayAs: now) ? "今日" : cal.isDate(d, inSameDayAs: now.addingTimeInterval(86400)) ? "聽日" : "後日"
        return day + TemplateAI.hourLabel(cal.component(.hour, from: d))
    }
}
