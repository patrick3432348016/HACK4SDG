import ActivityKit
import Foundation
import Observation
import UIKit

/// ActivityKit for the real Dynamic Island and Lock Screen, rendered by StreetWalkWidgets.
/// Local updates only: the free developer account has no push updates. The app starts/updates/ends activities for walks, finding, and upcoming meetups.
/// - Keep one Live Activity, showing the highest priority from IslandStatus.ordered: finding > meetup > walking.
/// - Update at most once per second (one demo second represents one walking minute); skip unchanged content.
/// - iOS cannot start a Live Activity while backgrounded. Defer automatically started walks until foreground, then continue background updates.
/// - Widgets count down from target themselves without waking the background app.
@MainActor
final class LiveIsland {
    static let shared = LiveIsland()

    private var activity: Activity<StreetWalkActivityAttributes>?
    /// Last published content.
    private var sent: IslandStatus?
    /// Desired content; nil means no active task.
    private var wanted: IslandStatus?
    private var lastPush = Date.distantPast
    private var flushTask: Task<Void, Never>?
    private var provider: (() -> IslandStatus?)?
    private var clock: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    /// After the user dismisses the Lock Screen activity, do not reopen it until the current task ends.
    private var userDismissed = false
    private var observers: [NSObjectProtocol] = []
    private let launchedAt = Date()
    /// Startup grace period before ending an inherited activity, allowing walk detection to resume.
    static let launchGrace: TimeInterval = 20

    private init() {
        // Adopt the first activity left after termination and close extras; update/end it after state recovery.
        let existing = Activity<StreetWalkActivityAttributes>.activities
        if let a = existing.first { adopt(a) }
        for a in existing.dropFirst() { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        // On foreground, start any deferred activity or refresh the existing one.
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    /// Store supplies the highest-priority state. Recompute on Observation changes and every 30 seconds for meetup countdowns.
    func attach(_ provider: @escaping () -> IslandStatus?) {
        self.provider = provider
        track()
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.refresh()
            }
        }
    }

    private func track() {
        guard let provider else { return }
        let s = withObservationTracking { provider() } onChange: { [weak self] in
            // onChange fires before mutation; read the new value on the next turn.
            Task { @MainActor in self?.track() }
        }
        show(s)
    }

    private func refresh() {
        guard let provider else { return }
        show(provider())
    }

    func show(_ s: IslandStatus?) {
        wanted = s
        if s == nil { userDismissed = false }
        guard flushTask == nil else { return }
        let wait = max(0, 1 - Date().timeIntervalSince(lastPush))
        flushTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let self else { return }
            self.flushTask = nil
            self.flush()
        }
    }

    private func flush() {
        let s = wanted
        if let s {
            guard !userDismissed else { return }
            if let a = activity, a.activityState == .active || a.activityState == .stale {
                guard s != sent else { return }
                sent = s
                lastPush = Date()
                Task { await a.update(Self.content(s)) }
            } else {
                start(s)
            }
        } else if let a = activity {
            // After startup, especially a locked/background relaunch, wait for walk detection to recover before ending an activity.
            // Recovered activity can keep updating in background, where creating a new one is prohibited.
            let since = Date().timeIntervalSince(launchedAt)
            if since < Self.launchGrace {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.launchGrace - since + 0.5))
                    self?.refresh()
                }
                return
            }
            // When idle, briefly retain a completed-walk summary; end finding/meetup activities immediately.
            let last = sent
            activity = nil
            sent = nil
            stateTask?.cancel()
            lastPush = Date()
            if let last, last.kind == .walk, last.minutes >= 2 {
                var done = last
                done.finished = true
                Task { await a.end(Self.content(done), dismissalPolicy: .after(Date().addingTimeInterval(10 * 60))) }
            } else {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    private func start(_ s: IslandStatus) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let a = try Activity.request(attributes: StreetWalkActivityAttributes(), content: Self.content(s), pushType: nil)
            adopt(a)
            sent = s
            lastPush = Date()
        } catch {
            // On ActivityAuthorizationError.visibility, retry at didBecomeActive through refresh.
            sent = nil
        }
    }

    private func adopt(_ a: Activity<StreetWalkActivityAttributes>) {
        activity = a
        sent = a.content.state
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in a.activityStateUpdates {
                guard let self, self.activity?.id == a.id else { return }
                if state == .dismissed || state == .ended {
                    // After user dismissal or system expiry beyond eight hours, do not reopen during the same task.
                    self.activity = nil
                    self.sent = nil
                    if state == .dismissed { self.userDismissed = true }
                }
            }
        }
    }

    /// Meetup stale time is its scheduled time, so the widget shows due rather than negative countdown. Other states become stale after 20 minutes without updates.
    static func content(_ s: IslandStatus) -> ActivityContent<IslandStatus> {
        var s = s
        s.lang = L.lang   // The widget runs separately and cannot read app language settings.
        let stale: Date
        if s.kind == .meet, let t = s.target {
            stale = t
        } else {
            stale = Date().addingTimeInterval(20 * 60)
        }
        return ActivityContent(state: s, staleDate: s.finished ? nil : stale)
    }
}
