import SwiftUI
import UIKit

// F8 live finding with real neighbors (2026-10-11).
// After mutual consent or meeting departure, exchange temporary GPS over private pair:<a>:<b> channels every 3 seconds in foreground.
// Do not persist coordinates to tables; stop on meeting, stop, cancellation, timeout, or peer termination.
// Far away: GPS bearing minus compass heading drives the arrow, distance, minutes and approximate scene position; vibrate within 50 m.
// Nearby: exchange UWB tokens for NISession distance and direction; alignment turns green and vibrates. Finish together within 3 m or on manual confirmation. See current thresholds below.
// Demo mode / demo neighbors retain simulated routes in AppStore+Find and scripted demos.
extension AppStore {
    /// Use live location only with a real backend and a real, non-demo neighbor.
    func canShareLive(with partnerID: String) -> Bool {
        guard !demoMode, supabase != nil, let p = resident(partnerID), p.isNeighbor, !p.isDemo else { return false }
        return true
    }

    /// Start sharing with the peer; f is the finding state about to enter the store.
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
        // Live finding uses directional guidance, not a simulated route.
        scene.setRoute(nil)
    }

    /// Stop sharing; notify also ends the peer's session.
    func stopLiveFind(notify: Bool, met: Bool = false) {
        liveFind?.stop(notify: notify, met: met)
        liveFind = nil
        liveSceneStamp = nil
    }

    /// The recipient accepts, starts mutual sharing, and opens finding to follow the approaching peer.
    func beginIncomingLiveFind(_ ask: IncomingFindAsk) {
        if find != nil { endFind() }
        banner = nil
        renaming = nil
        walkingWith = nil
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

    /// Every 0.25 seconds update distance, arrow and near/far state; finish automatically when close enough.
    func tickLiveFind(_ f: inout FindSession) {
        guard let lf = liveFind, f.stage != .met else { return }
        let name = resident(f.partnerID)?.name ?? L.t("街坊", "邻居")
        let now = Date()
        let token = f.token
        // Stop after one hour, or after 5 minutes without peer updates measured in foreground time.
        if now.timeIntervalSince(lf.started) > 3600 {
            endLiveLater(token, L.t("同\(name)分享位置已經一個鐘，自動停咗。", "和\(name)共享位置已经一小时，自动停止了。"))
            return
        }
        if let pf = lf.partnerFix, now.timeIntervalSince(max(pf.at, lf.resumedAt)) > 300 {
            endLiveLater(token, L.t("收唔到\(name)嘅位置，停咗分享。", "收不到\(name)的位置，已停止共享。"))
            return
        }
        let gps = lf.gpsDistance
        let ni = lf.freshNIDistance
        let fresh = lf.partnerFix.map { now.timeIntervalSince($0.at) < LiveFindMath.staleAfter } ?? false
        f.partnerStale = lf.partnerFix != nil && !fresh
        // Receiving a meeting peer's location indicates departure.
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
        // Vibrate and speak once within 50 m, as in simulated finding.
        if d <= 50 && f.stage == .going && fresh {
            f.stage = .near
            Haptics.success()
            say(L.t("\(name)喺附近，\(f.incoming ? "就快到" : "跟住箭咀行")。", "\(name)在附近，\(f.incoming ? "快到了" : "跟着箭头走")。"))
        }
        if fresh && LiveFindMath.isMet(gps: gps, ni: ni) {
            liveMet(&f, notify: true)
            return
        }
        checkLate(&f)
    }

    /// Handle manual meeting confirmation.
    func liveMetTapped() {
        guard var f = find, f.live, f.stage != .met else { return }
        liveMet(&f, notify: true)
        find = f
    }

    /// Finish both sides when notify is true; hide the screen after 3 seconds.
    func liveMet(_ f: inout FindSession, notify: Bool) {
        f.stage = .met
        f.etaMinutes = 0
        Haptics.success()
        say(L.t("見到喇！", "看到了！"))
        if let id = findAppointment, let i = appointments.firstIndex(where: { $0.id == id }) { appointments[i].status = .done }
        walkingWith = f.partnerID
        stopLiveFind(notify: notify, met: true)
        let token = f.token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if self.find?.token == token { self.endFind() }
        }
    }

    /// The peer stopped sharing or confirmed meeting.
    func livePartnerEvent(_ e: LiveFindSession.PartnerEvent, token: UUID) {
        guard var f = find, f.token == token, f.stage != .met else { return }
        switch e {
        case .ended(let met):
            if met {
                liveMet(&f, notify: false)
                find = f
            } else {
                let name = resident(f.partnerID)?.name ?? L.t("街坊", "邻居")
                stopLiveFind(notify: false)
                toast(L.t("\(name)停咗分享位置。", "\(name)停止共享位置了。"))
                endFind()
            }
        }
    }

    /// Defer endFind until the next turn; tick would otherwise overwrite find afterward.
    private func endLiveLater(_ token: UUID, _ message: String) {
        Task { @MainActor in
            guard self.find?.token == token else { return }
            self.stopLiveFind(notify: true)
            self.toast(message)
            self.endFind()
        }
    }

    /// Convert live coordinates to scene positions, snapping to roads for approximate visual placement.
    func liveScenePoint(_ fix: LiveFindSession.Fix?) -> Vec2? {
        guard let fix, let m = map else { return nil }
        let v = m.scenePoint(fix.geo)
        let h = m.half - 4
        return scene.nearestWalkable(Vec2(x: min(h, max(-h, v.x)), y: min(h, max(-h, v.y))))
    }

    /// Redraw only on new fixes; zoom out when the peer first appears to show both people.
    private func refreshLiveScene(_ lf: LiveFindSession) {
        let stamp = max(lf.myFix?.at ?? .distantPast, lf.partnerFix?.at ?? .distantPast)
        guard stamp != liveSceneStamp, stamp != .distantPast else { return }
        liveSceneStamp = stamp
        syncScene()
        // Use overview when both people fit inside the roughly 300 m base.
        if !liveCameraDone, liveScenePoint(lf.myFix) != nil, liveScenePoint(lf.partnerFix) != nil {
            liveCameraDone = true
            scene.resetCamera()
        }
    }

    /// Scene figures for live finding; omit the peer until its location arrives.
    func livePeople(_ f: FindSession, partner p: Resident) -> [ScenePerson] {
        var out = [ScenePerson(id: "me", color: me.uiColor, mobility: me.mobility,
                               motion: .stand(at: liveScenePoint(liveFind?.myFix) ?? myPosition()), label: L.t("你", "你"))]
        if let pp = liveScenePoint(liveFind?.partnerFix) {
            out.append(ScenePerson(id: p.id, color: p.uiColor, mobility: p.mobility, motion: .stand(at: pp), label: p.name, highlighted: true))
        }
        return out
    }
}
