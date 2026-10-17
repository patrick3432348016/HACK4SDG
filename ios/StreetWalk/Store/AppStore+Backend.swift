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
        let c = Palette.name(colorChoice).replacingOccurrences(of: "色", with: "")
        var s = L.isEn ? ["Walking Buddy", "Morning Neighbour", "Slow Walker", "Happy Walker"]
            : L.isCmn ? ["\(c)衣邻居", "走路友", "早安邻居", "慢慢走"] : ["\(c)衫街坊", "行路友", "早晨街坊", "慢慢行"]
        if let p = (map ?? fullMap)?.placeName, !p.isEmpty, p.count <= 5 { s.insert(L.t("\(p)街坊", "\(p)邻居", "\(p) Neighbour"), at: 1) }
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
                                tileX: tile.ix, tileY: tile.iy, communityName: (map ?? fullMap)?.placeName, block: !shareHome || block == "示意樓" ? nil : block,
                                floor: shareHome ? floorChoice : nil, streak: streak, streakDay: day)
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
        say(L.t("你同\(peer.nickname)而家係街坊。", "你和\(peer.nickname)现在是邻居了。", "You and \(peer.nickname) are now neighbours."))
        syncScene()
        if map != nil { scene.setCamera(target: bumpMeetSpot(), distance: scene.overviewDistance * 0.7, animated: true, duration: 1.0) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard self.bumpStage == .found(peer.id) else { return }
            self.remindPromptFor = peer.id
            self.say(L.t("開唔開出門提醒？開咗之後，佢出門你會知，你出門佢都會知。", "要开出门提醒吗？开了之后，他出门你会知道，你出门他也会知道。", "Turn on out-and-about alerts? Then you'll know when they go out, and they'll know when you do."), prompt: true)
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
        notifyIfBackground(id: "invite-\(a.id.uuidString)", body: L.t("\(p.name)約你\(dayTimeLabel(a.date))喺\(placeName(a.landmarkID) ?? "附近")一齊行。", "\(p.name)约你\(dayTimeLabel(a.date))在\(placeName(a.landmarkID) ?? "附近")一起散步。", "\(p.name) invites you for a walk \(dayTimeLabel(a.date)) at \(placeName(a.landmarkID) ?? "a place nearby")."))
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
            toast(L.t("\(resident(ask.fromID)?.name ?? "街坊")今次唔過嚟喇。", "\(resident(ask.fromID)?.name ?? "邻居")这次不过来了。", "\(resident(ask.fromID)?.name ?? "Your neighbour") isn't coming over this time."))
        case .findAskUnanswered(let id, let offline):
            guard let f = find, f.partnerID == id, f.stage == .asking, !partnerAgreed else { return }
            let name = resident(id)?.name ?? L.t("街坊", "邻居", "your neighbour")
            toast(offline ? L.t("未連線，問唔到\(name)。遲啲再試。", "未联网，问不了\(name)。稍后再试。", "Offline, can't ask \(name). Try again later.") : L.t("\(name)暫時冇回覆，可能冇開 App。", "\(name)暂时没回复，可能没开 App。", "No reply from \(name) yet. They may not have the app open."))
            endFind()
        case .partnerSaid(let id, let text):
            guard let p = resident(id), p.isNeighbor else { return }
            let line = L.t("\(p.name)：\(text)", "\(p.name)：\(text)", "\(p.name): \(text)")
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
        let text = L.t("\(p.name)想改做\(dayTimeLabel(a.date))，喺\(placeName(a.landmarkID) ?? "附近")。", "\(p.name)想改成\(dayTimeLabel(a.date))，在\(placeName(a.landmarkID) ?? "附近")。", "\(p.name) wants to change it to \(dayTimeLabel(a.date)) at \(placeName(a.landmarkID) ?? "a place nearby").")
        showBanner(BannerItem(symbol: "calendar.badge.clock", text: text, action: .openNeighbors, actionTitle: L.t("睇吓", "看看", "Have a look")), reply: true)
        say(text)
        notifyIfBackground(id: "meetup-\(a.id.uuidString)", body: text)
    }

    func meetupCancelledByPartner(_ id: UUID) {
        guard let i = appointments.firstIndex(where: { $0.id == id }), appointments[i].isOpen else { return }
        appointments[i].status = .cancelled
        let a = appointments[i]
        let name = resident(a.partnerID)?.name ?? L.t("街坊", "邻居", "your neighbour")
        if findAppointment == id { endFind() }
        if proposal?.editing == id { cancelProposal() }
        let text = L.t("\(name)取消咗\(dayTimeLabel(a.date))嘅約。", "\(name)取消了\(dayTimeLabel(a.date))的约。", "\(name) cancelled the walk plan for \(dayTimeLabel(a.date)).")
        showBanner(BannerItem(symbol: "calendar.badge.minus", text: text))
        say(text)
        notifyIfBackground(id: "meetup-\(id.uuidString)", body: text)
    }

    /// 约会当日对方出咗门 / 到咗（我未撳「出發」）：横幅话我知，可以即刻出发。
    private func partnerTripWithoutFind(_ id: UUID, partnerID: String, trip: PartnerTrip, ended: Bool) {
        guard let a = appointments.first(where: { $0.id == id }), let p = resident(partnerID), p.isNeighbor else { return }
        let place = placeName(a.landmarkID) ?? L.t("約好嘅地方", "约好的地方", "the meeting place")
        if ended {
            if findAppointment == id || a.isOpen { toast(L.t("\(p.name)今次冇過去\(place)。", "\(p.name)这次没去\(place)。", "\(p.name) isn't going to \(place) this time.")) }
            return
        }
        guard findAppointment != id, a.status == .accepted else { return }
        let text = trip.arrived ? L.t("\(p.name)已經到咗\(place)。", "\(p.name)已经到了\(place)。", "\(p.name) has arrived at \(place).")
            : L.t("\(p.name)出咗門去\(place)\(trip.etaMinutes.map { "，大約 \($0) 分鐘到" } ?? "")。", "\(p.name)已出门去\(place)\(trip.etaMinutes.map { "，大约 \($0) 分钟到" } ?? "")。", "\(p.name) is on the way to \(place)\(trip.etaMinutes.map { ", about \($0) min away" } ?? "").")
        showBanner(BannerItem(symbol: "figure.walk", text: text, action: .depart(id), actionTitle: L.t("出發", "出发", "Set off")))
        say(text)
        notifyIfBackground(id: "trip-\(id.uuidString)", body: text)
    }

    // MARK: - F8 收到「想過嚟搵你，方唔方便？」

    func incomingFindAsk(_ ask: IncomingFindAsk) {
        guard let p = resident(ask.fromID), p.isNeighbor else { return }
        incomingFind = ask
        let q = L.t("\(p.name)想過嚟搵你，方唔方便？", "\(p.name)想过来找你，方便吗？", "\(p.name) wants to come and find you. Is that OK?")
        say(q, prompt: true)
        Haptics.warning()
        notifyIfBackground(id: "find-\(ask.askID)", body: L.t("\(q)打開 App 答佢。", "\(q)打开 App 回复他。", "\(q) Open the app to reply."))
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
        let name = resident(ask.fromID)?.name ?? L.t("街坊", "邻居", "your neighbour")
        if accepted && canShareLive(with: ask.fromID) {
            beginIncomingLiveFind(ask)
            say(L.t("好，話咗俾\(name)知。而家同\(name)分享緊位置，佢會過嚟搵你。", "好，已告诉\(name)。现在正和\(name)共享位置，他会过来找你。", "OK, told \(name). Sharing your location with \(name) now. They'll come and find you."))
            Haptics.success()
        } else if accepted {
            say(L.t("好，話咗俾\(name)知。佢會過嚟\(placeName(ask.landmarkID).map { "\($0)附近" } ?? "")搵你。", "好，已告诉\(name)。他会来\(placeName(ask.landmarkID).map { "\($0)附近" } ?? "")找你。", "OK, told \(name). They'll come and find you\(placeName(ask.landmarkID).map { " near \($0)" } ?? "")."))
            Haptics.success()
        } else {
            say(L.t("冇問題，話咗俾\(name)知你而家唔方便。", "没问题，已告诉\(name)你现在不方便。", "No problem. Told \(name) you can't right now."))
            Haptics.light()
        }
    }

    // MARK: - 地标名（真后端：对方喺我底座外面嘅地标只有名，冇位置）

    /// 地标名：本机地标，或者只有名嘅（对方喺我地图外面）。
    func placeName(_ id: String?) -> String? { landmark(id)?.name ?? LandmarkIndex.syntheticName(id) }

    // MARK: - 本地通知（App 喺后台时；前台用横幅）

    func notifyNeighborOut(_ id: String) {
        guard isInBackground, let r = resident(id), r.isNeighbor, r.isOut, r.receiveRemind, remindAll, inRemindWindow else { return }
        notifyIfBackground(id: "out-\(id)", body: L.t("\(r.name)啱啱出門，喺\(placeName(r.atLandmarkID) ?? "附近")附近。", "\(r.name)刚刚出门，在\(placeName(r.atLandmarkID) ?? "附近")附近。", "\(r.name) just went out, near \(placeName(r.atLandmarkID) ?? "here")."))
    }

    func notifyIfBackground(id: String, body: String) {
        guard isInBackground else { return }
        Self.debugEvent("notify \(body)")
        let c = UNMutableNotificationContent()
        c.title = L.t("街坊行", "街坊行", "Kaifong Walk")
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
            self.toast(ok ? L.t("伺服器上你嘅資料都刪咗。", "服务器上你的资料都删了。", "Your data on the server has been deleted.") : L.t("未連線，伺服器上嘅資料未刪到。連返網之後再撳一次。", "未联网，服务器上的资料还没删。联网后再按一次。", "Offline, so your server data wasn't deleted. Tap again when you're back online."))
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
