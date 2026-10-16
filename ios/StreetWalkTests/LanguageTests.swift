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

    @Test func 普通话常见讲法更宽松() {
        // 只讲「邻居」：约 / 找第一个街坊（测试员 10-12：「约邻居明天一起走」被当听不明白）
        #expect(ai.parseVoice("约邻居明天一起走", context: ctx()) == .invite(partnerID: "chan", day: 1, hour: nil))
        #expect(ai.parseVoice("我想和邻居明天早上散步", context: ctx()) == .invite(partnerID: "chan", day: 1, hour: 8))
        #expect(ai.parseVoice("找邻居", context: ctx()) == .goFind(partnerID: "chan"))
        #expect(ai.parseVoice("陈太明天下午三点散步", context: ctx()) == .invite(partnerID: "chan", day: 1, hour: 15))
        #expect(ai.parseVoice("这里没地方坐", context: ctx()) == .report(.noSeat))
        #expect(ai.parseVoice("太阳很大", context: ctx()) == .report(.sunny))
        // 唔识嘅名唔会乱约
        #expect(ai.parseVoice("约李先生明天一起走", context: ctx()) == .unknown)
        #expect(TemplateAI.asksWeather("今天天气怎么样"))
        #expect(TemplateAI.topic("约李先生明天一起走") == .invite)
    }

    @Test func 普通话请几天假() {
        for s in ["请三天假", "请3天假", "请两天假", "请一个星期假", "我想请个三天假", "請兩天假"] {
            #expect(ai.parseVoice(s, context: ctx()) == .leave, "\(s)")
        }
        #expect(LeaveRequest.parse("请三天假") == LeaveRequest(startOffset: 0, days: 3))
        #expect(LeaveRequest.parse("请3天假") == LeaveRequest(startOffset: 0, days: 3))
        #expect(LeaveRequest.parse("请两天假") == LeaveRequest(startOffset: 0, days: 2))
        #expect(LeaveRequest.parse("请一个星期假") == LeaveRequest(startOffset: 0, days: 7))
        #expect(LeaveRequest.parse("明天请两天假") == LeaveRequest(startOffset: 1, days: 2))
        // 连续对话：豆包嘅字已转繁体
        #expect(LeaveRequest.parse("請兩天假") == LeaveRequest(startOffset: 0, days: 2))
        #expect(LeaveRequest.parse("請一個星期假") == LeaveRequest(startOffset: 0, days: 7))
        #expect(LeaveRequest.parse("請兩周假") == LeaveRequest(startOffset: 0, days: 14))
    }

    @Test func 普通话问热唔当反映() {
        for q in ["今天会很热吗", "明天热不热", "会不会下雨", "今天很热", "这里会不会很热", "明天冷不冷"] {
            #expect(ai.parseVoice(q, context: ctx()) == .unknown, "\(q)")
            #expect(TemplateAI.asksWeather(q), "\(q)")
        }
        // 讲明「这里」先系反映
        #expect(ai.parseVoice("这里好晒", context: ctx()) == .report(.sunny))
        #expect(ai.parseVoice("这里太晒", context: ctx()) == .report(.sunny))
        #expect(!TemplateAI.asksWeather("约陈太明天下午三点一起走"))
        #expect(!TemplateAI.asksWeather("这里没有凳子"))
    }

    @Test func 普通话求救同问医疗() {
        for s in ["救命", "救我", "我摔倒了", "我跌倒了起不来", "胸口好痛", "胸口疼", "喘不过气", "呼吸困难", "我老伴晕倒了", "流血了", "快叫救护车", "帮我报警"] {
            #expect(TemplateAI.safety(s) == .emergency, "\(s)")
        }
        for s in ["我头痛吃什么药", "要不要吃药", "感冒该看什么医生", "要不要看医生", "可以吃止痛药吗"] {
            #expect(TemplateAI.safety(s) == .medical, "\(s)")
        }
        // 唔好误认：「帮我」唔系求救；药房系地方
        for s in ["帮我约阿芳", "约陈太明天下午三点一起走", "今天天气怎么样", "这里太晒", "约陈太在药房门口见", "请三天假", "好的"] {
            #expect(TemplateAI.safety(s) == nil, "\(s)")
        }
    }

    @Test func 普通话改约取消改名() {
        #expect(ai.parseVoice("取消和陈太的约会", context: ctx()) == .cancelMeetup(partnerID: "chan"))
        #expect(ai.parseVoice("不约了", context: ctx()) == .cancelMeetup(partnerID: nil))
        #expect(ai.parseVoice("改到明天早上", context: ctx()) == .changeMeetup(partnerID: nil, day: 1, hour: 8, landmarkID: nil))
        #expect(ai.parseVoice("改在凉亭", context: ctx()) == .changeMeetup(partnerID: nil, day: nil, hour: nil, landmarkID: "shelter-1"))
        #expect(ai.parseVoice("凉亭改名叫大树底", context: ctx()) == .rename(landmarkID: "shelter-1", newName: "大樹底"))
    }
}
