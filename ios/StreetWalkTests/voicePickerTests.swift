import AVFoundation
import Foundation
import Testing
@testable import StreetWalk

// Voice selection tests: quality, locale, preferred names, user choice, upgrades and persistence.

struct VoicePickerTests {
    // Cantonese.
    let sinjiStd = VoiceInfo(id: "com.apple.voice.super-compact.zh-HK.Sinji", name: "Sinji", language: "yue-HK", tier: .standard, gender: .female)
    let sinjiEnh = VoiceInfo(id: "com.apple.voice.enhanced.zh-HK.Sinji", name: "Sinji", language: "yue-HK", tier: .enhanced, gender: .female)
    let sinjiPre = VoiceInfo(id: "com.apple.voice.premium.zh-HK.Sinji", name: "Sinji", language: "yue-HK", tier: .premium, gender: .female)
    let wing = VoiceInfo(id: "com.apple.voice.premium.yue-HK.Wing", name: "Wing", language: "yue-HK", tier: .premium, gender: .female)
    let fung = VoiceInfo(id: "com.apple.voice.premium.yue-HK.Fung", name: "Fung", language: "yue-HK", tier: .premium, gender: .male)
    let aasingOld = VoiceInfo(id: "com.apple.voice.enhanced.zh-HK.Aasing", name: "Aasing", language: "zh-HK", tier: .enhanced, gender: .male)
    // Mandarin.
    let tingting = VoiceInfo(id: "com.apple.voice.super-compact.zh-CN.Tingting", name: "Tingting", language: "zh-CN", tier: .standard, gender: .female)
    let yue = VoiceInfo(id: "com.apple.voice.premium.zh-CN.Yue", name: "Yue", language: "zh-CN", tier: .premium, gender: .female)
    let lilian = VoiceInfo(id: "com.apple.voice.premium.zh-CN.Lilian", name: "Lilian", language: "zh-CN", tier: .premium, gender: .female)
    let meijia = VoiceInfo(id: "com.apple.voice.super-compact.zh-TW.Meijia", name: "Meijia", language: "zh-TW", tier: .standard, gender: .female)
    let grandma = VoiceInfo(id: "com.apple.eloquence.zh-CN.Grandma", name: "Grandma", language: "zh-CN", tier: .standard, unsuitable: true)
    // English.
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
        // Premium Cantonese must never replace a standard Mandarin voice for Mandarin output.
        #expect(VoicePicker.pick(for: .mandarin, in: [sinjiPre, wing, tingting], chosen: nil) == tingting)
        #expect(VoicePicker.pick(for: .mandarin, in: [sinjiPre, wing], chosen: nil) == nil)
        // A saved Cantonese Wing choice must not carry into Mandarin.
        #expect(VoicePicker.pick(for: .mandarin, in: [wing, tingting], chosen: wing.id) == tingting)
        // Prefer mainland over Taiwan locale within a tier.
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
        // The initial installation scan is not a newly added voice event.
        #expect(VoicePicker.upgrade(previous: [], now: [sinjiStd, wing], language: .cantonese, chosen: nil) == nil)
        // Select newly added Wing after returning from Settings.
        #expect(VoicePicker.upgrade(previous: before, now: [sinjiStd, tingting, wing], language: .cantonese, chosen: nil) == wing)
        // With two additions, choose the better voice.
        #expect(VoicePicker.upgrade(previous: before, now: [sinjiStd, tingting, sinjiEnh, wing], language: .cantonese, chosen: nil) == wing)
        // Upgrade even after an explicit standard-voice selection.
        #expect(VoicePicker.upgrade(previous: before, now: [sinjiStd, tingting, wing], language: .cantonese, chosen: sinjiStd.id) == wing)
        // Do not switch for another voice at the existing premium tier.
        #expect(VoicePicker.upgrade(previous: before.union([wing.id]), now: [sinjiStd, tingting, wing, fung], language: .cantonese, chosen: nil) == nil)
        // A new Mandarin voice does not affect active Cantonese.
        #expect(VoicePicker.upgrade(previous: before, now: [sinjiStd, tingting, yue], language: .cantonese, chosen: nil) == nil)
        // No new voices.
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
        // Normal uses system default; 10-17 feedback requires clearly slower speech/longer pauses and clearly faster Fast.
        #expect(SpeechPace.normal.rate == AVSpeechUtteranceDefaultSpeechRate)
        #expect(SpeechPace.normal.rate - SpeechPace.slow.rate >= 0.08)
        #expect(SpeechPace.fast.rate - SpeechPace.normal.rate >= 0.05)
        #expect(SpeechPace.slow.pauseAfterSentence >= 0.6 && SpeechPace.fast.pauseAfterSentence < SpeechPace.normal.pauseAfterSentence)
        // Doubao slow/fast differ by 25% from Normal within the server's 0.7–1.3 range.
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
        v.choose(sinji)                 // User explicitly selected a standard voice.
        v.apply([sinji, tingting, wing])
        #expect(told == [wing])
        #expect(v.active == wing)
        #expect(v.hasNaturalVoice)
        v.apply([sinji, tingting, wing])
        #expect(told == [wing], "再睇一次唔会重复通知")
    }
}
