import Foundation
import Testing
import CryptoKit
@testable import StreetWalk

// 碰一碰（F5）：组员 B 原型嘅 8 个测试（ios/UWBMeetDemo/Tests/MeetCoreTests.swift，改用 Swift Testing、BumpMessage、BumpAgreement），
// 加：密钥协商来回、反射 / 窜改 / 重放、边部主动连、二维码内容、轮询后端、两部手机（假超宽带）经真 Bonjour 成个流程。

// MARK: - 组员 B 原型移植

struct BumpPortedFromBTests {
    /// B 原型嘅参数（0.30 米 / 0.5 秒），睇移植后判断一样。
    func bGate() -> ProximityGate { ProximityGate(threshold: 0.30, dwell: 0.50, maxGap: 0.35) }

    @Test func 持续靠近先触发而且只触发一次() {
        var gate = bGate()
        let r1 = gate.update(distance: 0.25, at: 0)
        #expect(!r1)
        let r2 = gate.update(distance: 0.25, at: 0.25)
        #expect(!r2)
        let r3 = gate.update(distance: 0.25, at: 0.51)
        #expect(r3)
        let r4 = gate.update(distance: 0.20, at: 0.60)
        #expect(!r4)
    }

    /// 2026-10-17（D-2）：一两下冇读数唔清零（贴近时超宽带成日漏读数）；够近嘅读数断太耐先重新计时。
    @Test func 读数断太耐先重新计时() {
        var gate = bGate()
        let r5 = gate.update(distance: 0.20, at: 0)
        #expect(!r5)
        let r6 = gate.update(distance: 0.20, at: 1)
        #expect(!r6, "断咗 1 秒（> maxGap）：由 1 秒重新计")
        let r7 = gate.update(distance: nil, at: 1.1)
        #expect(!r7)
        let r8 = gate.update(distance: 0.20, at: 1.2)
        #expect(!r8)
        let r9 = gate.update(distance: .nan, at: 1.3)
        #expect(!r9)
        let r10 = gate.update(distance: -1, at: 1.4)
        #expect(!r10)
        let r11 = gate.update(distance: 0.20, at: 1.5)
        #expect(r11, "中间几下坏读数唔清零，够 0.5 秒就算")
        var g2 = bGate()
        _ = g2.update(distance: 0.20, at: 0)
        _ = g2.update(distance: nil, at: 0.2)
        let r11b = g2.update(distance: nil, at: 0.45)
        #expect(!r11b)
        let r11c = g2.update(distance: 0.20, at: 0.6)
        #expect(!r11c, "够近读数断咗 0.6 秒（> 0.35）：重新计")
        let r11d = g2.update(distance: 0.35, at: 0.8)
        #expect(!r11d, "门限边缘（0.30–0.40）唔计时")
        let r11e = g2.update(distance: 0.20, at: 0.9)
        #expect(!r11e)
        let r11f = g2.update(distance: 0.20, at: 1.1)
        #expect(r11f, "边缘抖动唔清零：由 0.6 计到 1.1")
    }

    @Test func 远咗一下重新计时() {
        var gate = bGate()
        _ = gate.update(distance: 0.20, at: 0)
        _ = gate.update(distance: 0.50, at: 0.25)
        let r12 = gate.update(distance: 0.20, at: 0.50)
        #expect(!r12)
    }

    @Test func 两边都够近先收码() {
        var a = BumpAgreement()
        let code = PairCode.random()
        a.markPeerNear()
        let r13 = a.accept(code: code)
        #expect(!r13, "对方话够近唔算，自己都要量到")
        a.markLocalNear()
        #expect(a.bothNear)
        let r14 = a.accept(code: "abc")
        #expect(!r14, "格式唔啱嘅码唔收")
        let r15 = a.accept(code: code)
        #expect(r15)
        let r16 = a.accept(code: PairCode.random())
        #expect(!r16, "只收一次")
        #expect(a.code == code)
    }

    @Test func 取消之后唔会成功() {
        var a = BumpAgreement()
        a.markLocalNear(); a.markPeerNear()
        a.cancel()
        #expect(!a.bothNear)
        let r17 = a.accept(code: PairCode.random())
        #expect(!r17)
    }

    @Test func TCP分段同黏包() throws {
        let first = Data("first".utf8), second = Data("second".utf8)
        let a = try FrameBuffer.frame(first), b = try FrameBuffer.frame(second)
        var buffer = FrameBuffer()
        let r18 = try buffer.append(Data(a.prefix(2)))
        #expect(r18 == [])
        let r19 = try buffer.append(Data(a.dropFirst(2)) + b)
        #expect(r19 == [first, second])
    }

    @Test func 过大同空嘅帧都拒绝() {
        var buffer = FrameBuffer()
        #expect(throws: (any Error).self) { try buffer.append(Data([0, 2, 0, 0])) }
        #expect(throws: (any Error).self) { try FrameBuffer.frame(Data()) }
        #expect(throws: (any Error).self) { try FrameBuffer.frame(Data(repeating: 0, count: FrameBuffer.maximum + 1)) }
    }

    @Test func 重放同错会话都拒绝() {
        let session = UUID()
        func message(_ kind: BumpMessage.Kind, _ sequence: Int, _ id: UUID) -> BumpMessage {
            BumpMessage(session: id, sequence: sequence, kind: kind)
        }
        var g = SequenceGuard()
        let r20 = g.accept(message(.near, 0, session))
        #expect(!r20, "第一条一定係 hello")
        let r21 = g.accept(message(.hello, 0, session))
        #expect(r21)
        let r22 = g.accept(message(.hello, 0, session))
        #expect(!r22, "重放")
        let r23 = g.accept(message(.near, 1, UUID()))
        #expect(!r23, "错会话")
        let r24 = g.accept(message(.near, 1, session))
        #expect(r24)
    }
}

// MARK: - 新逻辑

struct BumpWireTests {
    /// 两部手机：id 细嗰部（a）係主动连嗰方。
    func pair() throws -> (a: BumpChannel, b: BumpChannel) {
        let ka = Curve25519.KeyAgreement.PrivateKey(), kb = Curve25519.KeyAgreement.PrivateKey()
        let ida = String(repeating: "1", count: 32), idb = String(repeating: "e", count: 32)
        let a = try BumpChannel(myKey: ka, myID: ida, peer: BumpHello(id: idb, key: kb.publicKey.rawRepresentation), initiator: true)
        let b = try BumpChannel(myKey: kb, myID: idb, peer: BumpHello(id: ida, key: ka.publicKey.rawRepresentation), initiator: false)
        return (a, b)
    }

    func record(_ framed: Data) throws -> Data {
        var f = FrameBuffer()
        let r = try f.append(framed)
        #expect(r.count == 1)
        return r[0]
    }

    @Test func 密钥协商之后两边解得开() throws {
        var (a, b) = try pair()
        let token = Data((0..<300).map { UInt8($0 & 255) })
        let m1 = try b.open(record(a.seal(.hello, token: token)))
        #expect(m1.kind == .hello && m1.token == token)
        let m2 = try a.open(record(b.seal(.hello, token: Data([1, 2, 3]))))
        #expect(m2.kind == .hello)
        let code = PairCode.random()
        _ = try b.open(record(a.seal(.near)))
        let m3 = try b.open(record(a.seal(.code, code: code)))
        #expect(m3.kind == .code && m3.code == code)
        let m4 = try a.open(record(b.seal(.near)))
        #expect(m4.kind == .near && m4.sequence == 1)
    }

    @Test func 反射窜改重放都解唔开() throws {
        var (a, b) = try pair()
        let r = try record(a.seal(.hello, token: Data([9])))
        #expect(throws: BumpChannel.Failure.decrypt) { try a.open(r) }   // 我自己嘅消息反射返嚟
        var bad = r
        bad[bad.count - 1] ^= 0x01
        #expect(throws: BumpChannel.Failure.decrypt) { try b.open(bad) }   // 窜改
        _ = try b.open(r)
        #expect(throws: BumpChannel.Failure.replay) { try b.open(r) }   // 重放
    }

    @Test func 第三者同搞错角色都解唔开() throws {
        var (a, _) = try pair()
        let r = try record(a.seal(.hello, token: Data([7])))
        let kc = Curve25519.KeyAgreement.PrivateKey()
        var c = try BumpChannel(myKey: kc, myID: String(repeating: "f", count: 32),
                                peer: BumpHello(id: String(repeating: "1", count: 32), key: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation),
                                initiator: false)
        #expect(throws: BumpChannel.Failure.decrypt) { try c.open(r) }
        // id 大嘅一方话自己主动连：唔信。
        #expect(throws: BumpChannel.Failure.badHello) {
            try BumpChannel(myKey: kc, myID: String(repeating: "f", count: 32),
                            peer: BumpHello(id: String(repeating: "1", count: 32), key: kc.publicKey.rawRepresentation), initiator: true)
        }
        #expect(throws: BumpChannel.Failure.badHello) {
            try BumpChannel(myKey: kc, myID: String(repeating: "f", count: 32), peer: BumpHello(id: "short", key: Data(count: 32)), initiator: false)
        }
    }

    @Test func 码同hello格式唔啱都拒绝() throws {
        var (a, b) = try pair()
        _ = try b.open(record(a.seal(.hello, token: Data([1]))))
        #expect(throws: BumpChannel.Failure.malformed) { try b.open(record(a.seal(.code, code: "not-a-code"))) }
        var (c, d) = try pair()
        #expect(throws: BumpChannel.Failure.malformed) { try d.open(record(c.seal(.hello))) }   // hello 冇令牌
    }

    @Test func 边部主动连() {
        let lo = String(repeating: "0", count: 31) + "1", mid = String(repeating: "7", count: 32), hi = String(repeating: "f", count: 32)
        #expect(BumpTieBreak.shouldConnect(me: lo, peer: hi))
        #expect(!BumpTieBreak.shouldConnect(me: hi, peer: lo))
        #expect(!BumpTieBreak.shouldConnect(me: mid, peer: mid))
        // 两部手机：刚好一部主动连
        for _ in 0..<50 {
            let x = BumpTieBreak.newInstanceID(), y = BumpTieBreak.newInstanceID()
            #expect(BumpTieBreak.shouldConnect(me: x, peer: y) != BumpTieBreak.shouldConnect(me: y, peer: x))
        }
        #expect(BumpTieBreak.pick(me: lo, visible: [hi, mid]) == mid, "揀比我大嘅入面最细")
        #expect(BumpTieBreak.pick(me: hi, visible: [lo, mid]) == nil, "冇比我大：等人连")
        #expect(BumpTieBreak.instanceID(fromServiceName: BumpTieBreak.serviceName(mid)) == mid)
        #expect(BumpTieBreak.instanceID(fromServiceName: "jf-xyz") == nil)
        #expect(BumpTieBreak.instanceID(fromServiceName: "meet-" + mid) == nil)
        #expect(BumpTieBreak.serviceName(mid).utf8.count <= 63, "Bonjour 名最长 63 字节")
    }

    @Test func 二维码内容() {
        let code = PairCode.random()
        #expect(PairCode.isValid(code))
        #expect(PairCode.qrPayload(code) == "jiefong:" + code)
        #expect(PairCode.parseQR(PairCode.qrPayload(code)) == code)
        #expect(PairCode.parseQR("  JIEFONG:" + code.uppercased() + "\n") == code, "大细楷、空白都收")
        #expect(PairCode.parseQR(code) == nil, "冇前缀")
        #expect(PairCode.parseQR("https://example.com/" + code) == nil)
        #expect(PairCode.parseQR("jiefong:" + code.dropLast()) == nil, "短咗")
        #expect(PairCode.parseQR("jiefong:" + code + "0") == nil, "长咗")
        #expect(PairCode.parseQR("jiefong:" + String(repeating: "g", count: 32)) == nil, "唔係十六进制")
        #expect(PairCode.parseQR("") == nil)
        #expect(Set((0..<200).map { _ in PairCode.random() }).count == 200)
    }

    @Test func 距离提示同进度环() {
        // 2026-10-17（D-2 / D-4）：30 厘米（隔一拳）保持 0.8 秒就算，唔使贴死。
        #expect(BumpTuning.nearDistance == 0.30 && BumpTuning.dwell == 0.8)
        #expect(BumpTuning.searchTimeout == 30 && BumpTuning.slowSearch < BumpTuning.searchTimeout, "D-6：30 秒失败，之前先提示用二维码")
        #expect(BumpTuning.progress(nil) == 0)
        #expect(BumpTuning.progress(1.5) == 0)
        #expect(BumpTuning.progress(BumpTuning.nearDistance) == 1)
        #expect(BumpTuning.progress(0.05) == 1)
        #expect((0.4...0.6).contains(BumpTuning.progress(0.75)))
        #expect(BumpTuning.hint(0.9) == "靠近啲")
        #expect(BumpTuning.hint(0.45) == "再近啲")
        #expect(BumpTuning.hint(0.25) == "好！拎穩唔好郁")
        #expect(BumpTuning.hint(nil) == "量緊距離…")
        var gate = ProximityGate()
        let r25 = gate.update(distance: 0.35, at: 0)
        #expect(!r25, "预设门限 30 厘米：35 厘米唔算")
        let r26 = gate.update(distance: 0.25, at: 0.1)
        #expect(!r26)
        let r27 = gate.update(distance: nil, at: 0.4)
        #expect(!r27)
        let r28 = gate.update(distance: 0.25, at: 0.6)
        #expect(!r28)
        let r29 = gate.update(distance: 0.25, at: 1.0)
        #expect(r29, "漏咗一下读数都照计")
    }

    @Test func 失败都有广东话解释() {
        let all: [BumpFailure] = [.unsupported, .localNetworkDenied, .nearbyDenied, .timeout, .background, .peerLeft, .noServer, .linkFailed, .network, .other]
        for f in all { #expect(!f.title.isEmpty && !f.hint.isEmpty) }
        #expect(BumpFailure.nearbyDenied.needsSettings && BumpFailure.localNetworkDenied.needsSettings)
        #expect(!BumpFailure.unsupported.canRetry && BumpFailure.timeout.canRetry)
    }
}

// MARK: - 后端轮询

/// 扮 link_neighbor：同一个码最多两个人；两个都交咗就互相返回对方。
@MainActor
final class FakePairServer {
    var submissions: [String: [String]] = [:]
    var profiles: [String: LinkedPeer] = [:]

    func link(user: String, code: String) -> LinkedPeer? {
        var s = submissions[code, default: []]
        if !s.contains(user) {
            guard s.count < 2 else { return nil }   // 第三部永远配唔上
            s.append(user)
        }
        submissions[code] = s
        guard s.count == 2, let other = s.first(where: { $0 != user }) else { return nil }
        return profiles[other]
    }

    static func peer(_ id: String, _ name: String) -> LinkedPeer {
        LinkedPeer(id: id, nickname: name, mobility: .walk, colorIndex: 1, skinTone: 1, ageGroup: .elder, block: nil, floor: 9)
    }
}

@MainActor
final class FakeLinker: NeighborLinker {
    let user: String
    let server: FakePairServer
    var calls = 0
    var nilFirst = 0
    var failing = false
    init(_ user: String, _ server: FakePairServer) { self.user = user; self.server = server }

    func link(code: String) async throws -> LinkedPeer? {
        calls += 1
        await Task.yield()
        if failing { throw URLError(.notConnectedToInternet) }
        if calls <= nilFirst { return nil }
        return server.link(user: user, code: code)
    }
}

@MainActor
struct LinkPollingTests {
    @Test func 配上就返回对方() async throws {
        let server = FakePairServer()
        server.profiles = ["a": FakePairServer.peer("a", "甲"), "b": FakePairServer.peer("b", "乙")]
        let code = PairCode.random()
        _ = server.link(user: "a", code: code)
        let lb = FakeLinker("b", server)
        lb.nilFirst = 2
        let p = try await LinkPolling.poll(lb, code: code, interval: 0.02, timeout: 30)
        #expect(p?.id == "a")
        #expect(lb.calls == 3)
        #expect(server.link(user: "c", code: code) == nil, "第三部配唔上")
        #expect(server.link(user: "a", code: code)?.id == "b", "两边都查到对方")
    }

    @Test func 够钟未配上返回nil() async throws {
        let l = FakeLinker("a", FakePairServer())
        let t0 = Date()
        let p = try await LinkPolling.poll(l, code: PairCode.random(), interval: 0.05, timeout: 0.3)
        #expect(p == nil)
        #expect(l.calls >= 1)
        #expect(Date().timeIntervalSince(t0) >= 0.25, "问到够钟先放弃")
    }

    @Test func 一直网络出错就抛错() async {
        let l = FakeLinker("a", FakePairServer())
        l.failing = true
        await #expect(throws: URLError.self) { try await LinkPolling.poll(l, code: PairCode.random(), interval: 0.05, timeout: 0.2) }
    }

    @Test func 测试后端过咗时间先配上() async throws {
        let t = LocalTestLinker()
        t.delay = 0.3
        let code = PairCode.random()
        #expect(try await t.link(code: code) == nil)
        try await Task.sleep(for: .seconds(0.35))
        let p = try await t.link(code: code)
        #expect(p == LocalTestLinker.peer(for: code))
        #expect(p?.nickname.hasPrefix("測試") == true)
        t.never = true
        #expect(try await t.link(code: PairCode.random()) == nil)
    }
}

// MARK: - 两部手机成个流程（假超宽带 + 真 Bonjour，模拟器上跑）

@MainActor
final class FakeRanging: BumpRanging {
    var isSupported = true
    var onDistance: ((Float?) -> Void)?
    var onFailure: ((BumpFailure) -> Void)?
    let token = Data(UUID().uuidString.utf8)
    var receivedToken: Data?
    var distances: [Float] = [0.9, 0.6, 0.35, 0.18, 0.15, 0.12]
    var hold: Float = 0.10
    private var task: Task<Void, Never>?

    func prepare() throws -> Data { token }

    func start(peerToken: Data) throws {
        receivedToken = peerToken
        let seq = distances, hold = hold
        task = Task { [weak self] in
            for d in seq {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                self?.onDistance?(d)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.onDistance?(hold)
            }
        }
    }

    func stop() { task?.cancel(); task = nil }
}

@MainActor
@Suite(.serialized)
struct NearbyBumpFlowTests {
    @Test func 唔支援就即刻讲() {
        let r = FakeRanging()
        r.isSupported = false
        let s = NearbyBumpService(ranging: { r })
        var updates: [BumpUpdate] = []
        s.startSearching(candidates: [], onUpdate: { updates.append($0) }, onFound: { _ in Issue.record("唔应该配上") })
        #expect(updates == [.failed(.unsupported)])
        #expect(s.phase == .idle)
    }

    @Test func 两部手机碰一碰配上() async throws {
        let server = FakePairServer()
        server.profiles = ["A": FakePairServer.peer("A", "甲"), "B": FakePairServer.peer("B", "乙")]
        let ra = FakeRanging(), rb = FakeRanging()
        let a = NearbyBumpService(ranging: { ra }, searchTimeout: 25), b = NearbyBumpService(ranging: { rb }, searchTimeout: 25)
        let la = FakeLinker("A", server), lb = FakeLinker("B", server)
        a.linker = la
        b.linker = lb
        var foundA: BumpMatch?, foundB: BumpMatch?
        var updA: [BumpUpdate] = [], updB: [BumpUpdate] = []
        a.startSearching(candidates: [], onUpdate: { updA.append($0) }, onFound: { foundA = $0 })
        b.startSearching(candidates: [], onUpdate: { updB.append($0) }, onFound: { foundB = $0 })
        let deadline = Date().addingTimeInterval(25)
        while (foundA == nil || foundB == nil), Date() < deadline,
              !updA.contains(where: { if case .failed = $0 { true } else { false } }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        a.cancel(); b.cancel()
        #expect(foundA == .linked(FakePairServer.peer("B", "乙")), "A 配到 B：\(updA)")
        #expect(foundB == .linked(FakePairServer.peer("A", "甲")), "B 配到 A：\(updB)")
        #expect(ra.receivedToken == rb.token && rb.receivedToken == ra.token, "超宽带令牌经加密通道交换")
        #expect(server.submissions.count == 1 && server.submissions.values.first?.count == 2, "两部交同一个码")
        #expect(updA.first == .searching && updA.contains(.linking) && updA.contains(.nearMe))
        #expect(updA.contains { if case .ranging(let d?) = $0 { d < 0.2 } else { false } })
    }

    @Test func 一部取消另一部知道() async throws {
        let ra = FakeRanging(), rb = FakeRanging()
        ra.distances = []; rb.distances = []
        ra.hold = 0.8; rb.hold = 0.8   // 一直唔够近
        let a = NearbyBumpService(ranging: { ra }, searchTimeout: 25), b = NearbyBumpService(ranging: { rb }, searchTimeout: 25)
        var updA: [BumpUpdate] = [], updB: [BumpUpdate] = []
        a.startSearching(candidates: [], onUpdate: { updA.append($0) }, onFound: { _ in Issue.record("唔应该配上") })
        b.startSearching(candidates: [], onUpdate: { updB.append($0) }, onFound: { _ in Issue.record("唔应该配上") })
        let deadline = Date().addingTimeInterval(20)
        func ranging(_ u: [BumpUpdate]) -> Bool { u.contains { if case .ranging = $0 { true } else { false } } }
        while !(ranging(updA) && ranging(updB)), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(ranging(updA) && ranging(updB), "两部都开始量：\(updA) / \(updB)")
        a.cancel()
        let d2 = Date().addingTimeInterval(5)
        while !updB.contains(.failed(.peerLeft)), Date() < d2 { try await Task.sleep(for: .milliseconds(100)) }
        #expect(updB.last == .failed(.peerLeft))
        #expect(b.phase == .idle)
        b.cancel()
    }

    /// D-2：中途超宽带出错 / 断线（唔係对方撳取消）：两部都静静重新搵，唔使撳「再試」，最后照样配上。
    @Test func 中途出错静静重新搵() async throws {
        let server = FakePairServer()
        server.profiles = ["A": FakePairServer.peer("A", "甲"), "B": FakePairServer.peer("B", "乙")]
        let ra = FakeRanging(), rb = FakeRanging()
        ra.distances = []; rb.distances = []
        ra.hold = 0.8; rb.hold = 0.8   // 第一轮一直唔够近
        let a = NearbyBumpService(ranging: { ra }, searchTimeout: 25), b = NearbyBumpService(ranging: { rb }, searchTimeout: 25)
        a.linker = FakeLinker("A", server)
        b.linker = FakeLinker("B", server)
        var foundA: BumpMatch?, foundB: BumpMatch?
        var updA: [BumpUpdate] = [], updB: [BumpUpdate] = []
        a.startSearching(candidates: [], onUpdate: { updA.append($0) }, onFound: { foundA = $0 })
        b.startSearching(candidates: [], onUpdate: { updB.append($0) }, onFound: { foundB = $0 })
        func ranging(_ u: [BumpUpdate]) -> Bool { u.contains { if case .ranging = $0 { true } else { false } } }
        func failed(_ u: [BumpUpdate]) -> Bool { u.contains { if case .failed = $0 { true } else { false } } }
        var deadline = Date().addingTimeInterval(15)
        while !(ranging(updA) && ranging(updB)), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(ranging(updA) && ranging(updB), "两部都开始量：\(updA) / \(updB)")
        ra.hold = 0.1; rb.hold = 0.1   // 重新开始之后就够近
        ra.onFailure?(.other)          // A 嘅超宽带出错
        deadline = Date().addingTimeInterval(20)
        while (foundA == nil || foundB == nil), Date() < deadline, !failed(updA), !failed(updB) {
            try await Task.sleep(for: .milliseconds(100))
        }
        a.cancel(); b.cancel()
        #expect(!failed(updA) && !failed(updB), "唔应该报失败：\(updA) / \(updB)")
        #expect(foundA == .linked(FakePairServer.peer("B", "乙")) && foundB == .linked(FakePairServer.peer("A", "甲")))
    }
}

// MARK: - 画面状态（store）

@MainActor
struct BumpStoreTests {
    func makeStore() -> AppStore {
        let s = AppStore()
        s.restoring = true
        s.clockTask?.cancel()
        s.announcer.voiceOverRunning = { false }
        s.localCommunity?.demoEnabled = false   // 真机模式
        s.residents = [Resident(id: "me", name: "你", floor: 12, colorIndex: 6, mobility: .walk, streakDays: 1, todayLine: "", isMe: true)]
        return s
    }

    @Test func 模拟器真机模式讲唔支援再转二维码() {
        let s = makeStore()
        s.startBump()
        #expect(s.bumpStage == .searching, "真机：圈入面冇人都照开碰一碰")
        // 有啲模拟器（例如 iPhone 17）报自己有超宽带：嗰度测唔到「唔支援」，只测转二维码。
        if !NearbyBumpService.deviceSupported { #expect(s.bumpProgress == .failed(.unsupported)) }
        s.bumpUseQR()
        #expect(s.bumpQR?.mode == .choose)
        s.cancelBump()
        #expect(s.bumpStage == .idle && s.bumpQR == nil)
    }

    @Test func 扫到唔啱嘅二维码讲清楚() {
        let s = makeStore()
        s.startBump()
        s.bumpScanQR()
        s.qrScanned("https://example.com")
        #expect(s.bumpQR?.note?.contains("唔係街坊行") == true)
        #expect(s.bumpQR?.linking == false)
        s.cancelBump()
    }

    @Test func 扫二维码配上就加街坊() async throws {
        let s = makeStore()
        LocalTestLinker.shared.delay = 0
        s.startBump()
        s.bumpScanQR()
        let code = PairCode.random()
        s.qrScanned(PairCode.qrPayload(code))
        #expect(s.bumpQR?.linking == true)
        let deadline = Date().addingTimeInterval(5)
        while s.bumpStage == .searching, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let peer = LocalTestLinker.peer(for: code)
        #expect(s.bumpStage == .found(peer.id))
        #expect(s.resident(peer.id)?.name == peer.nickname)
        #expect(LocalTestLinker.shared.submitted.contains(code))
        s.cancelBump()
    }

    @Test func 演示模式照用模拟() async throws {
        let s = makeStore()
        s.localCommunity?.demoEnabled = true
        s.residents.append(Resident(id: "wong", name: "黃太", floor: 3, colorIndex: 1, mobility: .walk, streakDays: 30, todayLine: ""))
        s.startBump()
        #expect(s.bumpStage == .searching && s.bumpProgress == .searching)
        let deadline = Date().addingTimeInterval(5)
        while s.bumpStage == .searching, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(s.bumpStage == .found("wong"))
    }
}
