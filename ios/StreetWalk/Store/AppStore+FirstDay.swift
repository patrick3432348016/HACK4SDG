import AVFoundation
import SwiftUI

/// 「今日三件事」任务卡嘅进度（存档 SavedState.firstDay）。
/// 字段全部可选：以后加字段，旧存档照样读得返（缺嘅当 nil）。
struct FirstDayProgress: Codable, Equatable {
    /// 完成首次使用嘅时间（任务卡由呢刻开始）。
    var started: Date?
    /// 之后行咗几多分钟（真机散步、演示散步都计）。
    var walkMinutes: Int?
    /// 有街坊喇（碰过一碰）。
    var bumped: Bool?
    /// 约过街坊（自己约，或者应承咗人哋嘅约）。
    var invited: Bool?
    /// 三件做齐嘅时间。
    var finishedAt: Date?
    /// 做齐之后卡已经收埋（唔再出）。
    var closed: Bool?

    static let walkGoal = 10

    var walked: Bool { (walkMinutes ?? 0) >= Self.walkGoal }
    var doneCount: Int { [walked, bumped == true, invited == true].filter { $0 }.count }
    var allDone: Bool { doneCount == 3 }
}

// 首次使用之后：「今日三件事」任务卡（UI/FirstDayCard），同首次使用最后一步「試一次」撳咪。
extension AppStore {
    // MARK: - 今日三件事

    /// 任务卡要唔要出：完成首次使用后、未收埋；三件未做齐就最多出 7 日。
    var showsFirstDay: Bool {
        guard phase == .main, let f = firstDay, f.closed != true, let start = f.started else { return false }
        return f.finishedAt != nil || Date().timeIntervalSince(start) < 7 * 86400
    }

    /// 第一次完成首次使用（改楼唔算）：开始任务卡。
    func startFirstDay() {
        guard firstDay == nil else { return }
        firstDay = FirstDayProgress(started: Date())
    }

    /// 记好一次散步（recordWalk）：累计分钟，够 10 分钟就打勾。
    func firstDayWalked(_ minutes: Int) {
        guard var f = firstDay, f.finishedAt == nil, minutes > 0 else { return }
        f.walkMinutes = (f.walkMinutes ?? 0) + minutes
        firstDay = f
        firstDayCheck()
    }

    /// 睇吓有冇新做好嘅（存盘后、任务卡出现时叫）：有街坊 → 碰一碰；约过 → 约佢。三件做齐讲一声。
    func firstDayCheck() {
        guard var f = firstDay, f.finishedAt == nil else { return }
        if f.bumped != true, !neighbors.isEmpty { f.bumped = true }
        if f.invited != true, appointments.contains(where: { !$0.fromPartner || $0.status == .accepted || $0.status == .done }) { f.invited = true }
        if f.allDone {
            f.finishedAt = Date()
            say(L.t("今日三件事做齊晒，好叻！", "今天三件事都做完了，真棒！"))
        }
        if f != firstDay { firstDay = f }
    }

    /// 做齐之后收埋任务卡。
    func closeFirstDay() {
        guard firstDay?.finishedAt != nil else { return }
        firstDay?.closed = true
    }

    /// 任务卡「約佢聽日一齊行」：有街坊就即刻出约人卡（聽日）；未有就讲要先碰一碰。
    func firstDayInvite() {
        guard let n = neighbors.first else {
            toast(L.t("要先見面碰一碰做街坊，先約得。", "要先见面碰一碰成为邻居，才能约。"))
            return
        }
        proposeMeetup(with: n.id, day: 1)
    }

    // MARK: - 首次使用「試一次」撳咪

    /// 开始听（第一次会问咪同语音识别权限）。返回 false = 用唔到咪（界面叫用户撳「或者撳呢句」）。
    /// 同主画面个咪（AppStore+Voice.micTapped）一样嘅步骤，但听到嘅字交俾引导自己答（唔经约人流程）。
    func tryMicStart() async -> Bool {
        guard !listening, !micStarting else { return false }
        micStarting = true
        defer { micStarting = false }
        let auth = await ensureVoiceAuth()
        guard auth.granted else { return false }
        if auth.prompted { try? await Task.sleep(for: .milliseconds(400)) }
        guard phase == .onboarding(.tryMic), AVAudioSession.sharedInstance().isInputAvailable else { return false }
        announcer.hold(speaker)
        do {
            try listener.start()
            listening = true
            Haptics.light()
            return true
        } catch {
            listening = false
            _ = announcer.release()
            return false
        }
    }

    /// 停咪，返回听到嘅字（冇就空）。聆听期间收起嘅句子唔再讲（引导每步只讲一句）。
    @discardableResult
    func tryMicStop() -> String {
        guard listening else { return "" }
        let text = listener.stop()
        listening = false
        _ = announcer.release()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 「今日天氣點」嘅答案：天文台实时天气（同「今日」页天气卡同一句）；未攞到就讲去边睇。
    var tryAnswer: String {
        if let tip = weatherTip, !tip.isEmpty { return tip }
        if let line = hko.report?.line, !line.isEmpty { return line }
        return L.t("而家未攞到天氣。入到去「今日」頁，會見到天氣同邊度有陰。", "现在还没拿到天气。进入「今日」页，会看到天气和哪里有阴凉。")
    }
}

extension Notification.Name {
    /// 自动演示脚本（-scriptOnboarding）：喺「試一次」一步当撳咗「或者撳呢句」。
    static let onbTryPhrase = Notification.Name("streetwalk.onbTryPhrase")
}
