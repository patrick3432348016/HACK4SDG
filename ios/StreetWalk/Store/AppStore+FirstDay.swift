import AVFoundation
import SwiftUI

/// First-day three-task progress persisted in SavedState.firstDay.
/// All fields are optional so future additions remain compatible with older saves.
struct FirstDayProgress: Codable, Equatable {
    /// Onboarding completion time, when the task card begins.
    var started: Date?
    /// Walking minutes since onboarding, including real and demo walks.
    var walkMinutes: Int?
    /// Has a neighbor after pairing.
    var bumped: Bool?
    /// Has arranged a walk, either by inviting or accepting.
    var invited: Bool?
    /// Time all three tasks were completed.
    var finishedAt: Date?
    /// Whether the completed card has been dismissed permanently.
    var closed: Bool?

    static let walkGoal = 10

    var walked: Bool { (walkMinutes ?? 0) >= Self.walkGoal }
    var doneCount: Int { [walked, bumped == true, invited == true].filter { $0 }.count }
    var allDone: Bool { doneCount == 3 }
}

// Post-onboarding FirstDayCard and the final onboarding microphone trial.
extension AppStore {
    // MARK: - Three first-day tasks

    /// Show after onboarding until dismissed; incomplete cards remain for at most seven days.
    var showsFirstDay: Bool {
        guard phase == .main, let f = firstDay, f.closed != true, let start = f.started else { return false }
        return f.finishedAt != nil || Date().timeIntervalSince(start) < 7 * 86400
    }

    /// Start tasks only after first onboarding, not after changing home.
    func startFirstDay() {
        guard firstDay == nil else { return }
        firstDay = FirstDayProgress(started: Date())
    }

    /// Accumulate recorded walk minutes and check the task at ten minutes.
    func firstDayWalked(_ minutes: Int) {
        guard var f = firstDay, f.finishedAt == nil, minutes > 0 else { return }
        f.walkMinutes = (f.walkMinutes ?? 0) + minutes
        firstDay = f
        firstDayCheck()
    }

    /// Reevaluate after persistence/card appearance: neighbor means paired, meetup means invited; announce completion once.
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

    /// Hide the card after completion.
    func closeFirstDay() {
        guard firstDay?.finishedAt != nil else { return }
        firstDay?.closed = true
    }

    /// First-day invitation action: open a draft for tomorrow if a neighbor exists; otherwise explain that pairing is required first.
    func firstDayInvite() {
        guard let n = neighbors.first else {
            toast(L.t("要先見面碰一碰做街坊，先約得。", "要先见面碰一碰成为邻居，才能约。"))
            return
        }
        proposeMeetup(with: n.id, day: 1)
    }

    // MARK: - Onboarding microphone trial

    /// Start listening; first use requests microphone and speech permissions. False means unavailable; offer the example button.
    /// Follow AppStore+Voice.micTapped, but route recognized text to onboarding instead of invitations.
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

    /// Stop listening and return the transcript or an empty string. Discard deferred speech; each onboarding step speaks once.
    @discardableResult
    func tryMicStop() -> String {
        guard listening else { return "" }
        let text = listener.stop()
        listening = false
        _ = announcer.release()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Answer the weather question using the live HKO sentence from Today, or explain where to check if unavailable.
    var tryAnswer: String {
        if let tip = weatherTip, !tip.isEmpty { return tip }
        if let line = hko.report?.line, !line.isEmpty { return line }
        return L.t("而家未攞到天氣。入到去「今日」頁，會見到天氣同邊度有陰。", "现在还没拿到天气。进入「今日」页，会看到天气和哪里有阴凉。")
    }
}

extension Notification.Name {
    /// -scriptOnboarding simulates tapping the example during the trial step.
    static let onbTryPhrase = Notification.Name("streetwalk.onbTryPhrase")
}
