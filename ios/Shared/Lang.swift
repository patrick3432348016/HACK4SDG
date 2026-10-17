import Foundation
import Observation

/// 界面语言：粤语（繁体，默认）/ 普通话（简体）/ 英文（2026-10-17 加）。App 同实时活动（StreetWalkWidgets）两个目标都编译。
///
/// 用法：所有用户睇到、听到嘅文字写成 `L.t("粵語原文", "普通话", "English")`。
/// SwiftUI 喺 body 入面调用 L.t 会读到 `AppLanguage.shared.current`（@Observable），切换语言即时重画。
/// 设定页切换：`AppLanguage.shared.set(.cmn)`（存 UserDefaults）；启动参数 `-lang cmn` 只影响今次（唔存）。
/// 地标名、人名属于数据，唔翻译。
enum AppLang: String, CaseIterable, Codable, Sendable {
    case yue, cmn, en

    /// 设定页显示（永远用该语言自己嘅写法）。
    var label: String {
        switch self {
        case .yue: return "粵語（繁體）"
        case .cmn: return "普通话（简体）"
        case .en: return "English"
        }
    }
    /// 语音识别 / 助手服务器用嘅地区代码。
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
            current = l   // 演示 / 截图：-lang cmn（唔存）
        } else {
            current = AppLang(rawValue: defaults.string(forKey: Self.key) ?? "") ?? .yue
        }
    }

    /// 用户喺设定页揀：即时生效兼存低。
    func set(_ l: AppLang) {
        current = l
        defaults.set(l.rawValue, forKey: Self.key)
    }
}

enum L {
    static var lang: AppLang { AppLanguage.shared.current }
    static var isCmn: Bool { lang == .cmn }
    static var isEn: Bool { lang == .en }
    /// 粤语原文 / 普通话 / 英文。英文未写嘅（过渡期）暂时显示普通话；交件前每个 L.t 都要有第三个参数。
    static func t(_ yue: String, _ cmn: String, _ en: String? = nil) -> String {
        switch lang {
        case .yue: return yue
        case .cmn: return cmn
        case .en: return en ?? cmn
        }
    }
}
