import Foundation
import Observation

/// Interface languages in this historical branch: Cantonese (Traditional Chinese, default) and Mandarin (Simplified Chinese). Compiled by both the app and StreetWalkWidgets.
///
/// Wrap user-visible and spoken text in L.t with Cantonese and Mandarin versions.
/// Calling L.t in a SwiftUI body reads AppLanguage.shared.current (@Observable), so language changes immediately redraw the UI.
/// Settings use AppLanguage.shared.set(.cmn) and persist to UserDefaults. The -lang cmn launch argument applies only to this run.
/// Landmark and person names are data; do not translate them here.
enum AppLang: String, CaseIterable, Codable, Sendable {
    case yue, cmn

    /// Settings label, always written in the language it represents.
    var label: String { self == .yue ? "粵語（繁體）" : "普通话（简体）" }
    /// Locale code for recognition and the assistant server.
    var locale: String { self == .yue ? "zh-HK" : "zh-CN" }
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
    /// Cantonese original / Mandarin translation.
    static func t(_ yue: String, _ cmn: String) -> String { isCmn ? cmn : yue }
}
