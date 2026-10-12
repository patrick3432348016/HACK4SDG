import Accessibility
import AVFoundation
import UIKit

/// 成员 A：播报的排队与读屏兼容（审核 A90 / A77）。Speaker 归 B，这里只在 A 侧包一层：
/// - VoiceOver 开着：改发读屏公告（低优先级 = 排喺读屏之后），唔会两把声撞埋；
/// - 新嘅取代旧嘅（2026-10-12，用户：「切到画面上一个画面声音没有停一直播」）：讲紧嘅句子已经讲咗超过 burstWindow，
///   新句一到就截断佢、清走排队，即刻讲新句（画面换咗 / 用户撳咗掣，旧嘅唔再啱；结果句唔会排到过期冇咗）；
/// - 同一个动作连住出几句（burstWindow 之内）：讲完一句先讲下一句；
/// - interrupt()：停低兼清空——换标签、关卡、取消、开关设定、引导换页、退后台（AppStore.hush()）；
/// - 过期：资讯句排咗超过 6 秒就唔讲（画面上仍然有），语音唔会落后画面；
/// - 要回应嘅句子（复述确认、问题）优先：清走排喺前面嘅资讯句，永远唔会被挤走；
/// - 聆听中：先收起，停咪之后先讲（播报会抢走麦克风、仲会录埋入去）；
/// - 设定「語音播報」关咗：唔自动读（读屏公告照出）；用户亲手撳「再聽一次」（force）仍然读。
/// AppStore 经 say() 调用；其他地方唔好直接用 speaker.speak。
@MainActor
final class Announcer {
    /// prompt = 要用户回应（「啱就撳『好』」、「要唔要打電話」）；info = 讲完就算。
    enum Kind { case info, prompt }

    struct Line: Equatable {
        var text: String
        var kind: Kind
        var at: Date
        /// 用户亲手要求（「再聽一次」）：「語音播報」关咗都读。
        var force = false
    }

    /// 最多排几句：多咗先丢最早嘅资讯句。
    static let maxQueued = 3
    /// 同一个动作连住出嘅几句：呢个时间之内嘅新句排队，唔截断。
    static let burstWindow: TimeInterval = 0.5
    /// 资讯句排咗咁耐仲未讲到就唔讲。
    static let staleAfter: TimeInterval = 6

    private var queue: [Line] = []
    private var held: [Line] = []
    private var pump: Task<Void, Never>?
    /// 而家讲紧嘅（经 Announcer 开始嘅）同几时开始。
    private var current: (line: Line, at: Date)?

    /// 读屏开着时用公告（测试可以改）。
    var voiceOverRunning: () -> Bool = { UIAccessibility.isVoiceOverRunning }
    /// 时钟（测试可以改）。
    var clock: () -> Date = { Date() }
    /// 测试用：当成合成器讲紧 / 讲完。nil = 睇真嘅合成器。
    var busy: (() -> Bool)?

    func say(_ text: String, kind: Kind = .info, force: Bool = false, via speaker: Speaker, holding: Bool) {
        guard !text.isEmpty else { return }
        enqueue(Line(text: text, kind: kind, at: clock(), force: force), via: speaker, holding: holding)
    }

    /// 入队（停咪后交返嘅句子都经呢度，保留原来嘅时间，过期就唔讲）。
    func enqueue(_ line: Line, via speaker: Speaker, holding: Bool) {
        if holding { held.append(line); return }
        if isStale(line) { return }
        if voiceOverRunning() { announce(line.text, speaker); return }
        if !line.force && !speaker.settings.enabled { return }
        let speaking = isSpeaking(speaker)
        if !speaking { current = nil }
        // 新嘅取代旧嘅：讲紧嘅已经讲咗一阵（唔系同一个动作连住出嘅），即刻截断。
        if speaking, current.map({ clock().timeIntervalSince($0.at) >= Self.burstWindow }) ?? true {
            interrupt(speaker)
            speakNow(line, speaker)
            return
        }
        // 要回应嘅句子唔好排喺旧资讯后面。
        if line.kind == .prompt { queue.removeAll { $0.kind == .info } }
        if queue.isEmpty && !speaking {
            speakNow(line, speaker)
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
        current = nil
        speaker.stop()
    }

    /// 停低兼清空（画面换咗、用户取消）：讲紧嘅、排紧嘅、聆听时收起嘅都唔再讲。
    func interrupt(_ speaker: Speaker) {
        queue = []
        held = []
        pump?.cancel()
        pump = nil
        current = nil
        speaker.stop()
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

    private func announce(_ text: String, _ speaker: Speaker) {
        var a = AttributedString(text)
        a.languageIdentifier = speaker.settings.language.bcp47
        a.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(a).post()
    }

    private func speakNow(_ line: Line, _ speaker: Speaker) {
        current = (line, clock())
        speaker.speak(line.text)
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
                    self.queue.filter { !self.isStale($0) }.forEach { self.announce($0.text, speaker) }
                    self.queue = []
                    break
                }
                let line = self.queue.removeFirst()
                if self.isStale(line) || (!line.force && !speaker.settings.enabled) { continue }
                self.speakNow(line, speaker)
                try? await Task.sleep(for: .milliseconds(300))
            }
            self?.pump = nil
        }
    }

    private func isSpeaking(_ speaker: Speaker) -> Bool {
        if let busy { return busy() }
        return speaker.isSpeaking
    }
}
