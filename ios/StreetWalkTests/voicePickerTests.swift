import AVFoundation
import Foundation
import Testing
@testable import StreetWalk

// 揀系统声音：档次、语言、推荐名、用户揀过、装咗新声音自动转用、设定存盘。

struct VoicePickerTests {
    // 粤语
    let sinjiStd = VoiceInfo(id: "com.apple.voice.super-compact.zh-HK.Sinji", name: "Sinji", language: "yue-HK", tier: .standard, gender: .female)
    let sinjiEnh = VoiceInfo(id: "com.apple.voice.enhanced.zh-HK.Sinji", name: "Sinji", language: "yue-HK", tier: .enhanced, gender: .female)
    let sinjiPre = VoiceInfo(id: "com.apple.voice.premium.zh-HK.Sinji", name: "Sinji", language: "yue-HK", tier: .premium, gender: .female)
    let wing = VoiceInfo(id: "com.apple.voice.premium.yue-HK.Wing", name: "Wing", language: "yue-HK", tier: .premium, gender: .female)
    let fung = VoiceInfo(id: "com.apple.voice.premium.yue-HK.Fung", name: "Fung", language: "yue-HK", tier: .premium, gender: .male)
    let aasingOld = VoiceInfo(id: "com.apple.voice.enhanced.zh-HK.Aasing", name: "Aasing", language: "zh-HK", tier: .enhanced, gender: .male)
    // 普通话
    let tingting = VoiceInfo(id: "com.apple.voice.super-compact.zh-CN.Tingting", name: "Tingting", language: "zh-CN", tier: .standard, gender: .female)
    let yue = VoiceInfo(id: "com.apple.voice.premium.zh-CN.Yue", name: "Yue", language: "zh-CN", tier: .premium, gender: .female)
    let lilian = VoiceInfo(id: "com.apple.voice.premium.zh-CN.Lilian", name: "Lilian", language: "zh-CN", tier: .premium, gender: .female)
    let meijia = VoiceInfo(id: "com.apple.voice.super-compact.zh-TW.Meijia", name: "Meijia", language: "zh-TW", tier: .standard, gender: .female)
    let grandma = VoiceInfo(id: "com.apple.eloquence.zh-CN.Grandma", name: "Grandma", language: "zh-CN", tier: .standard, unsuitable: true)
    // 英语
    let samantha = VoiceInfo(id: "com.apple.voice.super-compact.en-US.Samantha", name: "Samantha", language: "en-US", tier: .standard, gender: .female)
    let ava = VoiceInfo(id: "com.apple.voice.premium.en-US.Ava", name: "Ava", language: "en-US", tier: .premium, gender: .female)
    let serena = VoiceInfo(id: "com.apple.voice.premium.en-GB.Serena", name: "Serena", language: "en-GB", tier: .premium, gender: .female)
    let daniel = VoiceInfo(id: "com.apple.voice.enhanced.en-GB.Daniel", name: "Daniel", language: "en-GB", tier: .enhanced, gender: .male)
    let bubbles = VoiceInfo(id: "com.apple.speech.synthesis.voice.Bubbles", name: "Bubbles", language: "en-US", tier: .premium, unsuitable: true)

    var all: [VoiceInfo] { [sinjiStd, sinjiEnh, wing, fung, aasingOld, tingting, yue, lilian, meijia, grandma, samantha, ava, serena, daniel, bubbles] }

    @Test func 高品质先过增强先过标准() {
        let list = VoicePicker.candidates(for: .cantonese, in: [sinjiStd, sinjiEnh, wing])
        #expect(list.map(\.tier) == [.premium, .enhanced, .standard])
        #expect(VoicePicker.pick(for: .cantonese, in: [sinjiStd, sinjiEnh], chosen: nil) == sinjiEnh)
        #expect(VoicePicker.pick(for: .cantonese, in: [sinjiStd], chosen: nil) == sinjiStd)
    }

    @Test func 同档次按推荐名_粤语Wing然后善怡() {
        #expect(VoicePicker.candidates(for: .cantonese, in: [fung, sinjiPre, wing]).map(\.name) == ["Wing", "Sinji", "Fung"])
        #expect(VoicePicker.pick(for: .mandarin, in: [lilian, tingting, yue], chosen: nil) == yue)
        #expect(VoicePicker.pick(for: .english, in: [serena, ava, samantha], chosen: nil) == ava)
    }

    @Test func 粤语认yue同zhHK_唔认台湾同大陆() {
        let ids = Set(VoicePicker.candidates(for: .cantonese, in: all).map(\.id))
        #expect(ids == [sinjiStd.id, sinjiEnh.id, wing.id, fung.id, aasingOld.id])
    }

    @Test func 普通话永远唔揀粤语声() {
        // 只得粤语高品质同普通话标准：普通话都唔可以用粤语声（避开「普通话读成粤语」）
        #expect(VoicePicker.pick(for: .mandarin, in: [sinjiPre, wing, tingting], chosen: nil) == tingting)
        #expect(VoicePicker.pick(for: .mandarin, in: [sinjiPre, wing], chosen: nil) == nil)
        // 用户之前喺粤语揀咗 Wing，转普通话都唔会用佢
        #expect(VoicePicker.pick(for: .mandarin, in: [wing, tingting], chosen: wing.id) == tingting)
        // 大陆先过台湾（同档次）
        #expect(VoicePicker.pick(for: .mandarin, in: [meijia, tingting], chosen: nil) == tingting)
    }

    @Test func 怪声同机械声唔出() {
        #expect(!VoicePicker.candidates(for: .mandarin, in: all).contains(grandma))
        #expect(VoicePicker.pick(for: .english, in: [bubbles, samantha], chosen: nil) == samantha)
    }

    @Test func 英文美式先_但档次更重要() {
        #expect(VoicePicker.pick(for: .english, in: [samantha, daniel], chosen: nil) == daniel)
        #expect(VoicePicker.pick(for: .english, in: [serena, ava], chosen: nil) == ava)
    }

    @Test func 用户揀咗就用佢_冇咗就用返最好() {
        #expect(VoicePicker.pick(for: .cantonese, in: all, chosen: sinjiStd.id) == sinjiStd)
        #expect(VoicePicker.pick(for: .cantonese, in: all, chosen: "已经删咗嘅声") == wing)
    }

    @Test func 语言代码各种写法() {
        #expect(SpokenLanguage.cantonese.regionRank(of: "yue-HK") == 0)
        #expect(SpokenLanguage.cantonese.regionRank(of: "zh_HK") == 0)
        #expect(SpokenLanguage.cantonese.regionRank(of: "zh-Hant-HK") == 0)
        #expect(SpokenLanguage.cantonese.regionRank(of: "zh-CN") == nil)
        #expect(SpokenLanguage.mandarin.regionRank(of: "cmn-Hans-CN") == 0)
        #expect(SpokenLanguage.mandarin.regionRank(of: "zh-CN") == 0)
        #expect(SpokenLanguage.mandarin.regionRank(of: "zh-TW") == 1)
        #expect(SpokenLanguage.mandarin.regionRank(of: "yue-HK") == nil)
        #expect(SpokenLanguage.mandarin.regionRank(of: "zh-HK") == nil)
        #expect(SpokenLanguage.english.regionRank(of: "en-IN") == 3)
        #expect(SpokenLanguage.english.regionRank(of: "eu-ES") == nil)
    }

    @Test func 装咗更好嘅声就转() {
        let before: Set = [sinjiStd.id, tingting.id]
        // 第一次睇（新装 App）：唔当「新装咗」
        #expect(VoicePicker.upgrade(previous: [], now: [sinjiStd, wing], language: .cantonese, chosen: nil) == nil)
        // 由设定返嚟多咗 Wing：转
        #expect(VoicePicker.upgrade(previous: before, now: [sinjiStd, tingting, wing], language: .cantonese, chosen: nil) == wing)
        // 一次装两把：揀最好嗰把
        #expect(VoicePicker.upgrade(previous: before, now: [sinjiStd, tingting, sinjiEnh, wing], language: .cantonese, chosen: nil) == wing)
        // 用户亲手揀咗标准声，再去下载：都转
        #expect(VoicePicker.upgrade(previous: before, now: [sinjiStd, tingting, wing], language: .cantonese, chosen: sinjiStd.id) == wing)
        // 已经有高品质，再装一把同档次：唔转
        #expect(VoicePicker.upgrade(previous: before.union([wing.id]), now: [sinjiStd, tingting, wing, fung], language: .cantonese, chosen: nil) == nil)
        // 装咗普通话声，但而家讲粤语：唔关事
        #expect(VoicePicker.upgrade(previous: before, now: [sinjiStd, tingting, yue], language: .cantonese, chosen: nil) == nil)
        // 冇新嘢
        #expect(VoicePicker.upgrade(previous: before, now: [sinjiStd, tingting], language: .cantonese, chosen: nil) == nil)
    }

    @Test func 显示名同档次字() {
        #expect(sinjiStd.displayName == "善怡")
        #expect(wing.displayName == "Wing")
        #expect(yue.displayName == "月")
        #expect(wing.subtitle == "女聲 · 高品質")
        #expect(aasingOld.subtitle == "男聲 · 增強")
        #expect(VoiceInfo(id: "x", name: "X", language: "yue-HK", tier: .standard).subtitle == "標準")
    }

    @Test func 正常用系统语速_慢快拉开() {
        // 「正常」= 系统默认（10-11）；10-17 用户测试：慢同正常差唔多 → 慢明显慢、句之间停耐啲，快明显快
        #expect(SpeechPace.normal.rate == AVSpeechUtteranceDefaultSpeechRate)
        #expect(SpeechPace.normal.rate - SpeechPace.slow.rate >= 0.08)
        #expect(SpeechPace.fast.rate - SpeechPace.normal.rate >= 0.05)
        #expect(SpeechPace.slow.pauseAfterSentence >= 0.6 && SpeechPace.fast.pauseAfterSentence < SpeechPace.normal.pauseAfterSentence)
        // 豆包声（服务器收 0.7–1.3）：慢 / 快同正常差 25%
        #expect(TTSRoute.speed(.slow) <= 0.8 && TTSRoute.speed(.fast) >= 1.2 && TTSRoute.speed(.slow) >= 0.7 && TTSRoute.speed(.fast) <= 1.3)
    }

    @Test func 按句拆_逗号唔拆_唔加空格() {
        #expect(SpeechPace.sentences("你好，我係街坊行。陳太啱啱出咗門，喺涼亭附近。") == ["你好，我係街坊行。", "陳太啱啱出咗門，喺涼亭附近。"])
        #expect(SpeechPace.sentences("約陳太聽日三點。啱就撳「好」。") == ["約陳太聽日三點。", "啱就撳「好」。"])
        #expect(SpeechPace.sentences("佢話：「好呀。」你嚟唔嚟？") == ["佢話：「好呀。」", "你嚟唔嚟？"])
        #expect(SpeechPace.sentences("冇句號嘅一句") == ["冇句號嘅一句"])
        #expect(SpeechPace.sentences("真係？！好。") == ["真係？！", "好。"])
        #expect(SpeechPace.sentences("Hello, I'm StreetWalk. Mrs Chan just went out.").count == 1)
        #expect(!SpeechPace.sentences("8 樓陳太出門。").joined().contains("  "))
    }
}

@MainActor
struct VoiceSettingsTests {
    let wing = VoiceInfo(id: "w", name: "Wing", language: "yue-HK", tier: .premium, gender: .female)
    let sinji = VoiceInfo(id: "s", name: "Sinji", language: "yue-HK", tier: .standard, gender: .female)
    let tingting = VoiceInfo(id: "t", name: "Tingting", language: "zh-CN", tier: .standard, gender: .female)

    func fresh() -> (UserDefaults, String) {
        let name = "voice-test-\(UUID())"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func 默认_粤语正常速度开住() {
        let (d, name) = fresh()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let v = VoiceSettings(defaults: d, scanner: { [] }, watch: false)
        #expect(v.enabled)
        #expect(v.language == .cantonese)
        #expect(v.pace == .normal)
    }

    @Test func 改咗即刻存_下次读返() {
        let (d, name) = fresh()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let v = VoiceSettings(defaults: d, scanner: { [] }, watch: false)
        v.apply([sinji, wing, tingting])
        v.enabled = false
        v.pace = .slow
        v.choose(sinji)
        v.language = .mandarin
        let again = VoiceSettings(defaults: d, scanner: { [] }, watch: false)
        again.apply([sinji, wing, tingting])
        #expect(!again.enabled)
        #expect(again.pace == .slow)
        #expect(again.language == .mandarin)
        #expect(again.active == tingting)
        again.language = .cantonese
        #expect(again.active == sinji, "粤语揀过善怡，记得")
        #expect(!again.isAuto)
    }

    @Test func 下载完返嚟_自动转用兼通知() {
        let (d, name) = fresh()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let v = VoiceSettings(defaults: d, scanner: { [] }, watch: false)
        var told: [VoiceInfo] = []
        v.onUpgrade = { told.append($0) }
        v.apply([sinji, tingting])
        #expect(told.isEmpty, "第一次睇唔通知")
        #expect(!v.hasNaturalVoice)
        v.choose(sinji)                 // 用户亲手揀咗标准声
        v.apply([sinji, tingting, wing])
        #expect(told == [wing])
        #expect(v.active == wing)
        #expect(v.hasNaturalVoice)
        v.apply([sinji, tingting, wing])
        #expect(told == [wing], "再睇一次唔会重复通知")
    }
}
