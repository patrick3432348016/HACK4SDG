import Foundation

/// 成员 B：AIService 的模板实现（离线可跑）。关键词理解粤语，模板生成句子。
/// 之后接真模型时，新建一个实现同一协议的类，失败或超时就退回这里。
struct TemplateAI: AIService {

    // MARK: - 听懂一句话

    func parseVoice(_ raw: String, context: AIContext) -> VoiceIntent {
        let text = raw.replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { return .unknown }

        if text.contains("請假") || text.contains("告假") || text.contains("请假") { return .leave }

        // 改约 / 取消约：要讲到时间或地标，免得同改地标名撞。
        let partnerHit = context.residents.first { !$0.isMe && (text.contains($0.name) || text.contains("\($0.floor)樓")) }
        if text.contains("唔約") || (text.contains("取消") && (text.contains("約") || partnerHit != nil)) {
            return .cancelMeetup(partnerID: partnerHit?.id)
        }
        if !text.contains("改名"), let r = ["改去", "改喺", "改到", "改做", "改成", "改返"].compactMap({ text.range(of: $0) }).first {
            let before = String(text[..<r.lowerBound]), after = String(text[r.upperBound...])
            let lm = context.landmarks.first { after.contains($0.name) }
            let hour = parseHour(after)
            let day: Int? = after.contains("後日") ? 2 : (after.contains("聽日") || after.contains("明天")) ? 1 : after.contains("今日") ? 0 : nil
            let aboutMeetup = before.isEmpty || before.contains("約") || partnerHit != nil
            if aboutMeetup, lm != nil || hour != nil || day != nil {
                return .changeMeetup(partnerID: partnerHit?.id, day: day, hour: hour, landmarkID: lm?.id)
            }
        }

        if let r = ["改名做", "改名叫", "改做", "改名为"].compactMap({ text.range(of: $0) }).first {
            let before = String(text[..<r.lowerBound]), after = String(text[r.upperBound...])
            let newName = after.trimmingCharacters(in: .punctuationCharacters)
            if !newName.isEmpty, let lm = context.landmarks.first(where: { before.contains($0.name) || $0.name.contains(before) && !before.isEmpty }) {
                return .rename(landmarkID: lm.id, newName: newName)
            }
        }

        if context.finding, text.hasPrefix("我喺") || text.hasPrefix("我在") || text.hasPrefix("我到") { return .broadcast(raw) }

        if text.contains("好曬") || text.contains("好晒") || text.contains("好熱") || text.contains("好热") { return .report(.sunny) }
        if text.contains("冇櫈") || text.contains("冇凳") || text.contains("無櫈") || text.contains("没有凳") { return .report(.noSeat) }
        if text.contains("難行") || text.contains("唔好行") || text.contains("难走") { return .report(.rough) }

        let partner = context.residents.first { !$0.isMe && (text.contains($0.name) || text.contains("\($0.floor)樓")) }
        if let p = partner {
            if (text.contains("搵") || text.contains("過去") || text.contains("找")) && !text.contains("約") { return .goFind(partnerID: p.id) }
            if text.contains("約") || text.contains("一齊行") || text.contains("一起") {
                let day = text.contains("後日") ? 2 : (text.contains("聽日") || text.contains("明天") || text.contains("明日")) ? 1 : 0
                return .invite(partnerID: p.id, day: day, hour: parseHour(text))
            }
        }
        return .unknown
    }

    /// "下晝三點" → 15；"朝早8點" → 8。
    func parseHour(_ t: String) -> Int? {
        let digits: [Character: Int] = ["一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
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

    // MARK: - 生成句子

    func dailyLine(for r: Resident, passed: [Landmark]) -> String {
        if r.onLeave { return "\(r.floorLabel)今日請咗假" }
        guard let last = passed.last else { return r.isMe ? "\(r.floorLabel)今日仲未出門" : "\(r.floorLabel)今日仲未出門" }
        let seed = abs(r.id.hashValue)
        if passed.count >= 2, seed % 3 == 0 { return "\(r.floorLabel)今日經過\(passed[0].name)同\(last.name)" }
        if last.hasSeat, seed % 3 == 1 { return "\(r.floorLabel)喺\(last.name)坐咗陣" }
        return "\(r.floorLabel)今日行到\(last.name)"
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
        parts.append(best.2 >= 0.5 ? "嗰陣有樓遮住" : "嗰陣有啲曬")
        if l.hasSeat { parts.append("有櫈") }
        parts.append("兩個都行 \(minutes) 分鐘左右")
        return MeetProposal(date: date, landmarkID: l.id, reason: parts.joined(separator: "、"))
    }

    func walkAdvice(weather: Weather, now: Date, shadeTip: (landmark: Landmark, shadedFrom: Int?)?) -> String? {
        switch weather {
        case .rain: return "天文台話下晝會落大雨，不如早啲出門，或者聽日先行。"
        case .hot:
            if let tip = shadeTip, let h = tip.shadedFrom { return "今日好熱。\(tip.landmark.name)\(Self.hourLabel(h))後有樓遮住，嗰陣先出門啱啲。" }
            return "今日好熱，記得帶水，揀有遮蔭嘅路行。"
        case .normal:
            if let tip = shadeTip, let h = tip.shadedFrom { return "\(tip.landmark.name)\(Self.hourLabel(h))後有樓遮住，嗰陣行最舒服。" }
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
            case .sunny: suggestion = "加遮蔭或者種樹"
            case .noSeat: suggestion = "加張櫈"
            case .rough: suggestion = "整平路面、加扶手"
            }
            return MonthlyReport.Item(place: place, kind: v.0, count: v.1, suggestion: suggestion)
        }.filter { $0.count >= Self.minReporters }.sorted { $0.count > $1.count }
        let top = items.first.map { "最多人反映：\($0.place)\($0.kind.rawValue)（\($0.count) 人）。" } ?? ""
        return MonthlyReport(title: "\(placeName) · 本月散步報告",
                             summary: "本月 \(stats.walks) 人次散步，街坊約咗 \(stats.meetups) 次一齊行。\(top)只計 \(Self.minReporters) 人以上嘅反映，冇任何個人路線。",
                             items: items, walkers: stats.walks, meetups: stats.meetups)
    }

    /// 规格 F10：只输出人数 ≥ 10 的汇总。
    static let minReporters = 10

    static func hourLabel(_ h: Int) -> String {
        if h < 12 { return "朝早 \(h) 點" }
        if h == 12 { return "中午 12 點" }
        return h < 18 ? "下晝 \(h - 12) 點" : "夜晚 \(h - 12) 點"
    }
}
