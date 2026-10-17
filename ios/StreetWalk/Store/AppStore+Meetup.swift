import SwiftUI

// F7 约人：提议 → 对方确认 → 改时间 / 改地点 / 取消 → 出发前提醒 → 过期
extension AppStore {
    // MARK: - 提议

    /// announce：撳掣约人时讲出 AI 揀嘅时间、地点、理由（§4 语音 + 图像）；语音约人由复述卡自己讲。
    /// landmarkID：喺地标卡撳「約街坊喺度」——地点定咗，只揀时间。
    func proposeMeetup(with partnerID: String, day: Int? = nil, hour: Int? = nil, landmarkID: String? = nil, announce: Bool = true) {
        guard let p = resident(partnerID), let shade else { return }
        renaming = nil   // 约人卡盖住改名卡：之后讲嘢唔再当新名
        // 唔讲楼层：免得名同楼层对得上（A03）。
        guard p.isNeighbor else { toast(L.t("佢仲未係你街坊。見到面碰一碰，先可以約。", "他还不是你的邻居。见面碰一碰，才可以约。", "They're not your neighbour yet. Meet up and tap phones first, then you can invite them.")); return }
        var options: [MeetProposal] = []
        for (d, h) in candidateTimes(day: day, hour: hour) {
            let date = Self.today(at: Double(h), dayOffset: d)
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
            say(L.t("約\(p.name)\(dayTimeLabel(o.date))，喺\(landmark(o.landmarkID)?.name ?? "")，\(o.reason)。撳「好」就約。", "约\(p.name)\(dayTimeLabel(o.date))，在\(landmark(o.landmarkID)?.name ?? "")，\(o.reason)。按「好」就约。", "Invite \(p.name) for a walk \(dayTimeLabel(o.date)) at \(landmark(o.landmarkID)?.name ?? ""): \(o.reason). Tap “OK” to invite."), prompt: true)
        }
    }

    /// 候选时间：讲咗就用讲嘅；冇讲就由而家之后嘅朝早 / 下晝 / 傍晚揀。
    /// 我哋自己提嘅时间避开日落后（长者夜晚行唔安全，UX 评审 34）；用户自己讲咗钟点就照用佢讲嗰个。
    func candidateTimes(day: Int?, hour: Int?) -> [(Int, Int)] {
        let nowH = Self.hk.component(.hour, from: now)
        // 今日已经过咗嘅钟点唔提：讲咗"今日三點"而家已经四点，就改去聽日同一个钟。
        if var day, let hour {
            if day == 0 && hour <= nowH { day = 1 }
            return [(day, hour)] + daylight([(day, min(hour + 1, 21)), (day + 1, 8)], fallback: [(day + 1, 8)])
        }
        if let day {
            let hours = [8, 16, 18].filter { day > 0 || $0 > nowH + 1 }
            return daylight(hours.isEmpty ? [(day + 1, 8), (day + 1, 16)] : hours.map { (day, $0) }, fallback: [(day + 1, 8), (day + 1, 16)])
        }
        var c: [(Int, Int)] = []
        for h in [8, 16, 17, 18] where h > nowH + 1 { c.append((0, h)) }
        c += [(1, 8), (1, 17)]
        return daylight(c, fallback: [(1, 8), (1, 16)])
    }

    /// 只留太阳仲喺天上嘅钟点（未有遮荫资料就照留）；全部都日落咗就用 fallback。
    private func daylight(_ c: [(Int, Int)], fallback: [(Int, Int)]) -> [(Int, Int)] {
        guard let shade else { return c }
        let lit = c.filter { shade.isSunUp(at: Self.today(at: Double($0.1), dayOffset: $0.0)) }
        return lit.isEmpty ? fallback : lit
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
        guard ranked.count > 1 else { toast(L.t("附近只有一個地標，換唔到第二個。", "附近只有一个地标，换不了别的。", "There's only one landmark nearby, so you can't switch.")); return }
        guard let i = ranked.firstIndex(where: { $0.id == cur.landmarkID }) ?? ranked.indices.first else { return }
        let next = ranked[(i + 1) % ranked.count]
        if p.editing != nil {
            // 改约：时间同地点分开揀，换地点就全部时间一齐换（再揀第二个时间都系新地点）。
            p.options = p.options.map { MeetProposal(date: $0.date, landmarkID: next.id, reason: reason(for: next, at: $0.date)) }
        } else {
            p.options[p.index] = MeetProposal(date: cur.date, landmarkID: next.id, reason: reason(for: next, at: cur.date))
        }
        proposal = p
        scene.highlightLandmark(next.id)
        focus(onLandmark: next.id)
        Haptics.select()
    }

    /// 地点理由：遮荫按画面上的楼大约计（唔计树荫）。
    /// 测试反馈：时间地点要可以自己揀、行几耐都可以自己定。用自己揀嘅替换而家显示嗰个选项（「換個時間 / 地方」照旧轮住换）。
    /// 行几耐写入理由（理由会同步俾对方，佢都见到）。
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
        return (shade?.isSunUp(at: d) == false ? L.t("嗰陣已經日落", "那时已经日落", "sun has set by then") : s >= 0.5 ? L.t("嗰陣有樓遮住", "那时有楼挡着", "shady then (buildings)") : L.t("嗰陣會曬", "那时会晒", "too sunny then")) + (l.hasSeat ? L.t("、有櫈", "、有凳子", ", seats here") : "")
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
            // 改约：时间 / 地点换咗，要对方再确认一次。
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
        hush()   // 取消：「撳好就約」唔好再讲落去
        proposal = nil
        scene.highlightLandmark(nil)
        scene.fadeOccluders(toward: nil)
    }

    // MARK: - 改约、取消

    /// 打开一个已有约会来改：一打开就揀好第一个唔同嘅时间（UX 评审 12），地点照旧（可以再「換個地方」）。
    /// 选项：今日下晝 / 聽日朝早 / 聽日下晝（过咗嘅、日落后嘅、同原来差唔到半个钟嘅唔要）。
    /// keepCurrent：最尾加返「原本時間」，方便只改地点（回覆别人嘅邀请「換個時間」就唔加）。
    func startEditing(_ id: UUID, keepCurrent: Bool = true) {
        guard let a = appointments.first(where: { $0.id == id }), resident(a.partnerID) != nil else { return }
        renaming = nil
        let lm = landmark(a.landmarkID)
        var options: [MeetProposal] = []
        for (d, h) in Self.rescheduleSlots {
            guard options.count < 3 else { break }
            let date = Self.today(at: Double(h), dayOffset: d)
            guard date > now.addingTimeInterval(3600), abs(date.timeIntervalSince(a.date)) > 1800,
                  shade?.isSunUp(at: date) != false else { continue }
            options.append(MeetProposal(date: date, landmarkID: a.landmarkID, reason: lm.map { reason(for: $0, at: date) } ?? a.reason))
        }
        if keepCurrent || options.isEmpty { options.append(MeetProposal(date: a.date, landmarkID: a.landmarkID, reason: a.reason)) }
        proposal = Proposal(partnerID: a.partnerID, options: options, index: 0, editing: id)
        scene.highlightLandmark(a.landmarkID)
        focus(onLandmark: a.landmarkID)
    }

    /// 改时间嘅候选（日差, 钟点）：今日下晝、聽日朝早、聽日下晝，唔够就後日。
    static let rescheduleSlots: [(Int, Int)] = [(0, 16), (1, 8), (1, 16), (2, 8), (2, 16)]

    /// 改约卡揀咗边个时间（时间小按钮）。
    func pickProposalOption(_ i: Int) {
        guard var p = proposal, p.options.indices.contains(i), p.index != i else { return }
        p.index = i
        proposal = p
        scene.highlightLandmark(p.options[i].landmarkID)
        Haptics.select()
    }

    /// 直接改（语音"改做下晝 4 點""改去涼亭"复述确认后）。
    func changeMeetup(_ id: UUID, day: Int?, hour: Int?, minute: Int = 0, landmarkID: String?) {
        guard let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].isOpen else { toast(L.t("呢個約會已經冇咗。", "这个约会已经没有了。", "This walk plan no longer exists.")); return }
        var a = changed(appointments[i], day: day, hour: hour, minute: minute, landmarkID: landmarkID)
        guard a.date > now else { toast(L.t("嗰個時間已經過咗，揀過第二個。", "那个时间已经过了，换一个吧。", "That time has passed. Please pick another.")); return }
        // 冇变就唔好将已约好嘅打返做「等緊確認」、或者将对方嘅邀请变成我嘅反提议（A84）。
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

    /// 改咗之后嘅样子（未保存）：冇讲嘅部分保留原来的。minute：语音讲咗「四點十五」嘅分钟。
    func changed(_ a: Appointment, day: Int?, hour: Int?, minute: Int = 0, landmarkID: String?) -> Appointment {
        var a = a
        let cal = Self.hk
        if hour != nil || day != nil {
            let base = day.map { cal.startOfDay(for: now).addingTimeInterval(Double($0) * 86400) } ?? cal.startOfDay(for: a.date)
            // 只改日子：钟点连分钟都保留（自己揀咗 16:45，「改到聽日」都系 16:45）
            let seconds = hour == nil ? Double(cal.component(.minute, from: a.date)) * 60 : Double(minute) * 60
            a.date = base.addingTimeInterval(Double(hour ?? cal.component(.hour, from: a.date)) * 3600 + seconds)
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
        say(L.t("取消咗同\(name)嘅約，已經話咗俾\(name)知。", "取消了和\(name)的约，已经告诉\(name)了。", "Walk plan with \(name) cancelled. \(name) has been told."))
        Haptics.light()
    }

    /// 语音改约、取消时要改边一个：指名就揀佢，否则揀最近嘅未完成约会。
    func targetAppointment(partnerID: String?) -> Appointment? {
        appointments.filter { $0.isOpen && (partnerID == nil || $0.partnerID == partnerID) && $0.date > now.addingTimeInterval(-3600) }
            .min { $0.date < $1.date }
    }

    // MARK: - 对方的回覆、对方约我

    func partnerAnswered(_ id: UUID, accepted: Bool) {
        // 对方已经唔喺圈入面（或者圈仲未装好）：唔好出空名（A36）。
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

    /// 演示：陈太约你（经 CommunityService 送回来）。
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

    /// 对方只需一次确认（规格 F7）：我按「好」。
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

    /// 别人约我、我想换时间：打开改约卡（已经揀好一个唔同嘅时间），撳「發俾XX」就变成我反提议，等对方确认。
    func rescheduleInvitation(_ id: UUID) { startEditing(id, keepCurrent: false) }

    // MARK: - 出发前提醒、过期

    /// 每 30 秒、拉时间滑杆、装好地图时检查一次。
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
                // F8：过咗约定时间 10 分钟（冇喺找人画面）：提一次（A20）。有对方电话先问要唔要打；
                // 冇号码（PhoneBook 而家全空）就唔出「打電話」（撳咗只会话未有号码），叫佢喺附近搵吓。
                appointments[i].lateAsked = true
                let name = resident(a.partnerID)?.name ?? L.t("街坊", "邻居", "your neighbour")
                let canCall = PhoneBook.number(for: a.partnerID) != nil
                let text = L.t("同\(name)約咗\(dayTimeLabel(a.date))，過咗 10 分鐘。", "和\(name)约了\(dayTimeLabel(a.date))，已过 10 分钟。", "Your walk plan with \(name) was \(dayTimeLabel(a.date)). It's 10 minutes past. ")
                    + (canCall ? L.t("要唔要打電話俾佢？", "要不要打电话给他？", "Give them a call?") : L.t("仲未見到嘅話，喺附近搵吓。", "还没见到的话，在附近找找。", "If you can't see them yet, have a look around."))
                showBanner(canCall ? BannerItem(symbol: "clock.fill", text: text, action: .call(a.partnerID), actionTitle: L.t("打電話", "打电话", "Call"))
                                   : BannerItem(symbol: "clock.fill", text: text))
                say(text, prompt: true)
            } else if left < -3600, findAppointment != a.id {
                // 过咗约定时间一个钟都冇碰头：收埋，唔再提。
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

    // MARK: - 列表

    var todaysAppointments: [Appointment] {
        let cal = Self.hk
        return appointments.filter { cal.isDate($0.date, inSameDayAs: now) && $0.isOpen && !($0.fromPartner && $0.status == .waiting) }
            .sorted { $0.date < $1.date }
    }
    var invitations: [Appointment] { appointments.filter { $0.fromPartner && $0.status == .waiting } }
    /// 等你回覆嘅事有几多件：别人约你（未答）+ 街坊问「想過嚟搵你，方唔方便？」（未答）。标签栏红点用。
    var pendingReplies: Int {
        invitations.count + (incomingFind.map { resident($0.fromID) != nil } == true ? 1 : 0)
    }
    var upcomingAppointments: [Appointment] {
        let cal = Self.hk
        return appointments.filter { !cal.isDate($0.date, inSameDayAs: now) && $0.date > now && $0.isOpen && !($0.fromPartner && $0.status == .waiting) }
            .sorted { $0.date < $1.date }
    }
    /// 「街坊」页「我嘅約會」：今日嘅（未完成）+ 之后几日，按时间排（以前只列之后几日，今日约好嘅睇唔到）。
    var myAppointments: [Appointment] {
        (todaysAppointments + upcomingAppointments).sorted { $0.date < $1.date }
    }

    /// 按日差讲：琴日 / 今日 / 聽日 / 後日，再远就讲几月几号星期几（A62）；钟点有分钟就讲埋（「今日下晝 4 點 45 分」）。
    func dayTimeLabel(_ d: Date) -> String {
        L.isEn ? dayLabel(d) + " " + Self.clockLabel(d) : dayLabel(d) + Self.clockLabel(d)   // 英文：「tomorrow 3:15 pm」
    }

    /// 只讲日子：琴日 / 今日 / 聽日 / 後日 / 几月几号（星期几）。
    func dayLabel(_ d: Date) -> String {
        let cal = Self.hk
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        switch diff {
        case -1: return L.t("琴日", "昨天", "yesterday")
        case 0: return L.t("今日", "今天", "today")
        case 1: return L.t("聽日", "明天", "tomorrow")
        case 2: return L.t("後日", "后天", "the day after")
        default:
            if L.isEn {   // 英文：「Mon 20 Oct」
                let wdEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(cal.component(.weekday, from: d) + 6) % 7]
                return "\(wdEn) \(cal.component(.day, from: d)) \(Self.monthAbbr(cal.component(.month, from: d)))"
            }
            let wd = ["日", "一", "二", "三", "四", "五", "六"][(cal.component(.weekday, from: d) + 6) % 7]
            return "\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日（星期\(wd)）"
        }
    }

    /// 约会钟点（香港时间）：「下晝 4 點」；自己揀咗 16:45 就係「下晝 4 點 45 分」。
    nonisolated static func clockLabel(_ d: Date) -> String {
        let h = hk.component(.hour, from: d), m = hk.component(.minute, from: d)
        if L.isEn {   // 英文：「8 am」「3:15 pm」
            let h12 = h % 12 == 0 ? 12 : h % 12
            return (m == 0 ? "\(h12)" : "\(h12):\(m < 10 ? "0" : "")\(m)") + (h < 12 ? " am" : " pm")
        }
        return TemplateAI.timeLabel(hour: h, minute: m)
    }
}
