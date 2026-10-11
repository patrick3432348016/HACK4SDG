import Foundation
import Testing
@testable import StreetWalk

// 普通话版：语言切换（启动参数、存档、实时活动）同普通话语音意图。
// 唔改全局 AppLanguage.shared（其他测试并行跑，默认粤语）。
struct LanguageTests {
    @Test func 默认粤语同显示名() {
        #expect(ReportKind.noSeat.rawValue == "冇櫈", "存档值唔变")
        #expect(AppLang.cmn.spoken == .mandarin && AppLang.yue.spoken == .cantonese)
        #expect(AppLang.cmn.locale == "zh-CN" && AppLang.yue.locale == "zh-HK")
    }

    @Test func 启动参数同存档() {
        let d = UserDefaults(suiteName: "lang-test-\(UUID())")!
        #expect(AppLanguage(defaults: d, arguments: []).current == .yue, "默认粤语")
        #expect(AppLanguage(defaults: d, arguments: ["-lang", "cmn"]).current == .cmn)
        #expect(d.string(forKey: AppLanguage.key) == nil, "-lang 唔存")
        AppLanguage(defaults: d, arguments: []).set(.cmn)
        #expect(AppLanguage(defaults: d, arguments: []).current == .cmn, "设定页揀咗会记住")
    }

    @Test func 实时活动跟状态语言() {
        var s = IslandStatus(kind: .walk, minutes: 12)
        s.lang = .cmn
        #expect(s.title == "已走 12 分钟")
        s.lang = .yue
        #expect(s.title == "行緊 12 分鐘")
    }
}

struct MandarinVoiceTests {
    let ai = TemplateAI()
    let chan = { var r = Resident(id: "chan", name: "陳太", floor: 8, colorIndex: 0, mobility: .walk, streakDays: 3, todayLine: ""); r.isNeighbor = true; return r }()
    let me = Resident(id: "me", name: "你", floor: 12, colorIndex: 6, mobility: .walk, streakDays: 1, todayLine: "", isMe: true)
    let lms = [Landmark(id: "shelter-1", name: "涼亭", kind: .shelter, pos: .zero, hasSeat: true)]
    func ctx(finding: Bool = false) -> AIContext { AIContext(residents: [chan, me], landmarks: lms, now: Date(), walking: false, finding: finding) }

    @Test func 普通话约人() {
        #expect(ai.parseVoice("约陈太明天下午三点一起走", context: ctx()) == .invite(partnerID: "chan", day: 1, hour: 15))
        #expect(ai.parseVoice("约8楼后天早上一起散步", context: ctx()) == .invite(partnerID: "chan", day: 2, hour: 8))
        #expect(ai.parseHour("晚上七点") == 19)
    }

    @Test func 普通话请假反映找人() {
        #expect(ai.parseVoice("明天请假", context: ctx()) == .leave)
        #expect(ai.parseVoice("这里太晒了", context: ctx()) == .report(.sunny))
        #expect(ai.parseVoice("这里没有凳子", context: ctx()) == .report(.noSeat))
        #expect(ai.parseVoice("这条路不好走", context: ctx()) == .report(.rough))
        #expect(ai.parseVoice("去找陈太", context: ctx()) == .goFind(partnerID: "chan"))
        #expect(ai.parseVoice("我在凉亭", context: ctx(finding: true)) == .broadcast("我在凉亭"))
    }

    @Test func 普通话改约取消改名() {
        #expect(ai.parseVoice("取消和陈太的约会", context: ctx()) == .cancelMeetup(partnerID: "chan"))
        #expect(ai.parseVoice("不约了", context: ctx()) == .cancelMeetup(partnerID: nil))
        #expect(ai.parseVoice("改到明天早上", context: ctx()) == .changeMeetup(partnerID: nil, day: 1, hour: 8, landmarkID: nil))
        #expect(ai.parseVoice("改在凉亭", context: ctx()) == .changeMeetup(partnerID: nil, day: nil, hour: nil, landmarkID: "shelter-1"))
        #expect(ai.parseVoice("凉亭改名叫大树底", context: ctx()) == .rename(landmarkID: "shelter-1", newName: "大樹底"))
    }
}
