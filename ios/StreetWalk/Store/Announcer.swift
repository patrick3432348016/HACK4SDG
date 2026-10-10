import Accessibility
import AVFoundation
import UIKit

/// 成员 A：播报的排队与读屏兼容（审核 A90 / A77）。Speaker 归 B，这里不改它，只在 A 侧包一层：
/// - VoiceOver 开着：改发读屏公告（低优先级 = 排喺读屏之后），唔会两把声撞埋；
/// - 连续几句：讲完一句先讲下一句，唔再互相截断；
/// - 过期：资讯句排咗超过 6 秒就唔讲（画面上仍然有），语音唔会落后画面；
/// - 要回应嘅句子（复述确认、问题）优先：清走排喺前面嘅资讯句，永远唔会被挤走；
/// - 聆听中：先收起，停咪之后先讲（播报会抢走麦克风、仲会录埋入去）。
/// AppStore 经 say() 调用；其他地方唔好直接用 speaker.speak。
@MainActor
final class Announcer {
    /// prompt = 要用户回应（「啱就撳『好』」、「要唔要打電話」）；info = 讲完就算。
    enum Kind { case info, prompt }

    struct Line: Equatable {
        var text: String
        var kind: Kind
        var at: Date
    }

    /// 最多排几句：多咗先丢最早嘅资讯句。
    static let maxQueued = 3
    /// 资讯句排咗咁耐仲未讲到就唔讲。
    static let staleAfter: TimeInterval = 6

    private var queue: [Line] = []
    private var held: [Line] = []
    private var pump: Task<Void, Never>?
    /// 拎唔到合成器状态时，按字数估计讲完嘅时间。
    private var estimatedEnd = Date.distantPast

    /// 读屏开着时用公告（测试可以改）。
    var voiceOverRunning: () -> Bool = { UIAccessibility.isVoiceOverRunning }
    /// 时钟（测试可以改）。
    var clock: () -> Date = { Date() }
    /// 测试用：当成合成器讲紧 / 讲完。nil = 睇真嘅合成器。
    var busy: (() -> Bool)?

    func say(_ text: String, kind: Kind = .info, via speaker: Speaker, holding: Bool) {
        guard !text.isEmpty else { return }
        enqueue(Line(text: text, kind: kind, at: clock()), via: speaker, holding: holding)
    }

    /// 入队（停咪后交返嘅句子都经呢度，保留原来嘅时间，过期就唔讲）。
    func enqueue(_ line: Line, via speaker: Speaker, holding: Bool) {
        if holding { held.append(line); return }
        if isStale(line) { return }
        if voiceOverRunning() { announce(line.text); return }
        // 要回应嘅句子唔好排喺旧资讯后面。
        if line.kind == .prompt { queue.removeAll { $0.kind == .info } }
        if queue.isEmpty && !isSpeaking(speaker) {
            speakNow(line.text, speaker)
            return
        }
        queue.append(line)
        while queue.count > Self.maxQueued {
            if let i = queue.firstIndex(where: { $0.kind == .info }) { queue.remove(at: i) } else { queue.removeFirst() }
        }
        drain(speaker)
    }

    /// 开始聆听：停咗正在讲嘅，未讲嘅留到停咪之后。
    func hold(_ speaker: Speaker) {
        held = queue + held
        queue = []
        pump?.cancel()
        pump = nil
        speaker.announcerSynth?.stopSpeaking(at: .immediate)
        estimatedEnd = .distantPast
    }

    /// 停咪：交返聆听期间收起嘅句子（由调用方喺回应之后再入队）。
    func release() -> [Line] {
        defer { held = [] }
        return held
    }

    /// 排紧（未讲）嘅句子，测试用。
    var queued: [Line] { queue }
    var pendingCount: Int { queue.count + held.count }

    // MARK: - 内部

    private func isStale(_ line: Line) -> Bool {
        line.kind == .info && clock().timeIntervalSince(line.at) > Self.staleAfter
    }

    private func announce(_ text: String) {
        var a = AttributedString(text)
        a.languageIdentifier = "zh-HK"
        a.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(a).post()
    }

    private func speakNow(_ text: String, _ speaker: Speaker) {
        speaker.speak(text)
        // 粤语约每秒 3.5 个字（rate 0.42），加少少停顿。
        estimatedEnd = Date().addingTimeInterval(Double(text.count) / 3.5 + 0.5)
    }

    private func drain(_ speaker: Speaker) {
        guard pump == nil else { return }
        pump = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, !self.queue.isEmpty {
                if self.isSpeaking(speaker) {
                    try? await Task.sleep(for: .milliseconds(150))
                    continue
                }
                if self.voiceOverRunning() {
                    self.queue.filter { !self.isStale($0) }.forEach { self.announce($0.text) }
                    self.queue = []
                    break
                }
                let line = self.queue.removeFirst()
                if self.isStale(line) { continue }
                self.speakNow(line.text, speaker)
                try? await Task.sleep(for: .milliseconds(300))
            }
            self?.pump = nil
        }
    }

    private func isSpeaking(_ speaker: Speaker) -> Bool {
        if let busy { return busy() }
        if let s = speaker.announcerSynth { return s.isSpeaking }
        return Date() < estimatedEnd
    }
}

extension Speaker {
    /// Speaker 归 B，未公开「讲紧未 / 即刻停」（已请 B 加 isSpeaking、stop()）。暂时经反射读佢嘅合成器，
    /// 只喺呢一处；B 一加就改呢度，Announcer 其余唔使改。读唔到会退回按字数估时，单元测试会报错提醒。
    var announcerSynth: AVSpeechSynthesizer? {
        Mirror(reflecting: self).children.first { $0.label == "synth" }?.value as? AVSpeechSynthesizer
    }
}
