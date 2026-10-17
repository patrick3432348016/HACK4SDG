import Foundation

/// 界面语言同播报语言绑埋：揀普通话 → zh-CN、揀 English → en-US（声音、语音识别、助手 locale 都跟 AppLang.locale）。
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
    /// 设定页揀语言：界面即时转、存低，播报跟住转。
    @MainActor func choose(_ l: AppLang) {
        set(l)
        VoiceSettings.shared.followAppLanguage()
    }

    /// 启动时（StreetWalkApp.init，喺 AppStore.launch 之前）叫：第一次开 App 按 iOS 系统语言揀默认（测试反馈 A-5）。
    /// 单元测试一律用粤语（模拟器系统语言系简体中文，测试期望粤语字句；只改内存唔存）。
    static func prepareForLaunch() {
        if runningTests { shared.current = .yue; return }
        // -lang cmn / yue / en 只影响今次（AppLanguage.init 已经用咗），其余跟住新默认
        if let l = seedDefault(), !ProcessInfo.processInfo.arguments.contains("-lang") { shared.current = l }
    }

    /// 未揀过语言先揀：英文 → English；简体中文 → 普通话；繁体 / 粤语 → 粤语（见 systemDefault）。揀完即刻存低（之后同自己揀嘅一样，唔会再跟系统变）。
    /// 已经用开（完成咗首次使用）嘅旧用户一直睇紧粤语：存返粤语，唔会升级后突然转。设定页照样可以改。
    /// 返回今次揀咗嘅语言；已经揀过就 nil（唔郁）。
    @discardableResult
    static func seedDefault(defaults: UserDefaults = .standard, preferred: [String] = Locale.preferredLanguages,
                            region: String? = Locale.current.region?.identifier) -> AppLang? {
        guard defaults.string(forKey: key) == nil else { return nil }
        let l: AppLang = defaults.bool(forKey: "onboarded") ? .yue : systemDefault(preferred: preferred, region: region)
        defaults.set(l.rawValue, forKey: key)
        return l
    }

    /// 按系统语言清单揀：首选英文 → English；否则睇第一个中文（zh / yue：简体 → 普通话，繁体 / 香港 → 粤语）；
    /// 冇中文、清单有英文 → English；都冇就睇地区（内地、新加坡 → 普通话；香港、澳门、台湾或者唔知 → 粤语；其他 → English）。
    static func systemDefault(preferred: [String], region: String?) -> AppLang {
        let langs = preferred.map { $0.lowercased() }
        func isEn(_ l: String) -> Bool { l == "en" || l.hasPrefix("en-") }
        if let first = langs.first, isEn(first) { return .en }
        if let zh = langs.first(where: { $0.hasPrefix("zh") || $0.hasPrefix("yue") }) {
            if zh.hasPrefix("yue") || zh.contains("hant") { return .yue }
            if zh.contains("hans") { return .cmn }
            // 冇写明繁简（例如 zh-CN、zh-HK）：按地区
            return zh.hasSuffix("-cn") || zh.hasSuffix("-sg") ? .cmn : .yue
        }
        if langs.contains(where: isEn) { return .en }
        if region == "CN" || region == "SG" { return .cmn }
        if langs.isEmpty || region == nil || ["HK", "MO", "TW"].contains(region!) { return .yue }
        return .en
    }

    /// 喺单元测试入面跑（测试宿主 App 都会行 StreetWalkApp.init）。
    static var runningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil || env["XCTestSessionIdentifier"] != nil
    }
}

extension VoiceSettings {
    /// 播报语言跟界面语言（启动时同切换时叫）。
    func followAppLanguage() {
        let want = L.lang.spoken
        if language != want { language = want }
    }
}
