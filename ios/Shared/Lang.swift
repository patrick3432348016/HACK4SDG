import Foundation
import Observation

/// UI language: Cantonese (Traditional Chinese, default), Mandarin (Simplified Chinese), and English (added 2026-10-17). Shared by app and widget targets.
///
/// Usage: wrap all visible/spoken text in L.t("Cantonese", "Mandarin", "English").
/// Calling L.t in a SwiftUI body reads AppLanguage.shared.current (@Observable), so language changes immediately redraw the UI.
/// Settings use AppLanguage.shared.set(.cmn) and persist to UserDefaults. The -lang cmn launch argument applies only to this run.
/// Landmark and person names are data; do not translate them here.
enum AppLang: String, CaseIterable, Codable, Sendable {
    case yue, cmn, en

    /// Settings label, always written in the language it represents.
    var label: String {
        switch self {
        case .yue: return "粵語（繁體）"
        case .cmn: return "普通话（简体）"
        case .en: return "English"
        }
    }
    /// Locale code for recognition and the assistant server.
    var locale: String {
        switch self {
        case .yue: return "zh-HK"
        case .cmn: return "zh-CN"
        case .en: return "en-US"
        }
    }
}

@Observable
final class AppLanguage: @unchecked Sendable {
    static let shared = AppLanguage()
    static let key = "app.language"

    var current: AppLang

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        if let i = arguments.firstIndex(of: "-lang"), i + 1 < arguments.count, let l = AppLang(rawValue: arguments[i + 1]) {
            current = l   // Demo/screenshots: -lang cmn is not persisted.
        } else {
            current = AppLang(rawValue: defaults.string(forKey: Self.key) ?? "") ?? .yue
        }
    }

    /// A Settings selection takes effect immediately and is saved.
    func set(_ l: AppLang) {
        current = l
        defaults.set(l.rawValue, forKey: Self.key)
    }
}

enum L {
    static var lang: AppLang { AppLanguage.shared.current }
    static var isCmn: Bool { lang == .cmn }
    static var isEn: Bool { lang == .en }
    /// Cantonese / Mandarin / English. During migration, missing English falls back to Mandarin; every L.t must have its third argument before submission.
    static func t(_ yue: String, _ cmn: String, _ en: String? = nil) -> String {
        switch lang {
        case .yue: return yue
        case .cmn: return cmn
        case .en: return en ?? cmn
        }
    }
}
