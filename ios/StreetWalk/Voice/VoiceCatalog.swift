import Foundation

// Pure system-voice selection logic without AVFoundation, directly unit-tested.
// Language compatibility, quality ranking, ordering and automatic selection of newly installed voices.

/// Spoken language; AppLanguage synchronizes it with the current three-language interface.
enum SpokenLanguage: String, CaseIterable, Codable, Sendable {
    case cantonese = "yue"
    case mandarin = "cmn"
    case english = "en"

    /// Display name in Settings.
    var label: String {
        switch self {
        case .cantonese: return L.t("粵語", "粤语", "Cantonese")
        case .mandarin: return L.t("普通話", "普通话", "Mandarin")
        case .english: return "English"
        }
    }

    /// System locale for VoiceOver announcements and fallback voice selection.
    var bcp47: String {
        switch self {
        case .cantonese: return "zh-HK"
        case .mandarin: return "zh-CN"
        case .english: return "en-US"
        }
    }

    /// Selectable Settings languages, including English since 10-17.
    static let pickable: [SpokenLanguage] = [.cantonese, .mandarin, .english]

    /// Use a natural preview sentence for each language instead of asking Mandarin voices to read Cantonese text.
    var sample: String {
        switch self {
        case .cantonese: return "你好，我係街坊行。陳太啱啱出咗門，喺涼亭附近。"
        case .mandarin: return "你好，我是街坊行。陈太刚刚出门了，在凉亭附近。"
        case .english: return "Hello, this is StreetWalk. Mrs Chan just went out. She is near the pavilion."
        }
    }

    /// Whether a voice supports this language and its locale preference rank, with zero best.
    /// Accept both iOS 26 yue-HK and the older zh-HK Cantonese locale.
    /// Mandarin accepts zh-CN / cmn / zh-TW and must never select a Cantonese voice.
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

    /// Preferred named voices within a quality tier.
    /// Cantonese prefers Wing then Sin-ji; Mandarin prefers Yue then Li-lian due to reported older trailing-word omissions; English prefers Ava.
    var preferredNames: [String] {
        switch self {
        case .cantonese: return ["Wing", "Sinji", "Fung", "Aasing"]
        case .mandarin: return ["Yue", "Lilian", "Lili", "Yun", "Han", "Tingting"]
        case .english: return ["Ava", "Zoe", "Serena", "Malcolm", "Samantha"]
        }
    }
}

/// Apple default/enhanced/premium quality tiers map to localized standard/enhanced/premium labels.
/// The Hong Kong Chinese system Settings uses different localized names for these three tiers.
enum VoiceTier: Int, Comparable, Sendable {
    case standard = 1, enhanced = 2, premium = 3

    var label: String {
        switch self {
        case .standard: return L.t("標準", "标准", "Standard")
        case .enhanced: return L.t("增強", "增强", "Enhanced")
        case .premium: return L.t("高品質", "高品质", "Premium")
        }
    }

    static func < (a: VoiceTier, b: VoiceTier) -> Bool { a.rawValue < b.rawValue }
}

/// Installed-voice snapshot copied from AVSpeechSynthesisVoice for testability.
struct VoiceInfo: Equatable, Hashable, Sendable, Identifiable {
    enum Gender: Sendable { case female, male, unknown }

    var id: String          // AVSpeechSynthesisVoice.identifier
    var name: String        // System-provided English or localized voice name.
    var language: String    // For example yue-HK or zh-CN.
    var tier: VoiceTier
    var gender: Gender = .unknown
    /// Exclude novelty voices, mechanical Eloquence voices and Personal Voice from lists and automatic selection.
    var unsuitable = false

    /// Use localized Hong Kong Settings names where applicable; Wing and Fung retain English names.
    var displayName: String { Self.chineseNames[name] ?? name }

    /// Voice gender and quality label.
    var subtitle: String {
        let g: String? = switch gender {
        case .female: L.t("女聲", "女声", "Female")
        case .male: L.t("男聲", "男声", "Male")
        case .unknown: nil
        }
        return ([g, tier.label].compactMap { $0 }).joined(separator: " · ")
    }

    /// Names sourced from iOS 26.5 TextToSpeech.framework's zh_HK SpeechVoiceNames.strings.
    static let chineseNames: [String: String] = [
        "Sinji": "善怡", "Aasing": "阿成",
        "Tingting": "婷婷", "Meijia": "美佳", "Lilian": "黎瀲", "Lili": "莉莉", "Yue": "月", "Han": "瀚",
        "Yu-shu": "語舒", "Li-mu": "李牧", "Dongmei": "冬梅", "Fangfang": "盼盼", "Binbin": "彬彬",
        "Lanlan": "嵐嵐", "Lisheng": "理生", "Lulu": "南南", "Shanshan": "珊珊", "Shasha": "莎莎",
        "Taotao": "陶陶", "Tiantian": "田田", "Haohao": "浩浩", "Bobo": "波波",
    ]
}

/// Three speeds; Normal defaults to the system rate 0.5.
/// 10-11: restore Normal from 0.42 to 0.5 because low-tier Cantonese sounded unnaturally segmented.
/// 10-17: separate Slow to 0.4 with longer sentence pauses and Fast to 0.57 with minimal pauses after feedback that 0.46 was too similar.
enum SpeechPace: String, CaseIterable, Sendable {
    case slow, normal, fast

    var label: String {
        switch self {
        case .slow: return L.t("慢", "慢", "Slow")
        case .normal: return L.t("正常", "正常", "Normal")
        case .fast: return L.t("快", "快", "Fast")
        }
    }

    /// AVSpeechUtterance.rate, 0–1 with system default 0.5.
    var rate: Float {
        switch self {
        case .slow: return 0.4
        case .normal: return 0.5      // AVSpeechUtteranceDefaultSpeechRate
        case .fast: return 0.57
        }
    }

    /// Pause after each sentence, in seconds.
    var pauseAfterSentence: TimeInterval {
        switch self {
        case .slow: return 0.7
        case .normal: return 0.25
        case .fast: return 0.05
        }
    }

    /// Split on periods, question marks and exclamation marks, not commas; preserve coherent utterances without adding spaces.
    /// Keep closing quotation marks and brackets with the preceding sentence.
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
    /// Rank compatible voices by quality, locale, preferred name, then name.
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

    /// Use the user's saved compatible voice if still installed; otherwise choose the best available.
    static func pick(for language: SpokenLanguage, in voices: [VoiceInfo], chosen: String?) -> VoiceInfo? {
        let list = candidates(for: language, in: voices)
        if let chosen, let v = list.first(where: { $0.id == chosen }) { return v }
        return list.first
    }

    /// After returning from Settings, detect newly installed higher-tier voices for automatic selection and notification.
    /// previous contains all previously seen voice IDs; empty means first scan, not a new installation.
    static func upgrade(previous: Set<String>, now voices: [VoiceInfo], language: SpokenLanguage, chosen: String?) -> VoiceInfo? {
        guard !previous.isEmpty else { return nil }
        let list = candidates(for: language, in: voices)
        let fresh = list.filter { !previous.contains($0.id) }
        guard let best = fresh.first else { return nil }
        // Current voice means the selection before the new installation.
        let before = pick(for: language, in: voices.filter { previous.contains($0.id) }, chosen: chosen)
        guard best.tier > (before?.tier ?? .standard) || before == nil else { return nil }
        return best
    }
}
