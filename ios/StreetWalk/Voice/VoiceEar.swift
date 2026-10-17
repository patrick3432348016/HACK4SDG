import Foundation

// 组员 B 嘅豆包流式识别（2026-10-12）：手机收音 → Mac 语音服务器 /v1/voice/ear（WebSocket）→ 豆包，
// 讲完一句（豆包判定）就返嚟一句字。密钥只喺 Mac；局域网直连唔使登录，经 https 隧道要 Supabase 登录 token。
// 协议沿用 B（server/upstream_b/docs/DOUBAO-WINDOWS.md）：第一条 {token?, locale}，之后 16 kHz 单声道 PCM16（每段 200 ms），
// 服务器回 ready / transcript {text, final} / error。见 server/assistant/app_ear.py。

/// 一条识别通道。open() 等到 ready 先返回；之后嘅字经 onEvent 交返（主线程）。
@MainActor
final class VoiceEar {
    enum Event: Equatable {
        case partial(String)
        case final(String)
        case failed(String)
    }

    /// 音频线程直接送 PCM（攒够 200 ms 一段）。
    nonisolated let sender = EarSender()
    private let session = URLSession(configuration: .ephemeral)
    private var task: URLSessionWebSocketTask?
    private var generation = 0
    private var onEvent: ((Event) -> Void)?
    private var waiting: CheckedContinuation<Bool, Never>?

    var isOpen: Bool { task != nil }

    /// 「说完了」之后暂停收音（10-18 真机：一路听一路更新，答案一直出唔到）：照送静音俾豆包（佢会将讲紧嗰句收尾），
    /// 呢段时间嘅字唔要；答案讲完 release 先再听。holdGeneration 防止旧嘅等待解咗新嘅暂停。
    private(set) var held = false
    private(set) var holdGeneration = 0

    func hold() -> Int {
        holdGeneration += 1
        held = true
        sender.muted = true
        return holdGeneration
    }

    func release(_ gen: Int? = nil) {
        guard gen == nil || gen == holdGeneration else { return }
        held = false
        sender.muted = false
    }

    /// 连上并等豆包确认（最多 timeout 秒）。false = 连唔到（之后用返手机识别）。
    func open(_ url: URL, token: String?, locale: String, timeout: Double = 6, onEvent: @escaping (Event) -> Void) async -> Bool {
        close()
        generation += 1
        let gen = generation
        self.onEvent = onEvent
        let t = session.webSocketTask(with: url)
        t.maximumMessageSize = 1 << 20
        task = t
        t.resume()
        var hello: [String: String] = ["locale": locale]
        if let token { hello["token"] = token }
        let data = (try? JSONSerialization.data(withJSONObject: hello)) ?? Data()
        t.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
        receive(gen)
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            waiting = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, gen == self.generation else { return }
                self.resolve(false)
            }
        }
        if ok { sender.attach(t) } else { close() }
        return ok
    }

    func close() {
        generation += 1
        release()
        resolve(false)
        sender.attach(nil)
        if let t = task {
            t.send(.string(#"{"type":"stop"}"#)) { _ in }
            t.cancel(with: .normalClosure, reason: nil)
        }
        task = nil
        onEvent = nil
    }

    private func resolve(_ ok: Bool) {
        let c = waiting
        waiting = nil
        c?.resume(returning: ok)
    }

    private func receive(_ gen: Int) {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                switch result {
                case .failure:
                    if self.waiting != nil { self.resolve(false); return }
                    self.emit(.failed(L.t("連唔到語音伺服器。", "连不上语音服务器。", "Can't reach the voice server.")))
                case .success(let message):
                    if case .string(let s) = message { self.handle(s) }
                    self.receive(gen)
                }
            }
        }
    }

    private func handle(_ raw: String) {
        switch Self.parse(raw) {
        case .ready?: resolve(true)
        case .event(let e)?:
            if case .failed = e, waiting != nil { resolve(false); return }
            emit(e)
        case nil: break
        }
    }

    private func emit(_ e: Event) {
        let handler = onEvent
        if case .failed = e { close() }
        handler?(e)
    }

    enum Parsed: Equatable { case ready, event(Event) }

    /// 服务器一条讯息 → ready / 一句字 / 出错。其他（interrupted 等）唔理。纯逻辑，有单元测试。
    nonisolated static func parse(_ raw: String) -> Parsed? {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
              let type = obj["type"] as? String else { return nil }
        switch type {
        case "ready": return .ready
        case "transcript":
            guard let text = obj["text"] as? String else { return nil }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return .event((obj["final"] as? Bool) == true ? .final(t) : .partial(t))
        case "error":
            return .event(.failed((obj["message"] as? String) ?? L.t("語音識別出錯。", "语音识别出错。", "Speech recognition error.")))
        default: return nil
        }
    }
}

/// 音频线程用：攒够 6400 字节（16 kHz × 2 字节 × 0.2 秒）就经 WebSocket 送出。
final class EarSender: @unchecked Sendable {
    static let frameBytes = 6400
    private let lock = NSLock()
    private var buffer = Data()
    private var task: URLSessionWebSocketTask?
    private var _muted = false

    /// true：照送（保持连线、等豆包收尾），但送嘅系静音。
    var muted: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _muted }
        set { lock.lock(); _muted = newValue; lock.unlock() }
    }

    func attach(_ t: URLSessionWebSocketTask?) {
        lock.lock()
        task = t
        buffer = Data()
        lock.unlock()
    }

    func feed(_ pcm: Data) {
        lock.lock()
        buffer.append(_muted ? Data(count: pcm.count) : pcm)
        var frames: [Data] = []
        while buffer.count >= Self.frameBytes {
            frames.append(Data(buffer.prefix(Self.frameBytes)))
            buffer.removeFirst(Self.frameBytes)
        }
        let t = task
        lock.unlock()
        for f in frames { t?.send(.data(f)) { _ in } }
    }
}
