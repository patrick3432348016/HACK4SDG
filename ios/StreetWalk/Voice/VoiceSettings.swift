import AVFoundation
import Observation
import UIKit

/// 声音设定：开关、讲边种语言、用边把声、语速。即时存（UserDefaults），设定页同 Speaker 共用一份。
///
/// 其他人点用：
/// - 普通话版界面：`VoiceSettings.shared.language = .mandarin`（播报、读屏公告、试听句子跟住转；提示文字要自己换普通话版）。
/// - 想知而家用紧边把声：`VoiceSettings.shared.active`。
///
/// 系统声音由用户自己去 iPhone 设定下载（App 冇得代下载）。返到 App 会重新睇一次，装咗更好嘅就自动转用（onUpgrade）。
@MainActor
@Observable
final class VoiceSettings {
    static let shared = VoiceSettings()

    /// 自动播报开关。关咗：提示唔会自动读出嚟（读屏公告照出）；撳「再聽一次」仍然会读。
    var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    var language: SpokenLanguage { didSet { defaults.set(language.rawValue, forKey: Keys.language) } }
    var pace: SpeechPace { didSet { defaults.set(pace.rawValue, forKey: Keys.pace) } }

    /// 手机入面装咗、啱用嘅声音（全部语言）。未睇过 = 空。
    private(set) var installed: [VoiceInfo] = []
    private(set) var scanned = false
    /// 用户喺设定页揀咗嘅声音（每种语言一把）；冇揀 = 自动揀最好。
    private(set) var chosen: [SpokenLanguage: String] = [:]

    /// 装咗更好嘅声音、已经自动转用：AppStore 用嚟讲俾用户知。
    @ObservationIgnored var onUpgrade: ((VoiceInfo) -> Void)?
    /// 啱啱自动转咗用边把（设定页喺下载指引嘅位置改出「裝好咗」，唔会成段突然唔见）。
    private(set) var upgraded: (voice: VoiceInfo, at: Date)?
    var upgradedAt: Date? { upgraded?.at }
    /// 十分钟内装好嘅新声音。
    var recentUpgrade: VoiceInfo? {
        guard let u = upgraded, Date().timeIntervalSince(u.at) < 600, u.voice.id == active?.id else { return nil }
        return u.voice
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let scanner: @Sendable () -> [VoiceInfo]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    enum Keys {
        static let enabled = "voice.enabled"
        static let language = "voice.language"
        static let pace = "voice.pace"
        static let known = "voice.knownIDs"
        static func chosen(_ l: SpokenLanguage) -> String { "voice.chosen.\(l.rawValue)" }
    }

    /// watch：听 App 返到前台 / 系统声音有变就重新睇（测试用 false）。
    init(defaults: UserDefaults = .standard, scanner: @escaping @Sendable () -> [VoiceInfo] = { VoiceSettings.systemVoices() }, watch: Bool = true) {
        self.defaults = defaults
        self.scanner = scanner
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        #if DEBUG
        let saved = LaunchArgs.value("-voiceLanguage") ?? defaults.string(forKey: Keys.language)   // 截图用：-voiceLanguage cmn（唔存）
        #else
        let saved = defaults.string(forKey: Keys.language)
        #endif
        language = SpokenLanguage(rawValue: saved ?? "") ?? .cantonese
        pace = SpeechPace(rawValue: defaults.string(forKey: Keys.pace) ?? "") ?? .normal
        for l in SpokenLanguage.allCases { chosen[l] = defaults.string(forKey: Keys.chosen(l)) }
        guard watch else { return }
        let nc = NotificationCenter.default
        #if DEBUG
        if FakeVoices.mode != nil {
            defaults.removeObject(forKey: Keys.known)   // 每次都由「未装」开始演示
            observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                FakeVoices.wentAway = true
            })
        }
        #endif
        observers += [
            nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rescan() }
            },
            nc.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rescan() }
            },
        ]
        rescan()
    }

    // MARK: - 而家用边把

    /// 而家语言可以揀嘅声音（最好排先）。
    var voices: [VoiceInfo] { VoicePicker.candidates(for: language, in: installed) }
    /// 而家播报用嘅声音。
    var active: VoiceInfo? { voice(for: language) }
    func voice(for l: SpokenLanguage) -> VoiceInfo? { VoicePicker.pick(for: l, in: installed, chosen: chosen[l]) }
    /// 有冇装「增強」或以上嘅声音（冇就出下载指引）。
    var hasNaturalVoice: Bool { voices.contains { $0.tier >= .enhanced } }
    /// 用户有冇亲手揀过（冇 = 自动揀最好）。
    var isAuto: Bool { chosen[language].map { id in !voices.contains { $0.id == id } } ?? true }

    func choose(_ v: VoiceInfo) {
        chosen[language] = v.id
        defaults.set(v.id, forKey: Keys.chosen(language))
    }

    // MARK: - 睇手机装咗咩声音

    /// 未睇过就即刻睇（第一次播报前；平时喺背景睇，见 rescan）。
    func ensureScanned() {
        guard !scanned else { return }
        apply(scanner())
    }

    /// 喺背景重新睇（有啲模拟器查一次会卡住主线程）。
    func rescan() {
        scanTask?.cancel()
        let scanner = scanner
        scanTask = Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) { scanner() }.value
            guard !Task.isCancelled else { return }
            self?.apply(list)
        }
    }

    /// 睇完：记低、比较上一次，装咗更好嘅就转用同通知。测试直接调用。
    func apply(_ list: [VoiceInfo]) {
        let previous = Set(defaults.stringArray(forKey: Keys.known) ?? [])
        let upgrade = VoicePicker.upgrade(previous: previous, now: list, language: language, chosen: chosen[language])
        installed = list
        scanned = true
        defaults.set(list.map(\.id), forKey: Keys.known)
        guard let upgrade else { return }
        // 用户之前亲手揀咗把较差嘅：都转用新装嗰把（佢专登去下载，就係想用佢）。
        if chosen[language] != nil { choose(upgrade) }
        upgraded = (upgrade, Date())
        onUpgrade?(upgrade)
    }

    /// 系统真正装咗嘅声音。
    nonisolated static func systemVoices() -> [VoiceInfo] {
        var list = AVSpeechSynthesisVoice.speechVoices().map(VoiceInfo.init)
        #if DEBUG
        list += FakeVoices.next()
        #endif
        return list
    }
}

extension VoiceInfo {
    init(_ v: AVSpeechSynthesisVoice) {
        let tier: VoiceTier = switch v.quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
        let gender: Gender = switch v.gender {
        case .female: .female
        case .male: .male
        default: .unknown
        }
        let odd = v.voiceTraits.contains(.isNoveltyVoice) || v.voiceTraits.contains(.isPersonalVoice)
            || v.identifier.contains(".eloquence.")
        self.init(id: v.identifier, name: v.name, language: v.language, tier: tier, gender: gender, unsuitable: odd)
    }
}

#if DEBUG
/// 模拟器冇高品质声音、亦唔好喺度下载：截图 / 走流程用假声音（只喺 Debug 版）。
/// `-fakeVoices premium`：一开始就有 Wing、善怡增強等；`-fakeVoices later`：离开过 App 再返嚟（扮由 iPhone 设定下载完返嚟）先出现，用嚟试「自动转用」。
/// 假声音冇真嘅声，试听会用返标准声音读。
enum FakeVoices {
    /// 离开过 App（扮去咗 iPhone 设定下载）。
    nonisolated(unsafe) static var wentAway = false
    static var mode: String? { LaunchArgs.value("-fakeVoices") }

    static let premium: [VoiceInfo] = [
        VoiceInfo(id: "fake.premium.yue-HK.Wing", name: "Wing", language: "yue-HK", tier: .premium, gender: .female),
        VoiceInfo(id: "fake.premium.yue-HK.Fung", name: "Fung", language: "yue-HK", tier: .premium, gender: .male),
        VoiceInfo(id: "fake.enhanced.yue-HK.Sinji", name: "Sinji", language: "yue-HK", tier: .enhanced, gender: .female),
        VoiceInfo(id: "fake.enhanced.yue-HK.Aasing", name: "Aasing", language: "yue-HK", tier: .enhanced, gender: .male),
        VoiceInfo(id: "fake.premium.zh-CN.Yue", name: "Yue", language: "zh-CN", tier: .premium, gender: .female),
    ]

    static func next() -> [VoiceInfo] {
        switch mode {
        case "premium": return premium
        case "later": return wentAway ? premium : []
        default: return []
        }
    }
}
#endif
