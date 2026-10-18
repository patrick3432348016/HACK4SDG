import SwiftUI

// F7 invitations: propose, peer confirmation, reschedule / relocate / cancel, departure reminder, expiry.
extension AppStore {
    // MARK: - Suggestions

    /// announce speaks the chosen time, place and reason for button invitations; voice invitations use their recap card.
    /// landmarkID fixes the place when inviting from a landmark card; choose only the time.
    func proposeMeetup(with partnerID: String, day: Int? = nil, hour: Int? = nil, landmarkID: String? = nil, announce: Bool = true) {
        guard let p = resident(partnerID), let shade else { return }
        renaming = nil   // Opening an invitation card supersedes rename input.
        // Omit floor numbers to prevent linking a person's name to their floor (A03).
        guard p.isNeighbor else { toast(L.t("佢仲未係你街坊。見到面碰一碰，先可以約。", "他还不是你的邻居。见面碰一碰，才可以约。", "They're not your neighbour yet. Meet up and tap phones first, then you can invite them.")); return }
        var options: [MeetProposal] = []
        for (d, h) in candidateTimes(day: day, hour: hour) {
            let date = Self.today(at: h, dayOffset: d)
            if let id = landmarkID, let lm = landmark(id) {
                options.append(MeetProposal(date: date, landmarkID: lm.id, reason: reason(for: lm, at: date)))
            } else if let prop = ai.pickMeetupSpot(me: me, partner: p, date: date, landmarks: landmarks, shade: shade).map(honestReason) {
                options.append(prop)
            }
        }
        guard !options.isEmpty else { toast(L.t("附近未有合適嘅地標，暫時約唔到。", "附近还没有合适的地标，暂时约不了。", "No suitable landmark nearby yet, so you can't make a walk plan for now.")); return }
        proposal = Proposal(partnerID: partnerID, options: options, index: 0)
        scene.highlightLandmark(options[0].landmarkID)
        focus(onLandmark: options[0].landmarkID)
        if announce {
            let o = options[0]
            say(L.t("約\(p.name)\(dayTimeLabel(o.date))，喺\(landmark(o.landmarkID)?.name ?? "")。\(TemplateAI.whyHere(o.reason))撳「好」就約。", "约\(p.name)\(dayTimeLabel(o.date))，在\(landmark(o.landmarkID)?.name ?? "")。\(TemplateAI.whyHere(o.reason))按「好」就约。", "Invite \(p.name) for a walk \(dayTimeLabel(o.date)) at \(landmark(o.landmarkID)?.name ?? ""). \(TemplateAI.whyHere(o.reason)) Tap “OK” to invite."), prompt: true)
        }
    }

    /// Use an explicit time when supplied; otherwise offer more choices following 10-18 roommate feedback.
    /// Offer up to four remaining full / half hours today plus tomorrow's morning, late morning, afternoon and evening.
    /// Avoid suggested times after sunset (UX review 34) or today's afternoon when HKO forecasts heavy rain then.
    /// Respect an explicit user time. Return (day offset, hour), allowing half hours such as 16.5.
    func candidateTimes(day: Int?, hour: Int?) -> [(Int, Double)] {
        let nowH = Self.hk.component(.hour, from: now)
        // Move a specified time already passed today to the same time tomorrow.
        if var day, let hour {
            if day == 0 && hour <= nowH { day = 1 }
            return [(day, Double(hour))] + daylight([(day, Double(min(hour + 1, 21))), (day + 1, 8)], fallback: [(day + 1, 8)])
        }
        if let day {
            let hours: [Double] = [8, 10, 15, 16.5, 18].filter { day > 0 || $0 > Double(nowH + 1) }
            return daylight(hours.isEmpty ? [(day + 1, 8), (day + 1, 16)] : hours.map { (day, $0) }, fallback: [(day + 1, 8), (day + 1, 16)])
        }
        let nowM = Self.hk.component(.minute, from: now)
        var c: [(Int, Double)] = []
        var t = max(Double(nowH + 1) + (nowM >= 30 ? 0.5 : 0), 7)
        while t <= 18.5 && c.count < 4 {
            if !(weather == .rain && t >= 12) { c.append((0, t)) }
            t += 0.5
        }
        c += [(1, 8), (1, 10), (1, 15), (1, 17)]
        return daylight(c, fallback: [(1, 8), (1, 16)])
    }

    /// Keep daylight times, or all times if shade data is unavailable; use fallback when all are after sunset.
    private func daylight(_ c: [(Int, Double)], fallback: [(Int, Double)]) -> [(Int, Double)] {
        guard let shade else { return c }
        let lit = c.filter { shade.isSunUp(at: Self.today(at: $0.1, dayOffset: $0.0)) }
        return lit.isEmpty ? fallback : lit
    }

    /// Changing time preserves the current place (10-18 roommate feedback).
    func nextProposalTime() {
        guard var p = proposal, p.options.indices.contains(p.index) else { return }
        let keep = p.options[p.index].landmarkID
        p.index = (p.index + 1) % p.options.count
        let o = p.options[p.index]
        if o.landmarkID != keep, let lm = landmark(keep) {
            p.options[p.index] = MeetProposal(date: o.date, landmarkID: keep, reason: reason(for: lm, at: o.date))
        }
        proposal = p
        scene.highlightLandmark(keep)
        Haptics.select()
    }

    /// Changing place preserves time and updates every time option to the new place.
    func nextProposalPlace() {
        guard var p = proposal, p.options.indices.contains(p.index) else { return }
        let cur = p.options[p.index]
        // Cycle through alternatives, preferring shade and benches without repeating the same place.
        let ranked = landmarks.sorted {
            let a = ($0.hasSeat ? 1 : 0, shade?.shade(landmarkID: $0.id, at: cur.date) ?? 0), b = ($1.hasSeat ? 1 : 0, shade?.shade(landmarkID: $1.id, at: cur.date) ?? 0)
            return a != b ? a > b : $0.id < $1.id
        }
        guard ranked.count > 1 else { toast(L.t("附近只有一個地標，換唔到第二個。", "附近只有一个地标，换不了别的。", "There's only one landmark nearby, so you can't switch.")); return }
        guard let i = ranked.firstIndex(where: { $0.id == cur.landmarkID }) ?? ranked.indices.first else { return }
        let next = ranked[(i + 1) % ranked.count]
        p.options = p.options.map { $0.landmarkID == next.id ? $0 : MeetProposal(date: $0.date, landmarkID: next.id, reason: reason(for: next, at: $0.date)) }
        proposal = p
        scene.highlightLandmark(next.id)
        focus(onLandmark: next.id)
        Haptics.select()
    }

    /// Estimate place shade from displayed buildings, excluding tree shade.
    /// Feedback: allow manual time, place and walk-duration choices; replace the current option while retaining cycling controls.
    /// Include walk duration in the reason shared with the peer.
    func setCustomProposal(date: Date, landmarkID: String, minutes: Int) {
        guard var p = proposal, p.options.indices.contains(p.index), let lm = landmark(landmarkID) else { return }
        guard date > now else { toast(L.t("嗰個時間已經過咗，揀過第二個。", "那个时间已经过了，换一个吧。", "That time has passed. Please pick another.")); return }
        let walk = L.t("，一齊行 \(minutes) 分鐘", "，一起走 \(minutes) 分钟", ", walk together \(minutes) min")
        p.options[p.index] = MeetProposal(date: date, landmarkID: lm.id, reason: reason(for: lm, at: date) + walk)
        proposal = p
        scene.highlightLandmark(lm.id)
        focus(onLandmark: lm.id)
        Haptics.select()
    }

    func reason(for l: Landmark, at d: Date) -> String {
        let s = shade?.shade(landmarkID: l.id, at: d) ?? 0
        return (shade?.isSunUp(at: d) == false ? L.t("嗰陣已經日落", "那时已经日落", "Sun has set by then") : s >= 0.5 ? L.t("嗰陣有樓遮住", "那时有楼挡着", "Shady then (buildings)") : L.t("嗰陣會曬", "那时会晒", "Too sunny then")) + (l.hasSeat ? L.t("、有櫈", "、有凳子", ", seats here") : "")
    }

    /// 10-18 feedback: remote reasons arrive in the sender's language, causing mismatches on the recipient's UI.
    /// Rebuild displayed reasons locally for shade / sunset, seating, each person's walk and shared duration parsed from the original.
    func meetupReason(_ a: Appointment) -> String {
        guard let l = landmark(a.landmarkID) else { return Self.matchesLanguage(a.reason) ? a.reason : "" }
        var s = reason(for: l, at: a.date)
        if let p = resident(a.partnerID), let mine = landmark(me.homeLandmarkID)?.pos, let theirs = landmark(p.homeLandmarkID)?.pos {
            let m = max(1, Int((max(l.pos.distance(to: mine), l.pos.distance(to: theirs)) / 65).rounded()))
            s += L.t("、兩個都行 \(m) 分鐘左右", "、两人都走 \(m) 分钟左右", ", about \(m) minutes' walk for both")
        }
        if let m = Self.walkMinutes(in: a.reason) { s += Self.walkNote(m) }
        return s
    }

    /// Parse the shared walking duration from Cantonese, Mandarin or English reasons.
    nonisolated static func walkMinutes(in reason: String) -> Int? {
        guard let r = reason.range(of: #"(一齊行|一起走|walk together)\s*(for\s+)?"#, options: .regularExpression) else { return nil }
        var d = String(reason[r.upperBound...])
        if let end = d.firstIndex(where: { "，、,。.".contains($0) }) { d = String(d[..<end]) }
        d = d.trimmingCharacters(in: .whitespaces)
        if d.hasPrefix("半") || d.hasPrefix("half") { return 30 }
        let digits = Int(d.prefix(while: \.isNumber))
        if let digits, d.contains("分") || d.contains("min") { return digits }
        let h = digits ?? (d.hasPrefix("一") || d.hasPrefix("an ") ? 1 : d.hasPrefix("兩") || d.hasPrefix("两") ? 2 : 0)
        guard h > 0 else { return nil }
        return h * 60 + (d.contains("半") || d.contains("and a half") ? 30 : 0)
    }

    /// Check whether the sentence matches the current UI language; distinguish Cantonese and Mandarin with common markers.
    nonisolated static func matchesLanguage(_ text: String) -> Bool {
        let cjk = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        if L.isEn { return !cjk }
        guard cjk else { return false }
        let mandarin = ["那时", "凳子", "两人", "一起走", "已经"].contains { text.contains($0) }
        let cantonese = ["嗰陣", "櫈", "兩個", "一齊行", "已經"].contains { text.contains($0) }
        return L.isCmn ? (!cantonese || mandarin) : (!mandarin || cantonese)
    }

    func confirmProposal() {
        guard let p = proposal else { return }
        guard let partner = resident(p.partnerID), partner.isNeighbor else {
            cancelProposal(); toast(L.t("你同佢已經唔係街坊，約唔到。", "你和他已经不是邻居，约不了。", "You're no longer neighbours, so you can't invite them.")); return
        }
        let opt = p.options[p.index]
        if let id = p.editing {
            guard let a = appointments.first(where: { $0.id == id }), a.isOpen else {
                cancelProposal(); toast(L.t("呢個約會已經冇咗。", "这个约会已经没有了。", "This walk plan no longer exists.")); return
            }
            if a.date == opt.date && a.landmarkID == opt.landmarkID { cancelProposal(); toast(L.t("冇改到，照舊。", "没有改动，照旧。", "Nothing changed. Same as before.")); return }
        }
        let name = resident(p.partnerID)?.name ?? ""
        let place = landmark(opt.landmarkID)?.name ?? ""
        if let id = p.editing, let i = appointments.firstIndex(where: { $0.id == id }) {
            // Changing meeting time or place requires renewed peer confirmation.
            appointments[i].date = opt.date
            appointments[i].landmarkID = opt.landmarkID
            appointments[i].reason = opt.reason
            appointments[i].status = .waiting
            appointments[i].fromPartner = false
            appointments[i].reminded = false
            appointments[i].lateAsked = nil
            community.updateMeetup(appointments[i])
            toast(L.t("改咗：\(dayTimeLabel(opt.date))，喺\(place)附近。等緊\(name)確認。", "改了：\(dayTimeLabel(opt.date))，在\(place)附近。等\(name)确认。", "Changed: \(dayTimeLabel(opt.date)), near \(place). Waiting for \(name) to confirm."))
        } else {
            let a = Appointment(partnerID: p.partnerID, date: opt.date, landmarkID: opt.landmarkID, reason: opt.reason, status: .waiting)
            appointments.insert(a, at: 0)
            community.sendInvite(a)
            toast(L.t("幫你約咗\(name)\(dayTimeLabel(opt.date))，喺\(place)附近。等緊\(name)確認。", "帮你约了\(name)\(dayTimeLabel(opt.date))，在\(place)附近。等\(name)确认。", "Invited \(name) for a walk \(dayTimeLabel(opt.date)), near \(place). Waiting for \(name) to confirm."))
        }
        proposal = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
        Haptics.success()
    }

    func cancelProposal() {
        hush()   // Cancel the pending confirmation announcement.
        proposal = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
    }

    // MARK: - Rescheduling and cancellation

    /// Opening an existing meeting preselects a different time (UX review 12), preserving the place until explicitly changed.
    /// Offer this afternoon, tomorrow morning / afternoon; exclude past, after-dark and less-than-half-hour changes.
    /// keepCurrent appends the original time for place-only edits, but not when countering an incoming invitation.
    func startEditing(_ id: UUID, keepCurrent: Bool = true) {
        guard let a = appointments.first(where: { $0.id == id }), resident(a.partnerID) != nil else { return }
        renaming = nil
        let lm = landmark(a.landmarkID)
        var options: [MeetProposal] = []
        for (d, h) in Self.rescheduleSlots {
            guard options.count < 6 else { break }
            let date = Self.today(at: Double(h), dayOffset: d)
            guard date > now.addingTimeInterval(3600), abs(date.timeIntervalSince(a.date)) > 1800,
                  shade?.isSunUp(at: date) != false, !(weather == .rain && d == 0 && h >= 12) else { continue }
            options.append(MeetProposal(date: date, landmarkID: a.landmarkID, reason: lm.map { reason(for: $0, at: date) } ?? meetupReason(a)))
        }
        if keepCurrent || options.isEmpty { options.append(MeetProposal(date: a.date, landmarkID: a.landmarkID, reason: meetupReason(a))) }
        proposal = Proposal(partnerID: a.partnerID, options: options, index: 0, editing: id)
        scene.highlightLandmark(a.landmarkID)
        focus(onLandmark: a.landmarkID)
    }

    /// Reschedule candidates as (day offset, hour): this afternoon, tomorrow morning / afternoon, then the day after if needed.
    /// 10-18: add today's morning / afternoon / evening and tomorrow's four periods; omit this afternoon when rainy.
    static let rescheduleSlots: [(Int, Int)] = [(0, 10), (0, 15), (0, 17), (1, 8), (1, 10), (1, 15), (1, 17), (2, 8), (2, 16)]

    /// Selected time button in the rescheduling card.
    func pickProposalOption(_ i: Int) {
        guard var p = proposal, p.options.indices.contains(i), p.index != i else { return }
        p.index = i
        proposal = p
        scene.highlightLandmark(p.options[i].landmarkID)
        Haptics.select()
    }

    /// Apply a direct voice edit after recap confirmation.
    func changeMeetup(_ id: UUID, day: Int?, hour: Int?, minute: Int = 0, landmarkID: String?) {
        guard let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].isOpen else { toast(L.t("呢個約會已經冇咗。", "这个约会已经没有了。", "This walk plan no longer exists.")); return }
        var a = changed(appointments[i], day: day, hour: hour, minute: minute, landmarkID: landmarkID)
        guard a.date > now else { toast(L.t("嗰個時間已經過咗，揀過第二個。", "那个时间已经过了，换一个吧。", "That time has passed. Please pick another.")); return }
        // A84: unchanged proposals must not reset confirmed meetings to pending or turn incoming invitations into counteroffers.
        guard a.date != appointments[i].date || a.landmarkID != appointments[i].landmarkID else { toast(L.t("時間地點都冇變，照舊。", "时间地点都没变，照旧。", "Same time and place. No change.")); return }
        a.status = .waiting
        a.fromPartner = false
        a.reminded = false
        a.lateAsked = nil
        appointments[i] = a
        community.updateMeetup(a)
        let name = resident(a.partnerID)?.name ?? ""
        toast(L.t("改咗：\(dayTimeLabel(a.date))，喺\(landmark(a.landmarkID)?.name ?? "")附近。等緊\(name)確認。", "改了：\(dayTimeLabel(a.date))，在\(landmark(a.landmarkID)?.name ?? "")附近。等\(name)确认。", "Changed: \(dayTimeLabel(a.date)), near \(landmark(a.landmarkID)?.name ?? ""). Waiting for \(name) to confirm."))
        Haptics.success()
    }

    /// Preview without saving; preserve unspecified fields. minute carries explicit minutes from speech.
    func changed(_ a: Appointment, day: Int?, hour: Int?, minute: Int = 0, landmarkID: String?) -> Appointment {
        var a = a
        let cal = Self.hk
        if hour != nil || day != nil {
            let base = day.map { cal.startOfDay(for: now).addingTimeInterval(Double($0) * 86400) } ?? cal.startOfDay(for: a.date)
            // Date-only changes preserve hours and minutes, including custom times such as 16:45.
            let seconds = hour == nil ? Double(cal.component(.minute, from: a.date)) * 60 : Double(minute) * 60
            a.date = base.addingTimeInterval(Double(hour ?? cal.component(.hour, from: a.date)) * 3600 + seconds)
            // A time without a date that has passed today means tomorrow.
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
        say(L.t("取消咗同\(name)嘅約，已經話咗俾\(name)知。", "取消了和\(name)的约，已经告诉\(name)了。", "Walk plan with \(name) cancelled. \(name) has been told."))
        Haptics.light()
    }

    /// For voice reschedule / cancel, use the named person or otherwise the nearest unfinished meeting.
    func targetAppointment(partnerID: String?) -> Appointment? {
        appointments.filter { $0.isOpen && (partnerID == nil || $0.partnerID == partnerID) && $0.date > now.addingTimeInterval(-3600) }
            .min { $0.date < $1.date }
    }

    // MARK: - Peer responses and incoming invitations

    func partnerAnswered(_ id: UUID, accepted: Bool) {
        // A36: avoid blank names when the peer is absent or circle members have not loaded.
        guard let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].status == .waiting,
              let name = resident(appointments[i].partnerID)?.name else { return }
        let a = appointments[i]
        if accepted {
            appointments[i].status = .accepted
            let text = L.t("\(name)應承咗：\(dayTimeLabel(a.date))，喺\(landmark(a.landmarkID)?.name ?? "")附近見。", "\(name)答应了：\(dayTimeLabel(a.date))，在\(landmark(a.landmarkID)?.name ?? "")附近见。", "\(name) said yes: see you \(dayTimeLabel(a.date)) near \(landmark(a.landmarkID)?.name ?? "").")
            showBanner(BannerItem(symbol: "checkmark.circle.fill", text: text))
            say(text)
            Haptics.success()
        } else {
            appointments[i].status = .cancelled
            let text = L.t("\(name)話\(dayTimeLabel(a.date))唔得。換個時間再約？", "\(name)说\(dayTimeLabel(a.date))不行。换个时间再约？", "\(name) can't make it \(dayTimeLabel(a.date)). Try another time?")
            showBanner(BannerItem(symbol: "calendar.badge.exclamationmark", text: text, action: .invite(a.partnerID), actionTitle: L.t("再約", "再约", "Invite again")))
            say(text)
        }
    }

    /// Demo: Mrs Chan invites you through CommunityService.
    func partnerInvites(_ id: String = "chan") {
        guard let p = resident(id), p.isNeighbor, let shade else {
            toast(L.t("示範：要先碰一碰做咗街坊，先可以約你。", "演示：要先碰一碰成为邻居，才可以约你。", "Demo: you need to tap phones and become neighbours before they can invite you."))
            return
        }
        let h = Self.hk.component(.hour, from: now) < 15 ? 16 : 8
        let day = h == 8 ? 1 : 0
        guard let opt = ai.pickMeetupSpot(me: me, partner: p, date: Self.today(at: Double(h), dayOffset: day), landmarks: landmarks, shade: shade).map(honestReason) else { return }
        localCommunity?.simulateInvite(Appointment(partnerID: id, date: opt.date, landmarkID: opt.landmarkID, reason: opt.reason, status: .waiting, fromPartner: true))
    }

    func invitedBy(_ a: Appointment) {
        guard let p = resident(a.partnerID), p.isNeighbor else { return }
        appointments.insert(a, at: 0)
        let text = L.t("\(p.name)約你\(dayTimeLabel(a.date))喺\(landmark(a.landmarkID)?.name ?? "")一齊行。", "\(p.name)约你\(dayTimeLabel(a.date))在\(landmark(a.landmarkID)?.name ?? "")一起散步。", "\(p.name) invites you for a walk \(dayTimeLabel(a.date)) at \(landmark(a.landmarkID)?.name ?? "").")
        showBanner(BannerItem(symbol: "envelope.fill", text: text, action: .openNeighbors, actionTitle: L.t("睇吓", "看看", "Have a look")), reply: true)
        say(text)
    }

    /// F7: the recipient confirms once.
    func acceptInvitation(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[i].status = .accepted
        community.respond(to: appointments[i], accept: true)
        let a = appointments[i]
        say(L.t("約好咗：\(dayTimeLabel(a.date))，喺\(landmark(a.landmarkID)?.name ?? "")附近見\(resident(a.partnerID)?.name ?? "")。", "约好了：\(dayTimeLabel(a.date))，在\(landmark(a.landmarkID)?.name ?? "")附近见\(resident(a.partnerID)?.name ?? "")。", "All set: meet \(resident(a.partnerID)?.name ?? "") near \(landmark(a.landmarkID)?.name ?? "") \(dayTimeLabel(a.date))."))
        Haptics.success()
    }

    func declineInvitation(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }) else { return }
        appointments[i].status = .cancelled
        community.respond(to: appointments[i], accept: false)
        say(L.t("已經話咗俾\(resident(appointments[i].partnerID)?.name ?? "佢")知，今次唔去。", "已经告诉\(resident(appointments[i].partnerID)?.name ?? "他")了，这次不去。", "Told \(resident(appointments[i].partnerID)?.name ?? "them") you're not going this time."))
        Haptics.light()
    }

    /// Countering an invitation opens a different time; sending makes it my proposal awaiting the peer's confirmation.
    func rescheduleInvitation(_ id: UUID) { startEditing(id, keepCurrent: false) }

    // MARK: - Departure reminders and expiry

    /// Check every 30 seconds, after moving the time slider and after loading the map.
    func checkAppointments() {
        for i in appointments.indices where appointments[i].isOpen {
            let a = appointments[i]
            let left = a.date.timeIntervalSince(now)
            if a.status == .accepted, !a.reminded, left > 0, left <= 30 * 60, find == nil {
                appointments[i].reminded = true
                let name = resident(a.partnerID)?.name ?? ""
                let text = L.t("\(Int((left / 60).rounded())) 分鐘後約咗\(name)喺\(landmark(a.landmarkID)?.name ?? "")。", "\(Int((left / 60).rounded())) 分钟后约了\(name)在\(landmark(a.landmarkID)?.name ?? "")。", "Meeting \(name) at \(landmark(a.landmarkID)?.name ?? "") in \(Int((left / 60).rounded())) min.")
                showBanner(BannerItem(symbol: "bell.fill", text: text, action: .depart(a.id), actionTitle: L.t("出發", "出发", "Set off")))
                say(text)
            } else if a.status == .accepted, a.lateAsked != true, left < -600, left >= -3600, findAppointment != a.id {
                // F8 / A20: remind once when 10 minutes late outside finding; offer a call only when the peer has a phone number.
                // PhoneBook currently has no numbers; omit a nonfunctional call button and suggest looking nearby.
                appointments[i].lateAsked = true
                let name = resident(a.partnerID)?.name ?? L.t("街坊", "邻居", "your neighbour")
                let canCall = PhoneBook.number(for: a.partnerID) != nil
                let text = L.t("同\(name)約咗\(dayTimeLabel(a.date))，過咗 10 分鐘。", "和\(name)约了\(dayTimeLabel(a.date))，已过 10 分钟。", "Your walk plan with \(name) was \(dayTimeLabel(a.date)). It's 10 minutes past. ")
                    + (canCall ? L.t("要唔要打電話俾佢？", "要不要打电话给他？", "Give them a call?") : L.t("仲未見到嘅話，喺附近搵吓。", "还没见到的话，在附近找找。", "If you can't see them yet, have a look around."))
                showBanner(canCall ? BannerItem(symbol: "clock.fill", text: text, action: .call(a.partnerID), actionTitle: L.t("打電話", "打电话", "Call"))
                                   : BannerItem(symbol: "clock.fill", text: text))
                say(text, prompt: true)
            } else if left < -3600, findAppointment != a.id {
                // Hide meetings still unmet after one hour and stop reminders.
                appointments[i].status = .expired
                toast(L.t("同\(resident(a.partnerID)?.name ?? "街坊")\(dayTimeLabel(a.date))嘅約過咗時間，收埋咗。", "和\(resident(a.partnerID)?.name ?? "邻居")\(dayTimeLabel(a.date))的约已过时，已收起。", "Walk plan with \(resident(a.partnerID)?.name ?? "your neighbour") \(dayTimeLabel(a.date)) has passed. Put away."))
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

    // MARK: - Lists

    var todaysAppointments: [Appointment] {
        let cal = Self.hk
        return appointments.filter { cal.isDate($0.date, inSameDayAs: now) && $0.isOpen && !($0.fromPartner && $0.status == .waiting) }
            .sorted { $0.date < $1.date }
    }
    var invitations: [Appointment] { appointments.filter { $0.fromPartner && $0.status == .waiting } }
    /// Tab badge count: unanswered invitations plus unanswered requests to come and find me.
    var pendingReplies: Int {
        invitations.count + (incomingFind.map { resident($0.fromID) != nil } == true ? 1 : 0)
    }
    var upcomingAppointments: [Appointment] {
        let cal = Self.hk
        return appointments.filter { !cal.isDate($0.date, inSameDayAs: now) && $0.date > now && $0.isOpen && !($0.fromPartner && $0.status == .waiting) }
            .sorted { $0.date < $1.date }
    }
    /// My Meetings includes unfinished meetings today and future days, sorted by time.
    var myAppointments: [Appointment] {
        (todaysAppointments + upcomingAppointments).sorted { $0.date < $1.date }
    }

    /// Use relative labels through two days away, then month/day/weekday (A62); include nonzero minutes.
    func dayTimeLabel(_ d: Date) -> String {
        L.isEn ? dayLabel(d) + " " + Self.clockLabel(d) : dayLabel(d) + Self.clockLabel(d)   // English example: tomorrow 3:15 pm.
    }

    /// Date only: relative day labels or month/day/weekday.
    func dayLabel(_ d: Date) -> String {
        let cal = Self.hk
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        switch diff {
        case -1: return L.t("琴日", "昨天", "yesterday")
        case 0: return L.t("今日", "今天", "today")
        case 1: return L.t("聽日", "明天", "tomorrow")
        case 2: return L.t("後日", "后天", "the day after")
        default:
            if L.isEn {   // English example: Mon 20 Oct.
                let wdEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(cal.component(.weekday, from: d) + 6) % 7]
                return "\(wdEn) \(cal.component(.day, from: d)) \(Self.monthAbbr(cal.component(.month, from: d)))"
            }
            let wd = ["日", "一", "二", "三", "四", "五", "六"][(cal.component(.weekday, from: d) + 6) % 7]
            return "\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日（星期\(wd)）"
        }
    }

    /// Meeting time in Hong Kong time, including custom minutes.
    nonisolated static func clockLabel(_ d: Date) -> String {
        let h = hk.component(.hour, from: d), m = hk.component(.minute, from: d)
        if L.isEn {   // English examples: 8 am, 3:15 pm.
            let h12 = h % 12 == 0 ? 12 : h % 12
            return (m == 0 ? "\(h12)" : "\(h12):\(m < 10 ? "0" : "")\(m)") + (h < 12 ? " am" : " pm")
        }
        return TemplateAI.timeLabel(hour: h, minute: m)
    }
}
