import Foundation
import CryptoKit

// 碰一碰两部手机之间嘅传输格式（纯逻辑，冇硬件，全部有单元测试）。
// FrameBuffer、SequenceGuard 移植自组员 B 嘅 UWB 原型（ios/UWBMeetDemo/Core/FrameBuffer.swift、Models.swift，原檔唔郁）。
// 同 B 原型唔同：唔再要人手输入 20 位配对码——连上之后用一次性 Curve25519 密钥协商出加密钥匙（见 BumpChannel）。
//
// 安全说明（演示级，未经安全审计）：
// - 密钥协商挡得住旁边偷听；但冇身份认证，挡唔住喺本地网络做中间人。
// - 真正将「呢次连接」绑到「面前呢个人」嘅係超宽带：令牌经加密通道交换，距离要连续 ≤ 20 厘米先算碰到，
//   中间人要真係贴住你部手机先量得到咁近。
// - 后端（link_neighbor）只认两部手机交同一个一次性码，第三部永远配唔上；码用一次就作废。

/// TCP 上嘅长度前缀记录（4 字节大端长度 + 内容）。处理半个表头、几条黏埋一齐。组员 B。
struct FrameBuffer {
    static let maximum = 65_536
    enum Failure: Error { case invalidLength }
    private var buffer = Data()

    static func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximum else { throw Failure.invalidLength }
        let n = UInt32(payload.count)
        var result = Data([UInt8((n >> 24) & 255), UInt8((n >> 16) & 255),
                           UInt8((n >> 8) & 255), UInt8(n & 255)])
        result.append(payload)
        return result
    }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var records: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= Self.maximum else { throw Failure.invalidLength }
            guard buffer.count >= length + 4 else { break }
            records.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(length + 4))
        }
        return records
    }
}

/// 一次性配对码：128 bit 随机，32 位小写十六进制（NeighborLinking.swift 嘅约定）。二维码内容係 `jiefong:<码>`。
enum PairCode {
    static let qrPrefix = "jiefong:"

    static func random() -> String {
        // SymmetricKey 用系统嘅密码学随机数。
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }.hex
    }

    static func isValid(_ code: String) -> Bool {
        code.count == 32 && code.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    static func qrPayload(_ code: String) -> String { qrPrefix + code }

    /// 扫到嘅内容 → 码。唔係街坊行嘅二维码返回 nil。前缀唔分大小写，前后空白照收。
    static func parseQR(_ payload: String) -> String? {
        let s = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.lowercased().hasPrefix(qrPrefix) else { return nil }
        let code = String(s.dropFirst(qrPrefix.count)).lowercased()
        return isValid(code) ? code : nil
    }
}

/// 两部手机点样决定边部主动连：各自开一个随机 128 bit 实例 id，放喺 Bonjour 服务名入面；
/// id 细嘅一方连 id 大嘅一方，所以两部手机之间只会有一条连接。
enum BumpTieBreak {
    static let serviceType = "_jiefong._tcp"
    static let prefix = "jf-"

    static func newInstanceID() -> String { PairCode.random() }
    static func serviceName(_ id: String) -> String { prefix + id }

    static func instanceID(fromServiceName name: String) -> String? {
        guard name.hasPrefix(prefix) else { return nil }
        let id = String(name.dropFirst(prefix.count))
        return PairCode.isValid(id) ? id : nil
    }

    /// 我主动连对方？（id 细嘅连 id 大嘅；一样就唔连）
    static func shouldConnect(me: String, peer: String) -> Bool { me < peer }

    /// 同时见到几部（演示只预两部）：喺 id 比我大嘅入面揀最细嗰部，冇就等人连我。
    static func pick(me: String, visible: [String]) -> String? {
        visible.filter { shouldConnect(me: me, peer: $0) }.min()
    }
}

/// 连上之后第一条记录（明文）：版本、我嘅实例 id、一次性公钥。
struct BumpHello: Codable, Equatable {
    var version = 1
    let id: String
    let key: Data
}

/// 加密通道入面嘅消息。
struct BumpMessage: Codable, Equatable {
    enum Kind: String, Codable {
        /// 第一条：超宽带令牌（NIDiscoveryToken 归档）。
        case hello
        /// 我呢边量到够近（ProximityGate 触发）。
        case near
        /// 主动连嗰方定嘅一次性码（两边都够近之后先发）。
        case code
        /// 取消 / 停咗。
        case cancel
    }
    var version = 1
    let session: UUID
    let sequence: Int
    let kind: Kind
    var token: Data?
    var code: String?
}

/// 防重放：第一条一定係 hello，之后同一个会话、序号逐个加一。组员 B（改用 BumpMessage）。
struct SequenceGuard {
    private var session: UUID?
    private var next = 0

    mutating func accept(_ message: BumpMessage) -> Bool {
        guard message.version == 1, message.sequence == next else { return false }
        if let session {
            guard message.session == session, message.kind != .hello else { return false }
        } else {
            guard message.kind == .hello else { return false }
            session = message.session
        }
        next += 1
        return true
    }
}

/// 加密通道：一次性 Curve25519 密钥协商 → HKDF 分出两条方向嘅钥匙 → ChaChaPoly。
/// 两个方向用唔同钥匙：将我自己嘅消息反射返嚟都会解唔开。
struct BumpChannel {
    enum Failure: Error { case badKey, badHello, decrypt, replay, malformed }
    static let context = Data("jiefong/bump/v1".utf8)

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private let session = UUID()
    private var sequence = 0
    private var inbound = SequenceGuard()

    /// - initiator: 我係唔係主动连嗰方（id 细嗰方）。
    init(myKey: Curve25519.KeyAgreement.PrivateKey, myID: String, peer: BumpHello, initiator: Bool) throws {
        guard peer.version == 1, peer.key.count == 32, PairCode.isValid(peer.id), peer.id != myID else { throw Failure.badHello }
        // 主动连嗰方一定係 id 细嗰方（BumpTieBreak）；唔夹就唔信。
        guard BumpTieBreak.shouldConnect(me: initiator ? myID : peer.id, peer: initiator ? peer.id : myID) else { throw Failure.badHello }
        let peerKey: Curve25519.KeyAgreement.PublicKey
        do { peerKey = try .init(rawRepresentation: peer.key) } catch { throw Failure.badKey }
        let shared = try myKey.sharedSecretFromKeyAgreement(with: peerKey)
        guard shared.withUnsafeBytes({ $0.contains { $0 != 0 } }) else { throw Failure.badKey }   // 低阶点 → 全零
        let mine = myKey.publicKey.rawRepresentation
        let (iID, rID) = initiator ? (myID, peer.id) : (peer.id, myID)
        let (iKey, rKey) = initiator ? (mine, peer.key) : (peer.key, mine)
        let transcript = Self.context + Data(iID.utf8) + Data(rID.utf8) + iKey + rKey
        func derive(_ label: String) -> SymmetricKey {
            shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Self.context,
                                           sharedInfo: transcript + Data(label.utf8), outputByteCount: 32)
        }
        let i2r = derive("i2r"), r2i = derive("r2i")
        sendKey = initiator ? i2r : r2i
        receiveKey = initiator ? r2i : i2r
    }

    /// 封好一条消息，返回可以直接写落 TCP 嘅帧。
    mutating func seal(_ kind: BumpMessage.Kind, token: Data? = nil, code: String? = nil) throws -> Data {
        let m = BumpMessage(session: session, sequence: sequence, kind: kind, token: token, code: code)
        let plain = try JSONEncoder().encode(m)
        let box = try ChaChaPoly.seal(plain, using: sendKey, authenticating: Self.context)
        sequence += 1
        return try FrameBuffer.frame(box.combined)
    }

    /// 解开一条记录（已去咗长度前缀）。解唔开、格式唔啱、重放都会抛错。
    mutating func open(_ record: Data) throws -> BumpMessage {
        let plain: Data
        do { plain = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: record), using: receiveKey, authenticating: Self.context) }
        catch { throw Failure.decrypt }
        guard let m = try? JSONDecoder().decode(BumpMessage.self, from: plain) else { throw Failure.malformed }
        guard inbound.accept(m) else { throw Failure.replay }
        if let t = m.token, t.count > 16_384 { throw Failure.malformed }
        if m.kind == .hello, m.token == nil { throw Failure.malformed }
        if m.kind == .code, !PairCode.isValid(m.code ?? "") { throw Failure.malformed }
        return m
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
