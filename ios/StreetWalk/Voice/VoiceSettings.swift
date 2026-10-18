import AVFoundation
import Observation
import UIKit

/// Shared UserDefaults-backed voice enable, language, voice and speed settings for UI and Speaker.
///
/// Integration usage:
/// VoiceSettings.shared.language = .mandarin changes speech, announcements and preview; UI localization is handled separately by AppLanguage.
/// VoiceSettings.shared.active returns the selected voice.
///
/// Users download system voices in iPhone Settings; rescan on return and select higher-quality additions through onUpgrade.
@MainActor
@Observable
final class VoiceSettings {
    static let shared = VoiceSettings()

    /// Disabling automatic speech leaves VoiceOver announcements and explicit replay available.
    var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    var language: SpokenLanguage { didSet { defaults.set(language.rawValue, forKey: Keys.language) } }
    var pace: SpeechPace { didSet { defaults.set(pace.rawValue, forKey: Keys.pace) } }

    /// Installed suitable voices across languages; empty before the first scan.
    private(set) var installed: [VoiceInfo] = []
    private(set) var scanned = false
    /// Saved user choice per language; absent means automatic best voice.
    private(set) var chosen: [SpokenLanguage: String] = [:]

    /// Notify AppStore after automatically selecting a newly installed better voice.
    @ObservationIgnored var onUpgrade: ((VoiceInfo) -> Void)?
    /// Keep the newly selected voice visible in the guide's installed state instead of removing the section abruptly.
    private(set) var upgraded: (voice: VoiceInfo, at: Date)?
    var upgradedAt: Date? { upgraded?.at }
    /// Voice installed within the last ten minutes.
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

    /// watch rescans on foreground return or system voice changes; false in tests.
    init(defaults: UserDefaults = .standard, scanner: @escaping @Sendable () -> [VoiceInfo] = { VoiceSettings.systemVoices() }, watch: Bool = true) {
        self.defaults = defaults
        self.scanner = scanner
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        #if DEBUG
        let saved = LaunchArgs.value("-voiceLanguage") ?? defaults.string(forKey: Keys.language)   // Screenshot override -voiceLanguage cmn is not persisted.
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
            defaults.removeObject(forKey: Keys.known)   // Begin each demonstration in the not-installed state.
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

    // MARK: - Active voice

    /// Compatible voices for the current language, best first.
    var voices: [VoiceInfo] { VoicePicker.candidates(for: language, in: installed) }
    /// Voice currently used for speech.
    var active: VoiceInfo? { voice(for: language) }
    func voice(for l: SpokenLanguage) -> VoiceInfo? { VoicePicker.pick(for: l, in: installed, chosen: chosen[l]) }
    /// Whether enhanced or better is installed; otherwise show the download guide.
    var hasNaturalVoice: Bool { voices.contains { $0.tier >= .enhanced } }
    /// Whether the user explicitly chose a voice instead of automatic selection.
    var isAuto: Bool { chosen[language].map { id in !voices.contains { $0.id == id } } ?? true }

    func choose(_ v: VoiceInfo) {
        chosen[language] = v.id
        defaults.set(v.id, forKey: Keys.chosen(language))
    }

    // MARK: - Scan installed voices

    /// Scan immediately before first speech if needed; normal rescans run in background.
    func ensureScanned() {
        guard !scanned else { return }
        apply(scanner())
    }

    /// Rescan off-main because some simulators block during voice enumeration.
    func rescan() {
        scanTask?.cancel()
        let scanner = scanner
        scanTask = Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) { scanner() }.value
            guard !Task.isCancelled else { return }
            self?.apply(list)
        }
    }

    /// Store scan results, compare prior voices and announce a better new selection; tests invoke directly.
    func apply(_ list: [VoiceInfo]) {
        let previous = Set(defaults.stringArray(forKey: Keys.known) ?? [])
        let upgrade = VoicePicker.upgrade(previous: previous, now: list, language: language, chosen: chosen[language])
        installed = list
        scanned = true
        defaults.set(list.map(\.id), forKey: Keys.known)
        guard let upgrade else { return }
        // Select a newly downloaded better voice even over a manually chosen lower-tier voice.
        if chosen[language] != nil { choose(upgrade) }
        upgraded = (upgrade, Date())
        onUpgrade?(upgrade)
    }

    /// Actual system-installed voices.
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
/// Debug-only fake voices support simulator screenshots / flows without downloading premium voices.
/// -fakeVoices premium supplies them immediately; later supplies them after leaving and returning, testing automatic upgrade.
/// Fake entries have no audio; previews use standard system speech.
enum FakeVoices {
    /// App has been left, simulating a trip to system Settings.
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
