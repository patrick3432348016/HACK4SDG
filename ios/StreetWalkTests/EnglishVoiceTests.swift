import Foundation
import Testing
@testable import StreetWalk

// 英文界面：连唔到 Mac 语音服务器时，手机自己认英文句子（TemplateAI → EnglishText）。
// 唔改全局语言（测试固定粤语）：英文解析睇句子本身係唔係英文。
struct EnglishVoiceTests {
    let ai = TemplateAI()
    let chan = { var r = Resident(id: "chan", name: "陳太", floor: 8, colorIndex: 0, mobility: .walk, streakDays: 3, todayLine: ""); r.isNeighbor = true; r.isOut = true; return r }()
    let ming = { var r = Resident(id: "u-1234", name: "阿明", floor: 15, colorIndex: 1, mobility: .walk, streakDays: 3, todayLine: ""); r.isNeighbor = true; return r }()
    let me = Resident(id: "me", name: "你", floor: 12, colorIndex: 6, mobility: .walk, streakDays: 1, todayLine: "", isMe: true)
    let lms = [Landmark(id: "shelter-1", name: "涼亭", kind: .shelter, pos: .zero, hasSeat: true)]
    func ctx(finding: Bool = false) -> AIContext { AIContext(residents: [chan, ming, me], landmarks: lms, now: Date(), walking: true, finding: finding) }

    @Test func 认得英文() {
        #expect(EnglishText.isEnglish("Invite Mrs Chan tomorrow"))
        #expect(EnglishText.isEnglish("Invite 陳太 tomorrow at 3 pm"))
        #expect(!EnglishText.isEnglish("約陳太聽日下晝三點"))
    }

    @Test func 约人同钟点() {
        #expect(ai.parseVoice("Invite Mrs Chan tomorrow at 3:15 pm for 40 minutes", context: ctx()) == .invite(partnerID: "chan", day: 1, hour: 15))
        #expect(TemplateAI.parseClock("Invite Mrs Chan tomorrow at 3:15 pm for 40 minutes")! == (15, 15))
        #expect(TemplateAI.parseDuration("Invite Mrs Chan tomorrow at 3:15 pm for 40 minutes") == 40)
        #expect(ai.parseVoice("Walk with Ah Ming at half past two", context: ctx()) == .invite(partnerID: "u-1234", day: 0, hour: 14))
        #expect(TemplateAI.parseClock("walk with Ah Ming at half past two")! == (14, 30))
        #expect(ai.parseVoice("invite 陳太 the day after tomorrow in the morning", context: ctx()) == .invite(partnerID: "chan", day: 2, hour: 8))
        #expect(ai.parseVoice("Go for a walk with the 8th floor tomorrow at 4", context: ctx()) == .invite(partnerID: "chan", day: 1, hour: 16))
        #expect(ai.parseVoice("invite a neighbour tomorrow", context: ctx()) == .invite(partnerID: "chan", day: 1, hour: nil))
        #expect(TemplateAI.parseClock("quarter to five")! == (16, 45))
        #expect(TemplateAI.parseClock("at three fifteen")! == (15, 15))
        #expect(TemplateAI.parseClock("tomorrow 8 am")! == (8, 0))
        #expect(TemplateAI.parseClock("at 11 pm") == nil, "夜晚唔约")
        #expect(TemplateAI.parseDuration("walk for an hour and a half") == 90)
        #expect(TemplateAI.parseDuration("half an hour") == 30)
        #expect(TemplateAI.parseDuration("at most 15 minutes") == nil)
        #expect(TemplateAI.parseDuration("20 minutes past 3") == nil)
    }

    @Test func 天气反映请假() {
        #expect(TemplateAI.asksWeather("What's the weather like today?"))
        #expect(TemplateAI.asksWeather("Will it be hot tomorrow?"))
        #expect(!TemplateAI.asksWeather("too sunny here"))
        #expect(ai.parseVoice("No seats here", context: ctx()) == .report(.noSeat))
        #expect(ai.parseVoice("Too sunny here", context: ctx()) == .report(.sunny))
        #expect(ai.parseVoice("The path is very bumpy", context: ctx()) == .report(.rough))
        #expect(ai.parseVoice("Day off tomorrow", context: ctx()) == .leave)
        #expect(ai.parseVoice("Take three days off", context: ctx()) == .leave)
        #expect(EnglishText.leaveText("day off tomorrow") == "聽日請假")
        #expect(EnglishText.leaveText("take three days off") == "請3日假")
        #expect(LeaveRequest.parse(EnglishText.leaveText("take three days off from tomorrow")) == LeaveRequest(startOffset: 1, days: 3))
        #expect(LeaveRequest.parse(EnglishText.leaveText("a week off")).days == 7)
    }

    @Test func 找人改约取消() {
        #expect(ai.parseVoice("Go find Mrs Chan", context: ctx()) == .goFind(partnerID: "chan"))
        #expect(ai.parseVoice("Find a neighbour", context: ctx()) == .goFind(partnerID: "chan"))
        #expect(ai.parseVoice("I'm at the pavilion", context: ctx(finding: true)) == .broadcast("I'm at the pavilion"))
        #expect(ai.parseVoice("Change it to 5 pm", context: ctx()) == .changeMeetup(partnerID: nil, day: nil, hour: 17, landmarkID: nil))
        #expect(ai.parseVoice("Move my walk with Mrs Chan to tomorrow", context: ctx()) == .changeMeetup(partnerID: "chan", day: 1, hour: nil, landmarkID: nil))
        #expect(ai.parseVoice("Move to 涼亭", context: ctx()) == .changeMeetup(partnerID: nil, day: nil, hour: nil, landmarkID: "shelter-1"))
        #expect(ai.parseVoice("Cancel the walk with Mrs Chan", context: ctx()) == .cancelMeetup(partnerID: "chan"))
        #expect(TemplateAI.spokenMinute("change it to 4:30 pm") == 30)
    }

    @Test func 确认卡yesNo() {
        for s in ["yes", "Yes.", "OK", "okay", "sure", "Sounds good", "yes please", "no problem"] { #expect(AppStore.yesNo(s) == .yes, "\(s)") }
        for s in ["no", "No thanks", "don't", "cancel", "not now", "no, don't", "not ok"] { #expect(AppStore.yesNo(s) == .no, "\(s)") }
        #expect(AppStore.yesNo("yes invite Mrs Chan tomorrow at three") == nil, "长句当新请求")
    }

    @Test func 求救同问药() {
        #expect(TemplateAI.safety("Help!") == .emergency)
        #expect(TemplateAI.safety("I fell and can't get up") == .emergency)
        #expect(TemplateAI.safety("help me invite Mrs Chan tomorrow") == nil)
        #expect(TemplateAI.safety("What medicine should I take?") == .medical)
        #expect(TemplateAI.safety("Should I see a doctor") == .medical)
        #expect(TemplateAI.safety("Is the pharmacy open") == nil)
    }

    @Test func 回声同重复字() {
        #expect(!AppStore.looksLikeEcho("yes", spoken: ["Walk with Mrs Chan. If that's right, say \"yes\" or tap Yes."]))
        #expect(AppStore.looksLikeEcho("say yes or tap yes", spoken: ["Walk with Mrs Chan. If that's right, say \"yes\" or tap Yes."]))
        #expect(!AppStore.looksLikeEcho("invite Mrs Chan tomorrow", spoken: ["Didn't catch that. Please say it again, or pick a sentence."]))
        #expect(Listener.collapseRepeats("invite invite Mrs Chan") == "invite Mrs Chan")
        #expect(Listener.collapseRepeats("I like banana") == "I like banana")
    }

    @Test func 播报三种语言都用服务器() {
        let server = URL(string: "http://192.168.1.10:8765")!
        #expect(TTSRoute.decide(language: .english, server: server, cached: nil, scripted: false, english: true) == .server(server))
        #expect(TTSRoute.decide(language: .english, server: server, cached: nil, scripted: false, english: false) == .system, "服务器冇英文声先用 iPhone")
        #expect(TTSRoute.decide(language: .mandarin, server: server, cached: nil, scripted: false, mandarin: true) == .server(server))
        #expect(AssistantLocale(rawValue: AppLang.en.locale) == .english)
        #expect(SpokenLanguage.english.bcp47 == "en-US")
        #expect(SpokenLanguage.pickable.contains(.english))
    }
}
