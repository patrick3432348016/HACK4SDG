import Foundation

/// UI and speech languages are linked: Mandarin uses zh-CN and English uses en-US. Recognition, voice, and assistant locale follow AppLang.locale.
extension AppLang {
    var spoken: SpokenLanguage {
        switch self {
        case .yue: return .cantonese
        case .cmn: return .mandarin
        case .en: return .english
        }
    }
}

extension AppLanguage {
    /// Settings changes update the UI immediately, persist the selection, and switch speech.
    @MainActor func choose(_ l: AppLang) {
        set(l)
        VoiceSettings.shared.followAppLanguage()
    }

    /// Called from StreetWalkApp.init before AppStore.launch. First launch follows the iOS language (feedback A-5).
    /// Tests always use Cantonese: simulator language may be Simplified Chinese, but expected strings are Cantonese. Change memory only.
    static func prepareForLaunch() {
        if runningTests { shared.current = .yue; return }
        // -lang cmn/yue/en applies only to this run (already handled by AppLanguage.init); otherwise use the new default.
        if let l = seedDefault(), !ProcessInfo.processInfo.arguments.contains("-lang") { shared.current = l }
    }

    /// If unset, choose English for English, Mandarin for Simplified Chinese, and Cantonese for Traditional Chinese/Cantonese. Persist the choice rather than tracking future system changes.
    /// Existing onboarded users previously saw Cantonese: preserve that choice on upgrade. They can still change it in Settings.
    /// Return the selected language, or nil if already configured and unchanged.
    @discardableResult
    static func seedDefault(defaults: UserDefaults = .standard, preferred: [String] = Locale.preferredLanguages,
                            region: String? = Locale.current.region?.identifier) -> AppLang? {
        guard defaults.string(forKey: key) == nil else { return nil }
        let l: AppLang = defaults.bool(forKey: "onboarded") ? .yue : systemDefault(preferred: preferred, region: region)
        defaults.set(l.rawValue, forKey: key)
        return l
    }

    /// Prefer English when first in the system list; otherwise use the first Chinese entry, choosing Mandarin for Simplified and Cantonese for Traditional/Hong Kong.
    /// If no Chinese is listed, use English when available; otherwise use region: mainland China/Singapore → Mandarin, HK/Macau/Taiwan/unknown → Cantonese, elsewhere → English.
    static func systemDefault(preferred: [String], region: String?) -> AppLang {
        let langs = preferred.map { $0.lowercased() }
        func isEn(_ l: String) -> Bool { l == "en" || l.hasPrefix("en-") }
        if let first = langs.first, isEn(first) { return .en }
        if let zh = langs.first(where: { $0.hasPrefix("zh") || $0.hasPrefix("yue") }) {
            if zh.hasPrefix("yue") || zh.contains("hant") { return .yue }
            if zh.contains("hans") { return .cmn }
            // For Chinese locales without an explicit script, such as zh-CN or zh-HK, use the region.
            return zh.hasSuffix("-cn") || zh.hasSuffix("-sg") ? .cmn : .yue
        }
        if langs.contains(where: isEn) { return .en }
        if region == "CN" || region == "SG" { return .cmn }
        if langs.isEmpty || region == nil || ["HK", "MO", "TW"].contains(region!) { return .yue }
        return .en
    }

    /// Detect unit tests; the test host also runs StreetWalkApp.init.
    static var runningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil || env["XCTestSessionIdentifier"] != nil
    }
}

extension VoiceSettings {
    /// Synchronize speech language at startup and whenever UI language changes.
    func followAppLanguage() {
        let want = L.lang.spoken
        if language != want { language = want }
    }
}
