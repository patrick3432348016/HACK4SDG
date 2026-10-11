import SwiftUI
import UIKit

// F8「查找」式找人（真街坊，2026-10-11）：
// 找人期间（对方答「好」、我答「好」、或者约会出发）两部手机只经私有频道 pair:<a>:<b> 临时互传即时 GPS（前台每 3 秒），
// 唔落任何表；结束（見到、停止、取消、超时、对方停咗）即刻停。
// 远：GPS 方位 − 指南针 = 大箭咀，加距离、大约几分钟、场景入面对方大概位置；50 m 内震。
// 近（≤ 10 m）：交换超宽带令牌，NISession 精确距离同方向（对正咗转绿 + 震）；≤ 3 m 或撳「見到喇」两边一齐结束。
// 演示模式 / 示範街坊照用模拟路线（AppStore+Find），演示脚本唔受影响。
extension AppStore {
    /// 呢次找人用唔用即时位置：真后端、真街坊（唔係示範）。
    func canShareLive(with partnerID: String) -> Bool {
        guard !demoMode, supabase != nil, let p = resident(partnerID), p.isNeighbor, !p.isDemo else { return false }
        return true
    }

    /// 开始同对方分享位置（f 係即将放入 store 嘅找人状态）。
    func startLiveFind(_ f: inout FindSession) {
        guard canShareLive(with: f.partnerID), let s = supabase else { return }
        liveFind?.stop(notify: false)
        let lf = LiveFindSession(partnerID: f.partnerID, provider: s)
        let token = f.token
        lf.onPartnerEvent = { [weak self] e in self?.livePartnerEvent(e, token: token) }
        liveFind = lf
        liveSceneStamp = nil
        liveCameraDone = false
        f.live = true
        f.liveMode = .waiting
        lf.start()
        if isInBackground { lf.setForeground(false) }
        // 即时位置唔使模拟路线：箭咀带路
        scene.setRoute(nil)
    }

    /// 停止分享（notify：话俾对方知，佢嗰边都会结束）。
    func stopLiveFind(notify: Bool, met: Bool = false) {
        liveFind?.stop(notify: notify, met: met)
        liveFind = nil
        liveSceneStamp = nil
    }

    /// 被搵嗰边：答咗「好」→ 一齐分享位置，打开找人画面睇住对方行过嚟。
    func beginIncomingLiveFind(_ ask: IncomingFindAsk) {
        if find != nil { endFind() }
        banner = nil
        renaming = nil
        partnerAgreed = false
        findAppointment = nil
        findRoute = nil
        partnerRoute = nil
        var f = FindSession(partnerID: ask.fromID, landmarkID: ask.landmarkID, spontaneous: true, stage: .going)
        f.incoming = true
        startLiveFind(&f)
        find = f
        findFullScreen = true
        scene.followID = nil
        scene.highlightLandmark(landmark(ask.landmarkID)?.id)
        syncScene()
        startTicker()
    }

    /// 计时器每 0.25 秒：按即时位置更新距离、箭咀、远 / 近；够近自动「見到喇」。
    func tickLiveFind(_ f: inout FindSession) {
        guard let lf = liveFind, f.stage != .met else { return }
        let name = resident(f.partnerID)?.name ?? "街坊"
        let now = Date()
        let token = f.token
        // 超时：最多分享一个钟；对方位置停咗 5 分钟（我喺前台嘅时间计）都当佢走咗
        if now.timeIntervalSince(lf.started) > 3600 {
            endLiveLater(token, "同\(name)分享位置已經一個鐘，自動停咗。")
            return
        }
        if let pf = lf.partnerFix, now.timeIntervalSince(max(pf.at, lf.resumedAt)) > 300 {
            endLiveLater(token, "收唔到\(name)嘅位置，停咗分享。")
            return
        }
        let gps = lf.gpsDistance
        let ni = lf.freshNIDistance
        let fresh = lf.partnerFix.map { now.timeIntervalSince($0.at) < LiveFindMath.staleAfter } ?? false
        f.partnerStale = lf.partnerFix != nil && !fresh
        // 约会：收到对方位置 = 佢出咗门
        if lf.partnerFix != nil, !f.partnerOut { f.partnerOut = true }
        f.liveMode = LiveFindMath.mode(gps: gps, ni: ni)
        refreshLiveScene(lf)
        guard let d = ni ?? gps else { return }
        f.distance = d
        f.etaMinutes = LiveFindMath.etaMinutes(d)
        if let az = lf.freshNIAzimuth {
            f.bearing = az
            f.precise = true
            f.headingPoor = false
        } else if let b = lf.gpsBearing {
            f.bearing = LiveFindMath.arrowAngle(bearing: b, heading: lf.heading)
            f.precise = false
            f.headingPoor = !LiveFindMath.headingUsable(accuracy: lf.headingAccuracy)
        }
        let facing = !f.headingPoor && LiveFindMath.isFacing(f.bearing)
        if facing && !f.facing && f.liveMode == .near { Haptics.success() }
        f.facing = facing
        f.sweep = lf.needsSweep && ni != nil && lf.freshNIAzimuth == nil
        // 50 m 内震一下、讲一句（同模拟找人一样）
        if d <= 50 && f.stage == .going && fresh {
            f.stage = .near
            Haptics.success()
            say("\(name)喺附近，\(f.incoming ? "就快到" : "跟住箭咀行")。")
        }
        if fresh && LiveFindMath.isMet(gps: gps, ni: ni) {
            liveMet(&f, notify: true)
            return
        }
        checkLate(&f)
    }

    /// 撳「見到喇」。
    func liveMetTapped() {
        guard var f = find, f.live, f.stage != .met else { return }
        liveMet(&f, notify: true)
        find = f
    }

    /// 見到：两边一齐结束（notify = 话俾对方知），3 秒后收埋画面。
    func liveMet(_ f: inout FindSession, notify: Bool) {
        f.stage = .met
        f.etaMinutes = 0
        Haptics.success()
        say("見到喇！")
        if let id = findAppointment, let i = appointments.firstIndex(where: { $0.id == id }) { appointments[i].status = .done }
        stopLiveFind(notify: notify, met: true)
        let token = f.token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if self.find?.token == token { self.endFind() }
        }
    }

    /// 对方停咗分享 / 見到咗。
    func livePartnerEvent(_ e: LiveFindSession.PartnerEvent, token: UUID) {
        guard var f = find, f.token == token, f.stage != .met else { return }
        switch e {
        case .ended(let met):
            if met {
                liveMet(&f, notify: false)
                find = f
            } else {
                let name = resident(f.partnerID)?.name ?? "街坊"
                stopLiveFind(notify: false)
                toast("\(name)停咗分享位置。")
                endFind()
            }
        }
    }

    /// 计时器入面唔可以即刻 endFind（tick 之后会写返 find）：下一轮先结束。
    private func endLiveLater(_ token: UUID, _ message: String) {
        Task { @MainActor in
            guard self.find?.token == token else { return }
            self.stopLiveFind(notify: true)
            self.toast(message)
            self.endFind()
        }
    }

    /// 即时位置 → 场景坐标（贴返最近嘅路；画风优先，只係大概位置）。
    func liveScenePoint(_ fix: LiveFindSession.Fix?) -> Vec2? {
        guard let fix, let m = map else { return nil }
        let v = m.scenePoint(fix.geo)
        let h = m.half - 4
        return scene.nearestWalkable(Vec2(x: min(h, max(-h, v.x)), y: min(h, max(-h, v.y))))
    }

    /// 有新定位先重画场景入面两个人；第一次见到对方就将镜头移去两人中间。
    private func refreshLiveScene(_ lf: LiveFindSession) {
        let stamp = max(lf.myFix?.at ?? .distantPast, lf.partnerFix?.at ?? .distantPast)
        guard stamp != liveSceneStamp, stamp != .distantPast else { return }
        liveSceneStamp = stamp
        syncScene()
        if !liveCameraDone, let a = liveScenePoint(lf.myFix), let b = liveScenePoint(lf.partnerFix) {
            liveCameraDone = true
            scene.setCamera(target: (a + b) * 0.5, distance: scene.overviewDistance * 0.8, animated: true, duration: 1.0)
        }
    }

    /// 场景入面找人嘅两个人（即时位置）。对方未有位置就唔画佢。
    func livePeople(_ f: FindSession, partner p: Resident) -> [ScenePerson] {
        var out = [ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility,
                               motion: .stand(at: liveScenePoint(liveFind?.myFix) ?? myPosition()), label: "你")]
        if let pp = liveScenePoint(liveFind?.partnerFix) {
            out.append(ScenePerson(id: p.id, color: p.uiColor, mobility: p.mobility, motion: .stand(at: pp), label: p.name, highlighted: true))
        }
        return out
    }
}
