import Foundation
import Observation

/// 界面语言：粤语（繁体，默认）/ 普通话（简体）。App 同实时活动（StreetWalkWidgets）两个目标都编译。
///
/// 用法：所有用户睇到、听到嘅文字写成 `L.t("粵語原文", "普通话")`。
/// SwiftUI 喺 body 入面调用 L.t 会读到 `AppLanguage.shared.current`（@Observable），切换语言即时重画。
/// 设定页切换：`AppLanguage.shared.set(.cmn)`（存 UserDefaults）；启动参数 `-lang cmn` 只影响今次（唔存）。
/// 地标名、人名属于数据，唔翻译。
enum AppLang: String, CaseIterable, Codable, Sendable {
    case yue, cmn

    /// 设定页显示（永远用该语言自己嘅写法）。
    var label: String { self == .yue ? "粵語（繁體）" : "普通话（简体）" }
    /// 语音识别 / 助手服务器用嘅地区代码。
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
    /// 粤语原文 / 普通话。
    static func t(_ yue: String, _ cmn: String) -> String { isCmn ? cmn : yue }
}
