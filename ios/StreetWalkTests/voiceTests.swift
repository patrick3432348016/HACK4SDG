import Foundation
import Testing
@testable import StreetWalk

// 语音与社交流程：改名复述、非街坊保护、播送、反映、找人、约会日子、迟到询问、播报排队（对应审核 A02–A90）。

@MainActor
struct VoiceFlowTests {
    let lms = [Landmark(id: "shelter-1", name: "涼亭", kind: .shelter, pos: .zero, hasSeat: true),
               Landmark(id: "park-0", name: "公園櫈仔", kind: .park, pos: Vec2(x: 40, y: 0), hasSeat: true)]
    let me = Resident(id: "me", name: "你", floor: 12, colorIndex: 6, mobility: .walk, streakDays: 1, todayLine: "", isMe: true)
    var chan: Resident { var r = Resident(id: "chan", name: "陳太", floor: 8, colorIndex: 0, mobility: .walk, streakDays: 3, todayLine: "8 樓喺涼亭坐咗陣"); r.isNeighbor = true; return r }
    let wong = Resident(id: "wong", name: "黃太", floor: 3, colorIndex: 1, mobility: .walk, streakDays: 30, todayLine: "")

    /// 测试用的 store：唔写盘、唔跑定时器、唔用读屏公告。
    func makeStore(_ people: [Resident]? = nil) -> AppStore {
        let s = AppStore()
        s.restoring = true
        s.clockTask?.cancel()
        s.announcer.voiceOverRunning = { false }
        s.demoHour = 10
        s.landmarks = lms
        s.residents = people ?? [chan, wong, me]
        s.appointments = []
        s.reports = []
        return s
    }

    @Test func 语音改名要复述再撳好() {
        let s = makeStore()
        s.handle("涼亭改名做大樹底")
        #expect(s.voiceCard?.needsConfirm == true)
        #expect(s.landmark("shelter-1")?.name == "涼亭", "未撳「好」唔改")
        s.confirmVoice()
        #expect(s.landmark("shelter-1")?.name == "大樹底")
    }

    @Test func 改名中只讲新名() {
        let s = makeStore()
        s.select(.landmark("shelter-1"))
        s.renaming = "shelter-1"
        s.handle("大樹底")
        #expect(s.voiceCard?.intent == .rename(landmarkID: "shelter-1", newName: "大樹底"))
        #expect(s.voiceCard?.needsConfirm == true)
        s.rejectVoice()
        #expect(s.landmark("shelter-1")?.name == "涼亭")
        #expect(AppStore.spokenName("改名做「大樹底」。") == "大樹底")
        #expect(AppStore.spokenName("呢個名真係好長好長好長好長好長") == nil)
    }

    @Test func 改名后每日一句用新名() {
        let s = makeStore()
        s.rename("shelter-1", to: "大樹底")
        #expect(s.resident("chan")?.todayLine == "8 樓喺大樹底坐咗陣")
    }

    @Test func 讲非街坊个名唔会讲出楼层() {
        let s = makeStore()
        s.handle("約黃太聽日行")
        #expect(s.voiceCard == nil)
        #expect(!(s.toast ?? "").contains("3 樓"))
        #expect(s.phrasePicker, "当听唔明")
    }

    @Test func 播送讲乜就播乜() {
        let s = makeStore()
        s.find = FindSession(partnerID: "chan", landmarkID: "shelter-1", spontaneous: false, stage: .going)
        s.handle("我喺巴士站。")
        #expect(s.voiceCard?.detail == "我喺巴士站")
        s.confirmVoice()
        #expect(s.find?.broadcast == "我喺巴士站")
        s.find = FindSession(partnerID: "chan", landmarkID: "shelter-1", spontaneous: true, stage: .going)
        s.broadcastHere()
        #expect(s.find?.broadcast == "我就到涼亭", "临时找人个掣写「我就到」，就唔好播「我喺」")
    }

    @Test func 非街坊出门唔记唔讲() {
        let s = makeStore()
        s.neighborWentOut("wong", at: "shelter-1")
        #expect(s.resident("wong")?.isOut == false)
        #expect(s.resident("wong")?.atLandmarkID == nil)
        #expect(s.toast == nil)
    }

    @Test func 唔散步唔收反映_撤回认准嗰条() {
        let s = makeStore()
        #expect(!s.suggestedPhrases.contains("呢度好曬"))
        s.handle("呢度好曬")
        #expect(s.reports.isEmpty)
        s.walk = WalkSession(start: Date())
        s.handle("呢度冇櫈")
        let rid = s.voiceCard?.reportID
        #expect(rid != nil && rid == s.reports.first?.id)
        #expect(s.reports.first?.rawText == "呢度冇櫈")
        s.report(.sunny)
        s.rejectVoice()
        #expect(s.reports.map(\.kind) == [.sunny], "撤回语音嗰条，唔系最后一条")
    }

    @Test func 日子标签按日差() {
        let s = makeStore()
        let d = AppStore.today(at: 16)
        #expect(s.dayTimeLabel(d.addingTimeInterval(-86400)).hasPrefix("琴日"))
        #expect(s.dayTimeLabel(d).hasPrefix("今日"))
        #expect(s.dayTimeLabel(d.addingTimeInterval(86400)).hasPrefix("聽日"))
        #expect(s.dayTimeLabel(d.addingTimeInterval(2 * 86400)).hasPrefix("後日"))
        let far = s.dayTimeLabel(d.addingTimeInterval(3 * 86400))
        #expect(far.contains("月") && far.contains("星期") && !far.contains("後日"))
    }

    @Test func 改约建议唔同钟_冇变就照舊() {
        let s = makeStore()
        let a = Appointment(partnerID: "chan", date: AppStore.today(at: 16), landmarkID: "shelter-1", reason: "", status: .accepted)
        s.appointments = [a]
        #expect(s.suggestedPhrases.first == "改做下晝五點")
        s.handle("改做下晝四點")
        #expect(s.voiceCard == nil)
        s.changeMeetup(a.id, day: nil, hour: 16, landmarkID: nil)
        #expect(s.appointments[0].status == .accepted, "冇变唔好打返做等緊確認")
    }

    @Test func 碰一碰讲清楚点解碰唔到() {
        let s = makeStore([me])
        s.startBump()
        #expect(s.bumpStage == .idle)
        #expect(s.toast?.contains("只有你") == true)
        let t = makeStore([chan, me])
        t.startBump()
        #expect(t.toast?.contains("都已經係你街坊") == true)
    }

    @Test func 迟到十分钟只问一次() {
        let s = makeStore()
        s.demoHour = 16 + 11.0 / 60
        let a = Appointment(partnerID: "chan", date: AppStore.today(at: 16), landmarkID: "shelter-1", reason: "", status: .accepted)
        s.appointments = [a]
        s.findAppointment = a.id
        var f = FindSession(partnerID: "chan", landmarkID: "shelter-1", spontaneous: false, stage: .going)
        s.checkLate(&f)
        #expect(f.latePrompt)
        #expect(s.appointments[0].lateAsked == true)
        f.latePrompt = false
        s.checkLate(&f)
        #expect(!f.latePrompt)

        // 冇喺找人画面：横幅问要唔要打电话
        let t = makeStore()
        t.demoHour = 16 + 12.0 / 60
        t.appointments = [Appointment(partnerID: "chan", date: AppStore.today(at: 16), landmarkID: "shelter-1", reason: "", status: .accepted)]
        t.checkAppointments()
        #expect(t.banner?.action == .call("chan"))
        #expect(t.appointments[0].status == .accepted)
    }

    @Test func 约会到达估计按对方剩低嘅路() {
        let s = makeStore()
        s.findRoute = [Vec2(x: 0, y: 0), Vec2(x: 0, y: 700)]
        s.partnerRoute = [Vec2(x: 20, y: 0)]
        var f = FindSession(partnerID: "chan", landmarkID: "shelter-1", spontaneous: false, stage: .going, partnerOut: false)
        s.tickFind(&f, 0.01)
        #expect(f.etaMinutes == 0 && s.partnerTravelled == 0, "未出门唔郁、唔讲几耐到")
        #expect(f.stage == .going, "未出门唔会「喺附近」")
        s.partnerRoute = [Vec2(x: 20, y: 0), Vec2(x: 20, y: 300)]
        f.partnerOut = true
        s.tickFind(&f, 0.01)
        #expect(f.etaMinutes == 5, "按对方 300 米路计，唔系同我嘅直线距离")
    }

    @Test func 旧嘅找人回覆唔会落到新一次() {
        let s = makeStore()
        s.find = FindSession(partnerID: "chan", landmarkID: "shelter-1", spontaneous: true, stage: .asking)
        s.findAnswered(token: UUID(), accepted: true)
        #expect(!s.partnerAgreed)
        s.findAnswered(token: s.find!.token, accepted: true)
        #expect(s.partnerAgreed)
    }

    @Test func 聆听中播报先收起() {
        let s = makeStore()
        s.listening = true
        s.say("陳太應承咗")
        #expect(s.speaker.lastSpoken != "陳太應承咗")
        #expect(s.announcer.release().map(\.text) == ["陳太應承咗"])
    }

    @Test func 撳咗改名再去约人或找人_讲嘢唔会当新名() {
        let s = makeStore()
        s.select(.landmark("shelter-1"))
        s.renaming = "shelter-1"
        #expect(s.renamingNow == "shelter-1")
        // 冇撳「唔改喇」就去找人：找人画面盖住改名卡
        s.find = FindSession(partnerID: "chan", landmarkID: "shelter-1", spontaneous: false, stage: .going)
        #expect(s.renamingNow == nil)
        #expect(s.suggestedPhrases == ["我喺涼亭"])
        s.handle("我喺涼亭")
        #expect(s.voiceCard?.intent == .broadcast("我喺涼亭"))
        s.voiceCard = nil
        s.find = nil
        // 约人卡盖住都一样
        s.renaming = "shelter-1"
        s.proposal = Proposal(partnerID: "chan", options: [MeetProposal(date: AppStore.today(at: 16), landmarkID: "park-0", reason: "")], index: 0)
        #expect(s.renamingNow == nil)
        #expect(!s.suggestedPhrases.contains("大樹底"))
    }

    @Test func 改名只换完整地标名() {
        let names = ["涼亭", "車站涼亭", "公園"]
        #expect(AppStore.renamed("8 樓今日經過車站涼亭同涼亭", names: names, old: "涼亭", new: "大樹底") == "8 樓今日經過車站涼亭同大樹底")
        #expect(AppStore.renamed("3 樓喺車站涼亭坐咗陣", names: names, old: "車站涼亭", new: "總站") == "3 樓喺總站坐咗陣")
        #expect(AppStore.renamed("8 樓今日行到公園", names: names, old: "涼亭", new: "大樹底") == "8 樓今日行到公園")
    }

    @Test func 约会对方未出门唔入场景_出咗门先入() {
        let s = makeStore()
        s.findRoute = [Vec2(x: 0, y: 0), Vec2(x: 0, y: 4)]
        s.partnerRoute = [Vec2(x: 20, y: 0)]
        let f = FindSession(partnerID: "chan", landmarkID: "shelter-1", spontaneous: false, stage: .going, partnerOut: false)
        s.find = f
        s.syncScene()
        #expect(s.scene.personPosition("chan") == nil, "等緊佢出門：场景冇佢")
        #expect(s.scene.personPosition("me") != nil)
        // 我已经行到约定地方：对方未出门唔会「見到」
        var g = f
        s.tickFind(&g, 10)
        #expect(g.stage == .going)
        // 收到出门通知：先入场景、开始讲几耐到
        s.partnerUpdate(token: f.token, trip: PartnerTrip(etaMinutes: nil))
        #expect(s.find?.partnerOut == true)
        #expect(s.scene.personPosition("chan") != nil)
        // 后端报到咗：几耐到 = 0
        s.partnerUpdate(token: f.token, trip: PartnerTrip(etaMinutes: nil, arrived: true))
        #expect(s.find?.etaMinutes == 0)
        #expect(s.partnerTravelled == s.pathLength(s.partnerRoute ?? []))
        // 旧一次嘅通知唔理
        s.partnerUpdate(token: UUID(), trip: PartnerTrip(etaMinutes: 9))
        #expect(s.find?.etaMinutes == 0)
    }

    @Test func 播报过期唔讲_要回应嘅优先() {
        let s = makeStore()
        var t = Date()
        s.announcer.clock = { t }
        s.announcer.busy = { true }   // 当成讲紧一句长嘢
        s.say("資訊一")
        s.say("資訊二")
        #expect(s.announcer.queued.map(\.text) == ["資訊一", "資訊二"])
        // 复述确认：清走排喺前面嘅资讯句
        s.say("約陳太聽日三點。啱就撳「好」。", prompt: true)
        #expect(s.announcer.queued.map(\.text) == ["約陳太聽日三點。啱就撳「好」。"])
        // 排满都唔会挤走要回应嘅句子
        s.say("資訊三"); s.say("資訊四"); s.say("資訊五")
        #expect(s.announcer.queued.count == Announcer.maxQueued)
        #expect(s.announcer.queued.first?.kind == .prompt)
        // 停咪后交返嘅句子：排咗超过 6 秒嘅资讯句唔讲
        s.listening = true
        s.say("舊資訊")
        let held = s.announcer.release()
        t = t.addingTimeInterval(7)
        s.listening = false
        s.flushHeldSpeech(held)
        #expect(!s.announcer.queued.map(\.text).contains("舊資訊"))
        s.announcer.hold(s.speaker)   // 停咗排队循环
    }

    @Test func 播报关咗唔自动读_再听一次照读() {
        let s = makeStore()
        let suite = "voice-off-\(UUID())"
        let v = VoiceSettings(defaults: UserDefaults(suiteName: suite)!, scanner: { [] }, watch: false)
        s.speaker.settings = v
        s.announcer.busy = { false }   // 当成合成器得闲，每句即刻讲
        v.enabled = false
        s.say("陳太出咗門")
        #expect(s.speaker.lastSpoken != "陳太出咗門", "关咗唔自动读")
        s.sayAgain("再聽一次呢句")
        #expect(s.speaker.lastSpoken == "再聽一次呢句", "亲手撳「再聽一次」照读")
        s.announcer.hold(s.speaker)
        v.enabled = true
        s.say("開返就讀")
        #expect(s.speaker.lastSpoken == "開返就讀")
        s.announcer.hold(s.speaker)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func 未接伺服器唔讲同圈见到() {
        let s = makeStore()
        #expect(s.renameNote.contains("同圈"))
        s.localCommunity?.demoEnabled = false
        #expect(s.renameNote.contains("你部手機"))
        #expect(s.reportNote.contains("你部手機"))
    }

    @Test func 天气提示只得一句() {
        let tip = AppStore.oneSentence(["天文台話打鼓嶺而家 34 度。", "今日好熱。涼亭下晝 3 點後有樓遮住，嗰陣先出門啱啲。"])
        #expect(tip.filter { $0 == "。" }.count == 1)
        #expect(tip.hasSuffix("。"))
    }
}

@MainActor
struct CommunityFindTests {
    let lms = [Landmark(id: "a", name: "涼亭", kind: .shelter, pos: .zero, hasSeat: true)]

    @Test func 取消咗嘅询问唔会答() async {
        let c = LocalCommunityService(demoEnabled: true)
        c.declineNext = true
        var answered = false
        c.askToFind(partnerID: "chan", landmarkID: "a") { _ in answered = true }
        c.cancelFindAsk(partnerID: "chan")
        try? await Task.sleep(for: .seconds(2.7))
        #expect(!answered)
        #expect(c.declineNext, "冇答就唔好用咗「唔方便」")
    }

    @Test func 重启后等圈装好先回覆() async {
        let c = LocalCommunityService(demoEnabled: true)
        var events = 0
        c.onEvent = { _ in events += 1 }
        c.resume([Appointment(partnerID: "chan", date: Date().addingTimeInterval(3600), landmarkID: "a", reason: "", status: .waiting)])
        try? await Task.sleep(for: .seconds(3.3))
        #expect(events == 0)
        _ = c.circleMembers(blocks: [], landmarks: lms)
        try? await Task.sleep(for: .seconds(3.3))
        #expect(events == 1)
    }
}
