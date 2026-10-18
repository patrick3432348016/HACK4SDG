import Foundation

/// Member B: offline template implementation of AIService. Cantonese/Mandarin keywords and sentences follow the L.t UI language.
/// A real-model implementation can conform to the same protocol and fall back here on failure or timeout.
struct TemplateAI: AIService {

    // MARK: - Understanding an utterance

    func parseVoice(_ raw: String, context: AIContext) -> VoiceIntent {
        // Convert recognized Simplified Chinese to Traditional Chinese so names, landmarks, and keywords match Cantonese data.
        let text = Self.toHant(raw.replacingOccurrences(of: " ", with: ""))
        guard !text.isEmpty else { return .unknown }

        if Self.asksLeave(text) { return .leave }

        // Rescheduling/cancellation must mention a time or landmark to avoid confusion with landmark renaming.
        let partnerHit = context.residents.first { !$0.isMe && (text.contains($0.name) || text.contains("\($0.floor)樓") || text.contains("\($0.floor)層")) }
        if text.contains("唔約") || text.contains("不約") || (text.contains("取消") && (text.contains("約") || partnerHit != nil)) {
            return .cancelMeetup(partnerID: partnerHit?.id)
        }
        if !text.contains("改名"), let r = ["改去", "改喺", "改在", "改到", "改做", "改成", "改返", "改回"].compactMap({ text.range(of: $0) }).first {
            let before = String(text[..<r.lowerBound]), after = String(text[r.upperBound...])
            let lm = context.landmarks.filter { after.contains($0.name) }.max { $0.name.count < $1.name.count }   // When one name contains another, prefer the longest match.
            let hour = parseHour(after)
            let day = Self.parseDay(after)
            let aboutMeetup = before.isEmpty || before.contains("約") || partnerHit != nil
            if aboutMeetup, lm != nil || hour != nil || day != nil {
                return .changeMeetup(partnerID: partnerHit?.id, day: day, hour: hour, landmarkID: lm?.id)
            }
        }

        if let r = ["改名做", "改名叫", "改做", "改名為", "改名成"].compactMap({ text.range(of: $0) }).first {
            let before = String(text[..<r.lowerBound]), after = String(text[r.upperBound...])
            let newName = after.trimmingCharacters(in: .punctuationCharacters)
            if !newName.isEmpty, let lm = context.landmarks.first(where: { before.contains($0.name) || $0.name.contains(before) && !before.isEmpty }) {
                return .rename(landmarkID: lm.id, newName: newName)
            }
        }

        if context.finding, text.hasPrefix("我喺") || text.hasPrefix("我在") || text.hasPrefix("我到") { return .broadcast(raw) }

        if Self.isSunnyReport(text) { return .report(.sunny) }
        if Self.noSeatWords.contains(where: text.contains) { return .report(.noSeat) }
        if Self.roughWords.contains(where: text.contains) { return .report(.rough) }

        // Match a named person or floor. For a generic reference to a neighbor, choose an existing neighbor:
        // For finding, prefer someone outside; for invitations, choose the first neighbor.
        let others = context.residents.filter { !$0.isMe }
        let named = others.first { text.contains($0.name) || text.contains("\($0.floor)樓") || text.contains("\($0.floor)層") }
        let generic = Self.genericNeighborWords.contains(where: text.contains)
        let wantsFind = Self.findWords.contains(where: text.contains) && !text.contains("約")
        let wantsInvite = Self.inviteWords.contains(where: text.contains)
        if wantsFind, let p = named ?? (generic ? others.first(where: \.isOut) ?? others.first : nil) { return .goFind(partnerID: p.id) }
        if wantsInvite, let p = named ?? (generic ? others.first : nil) {
            let day = Self.parseDay(text) ?? 0
            return .invite(partnerID: p.id, day: day, hour: parseHour(text))
        }
        return .unknown
    }

    // Common Cantonese/Mandarin keywords, after conversion to Traditional Chinese.
    static let inviteWords = ["約", "一齊行", "一齊去", "一起", "散步", "行街", "陪我", "走走", "去走", "出去行"]
    static let findWords = ["搵", "找", "過去", "去見", "見見", "見下"]
    static let genericNeighborWords = ["鄰居", "街坊", "朋友", "老友"]
    static let sunnyWords = ["好曬", "太曬", "很曬", "曬得", "好熱", "太熱", "很熱", "熱死", "太陽好大", "太陽很大", "太陽太大", "冇遮", "沒遮", "沒有遮", "沒有樹蔭", "沒有陰"]
    static let noSeatWords = ["冇櫈", "冇凳", "無櫈", "沒有凳", "沒凳", "沒有椅", "沒椅", "沒地方坐", "沒有地方坐", "冇位坐", "沒得坐", "坐不了", "唔夠櫈"]
    static let roughWords = ["難行", "唔好行", "難走", "不好走", "路不平", "路爛", "路很爛", "好滑", "很滑", "路滑"]
    static let weatherWords = ["天氣", "天气", "落雨", "下雨", "會唔會熱", "熱不熱", "熱唔熱", "幾多度", "多少度", "幾度", "氣溫", "溫度", "颱風", "打風"]
    /// Treat temperature/rain questions, or statements about today/tomorrow, as weather requests.
    static let feelWords = ["熱", "曬", "太陽", "雨", "凍", "冷", "晴", "風"]
    /// Only an explicit reference to this place counts as a local resident report.
    static let hereWords = ["呢度", "呢處", "呢邊", "呢個位", "這裡", "這裏", "這兒", "這邊", "這個位", "此處"]

    /// Weather questions use the phone's Observatory summary, including questions about heat, cold, or rain today/tomorrow.
    static func asksWeather(_ raw: String) -> Bool {
        let t = toHant(raw.replacingOccurrences(of: " ", with: ""))
        if weatherWords.contains(where: t.contains) { return true }
        return feelWords.contains(where: t.contains) && (isQuestion(t) || parseDay(t) != nil)
    }

    /// Sun/heat statements count as reports only when explicitly about this location.
    /// Questions or references to today, tomorrow, or the weather are weather requests, not reports. t is already Traditional Chinese.
    static func isSunnyReport(_ t: String) -> Bool {
        guard sunnyWords.contains(where: t.contains), !isQuestion(t) else { return false }
        if hereWords.contains(where: t.contains) { return true }
        return parseDay(t) == nil && !weatherWords.contains(where: t.contains)
    }

    /// Recognize question particles, question marks, interrogatives, and affirmative-negative constructions. t is already Traditional Chinese.
    static func isQuestion(_ t: String) -> Bool {
        let markers = ["嗎", "吗", "?", "？", "咩", "乜", "幾多", "多少", "點樣", "怎", "如何", "係咪", "是否", "有冇", "有沒有", "什麼", "甚麼", "幾時"]
        if markers.contains(where: t.contains) || t.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).hasSuffix("呢") { return true }
        let c = Array(t)
        guard c.count >= 3 else { return false }
        for i in 1..<(c.count - 1) where (c[i] == "唔" || c[i] == "不") && c[i - 1] == c[i + 1] { return true }
        return false
    }

    /// Recognize leave requests, including durations inserted between the request verb and leave noun. t is already Traditional Chinese.
    static func asksLeave(_ t: String) -> Bool {
        if ["請假", "告假", "请假", "請個假", "休息一天", "休息一日", "今日唔行", "今天不走", "今天不去走"].contains(where: t.contains) { return true }
        return t.range(of: "[請请告][個个]?[0-9一二兩两三四五六七八九十半幾几成整]*[個个]?(日|天|星期|禮拜|礼拜|周|週)假", options: .regularExpression) != nil
    }

    // MARK: - Safety: recognize locally in both languages, with or without a Mac server

    enum Safety: Equatable { case emergency, medical }

    /// Require explicit emergency wording; an invitation request for help is not an emergency. Medication/doctor questions are medical requests.
    static func safety(_ raw: String) -> Safety? {
        let s = raw.filter { !$0.isWhitespace }
        let t = toHant(s)
        if [s, t].contains(where: { x in emergencyWords.contains(where: x.contains) })
            || t.range(of: "(胸口|心口).{0,3}(痛|疼)", options: .regularExpression) != nil { return .emergency }
        if isMedicalQuestion(t) { return .medical }
        return nil
    }

    /// Mandarin variants, Cantonese, and server voice_policy.py URGENT expressions. Chest-pain variants also use a regex.
    static let emergencyWords = ["救命", "救我", "摔倒", "跌倒", "跌親", "跌亲", "爬不起來", "爬不起来", "起不了身", "起唔到身",
                                 "喘不過氣", "喘不过气", "透不過氣", "透不过气", "唞唔到氣", "唞唔到气", "透唔到氣", "透唔到气",
                                 "呼吸困難", "呼吸困难", "暈倒", "晕倒", "暈低", "晕低", "流血", "流緊血", "流紧血",
                                 "叫救護車", "叫救护车", "叫白車", "叫白车", "報警", "报警", "我想自殺", "我想自杀", "我想死"]

    /// Medication/doctor questions in Traditional Chinese.
    static let medicalWords = ["什麼藥", "甚麼藥", "咩藥", "乜藥", "乜嘢藥", "咩嘢藥", "邊種藥", "哪種藥", "哪個藥",
                               "什麼醫生", "甚麼醫生", "哪個醫生", "咩醫生", "乜醫生", "邊個醫生", "什麼科", "甚麼科", "哪個科", "咩科", "邊科",
                               "要不要看醫生", "要唔要睇醫生", "使唔使睇醫生", "用不用看醫生", "需不需要看醫生", "需唔需要睇醫生", "要看醫生嗎", "要睇醫生嗎"]

    /// Medical requests include these expressions or a question mentioning medication. A pharmacy is a place and does not count.
    static func isMedicalQuestion(_ t: String) -> Bool {
        if medicalWords.contains(where: t.contains) { return true }
        var d = t
        for place in ["藥房", "藥店", "藥行", "藥局", "藥劑師"] { d = d.replacingOccurrences(of: place, with: "") }
        return d.contains("藥") && isQuestion(d)
    }

    /// Infer the broad unsupported intent (invite/find/report) to explain why the request could not be completed.
    enum Topic { case invite, find, report }
    static func topic(_ raw: String) -> Topic? {
        let t = toHant(raw.replacingOccurrences(of: " ", with: ""))
        if inviteWords.contains(where: t.contains) { return .invite }
        if findWords.contains(where: t.contains) { return .find }
        if ["反映", "報告", "投訴"].contains(where: t.contains) { return .report }
        return nil
    }

    /// ICU Simplified-to-Traditional conversion; leave unchanged if conversion fails.
    static func toHant(_ s: String) -> String {
        s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s
    }

    /// Recognize Cantonese and Mandarin expressions for the day after tomorrow (2), tomorrow (1), and today (0).
    static func parseDay(_ t: String) -> Int? {
        if t.contains("後日") || t.contains("後天") { return 2 }
        if t.contains("聽日") || t.contains("明天") || t.contains("明日") { return 1 }
        if t.contains("今日") || t.contains("今天") { return 0 }
        return nil
    }

    /// Interpret Cantonese and Mandarin time expressions, including 3 pm as 15 and 8 am as 8.
    func parseHour(_ t: String) -> Int? {
        let digits: [Character: Int] = ["一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        let t = Self.toHant(t)
        guard let r = t.range(of: "[0-9一二兩三四五六七八九十]+點", options: .regularExpression) else {
            if t.contains("朝早") || t.contains("早上") { return 8 }
            if t.contains("下晝") || t.contains("下午") { return 16 }
            if t.contains("夜晚") || t.contains("晚上") { return 19 }
            return nil
        }
        let s = String(t[r].dropLast())
        var h = Int(s) ?? 0
        if h == 0 {
            if s == "十" { h = 10 } else if s.hasPrefix("十") { h = 10 + (digits[s.last!] ?? 0) } else { h = s.reduce(0) { $0 * 10 + (digits[$1] ?? 0) } }
        }
        if (t.contains("下晝") || t.contains("下午") || t.contains("夜晚") || t.contains("晚上")) && h < 12 { h += 12 }
        return (5...21).contains(h) ? h : nil
    }

    // MARK: - Sentence generation

    func dailyLine(for r: Resident, passed: [Landmark]) -> String {
        if r.onLeave { return L.t("\(r.floorLabel)今日請咗假", "\(r.floorLabel)今天请假了") }
        guard let last = passed.last else { return L.t("\(r.floorLabel)今日仲未出門", "\(r.floorLabel)今天还没出门") }
        let seed = abs(r.id.hashValue)
        if passed.count >= 2, seed % 3 == 0 { return L.t("\(r.floorLabel)今日經過\(passed[0].name)同\(last.name)", "\(r.floorLabel)今天经过\(passed[0].name)和\(last.name)") }
        if last.hasSeat, seed % 3 == 1 { return L.t("\(r.floorLabel)喺\(last.name)坐咗陣", "\(r.floorLabel)在\(last.name)坐了一会儿") }
        return L.t("\(r.floorLabel)今日行到\(last.name)", "\(r.floorLabel)今天走到\(last.name)")
    }

    func nameLandmark(_ c: LandmarkCandidate) -> String {
        let n = c.osmName
        switch c.kind {
        case .busTerminus:
            if let n, n.contains("總站") { return n }
            return "巴士總站"
        case .busStop:
            if let n, n.count <= 5 { return n.hasSuffix("站") ? n : "\(n)站" }
            return "巴士站"
        case .park: return c.hasSeat ? "公園櫈仔" : (n ?? "公園")
        case .playground: return "遊樂場"
        case .pitch: return "球場邊"
        case .shelter: return "涼亭"
        case .bench: return "櫈仔"
        case .mall:
            if let n, n.count <= 5 { return "\(n)門口" }
            return "商場門口"
        case .market: return "街市門口"
        case .community: return "社區中心"
        case .lobby: return n.map { "\($0)樓下" } ?? "大堂"
        case .food: return n.map { "\($0)門口" } ?? "食肆門口"
        }
    }

    func alternativeNames(for l: Landmark) -> [String] {
        switch l.kind {
        case .lobby:
            let block = l.name.replacingOccurrences(of: "樓下", with: "")
            return ["\(block)大堂", "\(block)門口", "\(block)平台"]
        case .busTerminus, .busStop: return ["巴士站", "總站門口", "車站涼亭"]
        case .park: return ["公園", "大樹底", "公園涼亭"]
        case .pitch: return ["球場", "籃球場邊", "球場門口"]
        case .mall: return ["商場", "商場側門", "麥當勞附近"]
        default: return ["\(l.name)附近", "\(l.name)門口", "\(l.name)隔籬"]
        }
    }

    func pickMeetupSpot(me: Resident, partner: Resident, date: Date, landmarks: [Landmark], shade: ShadeProviding) -> MeetProposal? {
        guard !landmarks.isEmpty else { return nil }
        let mine = landmarks.first { $0.id == me.homeLandmarkID }?.pos ?? .zero
        let theirs = landmarks.first { $0.id == partner.homeLandmarkID }?.pos ?? .zero
        let scored = landmarks.map { l -> (Landmark, Double, Double) in
            let s = shade.shade(landmarkID: l.id, at: date)
            let walk = max(l.pos.distance(to: mine), l.pos.distance(to: theirs))
            return (l, (l.hasSeat ? 2 : 0) + s * 3 - walk / 120, s)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else { return nil }
        let l = best.0
        let minutes = max(1, Int((max(l.pos.distance(to: mine), l.pos.distance(to: theirs)) / 65).rounded()))
        var parts: [String] = []
        parts.append(best.2 >= 0.5 ? L.t("嗰陣有樓遮住", "那时有楼挡着") : L.t("嗰陣有啲曬", "那时有点晒"))
        if l.hasSeat { parts.append(L.t("有櫈", "有凳子")) }
        parts.append(L.t("兩個都行 \(minutes) 分鐘左右", "两人都走 \(minutes) 分钟左右"))
        return MeetProposal(date: date, landmarkID: l.id, reason: parts.joined(separator: "、"))
    }

    func walkAdvice(weather: Weather, now: Date, shadeTip: (landmark: Landmark, shadedFrom: Int?)?) -> String? {
        switch weather {
        case .rain: return L.t("天文台話下晝會落大雨，不如早啲出門，或者聽日先行。", "天文台说下午会下大雨，不如早点出门，或者明天再走。")
        case .hot:
            if let tip = shadeTip, let h = tip.shadedFrom { return L.t("今日好熱。\(tip.landmark.name)\(Self.hourLabel(h))後有樓遮住，嗰陣先出門啱啲。", "今天很热。\(tip.landmark.name)\(Self.hourLabel(h))后有楼挡住太阳，那时再出门比较好。") }
            return L.t("今日好熱，記得帶水，揀有遮蔭嘅路行。", "今天很热，记得带水，挑有树荫的路走。")
        case .normal:
            if let tip = shadeTip, let h = tip.shadedFrom { return L.t("\(tip.landmark.name)\(Self.hourLabel(h))後有樓遮住，嗰陣行最舒服。", "\(tip.landmark.name)\(Self.hourLabel(h))后有楼挡住太阳，那时走最舒服。") }
            return nil
        }
    }

    func monthlyReport(placeName: String, reports: [Report], landmarks: [Landmark], stats: MonthlyStats) -> MonthlyReport {
        var counts: [String: (ReportKind, Int)] = [:]
        for r in reports {
            let place = landmarks.first { $0.id == r.landmarkID }?.name ?? "附近"
            let key = place + r.kind.rawValue
            counts[key] = (r.kind, (counts[key]?.1 ?? 0) + 1)
        }
        let items = counts.map { key, v -> MonthlyReport.Item in
            let place = String(key.dropLast(v.0.rawValue.count))
            let suggestion: String
            switch v.0 {
            case .sunny: suggestion = L.t("加遮蔭或者種樹", "加遮阳棚或者种树")
            case .noSeat: suggestion = L.t("加張櫈", "加张凳子")
            case .rough: suggestion = L.t("整平路面、加扶手", "修平路面、加扶手")
            }
            return MonthlyReport.Item(place: place, kind: v.0, count: v.1, suggestion: suggestion)
        }.filter { $0.count >= Self.minReporters }.sorted { $0.count > $1.count }
        let top = items.first.map { L.t("最多人反映：\($0.place)\($0.kind.rawValue)（\($0.count) 人）。", "反映最多的：\($0.place)\($0.kind.label)（\($0.count) 人）。") } ?? ""
        return MonthlyReport(title: L.t("\(placeName) · 本月散步報告", "\(placeName) · 本月散步报告"),
                             summary: L.t("本月 \(stats.walks) 人次散步，街坊約咗 \(stats.meetups) 次一齊行。\(top)只計 \(Self.minReporters) 人以上嘅反映，冇任何個人路線。", "本月共 \(stats.walks) 人次散步，邻居约了 \(stats.meetups) 次一起走。\(top)只统计 \(Self.minReporters) 人以上的反映，不含任何个人路线。"),
                             items: items, walkers: stats.walks, meetups: stats.meetups)
    }

    /// F10 specification: output aggregates only when the participant count is at least 10.
    static let minReporters = 10

    static func hourLabel(_ h: Int) -> String {
        if h < 12 { return L.t("朝早 \(h) 點", "早上 \(h) 点") }
        if h == 12 { return L.t("中午 12 點", "中午 12 点") }
        return h < 18 ? L.t("下晝 \(h - 12) 點", "下午 \(h - 12) 点") : L.t("夜晚 \(h - 12) 點", "晚上 \(h - 12) 点")
    }

    /// Meetup time: use hourLabel for whole hours and include explicit minutes otherwise, such as 16:45.
    static func timeLabel(hour h: Int, minute m: Int) -> String {
        m == 0 ? hourLabel(h) : hourLabel(h) + L.t(" \(m) 分", " \(m) 分")
    }
}
