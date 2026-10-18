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
    /// User checkbox override (J-2): true checked, false unchecked, nil follows automatic detection.
    var walkMark: Bool?
    var bumpMark: Bool?
    var inviteMark: Bool?

    static let walkGoal = 10

    enum Item { case walk, bump, invite }

    var walked: Bool { (walkMinutes ?? 0) >= Self.walkGoal }
    /// Effective checked state, respecting an explicit user override.
    func isDone(_ i: Item) -> Bool {
        switch i {
        case .walk: return walkMark ?? walked
        case .bump: return bumpMark ?? (bumped == true)
        case .invite: return inviteMark ?? (invited == true)
        }
    }
    var doneCount: Int { [isDone(.walk), isDone(.bump), isDone(.invite)].filter { $0 }.count }
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
        if f.walkMark == false, f.walked { f.walkMark = nil }     // After a manual uncheck, another ten minutes can check it automatically again.
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
            say(L.t("今日三件事做齊晒，好叻！", "今天三件事都做完了，真棒！", "All 3 things done today. Well done!"))
        }
        if f != firstDay { firstDay = f }
    }

    /// Count an active walk toward ten minutes immediately instead of waiting for return home (A-3).
    func firstDayDone(_ i: FirstDayProgress.Item) -> Bool {
        guard let f = firstDay else { return false }
        if i == .walk, f.walkMark == nil, let w = walk, (f.walkMinutes ?? 0) + w.minutes >= FirstDayProgress.walkGoal { return true }
        return f.isDone(i)
    }

    var firstDayDoneCount: Int { [FirstDayProgress.Item.walk, .bump, .invite].filter { firstDayDone($0) }.count }

    /// J-2 checkbox tap toggles a persisted user choice.
    /// Unchecking the ten-minute task resets its counter; another ten minutes can complete it automatically.
    func firstDayToggle(_ item: FirstDayProgress.Item) {
        guard var f = firstDay else { return }
        let on = !firstDayDone(item)
        switch item {
        case .walk:
            if on { f.walkMark = true } else { f.walkMark = false; f.walkMinutes = 0 }
        case .bump: f.bumpMark = on
        case .invite: f.inviteMark = on
        }
        if !f.allDone {
            f.finishedAt = nil
        } else if f.finishedAt == nil {
            f.finishedAt = Date()
            say(L.t("今日三件事做齊晒，好叻！", "今天三件事都做完了，真棒！", "All 3 things done today. Well done!"))
        }
        firstDay = f
        Haptics.light()
    }

    /// -uiPreview firstDay prepares four minutes walked, paired status, and a meetup with Mrs Chan tomorrow at 8 am after map installation.
    func previewFirstDayIfNeeded() {
        guard UIPreview.is("firstDay") else { return }
        Task { @MainActor [weak self] in
            while self?.map == nil || self?.landmarks.isEmpty == true { try? await Task.sleep(for: .milliseconds(300)) }
            guard let self else { return }
            let day = Self.hk.startOfDay(for: self.now.addingTimeInterval(86400)).addingTimeInterval(8 * 3600)
            self.appointments = [Appointment(partnerID: "chan", date: day, landmarkID: self.landmarks[0].id, reason: "", status: .accepted)]
            self.firstDay = FirstDayProgress(started: Date(), walkMinutes: 4, bumped: true, invited: true)
        }
    }

    /// Hide the card after completion.
    func closeFirstDay() {
        guard firstDay?.finishedAt != nil else { return }
        firstDay?.closed = true
    }

    /// The task invitation uses tomorrow, or the first day after leave; without a neighbor, explain pairing first.
    func firstDayInvite() {
        guard let n = neighbors.first else {
            toast(L.t("要先見面碰一碰做街坊，先約得。", "要先见面碰一碰成为邻居，才能约。", "Meet and tap phones to become neighbours first. Then you can invite them."))
            return
        }
        proposeMeetup(with: n.id, day: nextWalkDayOffset)
    }

    /// If tomorrow is leave, name the first day after the break instead of contradicting the no-walk plan (10-18).
    var firstDayInviteTitle: String {
        let d = nextWalkDayOffset
        guard d > 1 else { return L.t("約佢聽日一齊行", "约他明天一起走", "Invite them for a walk tomorrow") }
        let day = dateLabel(now.addingTimeInterval(Double(d) * 86400))
        return L.t("休息完再約佢（\(day)）", "休息完再约他（\(day)）", "Invite them after your break (\(day))")
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
        if let line = hko.report?.line, !line.isEmpty { return L.isEn ? line + "." : line }
        return L.t("而家未攞到天氣。入到去「今日」頁，會見到天氣同邊度有陰。", "现在还没拿到天气。进入「今日」页，会看到天气和哪里有阴凉。", "No weather yet. Open Today to see the weather and where it’s shady.")
    }
}

extension Notification.Name {
    /// -scriptOnboarding simulates tapping the example during the trial step.
    static let onbTryPhrase = Notification.Name("streetwalk.onbTryPhrase")
}
