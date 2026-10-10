import Foundation
import Network
import CryptoKit

/// One demo pair, one TCP connection. Payloads authenticated/encrypted using CryptoKit.
/// A fresh 80-bit code is shared face-to-face before ranging, never sent on the network.
final class PeerTransport {
    static let serviceType = "_uwbmeet._tcp"
    var onReady: (() -> Void)?
    var onMessage: ((WireMessage) -> Void)?
    var onFailure: ((String) -> Void)?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var key: SymmetricKey?
    private var frames = FrameBuffer()
    private var inbound = SequenceGuard()
    private var session = UUID()
    private var sequence = 0
    private var generation = UUID()
    private let context = Data("Hack4SDG/UWBMeet/v1".utf8)

    static func newCode() -> String {
        // Swift's default random generator uses the system's cryptographically secure source.
        let raw = (0..<10).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined()
        return stride(from: 0, to: 20, by: 5).map { offset in
            String(raw.dropFirst(offset).prefix(5))
        }.joined(separator: "-")
    }

    static func normalized(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    static func validCode(_ code: String) -> Bool {
        let code = normalized(code)
        return code.count == 20 && code.allSatisfy { "0123456789ABCDEF".contains($0) }
    }

    func start(host: Bool, code: String) throws {
        stop()
        let current = generation
        let normalized = Self.normalized(code)
        guard Self.validCode(normalized) else { throw TransportError.badCode }
        key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(normalized.utf8)),
                                    salt: context, info: Data("contact-channel".utf8), outputByteCount: 32)
        let serviceName = "meet-" + SHA256.hash(data: Data(normalized.utf8)).prefix(6)
            .map { String(format: "%02x", $0) }.joined()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        if host {
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, self.generation == current else { return }
                if case .failed(let error) = state { self.fail("发布失败：\(error.localizedDescription)") }
            }
            listener.newConnectionHandler = { [weak self] candidate in
                guard let self, self.generation == current, self.connection == nil else {
                    candidate.cancel(); return
                }
                self.attach(candidate, generation: current)
            }
            listener.start(queue: .main)
        } else {
            let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
            self.browser = browser
            browser.stateUpdateHandler = { [weak self] state in
                guard let self, self.generation == current else { return }
                switch state {
                case .failed(let error): self.fail("搜索失败：\(error.localizedDescription)")
                case .waiting(let error): self.onFailure?("搜索受阻，请检查本地网络权限：\(error.localizedDescription)")
                default: break
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self, self.generation == current, self.connection == nil else { return }
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint, name == serviceName {
                        self.attach(NWConnection(to: result.endpoint, using: parameters), generation: current)
                        break
                    }
                }
            }
            browser.start(queue: .main)
        }
    }

    private func attach(_ connection: NWConnection, generation current: UUID) {
        self.connection = connection
        browser?.cancel()
        browser = nil
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, self.generation == current, let connection,
                  self.connection === connection else { return }
            switch state {
            case .ready: self.onReady?(); self.receive(connection, generation: current)
            case .failed(let error): self.fail("连接失败：\(error.localizedDescription)")
            case .waiting(let error): self.fail("连接不可用：\(error.localizedDescription)")
            default: break
            }
        }
        connection.start(queue: .main)
    }

    func send(_ kind: MessageKind, profile: PublicProfile? = nil, token: Data? = nil,
              contact: SharedContact? = nil, completion: (() -> Void)? = nil) {
        guard let connection, let key else { fail("连接尚未建立"); return }
        do {
            let message = WireMessage(version: 1, session: session, sequence: sequence,
                                      kind: kind, profile: profile, token: token, contact: contact)
            let plaintext = try JSONEncoder().encode(message)
            let encrypted = try ChaChaPoly.seal(plaintext, using: key, authenticating: context).combined
            let frame = try FrameBuffer.frame(encrypted)
            sequence += 1
            let current = generation
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                guard let self, self.generation == current else { return }
                if let error { self.fail("发送失败：\(error.localizedDescription)") }
                else { completion?() }
            })
        } catch { fail("无法编码或加密消息") }
    }

    private func receive(_ connection: NWConnection, generation current: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self, self.generation == current else { return }
            do {
                if let data, let key = self.key {
                    for frame in try self.frames.append(data) {
                        let box = try ChaChaPoly.SealedBox(combined: frame)
                        let plain = try ChaChaPoly.open(box, using: key, authenticating: self.context)
                        let message = try JSONDecoder().decode(WireMessage.self, from: plain)
                        guard self.inbound.accept(message) else { throw TransportError.invalidMessage }
                        self.onMessage?(message)
                        guard self.generation == current else { return }
                    }
                }
                if error != nil || done { self.fail("对方已断开连接，请重新开始") }
                else { self.receive(connection, generation: current) }
            } catch { self.fail("消息验证失败，请核对配对码并重新开始") }
        }
    }

    private func fail(_ message: String) {
        stop()
        onFailure?(message)
    }

    func stop() {
        generation = UUID()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        key = nil
        frames = FrameBuffer()
        inbound = SequenceGuard()
        sequence = 0
        session = UUID()
    }

    enum TransportError: Error { case badCode, invalidMessage }
}

