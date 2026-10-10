import Foundation
import Combine
import NearbyInteraction
import UIKit
import CryptoKit

final class MeetCoordinator: NSObject, ObservableObject, NISessionDelegate {
    enum Phase: Equatable { case idle, searching, ranging, confirming, exchanging, success, failed }
    @Published var isPatrick = true
    @Published var joinCode = ""
    @Published var shareWechat = true
    @Published var shareWhatsApp = false
    @Published private(set) var hostCode = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status = "两台手机打开页面，一台发起，另一台加入。"
    @Published private(set) var distance: Float?
    @Published private(set) var peer: PublicProfile?
    @Published private(set) var localConsent = false
    @Published private(set) var peerConsent = false
    @Published private(set) var logs: [String] = []
    let store = FriendStore()
    let supportsUWB = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    private let transport = PeerTransport()
    private var ni: NISession?
    private var peerToken: NIDiscoveryToken?
    private var gate = ProximityGate()
    private var exchange = ExchangeState()
    private var sentContact = false
    private var timer: Timer?
    private var began = Date()
    private var lastSample: TimeInterval?
    private var exchangeID = ""
    private var ownID: UUID
    private var myProfile: PublicProfile?

    var active: Bool { phase != .idle && phase != .failed && phase != .success }
    var commonInterests: String {
        guard let peer, let myProfile else { return "" }
        return myProfile.interests.filter { peer.interests.contains($0) }.joined(separator: "、")
    }

    override init() {
        if let value = UserDefaults.standard.string(forKey: "demoIdentity"), let id = UUID(uuidString: value) {
            ownID = id
        } else {
            ownID = UUID()
            UserDefaults.standard.set(ownID.uuidString, forKey: "demoIdentity")
        }
        super.init()
        transport.onReady = { [weak self] in self?.sendHello() }
        transport.onMessage = { [weak self] message in self?.receive(message) }
        transport.onFailure = { [weak self] message in self?.fail(message) }
        if !supportsUWB { status = "此设备不支持精确 UWB 测距，不能运行真实靠近演示。" }
    }

    func start(host: Bool) {
        guard supportsUWB else { fail("设备不支持精确 UWB 测距"); return }
        guard host || PeerTransport.validCode(joinCode) else {
            status = "请输入发起方屏幕上的 20 位配对码（可带连字符）。"; return
        }
        stopHardware()
        exchange = ExchangeState(); gate.reset(); sentContact = false
        localConsent = false; peerConsent = false
        peer = nil; peerToken = nil; distance = nil; lastSample = nil
        logs = []; began = Date()
        myProfile = .demo(id: ownID, isPatrick: isPatrick)
        let session = NISession()
        session.delegate = self
        session.delegateQueue = .main
        ni = session
        hostCode = host ? PeerTransport.newCode() : ""
        phase = .searching
        status = host ? "请让另一台手机输入配对码并加入。" : "正在寻找对应发起方…"
        do {
            try transport.start(host: host, code: host ? hostCode : joinCode)
            log("开始配对；距离门限 0.30 m / 持续 0.50 s（待实测）")
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        } catch { fail("无法开始配对：\(error.localizedDescription)") }
    }

    private func sendHello() {
        guard active, let token = ni?.discoveryToken, let myProfile else {
            fail("无法创建 UWB 会话令牌，请检查设备与权限"); return
        }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            transport.send(.hello, profile: myProfile, token: data)
            status = "已连接，正在验证会话并启动测距…"
            log("通信连接已建立")
        } catch { fail("无法编码 UWB 令牌") }
    }

    private func receive(_ message: WireMessage) {
        guard active || phase == .success else { return }
        switch message.kind {
        case .hello:
            guard peer == nil, let profile = message.profile, profile.valid,
                  profile.id != ownID, let data = message.token, data.count < 16_384 else {
                fail("对方名片或会话格式无效"); return
            }
            do {
                guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data),
                      let ni else { fail("对方 UWB 令牌无效"); return }
                peer = profile; peerToken = token
                // Keep the pairing secret out of the saved friend records.
                let attempt = [ownID.uuidString, profile.id.uuidString].sorted().joined(separator: ":")
                    + ":" + (hostCode.isEmpty ? PeerTransport.normalized(joinCode) : PeerTransport.normalized(hostCode))
                exchangeID = SHA256.hash(data: Data(attempt.utf8)).map { String(format: "%02x", $0) }.joined()
                ni.run(NINearbyPeerConfiguration(peerToken: token))
                phase = .ranging
                status = "请将两台手机靠近；保持屏幕亮起、页面在前台。"
                log("真实 UWB 测距已启动，等待传感器读数")
            } catch { fail("无法读取对方 UWB 令牌") }
        case .near:
            guard peer != nil else { fail("会话顺序错误"); return }
            exchange.markPeerNear(); updateConfirmation()
        case .consent:
            guard peer != nil, exchange.peerNear else { fail("收到无效确认"); return }
            exchange.consentFromPeer(); peerConsent = true
            log("对方已确认分享")
            advanceExchange()
        case .contact:
            guard exchange.canExchange, !exchange.receivedCard, let contact = message.contact,
                  contact.valid, contact.profile == peer else { fail("未授权或不匹配的联系方式"); return }
            do {
                // Persist before acknowledging receipt. A failed write must never report success.
                try store.store(contact, exchangeID: exchangeID)
                _ = exchange.markCardStored()
                transport.send(.receipt)
                log("对方允许分享的名片已保存，已发送回执")
                finishIfReady()
            } catch { fail("名片保存失败，请检查手机存储空间") }
        case .receipt:
            guard sentContact, exchange.markPeerReceipt() else { fail("收到无效保存回执"); return }
            log("对方已确认保存我的名片")
            finishIfReady()
        case .cancel:
            if phase != .success { fail("对方已取消，本次流程已结束。") }
            else { stopHardware() }
        }
    }

    func confirm() {
        guard phase == .confirming, exchange.consentLocally() else { return }
        localConsent = true
        transport.send(.consent)
        status = "已同意，等待双方确认并交换名片…"
        log("我已确认分享（不记录联系方式）")
        advanceExchange()
    }

    private func advanceExchange() {
        guard exchange.canExchange, !sentContact, let myProfile else { return }
        sentContact = true
        phase = .exchanging
        // Deliberately synthetic demo contacts; never silently import system contacts.
        let card = SharedContact(profile: myProfile,
                                 wechat: shareWechat ? (isPatrick ? "DEMO_PATRICK_ONLY" : "DEMO_CHEN_ONLY") : nil,
                                 whatsapp: shareWhatsApp ? "DEMO_NOT_A_PHONE_NUMBER" : nil)
        transport.send(.contact, contact: card)
        status = "双方已确认，正在交换并保存演示名片…"
    }

    private func finishIfReady() {
        guard exchange.complete else { return }
        do {
            try store.acknowledge(exchangeID)
            phase = .success
            status = "已成为运动伙伴 · 演示名片已保存"
            log("交换完成：本机保存成功，并收到对方保存回执")
            timer?.invalidate(); timer = nil
            ni?.delegate = nil; ni?.invalidate(); ni = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Keep the link until reset so the other side can receive its final receipt.
        } catch { fail("无法保存完成状态，请重新配对") }
    }

    private func updateConfirmation() {
        guard exchange.canConfirm, phase == .ranging else { return }
        phase = .confirming
        status = "双方均检测到靠近。请核对对方名片，再选择分享内容。"
        log("双方距离门限已满足，显示交友确认")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard session === ni, phase == .ranging,
              let object = nearbyObjects.first(where: { $0.discoveryToken == peerToken }) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        distance = object.distance
        lastSample = now
        if gate.update(distance: object.distance, at: now) {
            exchange.markLocalNear()
            transport.send(.near)
            log("本机连续测得距离满足门限")
            updateConfirmation()
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard session === ni, active else { return }
        fail("UWB 目标丢失或超时，请让双方重新开始。")
    }
    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard session === ni, active else { return }
        fail("UWB 会话不可用：\(error.localizedDescription)。请检查附近交互权限。")
    }
    func sessionWasSuspended(_ session: NISession) {
        guard session === ni, active else { return }
        fail("UWB 会话已暂停，请回到前台后重新开始。")
    }

    private func tick() {
        guard active else { return }
        if Date().timeIntervalSince(began) > 180 { fail("本轮超过 3 分钟，请重新开始配对。"); return }
        if phase == .ranging, let lastSample,
           ProcessInfo.processInfo.systemUptime - lastSample > gate.maxGap {
            distance = nil
            _ = gate.update(distance: nil, at: ProcessInfo.processInfo.systemUptime)
            status = "等待有效距离读数，请调整手机方向并保持页面打开。"
        }
    }

    func cancel() {
        guard active else { resetSession(); return }
        exchange.cancel()
        phase = .failed
        status = "已取消，双方重新开始即可重试。"
        timer?.invalidate(); timer = nil
        ni?.delegate = nil; ni?.invalidate(); ni = nil
        transport.send(.cancel, completion: { [weak self] in self?.transport.stop() })
    }

    func wentToBackground() {
        if active { fail("程序进入后台，本轮已结束。回到前台后重新开始。") }
        else { stopHardware() }
    }

    func resetSession() {
        stopHardware()
        exchange = ExchangeState(); gate.reset()
        phase = .idle; status = "已重置会话，请重新发起或加入。"
        hostCode = ""; peer = nil; distance = nil
        localConsent = false; peerConsent = false
    }

    func resetDemo() {
        resetSession()
        do { try store.reset(); log("已清除本机演示好友；另一台也需重置") }
        catch { status = "演示记录清除失败，请检查存储。" }
    }

    private func stopHardware() {
        timer?.invalidate(); timer = nil
        ni?.delegate = nil; ni?.invalidate(); ni = nil
        transport.stop()
    }

    private func fail(_ message: String) {
        if phase == .success { stopHardware(); return }
        exchange.cancel(); stopHardware()
        phase = .failed; status = message; distance = nil
        log(message)
    }

    private func log(_ message: String) {
        logs.append(String(format: "+%.1fs %@", Date().timeIntervalSince(began), message))
        if logs.count > 60 { logs.removeFirst() }
    }
}
