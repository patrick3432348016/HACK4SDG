import Foundation

/// Member B: offline template implementation of AIService. Cantonese/Mandarin keywords and sentences follow the L.t UI language.
/// A real-model implementation can conform to the same protocol and fall back here on failure or timeout.
struct TemplateAI: AIService {

    // MARK: - Understanding an utterance

    func parseVoice(_ raw: String, context: AIContext) -> VoiceIntent {
        // English local fallback uses the separate keyword parser in AI/TemplateAIEnglish.swift.
        if EnglishText.isEnglish(raw) { return EnglishText.parseVoice(raw, context: context) }
        // Convert recognized Simplified Chinese to Traditional Chinese so names, landmarks, and keywords match Cantonese data.
        let text = Self.toHant(raw.replacingOccurrences(of: " ", with: ""))
        guard !text.isEmpty else { return .unknown }

        if Self.asksLeave(text) { return .leave }

        // Rescheduling/cancellation must mention a time or landmark to avoid confusion with landmark renaming.
        let partnerHit = context.residents.first { !$0.isMe && (text.contains($0.name) || $0.altName.map(text.contains) == true || text.contains("\($0.floor)樓") || text.contains("\($0.floor)層")) }
        if text.contains("唔約") || text.contains("不約") || (text.contains("取消") && (text.contains("約") || partnerHit != nil)) {
            return .cancelMeetup(partnerID: partnerHit?.id)
        }
        if !text.contains("改名"), let r = Self.changeMarkers.compactMap({ text.range(of: $0) }).first {
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
        let named = others.first { text.contains($0.name) || $0.altName.map(text.contains) == true || text.contains("\($0.floor)樓") || text.contains("\($0.floor)層") }
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
        if EnglishText.isEnglish(raw) { return EnglishText.asksWeather(raw) }
        let t = toHant(raw.replacingOccurrences(of: " ", with: ""))
        if weatherWords.contains(where: t.contains) { return true }
        return feelWords.contains(where: t.contains) && (isQuestion(t) || parseDay(t) != nil)
    }

    /// Sun/heat statements count as reports only when explicitly about this location.
    /// Questions or references to today, tomorrow, or the weather are weather requests, not reports. t is already Traditional Chinese.
    static func isSunnyReport(_ t: String) -> Bool {
        if EnglishText.isEnglish(t) { return EnglishText.isSunnyReport(t) }
        guard sunnyWords.contains(where: t.contains), !isQuestion(t) else { return false }
        if hereWords.contains(where: t.contains) { return true }
        return parseDay(t) == nil && !weatherWords.contains(where: t.contains)
    }

    /// Recognize question particles, question marks, interrogatives, and affirmative-negative constructions. t is already Traditional Chinese.
    static func isQuestion(_ t: String) -> Bool {
        if EnglishText.isEnglish(t) { return EnglishText.isQuestion(t) }
        let markers = ["嗎", "吗", "?", "？", "咩", "乜", "幾多", "多少", "點樣", "怎", "如何", "係咪", "是否", "有冇", "有沒有", "什麼", "甚麼", "幾時"]
        if markers.contains(where: t.contains) || t.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).hasSuffix("呢") { return true }
        let c = Array(t)
        guard c.count >= 3 else { return false }
        for i in 1..<(c.count - 1) where (c[i] == "唔" || c[i] == "不") && c[i - 1] == c[i + 1] { return true }
        return false
    }

    /// Recognize leave requests, including durations inserted between the request verb and leave noun. t is already Traditional Chinese.
    static func asksLeave(_ t: String) -> Bool {
        if EnglishText.isEnglish(t) { return EnglishText.asksLeave(t) }
        if ["請假", "告假", "请假", "請個假", "休息一天", "休息一日", "今日唔行", "今天不走", "今天不去走"].contains(where: t.contains) { return true }
        return t.range(of: "[請请告][個个]?[0-9一二兩两三四五六七八九十半幾几成整]*[個个]?(日|天|星期|禮拜|礼拜|周|週)假", options: .regularExpression) != nil
    }

    // MARK: - Safety: recognize locally in both languages, with or without a Mac server

    enum Safety: Equatable { case emergency, medical }

    /// Require explicit emergency wording; an invitation request for help is not an emergency. Medication/doctor questions are medical requests.
    static func safety(_ raw: String) -> Safety? {
        if EnglishText.isEnglish(raw) { return EnglishText.safety(raw) }
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
        if EnglishText.isEnglish(raw) { return EnglishText.topic(raw) }
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

    /// Day offsets: day after tomorrow = 2; tomorrow/tomorrow morning = 1; today = 0.
    static func parseDay(_ t: String) -> Int? {
        if EnglishText.isEnglish(t) { return EnglishText.parseDay(t) }
        if t.contains("後日") || t.contains("後天") { return 2 }
        if ["聽日", "明天", "明日", "聽朝", "聽晚", "明早", "明晚"].contains(where: t.contains) { return 1 }
        if t.contains("今日") || t.contains("今天") { return 0 }
        return nil
    }

    /// For rescheduling, parse the new time/place after the change-to phrase.
    static let changeMarkers = ["改去", "改喺", "改在", "改到", "改做", "改成", "改返", "改回"]

    /// Parse hours: 3 pm becomes 15, 8 am becomes 8. In 3:15, this returns 15 for the afternoon hour; parseClock handles minutes.
    func parseHour(_ t: String) -> Int? {
        if EnglishText.isEnglish(t) { return EnglishText.parseHour(t) }
        if let c = Self.parseClock(t) { return c.hour }
        let t = Self.toHant(t.filter { !$0.isWhitespace })
        // Reject explicit hours outside 05:00–21:00; do not replace them with an inferred morning/afternoon time.
        if Self.clockRange(t) != nil || t.range(of: Self.colonPattern, options: .regularExpression) != nil { return nil }
        if Self.amWords.contains(where: t.contains) { return 8 }
        if t.contains("中午") { return 12 }
        if Self.pmWords.contains(where: t.contains) { return Self.eveningWords.contains(where: t.contains) ? 19 : 16 }
        return nil
    }

    // MARK: - Hours, minutes, and duration (2026-10-17 feedback: non-hour/half-hour times and walk duration were not recognized)

    static let hourPattern = "([0-9]{1,2}|[一二兩三四五六七八九十]{1,3})點"
    static let colonPattern = "[0-9]{1,2}:[0-5][0-9]"
    static let amWords = ["朝早", "早上", "上午", "早晨", "清早", "朝頭早", "聽朝", "今朝", "明早"]
    static let eveningWords = ["夜晚", "晚上", "傍晚", "黃昏", "今晚", "聽晚", "明晚"]
    static let pmWords = ["下晝", "下午", "晏晝", "中午"] + eveningWords

    /// Parse explicit 24-hour times, including quarter past/to, half past, zero-prefixed minutes, colon notation, and minutes before the hour.
    /// Cantonese clock expressions may count five-minute units, including quarter-past forms.
    /// Without am/pm, interpret hours 1–4 as afternoon. Return nil outside 05:00–21:00. Pure logic covered by unit tests.
    static func parseClock(_ raw: String) -> (hour: Int, minute: Int)? {
        if EnglishText.isEnglish(raw) { return EnglishText.parseClock(raw) }
        let t = toHant(raw.filter { !$0.isWhitespace }).replacingOccurrences(of: "：", with: ":")
        var hour: Int?, minute = 0
        if let r = t.range(of: colonPattern, options: .regularExpression) {
            let parts = t[r].split(separator: ":")
            hour = Int(parts[0])
            minute = Int(parts[1]) ?? 0
        } else if let r = clockRange(t) {
            hour = number(String(t[r].dropLast()))
            minute = minutes(after: t[r.upperBound...])
        }
        guard var h = hour, (0...23).contains(h) else { return nil }
        if pmWords.contains(where: t.contains) {
            if h < 12 { h += 12 }
        } else if !amWords.contains(where: t.contains), (1...4).contains(h) {
            h += 12
        }
        let total = h * 60 + minute   // Five minutes before the hour is negative.
        h = total / 60
        return (5...21).contains(h) ? (h, total % 60) : nil
    }

    /// Find the first actual clock-hour expression; idioms meaning a little earlier/faster are not times.
    static func clockRange(_ t: String) -> Range<String.Index>? {
        var from = t.startIndex
        while let r = t.range(of: hourPattern, options: .regularExpression, range: from..<t.endIndex) {
            let before = r.lowerBound > t.startIndex ? t[t.index(before: r.lowerBound)] : nil
            let after = r.upperBound < t.endIndex ? t[r.upperBound] : nil
            let little = t[r] == "一點" && (before.map { "早快慢遲晚有差多少好大細小再近遠高低耐".contains($0) } == true || after == "點" || after == "兒")
            if !little { return r }
            from = r.upperBound
        }
        return nil
    }

    /// Minutes after the hour marker; five minutes to the hour returns -5.
    private static func minutes(after s: Substring) -> Int {
        let s = String(s.prefix(6))
        // In a request to walk half an hour at three, half an hour is duration. An adjacent half-hour clock expression means 3:30 (10-18).
        if s.hasPrefix("半") { return ["半個鐘", "半個小時", "半小時"].contains(where: s.hasPrefix) ? 0 : 30 }
        for (w, m) in [("一刻", 15), ("1刻", 15), ("兩刻", 30), ("三刻", 45), ("3刻", 45), ("一個骨", 15), ("三個骨", 45), ("個字", 5)] where s.hasPrefix(w) { return m }
        let num = "([0-9]{1,2}|[零〇一二兩三四五六七八九十]{1,3})"
        if s.hasPrefix("差一刻") { return -15 }
        if s.hasPrefix("差"), let r = s.range(of: "^差" + num, options: .regularExpression), let n = number(String(s[r].dropFirst())), (1...30).contains(n) { return -n }
        if s.hasPrefix("踏"), let r = s.range(of: "^踏" + num, options: .regularExpression), let n = number(String(s[r].dropFirst())), (1...11).contains(n) { return n * 5 }
        // Try longest numeric prefixes first; stop before the first character of the phrase meaning together.
        guard let all = s.range(of: "^" + num, options: .regularExpression) else { return 0 }
        var len = s[all].count, n: Int?
        while len > 0, n == nil { n = number(String(s.prefix(len))); if n == nil { len -= 1 } }
        guard let n else { return 0 }
        let digits = String(s.prefix(len)), rest = s.dropFirst(len)
        if rest.hasPrefix("個字") { return (1...11).contains(n) ? n * 5 : 0 }
        // Forty minutes following a three-o'clock walk request is duration, not 3:40 (10-18 device test).
        if rest.hasPrefix("分鐘") || rest.hasPrefix("分鍾") { return 0 }
        if rest.hasPrefix("分") { return (0...59).contains(n) ? n : 0 }
        // Two or more numeric characters represent minutes, including fifteen, forty-five, zero-five, and 20.
        if digits.count >= 2 { return (0...59).contains(n) ? n : 0 }
        // A single Cantonese numeral after the hour means five-minute units only at the end or before a suitable location/walking phrase.
        // The equivalent Mandarin single-digit form is uncommon and is treated as the hour alone.
        let next = rest.first
        let ok = next == nil || next!.isPunctuation || "喺在去到出見见等散行走落嚟來来吧呀啊啦左鐘鐘前".contains(next!)
        guard ok, L.lang == .yue, (1...11).contains(n) else { return 0 }
        return n * 5
    }

    /// Explicit minutes, defaulting to 0. For rescheduling, inspect only the text after change-to.
    static func spokenMinute(_ raw: String) -> Int {
        if EnglishText.isEnglish(raw) {
            // For rescheduling, inspect only text after to/change.
            let t = EnglishText.norm(raw)
            let after = [" to ", " change ", " move ", " make it "].compactMap { t.range(of: $0, options: .backwards) }.first.map { String(t[$0.upperBound...]) } ?? t
            return max(0, EnglishText.parseClock(after)?.minute ?? EnglishText.parseClock(raw)?.minute ?? 0)
        }
        let t = toHant(raw.filter { !$0.isWhitespace })
        let after = changeMarkers.compactMap { t.range(of: $0) }.first.map { String(t[$0.upperBound...]) } ?? t
        return max(0, parseClock(after)?.minute ?? 0)
    }

    /// Convert Chinese/Arabic numbers, including zero-prefixed forms; return nil if unrecognized.
    static func number(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let d: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "兩": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let c = Array(s)
        if c.count == 2, c[0] == "零" || c[0] == "〇" { return d[c[1]] }
        if let i = c.firstIndex(of: "十") {
            guard i <= 1, c.count - i <= 2 else { return nil }
            let tens = i == 0 ? 1 : d[c[0]]
            let ones = i == c.count - 1 ? 0 : d[c[i + 1]]
            guard let tens, let ones else { return nil }
            return tens * 10 + ones
        }
        return c.count == 1 ? d[c[0]] : nil
    }

    /// Walking duration in minutes, including half an hour and one-and-a-half hours. Accept only 5–240 minutes.
    /// Exclude maximum walking distance, clock-time half-hours, and relative departure times. Pure logic covered by tests.
    static func parseDuration(_ raw: String) -> Int? {
        if EnglishText.isEnglish(raw) { return EnglishText.parseDuration(raw) }
        let t = toHant(raw.filter { !$0.isWhitespace })
        let num = "([0-9]{1,3}|[一二兩三四五六七八九十]{1,4})"
        // The middle Bool excludes a duration immediately following an hour marker, where it belongs to the clock time.
        let rules: [(String, Bool, (Int?) -> Int?)] = [
            ("([0-9]{1,2}|[一二兩三四五六七八九十]{1,3})?個半(?:鐘頭|鐘|鍾|小時)", false, { ($0 ?? 1) * 60 + 30 }),
            ("半(?:個)?(?:鐘頭|鐘|鍾|小時)", true, { _ in 30 }),
            (num + "(?:個鐘頭|個鐘|個鍾|個小時|鐘頭|小時)", false, { $0.map { $0 * 60 } }),
            (num + "(?:分鐘|分鍾)", false, { $0 }),
        ]
        for (pattern, notAfterClock, value) in rules {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = t as NSString
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                let before = ns.substring(to: m.range.location)
                let after = ns.substring(from: m.range.location + m.range.length)
                if String(before.suffix(3)).contains("最多") || String(before.suffix(3)).contains("最遠") || (notAfterClock && before.hasSuffix("點"))
                    || ["後", "前", "之後", "以內", "以内"].contains(where: after.hasPrefix) { continue }
                let said = m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound
                let n = said ? number(ns.substring(with: m.range(at: 1))) : nil
                if said, n == nil { continue }
                if let v = value(n), (5...240).contains(v) { return v }
            }
        }
        return nil
    }

    /// F7 acceptance: combine shade, seating, and both walking times into one sentence explaining the meeting-place choice.
    /// Wrap only for display/speech. Preserve the stored reason; the recipient recomputes it in their own language.
    static func whyHere(_ reason: String) -> String {
        var r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = r.last, "。.，,、；;".contains(last) { r.removeLast() }
        guard !r.isEmpty else { return "" }
        let prefix = L.t("揀呢度係因為：", "选这里的原因：", "Why here: ")
        if r.hasPrefix(prefix) { return r + L.t("。", "。", ".") }
        if L.isEn { r = r.prefix(1).lowercased() + r.dropFirst() }
        return prefix + r + L.t("。", "。", ".")
    }

    /// Describe walking together for the specified duration, using the selected language.
    static func walkPhrase(_ m: Int) -> String {
        let d = durationLabel(m)
        if L.isEn { return "for " + d }
        return L.t("一齊行", "一起走", "walk together ") + (d.first.map { $0.isASCII && $0.isNumber } == true ? " " : "") + d
    }

    /// Format durations such as forty minutes, half an hour, one hour, or one-and-a-half hours.
    static func durationLabel(_ m: Int) -> String {
        let h = m / 60
        let hs = h == 1 ? L.t("一", "一", "1") : h == 2 ? L.t("兩", "两", "2") : "\(h)"
        if m == 30 { return L.t("半個鐘", "半个小时", "half an hour") }
        if m % 60 == 0 { return L.t("\(hs)個鐘", "\(hs)个小时", h == 1 ? "an hour" : "\(h) hours") }
        if m % 60 == 30 { return L.t("\(hs)個半鐘", "\(hs)个半小时", h == 1 ? "an hour and a half" : "\(h) and a half hours") }
        return L.t("\(m) 分鐘", "\(m) 分钟", "\(m) minutes")
    }

    // MARK: - Sentence generation

    /// Start the daily sentence with the nickname; a floor number sounded like a different person in the 10-18 test. Omit the subject if unset.
    func dailyLine(for r: Resident, passed: [Landmark]) -> String {
        let who = r.lineSubject, en = who.isEmpty ? "" : "\(who): "
        if r.onLeave { return L.t("\(who)今日唔出門", "\(who)今天不出门", "\(en)not going out today") }
        guard let last = passed.last else { return L.t("\(who)今日仲未出門", "\(who)今天还没出门", "\(en)not out yet today") }
        let seed = abs(r.id.hashValue)
        if passed.count >= 2, seed % 3 == 0 { return L.t("\(who)今日經過\(passed[0].name)同\(last.name)", "\(who)今天经过\(passed[0].name)和\(last.name)", "\(en)passed \(passed[0].name) and \(last.name) today") }
        if last.hasSeat, seed % 3 == 1 { return L.t("\(who)喺\(last.name)坐咗陣", "\(who)在\(last.name)坐了一会儿", "\(en)sat a while at \(last.name)") }
        return L.t("\(who)今日行到\(last.name)", "\(who)今天走到\(last.name)", "\(en)walked to \(last.name) today")
    }

    func nameLandmark(_ c: LandmarkCandidate) -> String {
        if L.isEn { return nameLandmarkEn(c) }
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

    /// For English landmarks, regenerate from OSM English names at installation. Otherwise use the category name; do not append Chinese suffixes.
    private func nameLandmarkEn(_ c: LandmarkCandidate) -> String {
        // Use reasonably short names containing Latin letters to avoid mixed-language place labels.
        let n = c.osmName.flatMap { s -> String? in
            s.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.isASCII } && s.count <= 24 ? s : nil
        }
        switch c.kind {
        case .busTerminus:
            if let n, n.lowercased().contains("terminus") { return n }
            return n.map { "\($0) bus terminus" } ?? "Bus terminus"
        case .busStop: return n.map { $0.lowercased().contains("stop") ? $0 : "\($0) bus stop" } ?? "Bus stop"
        case .park: return c.hasSeat ? (n.map { "\($0) benches" } ?? "Park benches") : (n ?? "Park")
        case .playground: return "Playground"
        case .pitch: return "By the sports court"
        case .shelter: return "Shelter"
        case .bench: return "Benches"
        case .mall: return n.map { "\($0) entrance" } ?? "Mall entrance"
        case .market: return "Market entrance"
        case .community: return "Community centre"
        case .lobby: return c.osmName.map { "Below \($0)" } ?? "Lobby"
        case .food: return n.map { "\($0) entrance" } ?? "Restaurant entrance"
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
        parts.append(best.2 >= 0.5 ? L.t("嗰陣有樓遮住", "那时有楼挡着", "Shaded by buildings then") : L.t("嗰陣有啲曬", "那时有点晒", "A bit sunny then"))
        if l.hasSeat { parts.append(L.t("有櫈", "有凳子", "seats here")) }
        parts.append(L.t("兩個都行 \(minutes) 分鐘左右", "两人都走 \(minutes) 分钟左右", "about \(minutes) minutes' walk for both"))
        return MeetProposal(date: date, landmarkID: l.id, reason: parts.joined(separator: L.t("、", "、", ", ")))
    }

    func walkAdvice(weather: Weather, now: Date, shadeTip: (landmark: Landmark, shadedFrom: Int?)?) -> String? {
        switch weather {
        case .rain: return L.t("天文台話下晝會落大雨，不如早啲出門，或者聽日先行。", "天文台说下午会下大雨，不如早点出门，或者明天再走。", "The Observatory says heavy rain this afternoon. Go out early, or walk tomorrow.")
        case .hot:
            if let tip = shadeTip, let h = tip.shadedFrom { return L.t("今日好熱。\(tip.landmark.name)\(Self.hourLabel(h))後有樓遮住，嗰陣先出門啱啲。", "今天很热。\(tip.landmark.name)\(Self.hourLabel(h))后有楼挡住太阳，那时再出门比较好。", "Very hot today. \(tip.landmark.name) is shaded after \(Self.hourLabel(h)). Better to go out then.") }
            return L.t("今日好熱，記得帶水，揀有遮蔭嘅路行。", "今天很热，记得带水，挑有树荫的路走。", "Very hot today. Bring water and walk in the shade.")
        case .normal:
            if let tip = shadeTip, let h = tip.shadedFrom { return L.t("\(tip.landmark.name)\(Self.hourLabel(h))後有樓遮住，嗰陣行最舒服。", "\(tip.landmark.name)\(Self.hourLabel(h))后有楼挡住太阳，那时走最舒服。", "\(tip.landmark.name) is shaded after \(Self.hourLabel(h)). Best time to walk.") }
            return nil
        }
    }

    func monthlyReport(placeName: String, reports: [Report], landmarks: [Landmark], stats: MonthlyStats) -> MonthlyReport {
        var counts: [String: (ReportKind, Int)] = [:]
        for r in reports {
            let place = landmarks.first { $0.id == r.landmarkID }?.name ?? L.t("附近", "附近", "nearby")
            let key = place + r.kind.rawValue
            counts[key] = (r.kind, (counts[key]?.1 ?? 0) + 1)
        }
        let items = counts.map { key, v -> MonthlyReport.Item in
            let place = String(key.dropLast(v.0.rawValue.count))
            let suggestion: String
            switch v.0 {
            case .sunny: suggestion = L.t("加遮蔭或者種樹", "加遮阳棚或者种树", "Add shade or plant trees")
            case .noSeat: suggestion = L.t("加張櫈", "加张凳子", "Add a bench")
            case .rough: suggestion = L.t("整平路面、加扶手", "修平路面、加扶手", "Fix the path, add handrails")
            }
            return MonthlyReport.Item(place: place, kind: v.0, count: v.1, suggestion: suggestion)
        }.filter { $0.count >= Self.minReporters }.sorted { $0.count > $1.count }
        let top = items.first.map { L.t("最多人反映：\($0.place)\($0.kind.rawValue)（\($0.count) 人）。", "反映最多的：\($0.place)\($0.kind.label)（\($0.count) 人）。", "Most reported: \($0.place), \($0.kind.label) (\($0.count) people). ") } ?? ""
        return MonthlyReport(title: L.t("\(placeName) · 本月散步報告", "\(placeName) · 本月散步报告", "\(placeName) · Walking report this month"),
                             summary: L.t("本月 \(stats.walks) 人次散步，街坊約咗 \(stats.meetups) 次一齊行。\(top)只計 \(Self.minReporters) 人以上嘅反映，冇任何個人路線。", "本月共 \(stats.walks) 人次散步，邻居约了 \(stats.meetups) 次一起走。\(top)只统计 \(Self.minReporters) 人以上的反映，不含任何个人路线。", "\(stats.walks) walks this month. Neighbours walked together \(stats.meetups) times. \(top)Only counts reports from \(Self.minReporters)+ people. No personal routes."),
                             items: items, walkers: stats.walks, meetups: stats.meetups)
    }

    /// F10 specification: output aggregates only when the participant count is at least 10.
    static let minReporters = 10

    static func hourLabel(_ h: Int) -> String {
        if h < 12 { return L.t("朝早 \(h) 點", "早上 \(h) 点", "\(h) am") }
        if h == 12 { return L.t("中午 12 點", "中午 12 点", "12 noon") }
        return h < 18 ? L.t("下晝 \(h - 12) 點", "下午 \(h - 12) 点", "\(h - 12) pm") : L.t("夜晚 \(h - 12) 點", "晚上 \(h - 12) 点", "\(h - 12) pm")
    }

    /// Meetup time: use hourLabel for whole hours and include explicit minutes otherwise, such as 16:45.
    static func timeLabel(hour h: Int, minute m: Int) -> String {
        if L.isEn, m != 0 { return "\(h > 12 ? h - 12 : h):" + String(format: "%02d", m) + (h >= 12 ? " pm" : " am") }
        return m == 0 ? hourLabel(h) : hourLabel(h) + L.t(" \(m) 分", " \(m) 分", ":\(m)")
    }
}

extension Resident {
    /// Daily-sentence subject: nickname, or empty if the current user has not set one. Do not use a floor number (10-18 test).
    var lineSubject: String { isMe ? (nickname ?? "") : name }
}
