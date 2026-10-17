import Foundation
import Testing
@testable import StreetWalk

// 2026-10-17 组员真机测试（语音组）：
// A-4 认唔到整点、半点以外嘅时间，讲唔到行几耐；H-1 对住复述卡讲「好 / 不要」冇反应；
// H-2 识别字叠埋（「帮我约我的帮我帮我约」）；I-1 / I-2 试听状态同语速（见 voicePickerTests）。

struct SpokenTimeTests {
    func clock(_ s: String) -> [Int]? { TemplateAI.parseClock(s).map { [$0.hour, $0.minute] } }

    @Test func 整点半点以外嘅时间() {
        #expect(clock("约陈太明天下午三点十五散步") == [15, 15])
        #expect(clock("約陳太聽日下晝3點20分") == [15, 20])
        #expect(clock("三点一刻") == [15, 15], "冇讲上下午：一至四点当下午")
        #expect(clock("下午两点三刻") == [14, 45])
        #expect(clock("早上八点零五") == [8, 5])
        #expect(clock("四点四十五") == [16, 45])
        #expect(clock("下午三点半") == [15, 30])
        #expect(clock("15:20") == [15, 20])
        #expect(clock("下午3:20") == [15, 20])
        #expect(clock("下午三点差五分") == [14, 55])
        #expect(clock("十一點") == [11, 0])
        #expect(clock("夜晚十一點") == nil, "太夜唔约")
    }

    @Test func 粤语讲法同唔系钟点嘅一点() {
        #expect(clock("下晝三點三") == [15, 15], "三點三 = 3:15")
        #expect(clock("下晝三點踏九") == [15, 45])
        #expect(clock("三點兩個字") == [15, 10])
        #expect(clock("約陳太聽日下晝三點一齊行") == [15, 0], "「一齊」嘅「一」唔系分钟")
        #expect(clock("聽日早一點出門") == nil, "「早一點」唔系一点钟")
        #expect(TemplateAI.spokenMinute("同陳太三點嘅約改到四點十五") == 15, "改约只睇「改到」后面")
        #expect(TemplateAI().parseHour("约陈太明天三点十五") == 15)
        #expect(TemplateAI().parseHour("下晝") == 16, "冇钟点照旧")
    }

    @Test func 行几耐唔当分钟() {
        // 10-18 真机：「约邻居明天下午 3 点散步 40 分钟」确认卡变「3 点 2 分」
        for (text, walk) in [("约邻居明天下午3点散步40分钟", 40), ("约邻居明天下午三点散步四十分钟", 40), ("约邻居明天下午3点走半个钟", 30),
                             ("约邻居明天下午3点40分钟", 40), ("約街坊聽日下晝三點行半個鐘", 30), ("约邻居明天下午 3 点散步 40 分钟", 40)] {
            #expect(clock(text) == [15, 0], "\(text)")
            #expect(TemplateAI.spokenMinute(text) == 0, "\(text)")
            #expect(TemplateAI.parseDuration(text) == walk, "\(text)")
        }
        #expect(clock("下晝三點半鐘") == [15, 30], "三點半鐘照旧系 3:30")
    }

    @Test func 行几耐() {
        #expect(TemplateAI.parseDuration("约陈太明天下午三点走四十分钟") == 40)
        #expect(TemplateAI.parseDuration("散步一个小时") == 60)
        #expect(TemplateAI.parseDuration("走半个钟") == 30)
        #expect(TemplateAI.parseDuration("行一個半鐘") == 90)
        #expect(TemplateAI.parseDuration("散步40分钟") == 40)
        #expect(TemplateAI.parseDuration("最多行十五分鐘") == nil, "B 问嘅「最多行几远」")
        #expect(TemplateAI.parseDuration("下晝三點半鐘") == nil, "钟点唔系行几耐")
        #expect(TemplateAI.parseDuration("约陈太明天下午三点散步") == nil)
        #expect(TemplateAI.walkPhrase(40) == "一齊行 40 分鐘")
        #expect(TemplateAI.walkPhrase(60) == "一齊行一個鐘")
        #expect(TemplateAI.walkPhrase(30) == "一齊行半個鐘")
    }
}

struct TranscriptJoinTests {
    @Test func 字唔会叠埋() {
        #expect(Listener.collapseRepeats("帮我帮我约") == "帮我约")
        #expect(Listener.collapseRepeats("好的好的") == "好的")
        #expect(Listener.collapseRepeats("慢慢行") == "慢慢行", "一个字嘅叠字唔郁")
        // 用户由头再讲：唔好叠埋旧嗰段
        #expect(Listener.joined(committed: "帮我约我的", latest: "帮我帮我约") == "帮我约")
        #expect(Listener.joined(committed: "约陈太", latest: "约陈太明天三点") == "约陈太明天三点")
        // 停顿后由头再认（新一段唔包含旧段）：接埋
        #expect(Listener.joined(committed: "约陈太明天", latest: "下午三点") == "约陈太明天下午三点")
        // 头尾重叠只留一次
        #expect(Listener.joined(committed: "约陈太明天", latest: "明天下午三点") == "约陈太明天下午三点")
    }

    @Test func 对住复述卡讲好唔好() {
        for t in ["行", "行啊", "好的", "可以", "没问题", "冇問題", "OK"] { #expect(AppStore.yesNo(t) == .yes, "\(t)") }
        for t in ["不好", "不要", "算了", "取消", "唔得", "不行", "唔行", "不用了", "算啦"] { #expect(AppStore.yesNo(t) == .no, "\(t)") }
        #expect(AppStore.yesNo("好想約阿芳") == nil)
        #expect(AppStore.yesNo("嗯") == nil, "唔肯定：再问一次")
    }
}

@MainActor
struct VoiceAnswerFlowTests {
    let lms = [Landmark(id: "shelter-1", name: "涼亭", kind: .shelter, pos: .zero, hasSeat: true),
               Landmark(id: "park-0", name: "公園櫈仔", kind: .park, pos: Vec2(x: 40, y: 0), hasSeat: true)]
    let me = Resident(id: "me", name: "你", floor: 12, colorIndex: 6, mobility: .walk, streakDays: 1, todayLine: "", isMe: true)
    var chan: Resident { var r = Resident(id: "chan", name: "陳太", floor: 8, colorIndex: 0, mobility: .walk, streakDays: 3, todayLine: ""); r.isNeighbor = true; return r }

    func makeStore() -> AppStore {
        let s = AppStore()
        s.restoring = true
        s.clockTask?.cancel()
        s.announcer.voiceOverRunning = { false }
        s.demoHour = 10
        s.landmarks = lms
        s.residents = [chan, me]
        s.appointments = []
        s.reports = []
        let map = MapModel(tile: TileKey(ix: 0, iy: 0), center: GeoPoint(lat: 22.5044, lon: 114.1563), size: 200, buildings: [],
                           roads: [], areas: [], pois: [], trees: [], fetchedAt: Date(), source: "t")
        s.shade = ShadeService(map: map, landmarks: lms)
        return s
    }

    @Test func 约人卡讲啱分钟同行几耐() {
        let s = makeStore()
        s.handle("約陳太聽日下晝三點十五一齊行四十分鐘")
        #expect(s.voiceCard?.needsConfirm == true)
        #expect(s.voiceCard?.title == "約陳太聽日下晝 3 點 15 分一齊行 40 分鐘")
        #expect(s.voiceCard?.detail?.contains("一齊行") == false, "行几耐只喺标题讲一次")
        #expect(s.proposal?.options.first?.date == AppStore.today(at: 15.25, dayOffset: 1))
        #expect(s.proposal?.options.first?.reason.hasSuffix("，一齊行 40 分鐘") == true, "写入理由，对方都见到")
        s.handle("好")
        #expect(s.voiceCard == nil && s.proposal == nil)
        #expect(s.appointments.first?.date == AppStore.today(at: 15.25, dayOffset: 1))
    }

    @Test func 讲不要就撤回_听唔清再问() {
        let s = makeStore()
        s.handle("約陳太聽日下晝三點半一齊行")
        #expect(s.voiceCard?.title == "約陳太聽日下晝 3 點 30 分一齊行")
        s.handle("嗯")
        #expect(s.voiceCard?.needsConfirm == true, "听唔清：张卡留住")
        s.handle("唔好")
        #expect(s.voiceCard == nil && s.proposal == nil && s.appointments.isEmpty)
        // 长句当新请求：旧嘅提议撤回
        s.handle("約陳太聽日下晝三點一齊行")
        s.handle("今日天氣點")
        #expect(s.proposal == nil)
    }

    @Test func 改约讲分钟() {
        let s = makeStore()
        let a = Appointment(partnerID: "chan", date: AppStore.today(at: 15, dayOffset: 1), landmarkID: "shelter-1", reason: "", status: .accepted)
        s.appointments = [a]
        s.handle("改到聽日下晝四點十五")
        #expect(s.voiceCard?.title.contains("下晝 4 點 15 分") == true)
        s.handle("可以")
        #expect(s.appointments.first?.date == AppStore.today(at: 16.25, dayOffset: 1))
    }
}

@MainActor
struct PreviewStateTests {
    @Test func 试听即刻变播紧_停咗变返() {
        let sp = Speaker()
        sp.preview(nil, language: .cantonese)
        #expect(sp.previewing && sp.previewKey == "current")
        sp.stop()
        #expect(!sp.previewing && sp.previewKey == nil)
        sp.preview(nil, language: .cantonese, key: "x")
        #expect(sp.previewKey == "x")
        sp.speak("新嘅播报")
        #expect(!sp.previewing, "新播报取代试听")
        sp.stop()
    }
}

// 2026-10-18 组员真机测试（语音组）：天气句语言夹杂、普通话读「街坊行」、散步例句得两句、反映提示写死人数。
@MainActor
struct VoiceFix18Tests {
    @Test func 天气句跟而家嘅语言() {
        let r = HKOReport(station: "九龍城", temperature: 27)
        #expect(AppStore.inLanguage(.yue) { r.line } == "天文台話九龍城而家 27 度。")
        #expect(AppStore.inLanguage(.cmn) { r.line } == "天文台说九龙城现在 27 度。")
        #expect(AppStore.inLanguage(.en) { r.line } == "Observatory: 27°C in Kowloon City now")
        #expect(HKOReport.psrEnglish("中低") == "medium-low")
        // 警告名存繁体，普通话显示简体
        var hot = r
        hot.warnings = [.init(code: "WL", name: HKOReport.displayName(code: "WL", type: nil, name: nil))]
        #expect(AppStore.inLanguage(.cmn) { hot.walkWarnings } == ["山泥倾泻警告"])
        #expect(AppStore.inLanguage(.en) { hot.line }.contains("Landslip Warning"))
    }

    @Test func 普通话播报街坊行唔读háng() {
        #expect(Speaker.pronounced("欢迎来到街坊行", language: .mandarin) == "欢迎来到街坊形")
        #expect(Speaker.pronounced("歡迎嚟到街坊行", language: .cantonese) == "歡迎嚟到街坊行")
    }

    @Test func 散步例句有四句_反映提示唔写人数() {
        let s = AppStore()
        s.restoring = true
        s.clockTask?.cancel()
        s.residents = [Resident(id: "me", name: "你", floor: 12, colorIndex: 6, mobility: .walk, streakDays: 1, todayLine: "", isMe: true)]
        s.walk = WalkSession(start: Date())
        #expect(s.suggestedPhrases.count == 4)
        #expect(s.suggestedPhrases.contains("呢度難行"))
        #expect(!s.reportNote.contains("10"))
    }
}
