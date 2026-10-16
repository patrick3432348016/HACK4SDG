import Foundation
import Testing
@testable import StreetWalk

// 组员 B 嗰套（2026-10-12）：豆包识别嘅讯息、连续对话嘅「好 / 唔好」同回声保险、B 范围规则嘅卡、普通话用服务器声。

struct EarProtocolTests {
    @Test func 服务器讯息() {
        #expect(VoiceEar.parse(#"{"type":"ready","message":"豆包识别通道已连接"}"#) == .ready)
        #expect(VoiceEar.parse(#"{"type":"transcript","text":"北区","final":false}"#) == .event(.partial("北区")))
        #expect(VoiceEar.parse(#"{"type":"transcript","text":" 北区今日天气点 ","final":true}"#) == .event(.final("北区今日天气点")))
        #expect(VoiceEar.parse(#"{"type":"error","code":"UNAUTHORIZED","message":"請先登入。"}"#) == .event(.failed("請先登入。")))
        #expect(VoiceEar.parse(#"{"type":"transcript","text":"  ","final":true}"#) == nil)
        #expect(VoiceEar.parse(#"{"type":"interrupted","turn_id":2}"#) == nil)
        #expect(VoiceEar.parse("not json") == nil)
    }
}

struct ConversationRuleTests {
    @Test func 对住复述卡讲好唔会当新请求() {
        #expect(AppStore.yesNo("好呀") == .yes)
        #expect(AppStore.yesNo("係。") == .yes)
        #expect(AppStore.yesNo("唔好") == .no)
        #expect(AppStore.yesNo("取消佢") == .no)
        #expect(AppStore.yesNo("好想約阿芳") == nil, "长句系新请求")
        #expect(AppStore.yesNo("北區今日天氣點") == nil)
    }

    @Test func 否定先认_不好唔得唔会当好() {
        // 「不好」「唔得」「不可以」含「好 / 得 / 可以」，以前当咗「好」（连续对话豆包嘅字已转繁体：不對）
        for t in ["不好", "不对", "不對", "不可以", "不行", "唔好", "唔得", "唔可以", "唔係", "不好。", "唔得呀"] {
            #expect(AppStore.yesNo(t) == .no, "\(t)")
        }
        for t in ["好", "好的", "可以", "係", "對", "得"] {
            #expect(AppStore.yesNo(t) == .yes, "\(t)")
        }
    }

    @Test func 回声保险() {
        let spoken = ["全港預報參考，10月13日：天晴。日間乾燥及炎熱。"]
        #expect(AppStore.looksLikeEcho("日間乾燥", spoken: spoken))
        #expect(AppStore.looksLikeEcho("日间乾燥及炎热", spoken: spoken), "简体都认得")
        #expect(!AppStore.looksLikeEcho("咁聽日呢", spoken: spoken))
        #expect(!AppStore.looksLikeEcho("好", spoken: spoken), "一个字唔判断")
        #expect(!AppStore.looksLikeEcho("日間", spoken: []))
    }
}

@MainActor
struct PolicyCardTests {
    let base = AssistantFlowTests()

    @Test func 天气用b嘅原句唔当听唔明() throws {
        let r = try base.reply("info", command: #"{"intent":"help"}"#, data: #"{"policy":"weather","weather":{"source":"香港天文台"}}"#,
                               message: "天文台14点00分实况，北区测站参考：打鼓岭31度。")
        let c = AssistantFlow.card(r, lookup: base.lookup)
        #expect(c.kind == .info)
        #expect(c.title == "天文台天氣")
        #expect(c.detail?.contains("打鼓嶺31度") == true)
        #expect(!AssistantFlow.shouldFallBack(r, local: .unknown))
    }

    @Test func 拒答唔会退返手机模板() throws {
        let r = try base.reply("info", command: #"{"intent":"help"}"#, data: #"{"policy":"deny"}"#, message: "呢个问题唔喺我嘅服务范围。")
        #expect(AssistantFlow.card(r, lookup: base.lookup).kind == .info)
        #expect(!AssistantFlow.shouldFallBack(r, local: .invite(partnerID: "fang-id", day: 1, hour: 16)), "B：夹杂 App 词语都成句拒绝")
    }

    @Test func 冇policy嘅help照旧当听唔明() throws {
        let r = try base.reply("info", command: #"{"intent":"help"}"#, message: "可以说……")
        #expect(AssistantFlow.card(r, lookup: base.lookup).kind == .notUnderstood)
    }
}

struct MandarinServerVoiceTests {
    @Test func 服务器有普通话声就用() {
        let server = URL(string: "http://192.168.1.20:8765")!
        #expect(TTSRoute.decide(language: .mandarin, server: server, cached: nil, scripted: false, mandarin: true) == .server(server))
        #expect(TTSRoute.decide(language: .mandarin, server: server, cached: nil, scripted: false, mandarin: false) == .system)
    }
}
