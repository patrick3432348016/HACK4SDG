import Foundation

// 揀系统声音嘅纯逻辑（唔掂 AVFoundation，单元测试直接用）：
// 讲边种语言、声音档次、点样排先后、装咗新声音要唔要自动转。

/// 播报用嘅语言。界面文字暂时仲係粤语；普通话版界面会由另一位同事加，佢只要改 VoiceSettings.language。
enum SpokenLanguage: String, CaseIterable, Codable, Sendable {
    case cantonese = "yue"
    case mandarin = "cmn"
    case english = "en"

    /// 设定页嘅名。
    var label: String {
        switch self {
        case .cantonese: return L.t("粵語", "粤语")
        case .mandarin: return L.t("普通話", "普通话")
        case .english: return "English"
        }
    }

    /// 交俾系统嘅语言代码（读屏公告、揀唔到声音时嘅后备）。
    var bcp47: String {
        switch self {
        case .cantonese: return "zh-HK"
        case .mandarin: return "zh-CN"
        case .english: return "en-US"
        }
    }

    /// 设定页可以揀嘅语言（英文暂时唔出：提示句子未有英文版）。
    static let pickable: [SpokenLanguage] = [.cantonese, .mandarin]

    /// 试听句子（每种语言用自己嘅讲法，唔好叫普通话声音读粤语字）。
    var sample: String {
        switch self {
        case .cantonese: return "你好，我係街坊行。陳太啱啱出咗門，喺涼亭附近。"
        case .mandarin: return "你好，我是街坊行。陈太刚刚出门了，在凉亭附近。"
        case .english: return "Hello, I'm StreetWalk. Mrs Chan just went out. She's near the pavilion."
        }
    }

    /// 呢把声讲唔讲呢种语言；讲嘅话，地区排第几（0 最啱）。
    /// iOS 26 粤语声音嘅语言代码係 "yue-HK"（以前係 "zh-HK"），两样都认。
    /// 普通话只认 zh-CN / cmn / zh-TW，永远唔会揀到粤语声音（避开「普通话读成粤语」）。
    func regionRank(of language: String) -> Int? {
        let l = language.lowercased().replacingOccurrences(of: "_", with: "-")
        switch self {
        case .cantonese:
            if l.hasPrefix("yue") || l == "zh-hk" || l.hasPrefix("zh-hant-hk") || l.hasPrefix("zh-yue") { return 0 }
            if l == "zh-mo" || l.hasPrefix("zh-hant-mo") { return 1 }
            return nil
        case .mandarin:
            if l.hasPrefix("yue") || l == "zh-hk" || l.hasPrefix("zh-hant-hk") || l == "zh-mo" || l.hasPrefix("zh-hant-mo") { return nil }
            if l == "zh-cn" || l.hasPrefix("cmn") || l.hasPrefix("zh-hans") || l == "zh" { return 0 }
            if l == "zh-tw" || l.hasPrefix("zh-hant-tw") || l == "zh-sg" { return 1 }
            return nil
        case .english:
            guard l == "en" || l.hasPrefix("en-") else { return nil }
            if l == "en-us" { return 0 }
            if l == "en-gb" { return 1 }
            if l == "en-au" || l == "en-ie" || l == "en-nz" { return 2 }
            return 3
        }
    }

    /// 同一档次入面优先揀嘅声音（按名）。
    /// 粤语：Wing（女，高品质）→ 善怡；普通话：月 → 黎瀲（黎瀲旧版有漏读句尾字嘅报告，排第二）；英语：Ava。
    var preferredNames: [String] {
        switch self {
        case .cantonese: return ["Wing", "Sinji", "Fung", "Aasing"]
        case .mandarin: return ["Yue", "Lilian", "Lili", "Yun", "Han", "Tingting"]
        case .english: return ["Ava", "Zoe", "Serena", "Malcolm", "Samantha"]
        }
    }
}

/// 声音档次：Apple 嘅 default / enhanced / premium。界面写「標準 / 增強 / 高品質」。
/// iPhone 设定（香港中文）入面分别写「預設」、「已強化」、「優質」。
enum VoiceTier: Int, Comparable, Sendable {
    case standard = 1, enhanced = 2, premium = 3

    var label: String {
        switch self {
        case .standard: return L.t("標準", "标准")
        case .enhanced: return L.t("增強", "增强")
        case .premium: return L.t("高品質", "高品质")
        }
    }

    static func < (a: VoiceTier, b: VoiceTier) -> Bool { a.rawValue < b.rawValue }
}

/// 一把已经装咗嘅声音（由 AVSpeechSynthesisVoice 抄出嚟，方便测试）。
struct VoiceInfo: Equatable, Hashable, Sendable, Identifiable {
    enum Gender: Sendable { case female, male, unknown }

    var id: String          // AVSpeechSynthesisVoice.identifier
    var name: String        // 系统俾嘅名（英文名或者已经本地化）
    var language: String    // 例如 "yue-HK"、"zh-CN"
    var tier: VoiceTier
    var gender: Gender = .unknown
    /// 怪声（Bubbles、Zarvox）、Eloquence 机械声（Eddy、Grandma…）、个人声音：唔出喺列表，唔会自动揀。
    var unsuitable = false

    /// 香港中文 iPhone 设定显示嘅名（Sinji → 善怡）。Wing、Fung 系统都係用英文名。
    var displayName: String { Self.chineseNames[name] ?? name }

    /// 「女聲 · 高品質」
    var subtitle: String {
        let g: String? = switch gender {
        case .female: L.t("女聲", "女声")
        case .male: L.t("男聲", "男声")
        case .unknown: nil
        }
        return ([g, tier.label].compactMap { $0 }).joined(separator: " · ")
    }

    /// 出自 iOS 26.5 TextToSpeech.framework 嘅 zh_HK SpeechVoiceNames.strings。
    static let chineseNames: [String: String] = [
        "Sinji": "善怡", "Aasing": "阿成",
        "Tingting": "婷婷", "Meijia": "美佳", "Lilian": "黎瀲", "Lili": "莉莉", "Yue": "月", "Han": "瀚",
        "Yu-shu": "語舒", "Li-mu": "李牧", "Dongmei": "冬梅", "Fangfang": "盼盼", "Binbin": "彬彬",
        "Lanlan": "嵐嵐", "Lisheng": "理生", "Lulu": "南南", "Shanshan": "珊珊", "Shasha": "莎莎",
        "Taotao": "陶陶", "Tiantian": "田田", "Haohao": "浩浩", "Bobo": "波波",
    ]
}

/// 语速三档。默认「正常」= 系统默认 0.5。
/// 10-11：「正常」以前用 0.42，低档粤语声逐个字读（「每个字自己读自己的」），所以正常改返 0.5。
/// 10-17 用户测试：「慢」同「正常」差唔多（0.46 太近）。拉开：慢 0.4 + 句同句停耐啲（长者听得清），快 0.57、几乎唔停。
enum SpeechPace: String, CaseIterable, Sendable {
    case slow, normal, fast

    var label: String {
        switch self {
        case .slow: return L.t("慢", "慢")
        case .normal: return L.t("正常", "正常")
        case .fast: return L.t("快", "快")
        }
    }

    /// AVSpeechUtterance.rate（0–1，系统默认 0.5）。
    var rate: Float {
        switch self {
        case .slow: return 0.4
        case .normal: return 0.5      // AVSpeechUtteranceDefaultSpeechRate
        case .fast: return 0.57
        }
    }

    /// 每句讲完停几耐（秒）。
    var pauseAfterSentence: TimeInterval {
        switch self {
        case .slow: return 0.7
        case .normal: return 0.25
        case .fast: return 0.05
        }
    }

    /// 按句号、问号、感叹号拆句（逗号唔拆，一句保持一个 utterance 先读得连贯）；唔加空格。
    /// 句尾嘅「」』）」跟返上一句。
    static func sentences(_ text: String) -> [String] {
        let ends: Set<Character> = ["。", "！", "？", "!", "?"]
        let closers: Set<Character> = ["」", "』", "）", ")", "\"", "”", "’"]
        var out: [String] = []
        var cur = ""
        var ended = false
        for ch in text {
            if ended && !closers.contains(ch) && !ends.contains(ch) {
                out.append(cur); cur = ""; ended = false
            }
            cur.append(ch)
            if ends.contains(ch) { ended = true }
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

enum VoicePicker {
    /// 呢种语言可以用嘅声音，最好嘅排最前：档次 → 地区 → 推荐名 → 名。
    static func candidates(for language: SpokenLanguage, in voices: [VoiceInfo]) -> [VoiceInfo] {
        let preferred = language.preferredNames
        func nameRank(_ v: VoiceInfo) -> Int {
            preferred.firstIndex { $0.caseInsensitiveCompare(v.name) == .orderedSame || VoiceInfo.chineseNames[$0] == v.name } ?? preferred.count
        }
        return voices
            .filter { !$0.unsuitable && language.regionRank(of: $0.language) != nil }
            .sorted { a, b in
                if a.tier != b.tier { return a.tier > b.tier }
                let ra = language.regionRank(of: a.language)!, rb = language.regionRank(of: b.language)!
                if ra != rb { return ra < rb }
                let na = nameRank(a), nb = nameRank(b)
                if na != nb { return na < nb }
                return a.id < b.id
            }
    }

    /// 而家用边把：用户揀过而又仲喺度（同埋係呢种语言）就用佢，否则用最好嗰把。
    static func pick(for language: SpokenLanguage, in voices: [VoiceInfo], chosen: String?) -> VoiceInfo? {
        let list = candidates(for: language, in: voices)
        if let chosen, let v = list.first(where: { $0.id == chosen }) { return v }
        return list.first
    }

    /// 由 iPhone 设定返嚟、重新睇过一次：有冇新装、而且比而家用紧嗰把高档嘅声音？有就返佢（要自动转用、讲俾用户知）。
    /// previous 係上一次见到嘅全部声音 id；空 = 第一次睇（新装 App），唔当「新装咗」。
    static func upgrade(previous: Set<String>, now voices: [VoiceInfo], language: SpokenLanguage, chosen: String?) -> VoiceInfo? {
        guard !previous.isEmpty else { return nil }
        let list = candidates(for: language, in: voices)
        let fresh = list.filter { !previous.contains($0.id) }
        guard let best = fresh.first else { return nil }
        // 「而家用紧」= 未装新声音之前会用嗰把
        let before = pick(for: language, in: voices.filter { previous.contains($0.id) }, chosen: chosen)
        guard best.tier > (before?.tier ?? .standard) || before == nil else { return nil }
        return best
    }
}
