import Foundation

/// 成员 B：AIService 的模板实现（离线可跑）。关键词理解粤语同普通话，模板生成句子（跟 L.t 界面语言）。
/// 之后接真模型时，新建一个实现同一协议的类，失败或超时就退回这里。
struct TemplateAI: AIService {

    // MARK: - 听懂一句话

    func parseVoice(_ raw: String, context: AIContext) -> VoiceIntent {
        // 英文句子（英文界面、手机后备）：另一套关键词（AI/TemplateAIEnglish.swift）
        if EnglishText.isEnglish(raw) { return EnglishText.parseVoice(raw, context: context) }
        // 普通话识别出简体字：先转繁体，人名、地标名、关键词就同粤语一样对得上（陈太→陳太、凉亭→涼亭）。
        let text = Self.toHant(raw.replacingOccurrences(of: " ", with: ""))
        guard !text.isEmpty else { return .unknown }

        if Self.asksLeave(text) { return .leave }

        // 改约 / 取消约：要讲到时间或地标，免得同改地标名撞。
        let partnerHit = context.residents.first { !$0.isMe && (text.contains($0.name) || text.contains("\($0.floor)樓") || text.contains("\($0.floor)層")) }
        if text.contains("唔約") || text.contains("不約") || (text.contains("取消") && (text.contains("約") || partnerHit != nil)) {
            return .cancelMeetup(partnerID: partnerHit?.id)
        }
        if !text.contains("改名"), let r = Self.changeMarkers.compactMap({ text.range(of: $0) }).first {
            let before = String(text[..<r.lowerBound]), after = String(text[r.upperBound...])
            let lm = context.landmarks.filter { after.contains($0.name) }.max { $0.name.count < $1.name.count }   // 名有包含关系时揀最长
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

        // 讲到名 / 楼层就揀嗰个；只讲「鄰居 / 街坊」（普通话常见：「约邻居明天一起走」「找邻居」）就揀一个街坊：
        // 找人揀喺外面嗰个，约人揀第一个。
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

    // 关键词（已转繁体；粤语 + 普通话常见讲法）。
    static let inviteWords = ["約", "一齊行", "一齊去", "一起", "散步", "行街", "陪我", "走走", "去走", "出去行"]
    static let findWords = ["搵", "找", "過去", "去見", "見見", "見下"]
    static let genericNeighborWords = ["鄰居", "街坊", "朋友", "老友"]
    static let sunnyWords = ["好曬", "太曬", "很曬", "曬得", "好熱", "太熱", "很熱", "熱死", "太陽好大", "太陽很大", "太陽太大", "冇遮", "沒遮", "沒有遮", "沒有樹蔭", "沒有陰"]
    static let noSeatWords = ["冇櫈", "冇凳", "無櫈", "沒有凳", "沒凳", "沒有椅", "沒椅", "沒地方坐", "沒有地方坐", "冇位坐", "沒得坐", "坐不了", "唔夠櫈"]
    static let roughWords = ["難行", "唔好行", "難走", "不好走", "路不平", "路爛", "路很爛", "好滑", "很滑", "路滑"]
    static let weatherWords = ["天氣", "天气", "落雨", "下雨", "會唔會熱", "熱不熱", "熱唔熱", "幾多度", "多少度", "幾度", "氣溫", "溫度", "颱風", "打風"]
    /// 冷熱晴雨：问句（「今天会很热吗」「明天冷不冷」）或者讲今日 / 聽日（「今天很热」）就当问天气。
    static let feelWords = ["熱", "曬", "太陽", "雨", "凍", "冷", "晴", "風"]
    /// 讲明「呢度」先算反映呢个位（「这里好晒」「呢度好曬」）。
    static let hereWords = ["呢度", "呢處", "呢邊", "呢個位", "這裡", "這裏", "這兒", "這邊", "這個位", "此處"]

    /// 问天气（手机自己答：天文台嗰句）。「今天会很热吗」「明天热不热」「会不会下雨」「今日熱唔熱」都系。
    static func asksWeather(_ raw: String) -> Bool {
        if EnglishText.isEnglish(raw) { return EnglishText.asksWeather(raw) }
        let t = toHant(raw.replacingOccurrences(of: " ", with: ""))
        if weatherWords.contains(where: t.contains) { return true }
        return feelWords.contains(where: t.contains) && (isQuestion(t) || parseDay(t) != nil)
    }

    /// 曬 / 熱只喺讲紧「呢度」先当反映（「这里好晒」「呢度好曬」「太陽好大」）；
    /// 问句（「今天会很热吗」）、讲今日聽日 / 天气（「今天很热」）系问天气，唔记反映。t 已转繁体。
    static func isSunnyReport(_ t: String) -> Bool {
        if EnglishText.isEnglish(t) { return EnglishText.isSunnyReport(t) }
        guard sunnyWords.contains(where: t.contains), !isQuestion(t) else { return false }
        if hereWords.contains(where: t.contains) { return true }
        return parseDay(t) == nil && !weatherWords.contains(where: t.contains)
    }

    /// 问句：「嗎」「？」「咩」「幾多」「點樣」…、A唔A / A不A（熱唔熱、會不會、要不要），或者句尾「呢」。t 已转繁体。
    static func isQuestion(_ t: String) -> Bool {
        if EnglishText.isEnglish(t) { return EnglishText.isQuestion(t) }
        let markers = ["嗎", "吗", "?", "？", "咩", "乜", "幾多", "多少", "點樣", "怎", "如何", "係咪", "是否", "有冇", "有沒有", "什麼", "甚麼", "幾時"]
        if markers.contains(where: t.contains) || t.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).hasSuffix("呢") { return true }
        let c = Array(t)
        guard c.count >= 3 else { return false }
        for i in 1..<(c.count - 1) where (c[i] == "唔" || c[i] == "不") && c[i - 1] == c[i + 1] { return true }
        return false
    }

    /// 请假：「請假」「聽日請假」，或者「請三天假」「请3天假」「請兩日假」「请一个星期假」（請同假中间系日数）。t 已转繁体。
    static func asksLeave(_ t: String) -> Bool {
        if EnglishText.isEnglish(t) { return EnglishText.asksLeave(t) }
        if ["請假", "告假", "请假", "請個假", "休息一天", "休息一日", "今日唔行", "今天不走", "今天不去走"].contains(where: t.contains) { return true }
        return t.range(of: "[請请告][個个]?[0-9一二兩两三四五六七八九十半幾几成整]*[個个]?(日|天|星期|禮拜|礼拜|周|週)假", options: .regularExpression) != nil
    }

    // MARK: - 安全（手机先认：两种语言、有冇 Mac 服务器都一样，唔交服务器）

    enum Safety: Equatable { case emergency, medical }

    /// 紧急求助只认好明确嘅讲法（唔会将「帮我约阿芳」当求救）；问食咩藥 / 睇咩醫生当医疗问题。
    static func safety(_ raw: String) -> Safety? {
        if EnglishText.isEnglish(raw) { return EnglishText.safety(raw) }
        let s = raw.filter { !$0.isWhitespace }
        let t = toHant(s)
        if [s, t].contains(where: { x in emergencyWords.contains(where: x.contains) })
            || t.range(of: "(胸口|心口).{0,3}(痛|疼)", options: .regularExpression) != nil { return .emergency }
        if isMedicalQuestion(t) { return .medical }
        return nil
    }

    /// 普通话（简繁都列）+ 粤语 + B 服务器嘅讲法（voice_policy.py URGENT）。胸口痛 / 心口痛另外用正则（「胸口好痛」都算）。
    static let emergencyWords = ["救命", "救我", "摔倒", "跌倒", "跌親", "跌亲", "爬不起來", "爬不起来", "起不了身", "起唔到身",
                                 "喘不過氣", "喘不过气", "透不過氣", "透不过气", "唞唔到氣", "唞唔到气", "透唔到氣", "透唔到气",
                                 "呼吸困難", "呼吸困难", "暈倒", "晕倒", "暈低", "晕低", "流血", "流緊血", "流紧血",
                                 "叫救護車", "叫救护车", "叫白車", "叫白车", "報警", "报警", "我想自殺", "我想自杀", "我想死"]

    /// 问食咩藥 / 睇咩醫生（繁体）。
    static let medicalWords = ["什麼藥", "甚麼藥", "咩藥", "乜藥", "乜嘢藥", "咩嘢藥", "邊種藥", "哪種藥", "哪個藥",
                               "什麼醫生", "甚麼醫生", "哪個醫生", "咩醫生", "乜醫生", "邊個醫生", "什麼科", "甚麼科", "哪個科", "咩科", "邊科",
                               "要不要看醫生", "要唔要睇醫生", "使唔使睇醫生", "用不用看醫生", "需不需要看醫生", "需唔需要睇醫生", "要看醫生嗎", "要睇醫生嗎"]

    /// 问医疗：上面嘅讲法，或者讲到「藥」又系问句（「要不要吃药」「可以食止痛藥嗎」）；藥房、藥店系地方，唔算。
    static func isMedicalQuestion(_ t: String) -> Bool {
        if medicalWords.contains(where: t.contains) { return true }
        var d = t
        for place in ["藥房", "藥店", "藥行", "藥局", "藥劑師"] { d = d.replacingOccurrences(of: place, with: "") }
        return d.contains("藥") && isQuestion(d)
    }

    /// 听唔明嘅句子大概想做乜（用嚟讲点解做唔到）：约人 / 找人 / 反映。
    enum Topic { case invite, find, report }
    static func topic(_ raw: String) -> Topic? {
        if EnglishText.isEnglish(raw) { return EnglishText.topic(raw) }
        let t = toHant(raw.replacingOccurrences(of: " ", with: ""))
        if inviteWords.contains(where: t.contains) { return .invite }
        if findWords.contains(where: t.contains) { return .find }
        if ["反映", "報告", "投訴"].contains(where: t.contains) { return .report }
        return nil
    }

    /// 简体转繁体（ICU）；转唔到就原样。
    static func toHant(_ s: String) -> String {
        s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s
    }

    /// 後日 / 後天 → 2；聽日 / 明天 / 明日 / 聽朝 / 明早 → 1；今日 / 今天 → 0。
    static func parseDay(_ t: String) -> Int? {
        if EnglishText.isEnglish(t) { return EnglishText.parseDay(t) }
        if t.contains("後日") || t.contains("後天") { return 2 }
        if ["聽日", "明天", "明日", "聽朝", "聽晚", "明早", "明晚"].contains(where: t.contains) { return 1 }
        if t.contains("今日") || t.contains("今天") { return 0 }
        return nil
    }

    /// 改约嘅讲法（「改到下晝四點」）：后面先系新时间 / 地点。
    static let changeMarkers = ["改去", "改喺", "改在", "改到", "改做", "改成", "改返", "改回"]

    /// "下晝三點" → 15；"朝早8點" → 8；普通话 "下午三点" → 15；"三點十五" → 15（分钟见 parseClock）。
    func parseHour(_ t: String) -> Int? {
        if EnglishText.isEnglish(t) { return EnglishText.parseHour(t) }
        if let c = Self.parseClock(t) { return c.hour }
        let t = Self.toHant(t.filter { !$0.isWhitespace })
        // 讲咗钟点但唔喺 5–21 点（例如「夜晚十一點」）：唔约，唔好改用「朝早 / 下晝」估
        if Self.clockRange(t) != nil || t.range(of: Self.colonPattern, options: .regularExpression) != nil { return nil }
        if Self.amWords.contains(where: t.contains) { return 8 }
        if t.contains("中午") { return 12 }
        if Self.pmWords.contains(where: t.contains) { return Self.eveningWords.contains(where: t.contains) ? 19 : 16 }
        return nil
    }

    // MARK: - 钟点同分钟、行几耐（2026-10-17 用户测试：认唔到整点、半点以外嘅时间，又唔可以讲行几耐）

    static let hourPattern = "([0-9]{1,2}|[一二兩三四五六七八九十]{1,3})點"
    static let colonPattern = "[0-9]{1,2}:[0-5][0-9]"
    static let amWords = ["朝早", "早上", "上午", "早晨", "清早", "朝頭早", "聽朝", "今朝", "明早"]
    static let eveningWords = ["夜晚", "晚上", "傍晚", "黃昏", "今晚", "聽晚", "明晚"]
    static let pmWords = ["下晝", "下午", "晏晝", "中午"] + eveningWords

    /// 讲咗几点几分（24 小时制）：「三點十五」「3點20分」「三點一刻」「下午兩點三刻」「八點零五」「三點半」「15:20」「三點差五分」，
    /// 粤语「三點三」（= 3:15）「三點踏九」「三點兩個字」「三點一個骨」。
    /// 冇讲上下午：一至四點当下晝（约散步唔会约凌晨）。唔喺 5–21 点返回 nil。纯逻辑，有单元测试。
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
        let total = h * 60 + minute   // 「差五分」系负数
        h = total / 60
        return (5...21).contains(h) ? (h, total % 60) : nil
    }

    /// 第一个「几點」（「早一點」「快一點」「一點點」嘅「一點」係「少少」，唔系钟点）。
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

    /// 「點」后面嘅分钟（「三點差五分」返回 -5）。
    private static func minutes(after s: Substring) -> Int {
        let s = String(s.prefix(6))
        if s.hasPrefix("半") { return 30 }
        for (w, m) in [("一刻", 15), ("1刻", 15), ("兩刻", 30), ("三刻", 45), ("3刻", 45), ("一個骨", 15), ("三個骨", 45), ("個字", 5)] where s.hasPrefix(w) { return m }
        let num = "([0-9]{1,2}|[零〇一二兩三四五六七八九十]{1,3})"
        if s.hasPrefix("差一刻") { return -15 }
        if s.hasPrefix("差"), let r = s.range(of: "^差" + num, options: .regularExpression), let n = number(String(s[r].dropFirst())), (1...30).contains(n) { return -n }
        if s.hasPrefix("踏"), let r = s.range(of: "^踏" + num, options: .regularExpression), let n = number(String(s[r].dropFirst())), (1...11).contains(n) { return n * 5 }
        // 数字由长到短试（「十五一齊行」嘅「十五一」唔系数字，要「十五」）
        guard let all = s.range(of: "^" + num, options: .regularExpression) else { return 0 }
        var len = s[all].count, n: Int?
        while len > 0, n == nil { n = number(String(s.prefix(len))); if n == nil { len -= 1 } }
        guard let n else { return 0 }
        let digits = String(s.prefix(len)), rest = s.dropFirst(len)
        if rest.hasPrefix("個字") { return (1...11).contains(n) ? n * 5 : 0 }
        if rest.hasPrefix("分") { return (0...59).contains(n) ? n : 0 }
        // 两个字以上（「十五」「四十五」「零五」「20」）就系分钟
        if digits.count >= 2 { return (0...59).contains(n) ? n : 0 }
        // 得一个数字（「三點三」）：粤语讲法，每个数字 5 分钟；后面要冇字或者係「喺 / 去 / 散步」之类（「三點一齊行」嘅「一」唔系分钟）。
        // 普通话「三点三」唔常讲（会当「三点」）。
        let next = rest.first
        let ok = next == nil || next!.isPunctuation || "喺在去到出見见等散行走落嚟來来吧呀啊啦左鐘鐘前".contains(next!)
        guard ok, L.lang == .yue, (1...11).contains(n) else { return 0 }
        return n * 5
    }

    /// 讲咗嘅分钟（冇讲 = 0）。改约只睇「改到」后面（「三點嘅約改到四點十五」= 15）。
    static func spokenMinute(_ raw: String) -> Int {
        if EnglishText.isEnglish(raw) {
            // 改约只睇「to / change」后面
            let t = EnglishText.norm(raw)
            let after = [" to ", " change ", " move ", " make it "].compactMap { t.range(of: $0, options: .backwards) }.first.map { String(t[$0.upperBound...]) } ?? t
            return max(0, EnglishText.parseClock(after)?.minute ?? EnglishText.parseClock(raw)?.minute ?? 0)
        }
        let t = toHant(raw.filter { !$0.isWhitespace })
        let after = changeMarkers.compactMap { t.range(of: $0) }.first.map { String(t[$0.upperBound...]) } ?? t
        return max(0, parseClock(after)?.minute ?? 0)
    }

    /// 「十五」「二十」「四十五」「兩」「零五」「05」→ 数字；唔识返回 nil。
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

    /// 一齊行几耐（分钟）：「走四十分鐘」「散步一個鐘」「行半個鐘」「一個半小時」「40分钟」。5–240 分钟先算。
    /// 「最多行十五分鐘」系 B 服务器问嘅「最多行几远」，唔当；「三點半鐘」系钟点；「十分鐘後」系几时，都唔当。纯逻辑，有单元测试。
    static func parseDuration(_ raw: String) -> Int? {
        if EnglishText.isEnglish(raw) { return EnglishText.parseDuration(raw) }
        let t = toHant(raw.filter { !$0.isWhitespace })
        let num = "([0-9]{1,3}|[一二兩三四五六七八九十]{1,4})"
        // 中间嘅 Bool：前面係「點」就唔当（「三點半鐘」系钟点）
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

    /// 「一齊行 40 分鐘」「一齊行一個鐘」（普通话「一起走半个小时」）。
    static func walkPhrase(_ m: Int) -> String {
        let d = durationLabel(m)
        if L.isEn { return "for " + d }
        return L.t("一齊行", "一起走", "walk together ") + (d.first.map { $0.isASCII && $0.isNumber } == true ? " " : "") + d
    }

    /// 「40 分鐘」「半個鐘」「一個鐘」「一個半鐘」（普通话「半个小时」「一个小时」）。
    static func durationLabel(_ m: Int) -> String {
        let h = m / 60
        let hs = h == 1 ? L.t("一", "一", "1") : h == 2 ? L.t("兩", "两", "2") : "\(h)"
        if m == 30 { return L.t("半個鐘", "半个小时", "half an hour") }
        if m % 60 == 0 { return L.t("\(hs)個鐘", "\(hs)个小时", h == 1 ? "an hour" : "\(h) hours") }
        if m % 60 == 30 { return L.t("\(hs)個半鐘", "\(hs)个半小时", h == 1 ? "an hour and a half" : "\(h) and a half hours") }
        return L.t("\(m) 分鐘", "\(m) 分钟", "\(m) minutes")
    }

    // MARK: - 生成句子

    /// 今日一句用网名开头（10-18 测试：「7 楼今天请假了」似讲第二个人）；我未改网名就唔讲主语。
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

    /// 英文界面嘅地标名（install 时用 OSM 英文名再起一次）：冇英文名就用类别名，唔好砌「門口」「站」落英文度。
    private func nameLandmarkEn(_ c: LandmarkCandidate) -> String {
        // 只用有英文字母、唔太长嘅名（中文名喺英文界面照用会变成「SushiToni門口」呢类半中半英）
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

    /// 规格 F10：只输出人数 ≥ 10 的汇总。
    static let minReporters = 10

    static func hourLabel(_ h: Int) -> String {
        if h < 12 { return L.t("朝早 \(h) 點", "早上 \(h) 点", "\(h) am") }
        if h == 12 { return L.t("中午 12 點", "中午 12 点", "12 noon") }
        return h < 18 ? L.t("下晝 \(h - 12) 點", "下午 \(h - 12) 点", "\(h - 12) pm") : L.t("夜晚 \(h - 12) 點", "晚上 \(h - 12) 点", "\(h - 12) pm")
    }

    /// 约会钟点：整点同 hourLabel 一样；有分钟就讲埋（自己揀 16:45 →「下晝 4 點 45 分」）。
    static func timeLabel(hour h: Int, minute m: Int) -> String {
        if L.isEn, m != 0 { return "\(h > 12 ? h - 12 : h):" + String(format: "%02d", m) + (h >= 12 ? " pm" : " am") }
        return m == 0 ? hourLabel(h) : hourLabel(h) + L.t(" \(m) 分", " \(m) 分", ":\(m)")
    }
}

extension Resident {
    /// 今日一句嘅主语：网名（我就用自己改嘅网名，未改就空），唔用「N 樓」（10-18 测试）。
    var lineSubject: String { isMe ? (nickname ?? "") : name }
}
