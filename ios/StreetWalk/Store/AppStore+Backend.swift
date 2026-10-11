import SwiftUI
import UIKit
import BackgroundTasks
@preconcurrency import UserNotifications

// 真后端接线（关咗演示模式时）：换 CommunityService、网名、碰一碰配上后加街坊、收街坊事件、后台刷新、本地通知。
// 演示模式照用 LocalCommunityService（示範街坊），演示脚本、演示视频唔受影响。
extension AppStore {
    /// 真后端（演示模式时 nil）。
    var supabase: SupabaseCommunityService? { community as? SupabaseCommunityService }
    /// 界面「未連線」：用紧真后端，而上一次请求因为冇网络 / 服务器暂时唔得而失败。
    var backendOffline: Bool { supabase?.isOffline ?? false }

    private static var launchArgsApplied = false

    /// 按演示模式揀 CommunityService：演示 → 示範街坊；真 → Supabase。启动时、设置里开关演示模式时调。
    func installCommunity() {
        if !Self.launchArgsApplied {
            Self.launchArgsApplied = true
            if LaunchArgs.has("-resetOnboarding") { nickname = "" }
            // 开发用：自动脚本 / 两部模拟器测试时直接填网名
            if let n = LaunchArgs.value("-debugNickname").flatMap(CommunityProfile.cleanNickname) { nickname = n }
        }
        if demoMode {
            if let s = supabase {
                s.deactivate()
                s.onEvent = nil
                s.profileProvider = nil
            }
            if let l = localCommunity { l.demoEnabled = true } else { community = LocalCommunityService(demoEnabled: true) }
            community.onEvent = { [weak self] e in self?.receive(e) }
        } else {
            localCommunity?.onEvent = nil
            let s = SupabaseCommunityService.shared
            community = s
            s.profileProvider = { [weak self] in self?.communityProfile() }
            s.onEvent = { [weak self] e in self?.receive(e) }
            s.activate()
            // 上次闪退 / 散步途中被收咗：服务器可能仲当我出咗门
            if walk == nil { s.publishOuting(landmarkID: nil) }
        }
        startDebugCommandsIfNeeded()
    }

    // MARK: - 网名

    /// 真后端要有网名先上得排行榜（旧用户升级后补填）。
    var needsNickname: Bool { !demoMode && phase == .main && CommunityProfile.cleanNickname(nickname) == nil }

    /// 网名建议（一撳就用）：唔使打字，亦唔使用真名。
    var nicknameSuggestions: [String] {
        var s = ["\(Palette.name(colorChoice).replacingOccurrences(of: "色", with: ""))衫街坊", "行路友", "早晨街坊", "慢慢行"]
        if let p = (map ?? fullMap)?.placeName, !p.isEmpty, p.count <= 5 { s.insert("\(p)街坊", at: 1) }
        return s.filter { CommunityProfile.cleanNickname($0) != nil }
    }

    /// 改网名（首次使用、设置页）。唔啱规则（空、超过 20 字）返回 false。
    @discardableResult
    func setNickname(_ s: String) -> Bool {
        guard let n = CommunityProfile.cleanNickname(s) else { return false }
        nickname = n
        if let i = residents.firstIndex(where: \.isMe) { residents[i].nickname = n }
        if phase == .main { uploadProfile() }
        return true
    }

    /// 上传嘅个人资料。未完成首次使用、冇网名、未知屋企格子 → nil（唔上传、唔登录）。
    func communityProfile() -> CommunityProfile? {
        // 地图未装好：未知座数（唔好用空值盖过服务器上嘅）
        guard phase == .main, map != nil, let nick = CommunityProfile.cleanNickname(nickname) else { return nil }
        let d = UserDefaults.standard
        guard d.bool(forKey: "onboarded") || LaunchArgs.has("-skipOnboarding") else { return nil }
        let saved: TileKey? = d.string(forKey: "homeTile").flatMap { s in
            let p = s.split(separator: ",").compactMap { Int($0) }
            return p.count == 2 ? TileKey(ix: p[0], iy: p[1]) : nil
        }
        guard let tile = saved ?? fullMap?.tile ?? map?.tile else { return nil }
        let streak = myStreak()
        let log = walkLog, leaves = leaveDays, demo = demoMode
        let day = BackendMapping.streakDay(today: now, streak: streak,
                                           walkedOrLeave: { k in (log[k].map { $0.walks > 0 && (demo || !$0.demo) } ?? false) || leaves.contains(k) },
                                           leave: { leaves.contains($0) })
        let block = residents.first(where: \.isMe)?.blockShort
        return CommunityProfile(nickname: nick, mobility: mobilityChoice, colorIndex: colorChoice, skinTone: skinChoice, ageGroup: ageChoice,
                                tileX: tile.ix, tileY: tile.iy, communityName: (map ?? fullMap)?.placeName, block: block == "示意樓" ? nil : block,
                                floor: floorChoice, streak: streak, streakDay: day)
    }

    // MARK: - 前台 / 后台

    /// AppStore.appActive 调：真后端前台开 Realtime、补拉；退后台断线、排后台刷新。
    func backendAppActive(_ active: Bool) {
        guard let s = supabase else { return }
        s.setForeground(active)
        if active {
            uploadProfile()
            runDebugLinkIfNeeded()
        } else {
            BackgroundRefresh.schedule()
        }
    }

    /// 后台刷新：BGAppRefreshTask（StreetWalkApp 的 .backgroundTask）同定位模块喺后台被叫醒时调。
    /// 送出排队嘅写入、拉一次街坊出门 / 约会 / 找人询问；有新嘢就出本地通知（尊重「出門提醒」开关同接收时段）。
    /// 60 秒内重复叫只做一次；演示模式唔做嘢。
    func backgroundRefresh() async {
        guard let s = supabase else { return }
        Self.debugEvent("backgroundRefresh start (background=\(isInBackground))")
        uploadProfile()
        await s.backgroundRefresh()
        BackgroundRefresh.schedule()
        Self.debugEvent("backgroundRefresh done")
    }

    // MARK: - 碰一碰配上（碰一碰模块 / 二维码 / -debugLinkCode 调）

    /// 服务器已经配上（NeighborLinker.link 返回对方）：加入圈、标做街坊，然后照碰一碰流程讲「你同〈網名〉而家係街坊」、问开唔开出门提醒。
    func addLinkedNeighbor(_ peer: LinkedPeer) {
        var r = BackendMapping.resident(peer)
        if let i = residents.firstIndex(where: { $0.id == peer.id }) {
            r.streakDays = residents[i].streakDays
            r.todayLine = residents[i].todayLine
            r.isOut = residents[i].isOut
            r.atLandmarkID = residents[i].atLandmarkID
            residents[i] = r
        } else {
            residents.append(r)
        }
        tab = .neighbors
        bumpStage = .found(peer.id)
        Haptics.success()
        say("你同\(peer.nickname)而家係街坊。")
        syncScene()
        if map != nil { scene.setCamera(target: bumpMeetSpot(), distance: scene.overviewDistance * 0.7, animated: true, duration: 1.0) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard self.bumpStage == .found(peer.id) else { return }
            self.remindPromptFor = peer.id
            self.say("開唔開出門提醒？開咗之後，佢出門你會知，你出門佢都會知。", prompt: true)
        }
    }

    private static var debugLinkStarted = false

    /// 开发用：两部模拟器用同一个 `-debugLinkCode <码>` 启动，就当碰咗一碰（唔使超宽带）。每 2 秒试一次，试 60 秒。
    func runDebugLinkIfNeeded() {
        guard let code = LaunchArgs.value("-debugLinkCode"), !Self.debugLinkStarted else { return }
        Self.debugLinkStarted = true
        debugLink(code: code)
    }

    /// 用一次性码配对（同碰一碰模块交俾 NeighborLinker 嘅码一样），配上就 addLinkedNeighbor。
    func debugLink(code: String) {
        guard let s = supabase else { print("[debugLink] 演示模式冇真后端"); return }
        Task { @MainActor in
            while self.phase != .main || self.map == nil || self.residents.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
            for _ in 0..<30 {
                do {
                    if let peer = try await s.link(code: code) {
                        print("[debugLink] 配上 \(peer.nickname) \(peer.id)")
                        self.addLinkedNeighbor(peer)
                        return
                    }
                } catch {
                    print("[debugLink] \(error)")
                }
                try? await Task.sleep(for: .seconds(2))
            }
            print("[debugLink] 60 秒都配唔上")
        }
    }

    // MARK: - 街坊事件（真后端追加嘅）

    /// 有人约我：已经有同一个约会（例如重连后再收到）就当改约，唔会出两张。
    func receiveInvite(_ a: Appointment) {
        if appointments.contains(where: { $0.id == a.id }) { meetupChangedByPartner(a); return }
        let before = appointments.count
        invitedBy(a)
        guard appointments.count > before, let p = resident(a.partnerID) else { return }
        notifyIfBackground(id: "invite-\(a.id.uuidString)", body: "\(p.name)約你\(dayTimeLabel(a.date))喺\(placeName(a.landmarkID) ?? "附近")一齊行。")
    }

    func receiveBackend(_ e: CommunityEvent) {
        switch e {
        case .membersChanged:
            // 首次使用途中唔郁（选楼画面嘅地图唔系屋企底座）
            if phase == .main, map != nil { populate() }
        case .meetupChanged(let a): meetupChangedByPartner(a)
        case .meetupCancelled(let id): meetupCancelledByPartner(id)
        case .findAsked(let ask): incomingFindAsk(ask)
        case .findAskCancelled(let askID):
            guard let ask = incomingFind, ask.askID == askID else { return }
            incomingFind = nil
            toast("\(resident(ask.fromID)?.name ?? "街坊")今次唔過嚟喇。")
        case .findAskUnanswered(let id, let offline):
            guard let f = find, f.partnerID == id, f.stage == .asking, !partnerAgreed else { return }
            let name = resident(id)?.name ?? "街坊"
            toast(offline ? "未連線，問唔到\(name)。遲啲再試。" : "\(name)暫時冇回覆，可能冇開 App。")
            endFind()
        case .partnerSaid(let id, let text):
            guard let p = resident(id), p.isNeighbor else { return }
            let line = "\(p.name)：\(text)"
            showBanner(BannerItem(symbol: "text.bubble.fill", text: line))
            say(line)
        case .partnerTrip(let mid, let id, let trip, let ended):
            partnerTripWithoutFind(mid, partnerID: id, trip: trip, ended: ended)
        default:
            break
        }
    }

    /// 对方改咗时间地点：变返「等我確認」（約你嘅），横幅讲清楚改咗乜。
    func meetupChangedByPartner(_ a: Appointment) {
        guard let p = resident(a.partnerID), p.isNeighbor else { return }
        guard let i = appointments.firstIndex(where: { $0.id == a.id }) else {
            var n = a
            n.fromPartner = true
            invitedBy(n)
            return
        }
        appointments[i].date = a.date
        appointments[i].landmarkID = a.landmarkID
        appointments[i].reason = a.reason
        appointments[i].status = .waiting
        appointments[i].fromPartner = true
        appointments[i].reminded = false
        appointments[i].lateAsked = nil
        let text = "\(p.name)想改做\(dayTimeLabel(a.date))，喺\(placeName(a.landmarkID) ?? "附近")。"
        showBanner(BannerItem(symbol: "calendar.badge.clock", text: text, action: .openNeighbors, actionTitle: "睇吓"))
        say(text)
        notifyIfBackground(id: "meetup-\(a.id.uuidString)", body: text)
    }

    func meetupCancelledByPartner(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].isOpen else { return }
        appointments[i].status = .cancelled
        let a = appointments[i]
        let name = resident(a.partnerID)?.name ?? "街坊"
        if findAppointment == id { endFind() }
        if proposal?.editing == id { cancelProposal() }
        let text = "\(name)取消咗\(dayTimeLabel(a.date))嘅約。"
        showBanner(BannerItem(symbol: "calendar.badge.minus", text: text))
        say(text)
        notifyIfBackground(id: "meetup-\(id.uuidString)", body: text)
    }

    /// 约会当日对方出咗门 / 到咗（我未撳「出發」）：横幅话我知，可以即刻出发。
    private func partnerTripWithoutFind(_ id: UUID, partnerID: String, trip: PartnerTrip, ended: Bool) {
        guard let a = appointments.first(where: { $0.id == id }), let p = resident(partnerID), p.isNeighbor else { return }
        let place = placeName(a.landmarkID) ?? "約好嘅地方"
        if ended {
            if findAppointment == id || a.isOpen { toast("\(p.name)今次冇過去\(place)。") }
            return
        }
        guard findAppointment != id, a.status == .accepted else { return }
        let text = trip.arrived ? "\(p.name)已經到咗\(place)。"
            : "\(p.name)出咗門去\(place)\(trip.etaMinutes.map { "，大約 \($0) 分鐘到" } ?? "")。"
        showBanner(BannerItem(symbol: "figure.walk", text: text, action: .depart(id), actionTitle: "出發"))
        say(text)
        notifyIfBackground(id: "trip-\(id.uuidString)", body: text)
    }

    // MARK: - F8 收到「想過嚟搵你，方唔方便？」

    func incomingFindAsk(_ ask: IncomingFindAsk) {
        guard let p = resident(ask.fromID), p.isNeighbor else { return }
        incomingFind = ask
        let q = "\(p.name)想過嚟搵你，方唔方便？"
        say(q, prompt: true)
        Haptics.warning()
        notifyIfBackground(id: "find-\(ask.askID)", body: "\(q)打開 App 答佢。")
        // 對方等 2 分鐘就當冇回覆：張卡都收埋
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(SupabaseCommunityService.askTimeout))
            if self.incomingFind?.askID == ask.askID { self.incomingFind = nil }
        }
    }

    /// 撳「好」/「唔方便」。
    func answerIncomingFind(_ accepted: Bool) {
        guard let ask = incomingFind else { return }
        incomingFind = nil
        community.answerFindAsk(ask, accepted: accepted)
        let name = resident(ask.fromID)?.name ?? "街坊"
        if accepted && canShareLive(with: ask.fromID) {
            beginIncomingLiveFind(ask)
            say("好，話咗俾\(name)知。而家同\(name)分享緊位置，佢會過嚟搵你。")
            Haptics.success()
        } else if accepted {
            say("好，話咗俾\(name)知。佢會過嚟\(placeName(ask.landmarkID).map { "\($0)附近" } ?? "")搵你。")
            Haptics.success()
        } else {
            say("冇問題，話咗俾\(name)知你而家唔方便。")
            Haptics.light()
        }
    }

    // MARK: - 地标名（真后端：对方喺我底座外面嘅地标只有名，冇位置）

    /// 地标名：本机地标，或者只有名嘅（对方喺我地图外面）。
    func placeName(_ id: String?) -> String? { landmark(id)?.name ?? LandmarkIndex.syntheticName(id) }

    // MARK: - 本地通知（App 喺后台时；前台用横幅）

    func notifyNeighborOut(_ id: String) {
        guard isInBackground, let r = resident(id), r.isNeighbor, r.isOut, r.receiveRemind, remindAll, inRemindWindow else { return }
        notifyIfBackground(id: "out-\(id)", body: "\(r.name)啱啱出門，喺\(placeName(r.atLandmarkID) ?? "附近")附近。")
    }

    func notifyIfBackground(id: String, body: String) {
        guard isInBackground else { return }
        Self.debugEvent("notify \(body)")
        let c = UNMutableNotificationContent()
        c.title = "街坊行"
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    // MARK: - 清除纪录

    /// 设置「清除我嘅紀錄」：真后端时连服务器上嘅资料一齐删（冇网络就话俾用户知）。之后用新身份重新上传资料。
    func clearServerData() {
        guard let s = supabase else { return }
        Task { @MainActor in
            let ok = await s.deleteMyServerData()
            self.toast(ok ? "伺服器上你嘅資料都刪咗。" : "未連線，伺服器上嘅資料未刪到。連返網之後再撳一次。")
            if ok { self.populate(); self.uploadProfile() }
        }
    }
}

/// BGAppRefreshTask（Info.plist 已声明 hk.hack4sdg.streetwalk.refresh；StreetWalkApp 用 .backgroundTask 登记处理）。
enum BackgroundRefresh {
    static let taskID = "hk.hack4sdg.streetwalk.refresh"

    /// 退后台时排下一次（系统决定几时叫，最早 15 分钟后）。
    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: taskID)
        r.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}
