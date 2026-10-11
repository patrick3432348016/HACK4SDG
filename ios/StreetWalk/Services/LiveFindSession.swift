import Foundation
import CoreLocation
import NearbyInteraction

/// 开 / 关同街坊之间嘅私有频道（SupabaseCommunityService 实现；pair:<小uuid>:<大uuid>，服务器只放行互为街坊嘅两个人）。
@MainActor
protocol PairChannelProvider: AnyObject {
    func openPairChannel(with partnerID: String) -> RealtimeChannel?
    func closePairChannel(_ ch: RealtimeChannel)
}

extension SupabaseCommunityService: PairChannelProvider {}

/// 「查找」式找人：找人期间两部手机只经私有频道互传即时 GPS（App 喺前台时每 3 秒一次；唔落任何表），
/// 加指南针方向；近距离（GPS ≤ 30 m）交换超宽带令牌，用 NISession 量精确距离同方向。
/// 一结束（見到、停止、取消、超时）就 stop()：停定位、离开频道、停超宽带。
@MainActor
final class LiveFindSession: NSObject, CLLocationManagerDelegate, NISessionDelegate {
    struct Fix: Equatable {
        var geo: GeoPoint
        var accuracy: Double
        var at: Date
    }
    enum PartnerEvent: Equatable { case ended(met: Bool) }
    enum NIState: Equatable { case idle, waitingPeer, ranging, unsupported, denied }

    let partnerID: String
    let started = Date()
    /// 上次返前台（对方位置停咗几耐由呢度计）。
    private(set) var resumedAt = Date()
    private(set) var myFix: Fix?
    private(set) var partnerFix: Fix?
    /// 手机顶指住嘅方向（度，正北 0）；精度（度，负数 = 无效）。
    private(set) var heading: Double?
    private(set) var headingAccuracy: Double?
    private(set) var niDistance: Double?
    /// 超宽带水平角（度，向右为正）；nil = 未有方向。
    private(set) var niAzimuth: Double?
    private(set) var niAt: Date?
    private(set) var niState: NIState = .idle
    /// 镜头辅助未收敛：叫用户慢慢左右移动手机。
    private(set) var needsSweep = false
    private(set) var channelJoined = false
    private(set) var channelRefused: String?
    private(set) var sentCount = 0
    private(set) var receivedCount = 0
    private(set) var stopped = false

    /// 对方离开（停止 / 見到）。
    var onPartnerEvent: ((PartnerEvent) -> Void)?

    private weak var provider: PairChannelProvider?
    private var channel: RealtimeChannel?
    private let manager = CLLocationManager()
    private var sendTask: Task<Void, Never>?
    private var foreground = true

    private var ni: NISession?
    private var niPeer: NIDiscoveryToken?
    private var niConfig: NINearbyPeerConfiguration?
    private var sentToken = false
    private var cameraAssist = false
    private var directionMissingSince: Date?

    init(partnerID: String, provider: PairChannelProvider) {
        self.partnerID = partnerID
        self.provider = provider
        super.init()
    }

    // MARK: - 开始 / 停止

    func start() {
        guard !stopped else { return }
        if let ch = provider?.openPairChannel(with: partnerID) {
            channel = ch
            ch.onJoin = { [weak self] ok, reason in
                guard let self, !self.stopped else { return }
                self.channelJoined = ok
                self.channelRefused = ok ? nil : reason
                if ok { self.sendLocation() }
            }
            ch.onBroadcast = { [weak self] event, payload in self?.received(event, payload) }
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.headingFilter = 2
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        resumeSensors()
    }

    /// 结束：话俾对方知（bye），停晒所有嘢。可以叫多次。
    func stop(notify: Bool, met: Bool = false) {
        guard !stopped else { return }
        if notify { channel?.broadcast("bye", .object(["met": .bool(met)])) }
        stopped = true
        pauseSensors()
        stopNI()
        if let ch = channel {
            ch.onBroadcast = nil
            ch.onJoin = nil
            // 等 bye 送出先离开频道（同一条 WebSocket，按次序送）
            provider?.closePairChannel(ch)
        }
        channel = nil
        myFix = nil
        partnerFix = nil
    }

    /// App 前台 / 后台：后台即刻停传位置（只喺前台分享），返前台再开。
    func setForeground(_ on: Bool) {
        guard !stopped, on != foreground else { return }
        foreground = on
        if on { resumeSensors() } else { pauseSensors() }
    }

    private func resumeSensors() {
        resumedAt = Date()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LiveFindMath.sendInterval))
                guard let self, !Task.isCancelled else { return }
                self.sendLocation()
            }
        }
    }

    private func pauseSensors() {
        sendTask?.cancel()
        sendTask = nil
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - 位置

    /// 传我而家嘅位置（只传 15 秒内嘅定位）。
    private func sendLocation() {
        guard !stopped, foreground, channelJoined, let f = myFix, Date().timeIntervalSince(f.at) < 15 else { return }
        channel?.broadcast("loc", Self.locPayload(f))
        sentCount += 1
    }

    static func locPayload(_ f: Fix) -> JSONValue {
        .object(["lat": .number(f.geo.lat), "lon": .number(f.geo.lon), "acc": .number(f.accuracy.rounded())])
    }

    static func fix(from p: JSONValue, at: Date = Date()) -> Fix? {
        guard let lat = p["lat"]?.double, let lon = p["lon"]?.double, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return Fix(geo: GeoPoint(lat: lat, lon: lon), accuracy: p["acc"]?.double ?? 20, at: at)
    }

    private func received(_ event: String, _ p: JSONValue) {
        guard !stopped else { return }
        switch event {
        case "loc":
            guard let f = Self.fix(from: p) else { return }
            partnerFix = f
            receivedCount += 1
            maybeStartNI()
        case "ni":
            guard let s = p["token"]?.string, let data = Data(base64Encoded: s),
                  let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else { return }
            peerTokenArrived(token, wantsReply: p["want"]?.bool ?? true)
        case "bye":
            onPartnerEvent?(.ended(met: p["met"]?.bool ?? false))
        default:
            break
        }
    }

    /// GPS 距离（两边都有定位先有）。
    var gpsDistance: Double? {
        guard let a = myFix, let b = partnerFix else { return nil }
        return LiveFindMath.distance(a.geo, b.geo)
    }

    var gpsBearing: Double? {
        guard let a = myFix, let b = partnerFix else { return nil }
        return LiveFindMath.bearing(from: a.geo, to: b.geo)
    }

    /// 2 秒内嘅超宽带距离。
    var freshNIDistance: Double? {
        guard let d = niDistance, let t = niAt, Date().timeIntervalSince(t) < LiveFindMath.niFresh else { return nil }
        return d
    }

    var freshNIAzimuth: Double? {
        guard freshNIDistance != nil else { return nil }
        return niAzimuth
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        let f = Fix(geo: GeoPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude), accuracy: l.horizontalAccuracy, at: l.timestamp)
        MainActor.assumeIsolated {
            guard !self.stopped else { return }
            let first = self.myFix == nil
            self.myFix = f
            if first { self.sendLocation() }
            self.maybeStartNI()
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        let v = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        let acc = h.headingAccuracy
        MainActor.assumeIsolated {
            self.heading = v
            self.headingAccuracy = acc
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ m: CLLocationManager) -> Bool { true }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}

    // MARK: - 超宽带（近距离）

    private var niSupported: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }

    /// GPS 话够近就开 NISession、经频道传我嘅令牌。
    private func maybeStartNI() {
        guard !stopped, foreground, !sentToken, niState == .idle, let d = gpsDistance, d <= LiveFindMath.niStartDistance else { return }
        guard niSupported else { niState = .unsupported; return }
        sendMyToken(wantReply: true)
    }

    private func ensureNISession() -> NISession? {
        if let ni { return ni }
        guard niSupported else { niState = .unsupported; return nil }
        let s = NISession()
        s.delegate = self
        s.delegateQueue = .main
        ni = s
        return s
    }

    /// wantReply：叫对方都传佢嘅令牌返嚟（我新开咗 NISession）；回覆嗰个唔使再叫，免得两边传嚟传去。
    private func sendMyToken(wantReply: Bool) {
        guard let s = ensureNISession(), let token = s.discoveryToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        channel?.broadcast("ni", .object(["token": .string(data.base64EncodedString()), "want": .bool(wantReply)]))
        sentToken = true
        if niState == .idle { niState = .waitingPeer }
    }

    private func peerTokenArrived(_ token: NIDiscoveryToken, wantsReply: Bool) {
        guard niState != .denied, let s = ensureNISession() else { return }
        if wantsReply || !sentToken { sendMyToken(wantReply: false) }
        niPeer = token
        let c = NINearbyPeerConfiguration(peerToken: token)
        c.isCameraAssistanceEnabled = cameraAssist
        niConfig = c
        s.run(c)
        niState = .ranging
    }

    private func stopNI() {
        ni?.delegate = nil
        ni?.invalidate()
        ni = nil
        niPeer = nil
        niConfig = nil
        niDistance = nil
        niAzimuth = nil
    }

    /// 有距离冇方向 3 秒：开镜头辅助（iPhone 14 之后好多时要靠镜头先知方向）。
    private func checkCameraAssist(hasDirection: Bool) {
        if hasDirection { directionMissingSince = nil; return }
        let now = Date()
        guard let since = directionMissingSince else { directionMissingSince = now; return }
        guard !cameraAssist, now.timeIntervalSince(since) > 3, NISession.deviceCapabilities.supportsCameraAssistance,
              let peer = niPeer, let s = ni else { return }
        cameraAssist = true
        let c = NINearbyPeerConfiguration(peerToken: peer)
        c.isCameraAssistanceEnabled = true
        niConfig = c
        s.run(c)
    }

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        MainActor.assumeIsolated {
            guard session === self.ni, let o = nearbyObjects.first(where: { $0.discoveryToken == self.niPeer }) else { return }
            if let d = o.distance {
                self.niDistance = Double(d)
                self.niAt = Date()
            }
            if let dir = o.direction {
                self.niAzimuth = LiveFindMath.niAzimuth(x: dir.x, z: dir.z)
            } else if let h = o.horizontalAngle {
                self.niAzimuth = Double(h) * 180 / .pi
            } else {
                self.niAzimuth = nil
            }
            self.checkCameraAssist(hasDirection: self.niAzimuth != nil)
        }
    }

    nonisolated func session(_ session: NISession, didUpdateAlgorithmConvergence convergence: NIAlgorithmConvergence, for object: NINearbyObject?) {
        let converged: Bool
        if case .converged = convergence.status { converged = true } else { converged = false }
        MainActor.assumeIsolated {
            guard session === self.ni else { return }
            self.needsSweep = !converged
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        MainActor.assumeIsolated {
            guard session === self.ni else { return }
            self.niDistance = nil
            self.niAzimuth = nil
            if reason == .peerEnded {
                // 对方停咗超宽带（例如退后台）：等佢再传令牌
                self.niState = .waitingPeer
            } else if let c = self.niConfig {
                session.run(c)   // 超时（遮住 / 行远咗）：苹果建议用返同一个配置再开
            }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {}

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        MainActor.assumeIsolated {
            guard session === self.ni, let c = self.niConfig else { return }
            session.run(c)
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        let denied = (error as? NIError)?.code == .userDidNotAllow
        MainActor.assumeIsolated {
            guard session === self.ni else { return }
            self.stopNI()
            self.sentToken = false
            // 冇权限就用返 GPS 箭咀；其他错误等下次 GPS 够近再试
            self.niState = denied ? .denied : .idle
        }
    }
}
