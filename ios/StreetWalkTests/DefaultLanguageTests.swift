import Foundation
import Testing
@testable import StreetWalk

// 测试反馈 A-5：第一次开 App 按 iOS 系统语言揀界面语言；揀过 / 旧用户唔覆盖。
// 只用独立 UserDefaults，唔郁 AppLanguage.shared（其他测试并行跑，默认粤语）。
struct DefaultLanguageTests {
    @Test func 按系统语言揀() {
        #expect(AppLanguage.systemDefault(preferred: ["zh-Hans-CN", "en-CN"], region: "CN") == .cmn)
        #expect(AppLanguage.systemDefault(preferred: ["zh-Hans-HK"], region: "HK") == .cmn, "简体就系普通话")
        #expect(AppLanguage.systemDefault(preferred: ["zh-Hant-HK"], region: "HK") == .yue)
        #expect(AppLanguage.systemDefault(preferred: ["yue-Hant-HK"], region: "HK") == .yue)
        #expect(AppLanguage.systemDefault(preferred: ["zh-Hant-TW"], region: "TW") == .yue, "繁体照用粤语界面")
        // 首选英文 → English（2026-10-17 加英文版）
        #expect(AppLanguage.systemDefault(preferred: ["en-US", "zh-Hans-CN"], region: "US") == .en, "首选英文")
        #expect(AppLanguage.systemDefault(preferred: ["en-GB"], region: "CN") == .en)
        #expect(AppLanguage.systemDefault(preferred: ["en-HK", "zh-Hant-HK"], region: "HK") == .en)
        #expect(AppLanguage.systemDefault(preferred: ["en"], region: nil) == .en)
        // 首选唔系英文：睇第一个中文
        #expect(AppLanguage.systemDefault(preferred: ["ja-JP", "zh-Hans-CN", "en-US"], region: "JP") == .cmn, "睇第一个中文")
        #expect(AppLanguage.systemDefault(preferred: ["ja-JP", "en-US"], region: "HK") == .en, "冇中文、有英文")
        #expect(AppLanguage.systemDefault(preferred: ["ja-JP"], region: "CN") == .cmn, "冇中文冇英文睇地区")
        #expect(AppLanguage.systemDefault(preferred: ["ja-JP"], region: "HK") == .yue)
        #expect(AppLanguage.systemDefault(preferred: ["fr-FR"], region: "FR") == .en)
        #expect(AppLanguage.systemDefault(preferred: [], region: nil) == .yue)
    }

    @Test func 只喺第一次揀_唔覆盖() {
        let d = UserDefaults(suiteName: "lang-seed-\(UUID())")!
        #expect(AppLanguage.seedDefault(defaults: d, preferred: ["zh-Hans-CN"], region: "CN") == .cmn)
        #expect(d.string(forKey: AppLanguage.key) == "cmn", "揀完存低")
        #expect(AppLanguage(defaults: d, arguments: []).current == .cmn)
        // 之后系统语言变咗、或者再启动：唔再郁
        #expect(AppLanguage.seedDefault(defaults: d, preferred: ["zh-Hant-HK"], region: "HK") == nil)
        #expect(d.string(forKey: AppLanguage.key) == "cmn")

        // 自己喺设定揀过粤语：唔覆盖
        let chose = UserDefaults(suiteName: "lang-seed-\(UUID())")!
        AppLanguage(defaults: chose, arguments: []).set(.yue)
        #expect(AppLanguage.seedDefault(defaults: chose, preferred: ["zh-Hans-CN"], region: "CN") == nil)
        #expect(chose.string(forKey: AppLanguage.key) == "yue")

        // 英文系统第一次开：揀 English 存低；-lang en 都读得到
        let en = UserDefaults(suiteName: "lang-seed-\(UUID())")!
        #expect(AppLanguage.seedDefault(defaults: en, preferred: ["en-GB"], region: "HK") == .en)
        #expect(en.string(forKey: AppLanguage.key) == "en")
        #expect(AppLanguage(defaults: en, arguments: []).current == .en)
        #expect(AppLanguage(defaults: chose, arguments: ["-lang", "en"]).current == .en, "启动参数只影响今次")
        #expect(chose.string(forKey: AppLanguage.key) == "yue")

        // 旧用户（已完成首次使用、未揀过）：保持粤语
        let old = UserDefaults(suiteName: "lang-seed-\(UUID())")!
        old.set(true, forKey: "onboarded")
        #expect(AppLanguage.seedDefault(defaults: old, preferred: ["zh-Hans-CN"], region: "CN") == .yue)
    }
}
