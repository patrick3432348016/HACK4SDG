import Foundation

// Local English fallback when the Mac voice server is unavailable or in demo mode; produces the same VoiceIntent as Chinese parsing.
// Detect whether the utterance is English independently of UI language, so tests with a fixed Cantonese UI can cover it. Pure logic.
enum EnglishText {
    /// Predominantly Latin letters, allowing embedded Chinese names.
    static func isEnglish(_ s: String) -> Bool {
        var latin = 0, cjk = 0
        for u in s.unicodeScalars where u.properties.isAlphabetic {
            if u.value < 0x250 { latin += 1 } else if (0x3400...0x9FFF).contains(u.value) || (0xF900...0xFAFF).contains(u.value) { cjk += 1 }
        }
        return latin >= 2 && latin > cjk * 2
    }

    /// Lowercase, replace punctuation with spaces, and pad both ends for whole-word matching. Preserve apostrophe, colon, and slash.
    static func norm(_ raw: String) -> String {
        var s = raw.lowercased().replacingOccurrences(of: "’", with: "'")
        s = s.replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(of: "p.m.", with: "pm")
        let kept = s.map { c -> Character in
            c.isLetter || c.isNumber || c == "'" || c == ":" || c == "/" ? c : " "
        }
        var out = " " + String(kept).split(separator: " ").joined(separator: " ") + " "
        // Separate the am/pm suffix in compact clock expressions.
        out = out.replacingOccurrences(of: "([0-9])(am|pm) ", with: "$1 $2 ", options: .regularExpression)
        out = out.replacingOccurrences(of: " a m ", with: " am ").replacingOccurrences(of: " p m ", with: " pm ")
        return out
    }

    static func words(_ raw: String) -> [String] { norm(raw).split(separator: " ").map(String.init) }

    static func has(_ t: String, _ phrases: [String]) -> Bool { phrases.contains { t.contains(" \($0) ") } }

    // MARK: Numbers

    static let small: [String: Int] = [
        "zero": 0, "oh": 0, "one": 1, "a": 1, "an": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Int] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50]

    /// Read a number starting at w[i], such as 45, forty five, or twelve. Return its value and the number of consumed words.
    static func number(_ w: [String], _ i: Int, allowA: Bool = false) -> (Int, Int)? {
        guard i < w.count else { return nil }
        if let n = Int(w[i]) { return (n, 1) }
        if !allowA, w[i] == "a" || w[i] == "an" || w[i] == "oh" { return nil }
        if let t = tens[w[i]] {
            if i + 1 < w.count, let o = small[w[i + 1]], (1...9).contains(o), w[i + 1] != "a", w[i + 1] != "an" { return (t + o, 2) }
            return (t, 1)
        }
        if let n = small[w[i]] { return (n, 1) }
        return nil
    }

    // MARK: Dates, times, and walk duration

    /// today 0、tomorrow 1、the day after tomorrow 2。
    static func parseDay(_ raw: String) -> Int? {
        let t = norm(raw)
        if t.contains(" day after tomorrow ") { return 2 }
        if has(t, ["tomorrow", "tmr", "tomorrow's"]) { return 1 }
        if has(t, ["today", "tonight", "this morning", "this afternoon", "this evening", "today's"]) { return 0 }
        return nil
    }

    static let amWords = ["am", "morning"]
    static let pmWords = ["pm", "afternoon", "evening", "tonight", "night"]

    /// Parse explicit 24-hour times from numeric and spoken forms, including quarter-to, half-past, and minutes-past expressions.
    /// Without am/pm, hours 1–4 mean afternoon. Return nil outside 05:00–21:00.
    static func parseClock(_ raw: String) -> (hour: Int, minute: Int)? {
        let t = norm(raw)
        let w = t.split(separator: " ").map(String.init)
        var hour: Int?, minute = 0
        if let r = t.range(of: "[0-9]{1,2}:[0-5][0-9]", options: .regularExpression) {
            let p = t[r].split(separator: ":")
            hour = Int(p[0]); minute = Int(p[1]) ?? 0
        } else if t.contains(" noon ") || t.contains(" midday ") {
            hour = 12
        } else {
            for i in 0..<w.count where hour == nil {
                // half past two / quarter past two / quarter to five / 20 (minutes) past 3 / ten to four
                if w[i] == "past" || w[i] == "to" || w[i] == "after" || w[i] == "before" {
                    guard i >= 1, let (h, _) = number(w, i + 1), (1...12).contains(h) else { continue }
                    var m: Int?
                    if w[i - 1] == "half" { m = 30 }
                    else if w[i - 1] == "quarter" { m = 15 }
                    else {
                        var j = i - 1
                        if ["minutes", "minute", "mins"].contains(w[j]) { j -= 1 }
                        if j >= 0 {
                            if j >= 1, let (n, used) = number(w, j - 1), used == 2 { m = n }
                            else if let (n, _) = number(w, j) { m = n }
                        }
                    }
                    guard let mm = m, (1...30).contains(mm) else { continue }
                    if w[i] == "past" || w[i] == "after" { hour = h; minute = mm } else { hour = h - 1; minute = 60 - mm }
                    continue
                }
                // N o'clock / N am / N pm / at N [M]
                guard let (h, used) = number(w, i), (1...12).contains(h) else { continue }
                let next = i + used < w.count ? w[i + used] : ""
                let prev = i > 0 ? w[i - 1] : ""
                if ["o'clock", "oclock", "am", "pm"].contains(next) || prev == "at" || prev == "around" || prev == "about" || prev == "by" {
                    // 「at 4」「at three fifteen」「at 2 30」
                    if !["o'clock", "oclock"].contains(next), let (m, _) = number(w, i + used), (0...59).contains(m),
                       !["minutes", "minute", "mins", "hours", "hour", "days", "day"].contains(i + used + 1 < w.count ? w[i + used + 1] : "") {
                        // In at 3 for 40 minutes, for is not numeric; only actual time expressions such as at three thirty contribute minutes.
                        minute = m
                    }
                    hour = h
                }
            }
        }
        guard var h = hour, (0...23).contains(h) else { return nil }
        if has(t, pmWords) {
            if h < 12 { h += 12 }
        } else if !has(t, amWords), (1...4).contains(h) {
            h += 12
        }
        let total = h * 60 + minute
        h = total / 60
        return (5...21).contains(h) ? (h, total % 60) : nil
    }

    /// Use an explicit hour; otherwise morning = 8, noon = 12, afternoon = 16, evening/tonight = 19.
    static func parseHour(_ raw: String) -> Int? {
        if let c = parseClock(raw) { return c.hour }
        let t = norm(raw)
        if t.range(of: "[0-9]{1,2}:[0-5][0-9]", options: .regularExpression) != nil || has(t, ["am", "pm", "o'clock", "oclock"]) { return nil }
        if has(t, ["morning"]) { return 8 }
        if has(t, ["lunchtime", "lunch time"]) { return 12 }
        if has(t, ["evening", "tonight"]) { return 19 }
        if has(t, ["afternoon"]) { return 16 }
        return nil
    }

    /// Walking duration in minutes, including fractional hours. Accept only 5–240 minutes.
    /// Exclude upper bounds and relative departure times such as at most 15 minutes, in 10 minutes, or 10 minutes later.
    static func parseDuration(_ raw: String) -> Int? {
        let t = norm(raw)
        let w = t.split(separator: " ").map(String.init)
        func blocked(_ start: Int, _ end: Int) -> Bool {
            let before = w[max(0, start - 3)..<start].joined(separator: " ")
            let after = end < w.count ? w[end...].prefix(2).joined(separator: " ") : ""
            let b = " " + before
            let nextIsNumber = end + 1 < w.count && number(w, end + 1) != nil
            return ["most", "max", "maximum", "up to", "within", "in", "under", "no more than"].contains { b.hasSuffix(" " + $0) }
                || ["later", "from now", "away", "ago", "before", "after", "past"].contains { after.hasPrefix($0) }
                || (after.hasPrefix("to") && nextIsNumber)
        }
        if let r = t.range(of: " (an|one|1) hour and a half ", options: .regularExpression) ?? t.range(of: " (one and a half|1 and a half|1\\.5|one and half) hours? ", options: .regularExpression) {
            _ = r; return 90
        }
        if let r = t.range(of: " ([0-9]|two|three) and a half hours ", options: .regularExpression) {
            let first = t[r].split(separator: " ").first.map(String.init) ?? ""
            if let n = Int(first) ?? small[first] { return n * 60 + 30 }
        }
        for i in 0..<w.count {
            if w[i] == "half", i + 2 < w.count, (w[i + 1] == "an" || w[i + 1] == "a"), w[i + 2] == "hour" {
                if !blocked(i, i + 3) { return 30 }
                continue
            }
            guard ["minutes", "minute", "mins", "min", "hours", "hour", "hrs", "hr"].contains(w[i]), i >= 1 else { continue }
            var n: Int?, start = i - 1
            if i >= 2, let (v, used) = number(w, i - 2, allowA: true), used == 2 { n = v; start = i - 2 }
            else if let (v, _) = number(w, i - 1, allowA: true) { n = v }
            guard let v = n else { continue }
            if blocked(start, i + 1) { continue }
            let m = w[i].hasPrefix("h") ? v * 60 : v
            if (5...240).contains(m) { return m }
        }
        return nil
    }

    // MARK: Intents

    static let inviteWords = ["invite", "walk with", "go for a walk", "go walking", "take a walk", "a walk", "for a walk", "stroll",
                              "walk together", "meet up", "meet", "come with me", "walk", "go out with"]
    static let findWords = ["find", "look for", "looking for", "go see", "go and see", "go to see", "go over to", "visit", "where is", "where's"]
    static let genericNeighbourWords = ["neighbour", "neighbor", "neighbours", "neighbors", "friend", "friends", "someone", "somebody"]
    static let sunnyWords = ["too sunny", "very sunny", "so sunny", "really sunny", "too hot", "very hot", "so hot", "really hot", "no shade",
                             "not shady", "no shelter", "too much sun", "sun is too strong", "sun is strong", "baking", "boiling", "scorching", "sunny"]
    static let noSeatWords = ["no seats", "no seat", "no bench", "no benches", "nowhere to sit", "no place to sit", "nothing to sit",
                              "can't sit", "cannot sit", "no chairs", "no chair", "not enough seats", "no seating"]
    static let roughWords = ["hard to walk", "difficult to walk", "rough", "bumpy", "uneven", "slippery", "potholes", "broken pavement", "steep"]
    static let weatherWords = ["weather", "rain", "raining", "rainy", "temperature", "degrees", "typhoon", "forecast", "umbrella", "storm", "thunderstorm"]
    static let feelWords = ["hot", "cold", "warm", "sunny", "sun", "wind", "windy", "humid", "cool", "chilly"]
    static let hereWords = ["here", "this spot", "this place", "this area", "over here", "this corner"]
    static let planWords = ["walk", "walks", "plan", "plans", "meeting", "meet", "meetup", "meet up", "appointment", "date"]

    static func isQuestion(_ raw: String) -> Bool {
        if raw.contains("?") || raw.contains("？") { return true }
        let w = words(raw)
        guard let first = w.first else { return false }
        return ["what", "which", "should", "can", "could", "do", "does", "is", "are", "will", "would", "how", "when", "where", "who", "shall", "may"].contains(first)
    }

    static func asksWeather(_ raw: String) -> Bool {
        let t = norm(raw)
        if has(t, weatherWords) { return true }
        return has(t, feelWords) && (isQuestion(raw) || parseDay(raw) != nil) && !has(t, hereWords)
    }

    static func isSunnyReport(_ raw: String) -> Bool {
        let t = norm(raw)
        guard has(t, sunnyWords), !isQuestion(raw) else { return false }
        if has(t, hereWords) { return true }
        return parseDay(raw) == nil && !has(t, weatherWords) && !(t.trimmingCharacters(in: .whitespaces) == "sunny")
    }

    static func asksLeave(_ raw: String) -> Bool {
        let t = norm(raw)
        if has(t, ["day off", "days off", "week off", "weeks off", "time off", "on leave", "take leave", "request leave", "a break",
                   "skip today", "skip tomorrow", "not walking today", "not walking tomorrow", "no walk today", "no walking today",
                   "rest day", "take the day off", "off tomorrow", "off today", "leave tomorrow", "leave today"]) { return true }
        return t.range(of: " (take|taking|want|need) .{0,20}(days?|weeks?) (off|of rest|break) ", options: .regularExpression) != nil
    }

    /// Convert English leave requests into the Chinese forms understood by LeaveRequest.parse, preserving the date and duration.
    static func leaveText(_ raw: String) -> String {
        let t = norm(raw)
        let w = t.split(separator: " ").map(String.init)
        var start = ""
        if t.contains(" day after tomorrow ") { start = "後日" }
        else if has(t, ["tomorrow", "tmr"]) { start = "聽日" }
        else if has(t, ["next week"]) { start = "下星期" }
        var days = 1
        for i in 0..<w.count {
            if ["days", "day"].contains(w[i]), i >= 1 {
                if i >= 2, let (n, used) = number(w, i - 2, allowA: true), used == 2 { days = n }
                else if let (n, _) = number(w, i - 1, allowA: true), w[i - 1] != "the" { days = n }
            }
            if ["week", "weeks"].contains(w[i]), i >= 1, w[i - 1] != "next" {
                let n = number(w, i - 1, allowA: true)?.0 ?? (w[i - 1] == "whole" || w[i - 1] == "the" ? 1 : 1)
                days = n * 7
            }
        }
        days = max(1, min(14, days))
        return start + "請" + (days > 1 ? "\(days)日" : "") + "假"
    }

    static func safety(_ raw: String) -> TemplateAI.Safety? {
        let t = norm(raw)
        let w = t.split(separator: " ").map(String.init)
        if !w.isEmpty, w.count <= 4, w.contains("help"), w.allSatisfy({ ["help", "me", "please", "somebody", "someone", "anyone", "i", "need"].contains($0) }) {
            return .emergency
        }
        if has(t, ["i fell", "i've fallen", "i have fallen", "fell down", "i fall", "can't get up", "cannot get up", "can't breathe", "cannot breathe",
                   "hard to breathe", "chest pain", "chest hurts", "pain in my chest", "bleeding", "ambulance", "call 999", "call the police",
                   "heart attack", "i fainted", "passed out", "emergency", "kill myself", "want to die", "end my life"]) { return .emergency }
        // Medical question.
        if has(t, ["what medicine", "which medicine", "what pills", "which pills", "what drug", "which drug", "what tablets", "which doctor",
                   "see a doctor", "see the doctor", "need a doctor", "go to the doctor", "what should i take"]) { return .medical }
        var d = t
        for p in ["pharmacy", "pharmacist", "chemist", "drugstore"] { d = d.replacingOccurrences(of: p, with: "") }
        if has(d, ["medicine", "medication", "pill", "pills", "tablet", "tablets", "drug", "drugs", "painkiller", "painkillers", "panadol", "paracetamol", "dose"]),
           isQuestion(raw) || has(d, ["should i", "can i take", "can i have"]) { return .medical }
        return nil
    }

    static func topic(_ raw: String) -> TemplateAI.Topic? {
        let t = norm(raw)
        if has(t, inviteWords) { return .invite }
        if has(t, findWords) { return .find }
        if has(t, ["report", "complain", "complaint"]) { return .report }
        return nil
    }

    // MARK: Person matching: names, romanized Chinese names, and floors

    static let surnames: [Character: String] = [
        "陳": "chan", "陈": "chan", "黃": "wong", "黄": "wong", "王": "wong", "李": "lee", "梁": "leung", "何": "ho", "張": "cheung", "张": "cheung",
        "林": "lam", "劉": "lau", "刘": "lau", "吳": "ng", "吴": "ng", "周": "chow", "鄭": "cheng", "郑": "cheng", "馮": "fung", "冯": "fung",
        "蔡": "choi", "麥": "mak", "麦": "mak", "謝": "tse", "谢": "tse", "楊": "yeung", "杨": "yeung", "羅": "law", "罗": "law", "葉": "yip",
        "叶": "yip", "徐": "tsui", "朱": "chu", "胡": "wu", "郭": "kwok", "馬": "ma", "马": "ma", "曾": "tsang", "鄧": "tang", "邓": "tang",
        "袁": "yuen", "方": "fong", "余": "yu", "蘇": "so", "苏": "so", "潘": "poon", "歐": "au", "区": "au", "區": "au", "譚": "tam", "谭": "tam",
        "盧": "lo", "卢": "lo", "黎": "lai", "莫": "mok", "簡": "kan", "文": "man", "杜": "to", "江": "kong", "戴": "tai", "雷": "lui", "鍾": "chung",
        "钟": "chung", "姚": "yiu", "唐": "tong", "石": "shek", "孔": "hung", "高": "ko", "趙": "chiu", "赵": "chiu", "關": "kwan", "关": "kwan",
    ]
    static let given: [Character: String] = [
        "明": "ming", "芳": "fong", "珍": "chun", "玲": "ling", "華": "wah", "华": "wah", "強": "keung", "强": "keung", "英": "ying", "美": "mei",
        "蘭": "lan", "兰": "lan", "娟": "kuen", "雄": "hung", "偉": "wai", "伟": "wai", "寶": "po", "宝": "po", "妹": "mui", "嬌": "kiu",
        "欣": "yan", "儀": "yee", "仪": "yee", "婷": "ting", "敏": "man", "輝": "fai", "辉": "fai", "國": "kwok", "国": "kwok", "東": "tung",
        "东": "tung", "成": "shing", "雯": "man", "麗": "lai", "丽": "lai", "清": "ching", "芬": "fun", "霞": "ha", "鳳": "fung", "凤": "fung",
    ]
    /// Map titles to English prefixes and Cantonese romanized suffixes, such as Chan Tai.
    static let titles: [(String, [String], String)] = [
        ("先生", ["mr", "mister"], "sin sang"), ("小姐", ["miss", "ms"], "siu je"), ("師奶", ["mrs"], "si nai"), ("师奶", ["mrs"], "si nai"),
        ("伯伯", ["uncle", "grandpa"], "pak pak"), ("婆婆", ["granny", "grandma", "auntie"], "por por"), ("姨姨", ["auntie", "aunty", "aunt"], "yi yi"),
        ("公公", ["grandpa"], "kung kung"), ("太", ["mrs", "madam", "missus"], "tai"), ("生", ["mr", "mister"], "sang"), ("伯", ["uncle", "mr", "grandpa"], "pak"),
        ("婆", ["granny", "grandma"], "por"), ("姨", ["auntie", "aunty", "aunt"], "yi"), ("叔", ["uncle"], "suk"), ("姐", ["miss", "sister"], "je"),
    ]
    /// Require a title for names that collide with common English words, such as so, to, or man.
    static let ambiguous: Set<String> = ["so", "to", "man", "ma", "law", "lo", "yu", "au", "fu", "kan", "hung", "ng", "ho", "tai", "ko", "tong", "mak", "lam", "tang", "wu", "kong", "fong"]

    /// Generate English variants of a Chinese name, such as Mrs Chan, Chan Tai, or Madam Chan.
    static func aliases(of name: String) -> [String] {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard let first = n.first else { return [] }
        var out: [String] = []
        if first == "阿", n.count >= 2 {
            let c = n[n.index(after: n.startIndex)]
            if let r = given[c] ?? surnames[c] { out += ["ah \(r)", "a \(r)", "uncle \(r)", "auntie \(r)"] }
            return out
        }
        guard let sur = surnames[first] else { return [] }
        let rest = String(n.dropFirst())
        if let (_, pre, post) = titles.first(where: { rest == $0.0 }) {
            out += pre.map { "\($0) \(sur)" }
            out.append("\(sur) \(post)")
        } else if let c = rest.first, let g = given[c] {
            out += ["\(sur) \(g)", "ah \(g)"]
        }
        if !ambiguous.contains(sur) { out.append(sur) }
        return out
    }

    /// Match references by English/Chinese name, romanization, or floor expressions such as 8/F, 8th floor, or floor 8.
    static func mentions(_ r: Resident, in raw: String) -> Bool {
        let t = norm(raw)
        if !r.name.isEmpty, raw.contains(r.name) { return true }
        let n = norm(r.name)
        if n.trimmingCharacters(in: .whitespaces).count >= 2, n.contains(where: { $0.isASCII && $0.isLetter }), t.contains(n) { return true }
        if aliases(of: r.name).contains(where: { t.contains(" \($0) ") }) { return true }
        if r.id.count <= 10, r.id.allSatisfy({ $0.isASCII && $0.isLowercase }), !ambiguous.contains(r.id), t.contains(" \(r.id) ") { return true }
        if r.floor > 0 {
            let f = r.floor
            let ord = ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth"]
            var pats = [" \(f)/f ", " \(f) f ", " floor \(f) ", " \(f)th floor ", " \(f)st floor ", " \(f)nd floor ", " \(f)rd floor ", " level \(f) "]
            if f < ord.count { pats.append(" \(ord[f]) floor ") }
            if pats.contains(where: t.contains) { return true }
        }
        return false
    }

    // MARK: Complete utterances

    static func parseVoice(_ raw: String, context: AIContext) -> VoiceIntent {
        let t = norm(raw)
        guard t.trimmingCharacters(in: .whitespaces).count > 0 else { return .unknown }
        if asksLeave(raw) { return .leave }

        let others = context.residents.filter { !$0.isMe }
        let partnerHit = others.first { mentions($0, in: raw) }

        // Cancel a meetup.
        if has(t, ["cancel", "call off", "called off"]) && (has(t, planWords) || partnerHit != nil)
            || has(t, ["don't want to meet", "not meeting", "can't make it", "cannot make it"]) {
            return .cancelMeetup(partnerID: partnerHit?.id)
        }
        // Rescheduling must mention a time, date, or landmark.
        if !has(t, ["rename", "name it", "call it"]),
           let r = [" change ", " move ", " switch ", " reschedule ", " postpone ", " push ", " make it ", " change it to "].compactMap({ t.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            let before = String(t[..<r.lowerBound]), after = " " + String(t[r.upperBound...])
            let lm = context.landmarks.filter { !$0.name.isEmpty && (after.contains(norm($0.name)) || raw.contains($0.name)) }.max { $0.name.count < $1.name.count }
            let hour = parseHour(after), day = parseDay(after)
            let aboutMeetup = before.split(separator: " ").count <= 3 || has(" " + before + " ", planWords) || partnerHit != nil
            if aboutMeetup, lm != nil || hour != nil || day != nil {
                return .changeMeetup(partnerID: partnerHit?.id, day: day, hour: hour, landmarkID: lm?.id)
            }
        }
        // Landmark renaming, such as rename the pavilion to Chess Corner.
        if let r = t.range(of: " rename ") ?? t.range(of: " change the name of "), let to = t.range(of: " to ", range: r.upperBound..<t.endIndex) {
            let target = String(t[r.upperBound..<to.lowerBound])
            let newName = raw.components(separatedBy: " to ").last?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) ?? ""
            if !newName.isEmpty, let lm = context.landmarks.first(where: { target.contains(norm($0.name).trimmingCharacters(in: .whitespaces)) || raw.contains($0.name) }) {
                return .rename(landmarkID: lm.id, newName: newName)
            }
        }
        if context.finding, has(t, ["i'm at", "i am at", "i'm near", "i am near", "i'm by", "i'm in", "i'm here", "i am here", "i'm waiting"]) { return .broadcast(raw) }

        if isSunnyReport(raw) { return .report(.sunny) }
        if has(t, noSeatWords) { return .report(.noSeat) }
        if has(t, roughWords) { return .report(.rough) }

        let generic = has(t, genericNeighbourWords)
        let wantsInvite = has(t, inviteWords) && !has(t, ["find", "look for", "looking for", "where is", "where's"])
        let wantsFind = has(t, findWords) && !has(t, ["invite"])
        if wantsFind && !has(t, ["invite", "walk with", "for a walk"]),
           let p = partnerHit ?? (generic ? others.first(where: \.isOut) ?? others.first : nil) { return .goFind(partnerID: p.id) }
        if wantsInvite || (partnerHit != nil && parseHour(raw) != nil) {
            if let p = partnerHit ?? (generic ? others.first : nil) {
                return .invite(partnerID: p.id, day: parseDay(raw) ?? 0, hour: parseHour(raw))
            }
        }
        return .unknown
    }

    // MARK: Confirmation card: yes/no

    /// Accept only short responses; negative expressions take precedence.
    static func yesNo(_ raw: String) -> AppStore.YesNo? {
        let t = norm(raw)
        let w = t.split(separator: " ")
        guard (1...5).contains(w.count) else { return nil }
        if has(t, ["no problem", "no worries", "not a problem", "why not"]) { return .yes }
        if has(t, ["no", "nope", "nah", "don't", "dont", "do not", "cancel", "not now", "stop", "never mind", "nevermind", "wrong",
                   "not right", "forget it", "not ok", "not okay", "not yet", "later"]) { return .no }
        guard w.count <= 4 else { return nil }
        if has(t, ["yes", "yeah", "yep", "yup", "ok", "okay", "sure", "sounds good", "good", "right", "correct", "confirm", "go ahead",
                   "do it", "fine", "alright", "all right", "great", "perfect", "please", "that's right", "of course", "let's go"]) { return .yes }
        return nil
    }
}
