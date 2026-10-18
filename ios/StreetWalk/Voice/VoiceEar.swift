import Foundation

// B's Doubao streaming recognition (2026-10-12): phone capture to Mac /v1/voice/ear WebSocket to Doubao.
// Return completed transcripts; keys remain on the server. Direct LAN access is unauthenticated; HTTPS tunnels require a Supabase token.
// Follow B's DOUBAO-WINDOWS protocol: initial token/locale JSON, then 200 ms chunks of 16 kHz mono PCM16.
// Server emits ready, transcript with text/final, or error; see assistant/app_ear.py.

/// open waits for ready; subsequent events arrive through onEvent on the main thread.
@MainActor
final class VoiceEar {
    enum Event: Equatable {
        case partial(String)
        case final(String)
        case failed(String)
    }

    /// Send PCM directly from the audio thread, buffering 200 ms per chunk.
    nonisolated let sender = EarSender()
    private let session = URLSession(configuration: .ephemeral)
    private var task: URLSessionWebSocketTask?
    private var generation = 0
    private var onEvent: ((Event) -> Void)?
    private var waiting: CheckedContinuation<Bool, Never>?

    var isOpen: Bool { task != nil }

    /// Connect and await Doubao readiness up to timeout seconds; false triggers device-recognition fallback.
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
                    self.emit(.failed(L.t("連唔到語音伺服器。", "连不上语音服务器。")))
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

    /// Pure, tested message parser for ready/transcript/error; ignore other messages such as interrupted.
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
            return .event(.failed((obj["message"] as? String) ?? L.t("語音識別出錯。", "语音识别出错。")))
        default: return nil
        }
    }
}

/// Audio-thread buffer sends 6400-byte chunks: 16 kHz * 2 bytes * 0.2 seconds.
final class EarSender: @unchecked Sendable {
    static let frameBytes = 6400
    private let lock = NSLock()
    private var buffer = Data()
    private var task: URLSessionWebSocketTask?

    func attach(_ t: URLSessionWebSocketTask?) {
        lock.lock()
        task = t
        buffer = Data()
        lock.unlock()
    }

    func feed(_ pcm: Data) {
        lock.lock()
        buffer.append(pcm)
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
