import ActivityKit
import Foundation
import Observation
import UIKit

/// 真·灵动岛 + 锁屏嘅实时活动（ActivityKit，小组件扩展 StreetWalkWidgets 负责画）。
/// 只做本地更新（免费开发者账号冇推送）：散步、找人、约会快到期间 App 自己开始、更新、结束。
/// - 同一时间只有一个实时活动，显示最紧要嗰样（IslandStatus.ordered：找人 > 约会 > 散步）。
/// - 更新最多每秒一次（演示散步 1 秒 = 1 分钟）。内容冇变唔送。
/// - iOS 唔俾 App 喺背景「开始」实时活动（锁住机时自动开始嘅散步）：等下次返前台先开，之后背景都会更新。
/// - 约会倒数由小组件自己按 target 计（App 喺背景唔使醒）。
@MainActor
final class LiveIsland {
    static let shared = LiveIsland()

    private var activity: Activity<StreetWalkActivityAttributes>?
    /// 最后送咗出去嘅内容。
    private var sent: IslandStatus?
    /// 而家想显示嘅内容（nil = 冇嘢进行紧）。
    private var wanted: IslandStatus?
    private var lastPush = Date.distantPast
    private var flushTask: Task<Void, Never>?
    private var provider: (() -> IslandStatus?)?
    private var clock: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    /// 用户喺锁屏扫走咗：今次（直到冇嘢进行紧）唔再开。
    private var userDismissed = false
    private var observers: [NSObjectProtocol] = []
    private let launchedAt = Date()
    /// 启动后几耐内唔收上次留低嘅实时活动（等散步检测接手）。
    static let launchGrace: TimeInterval = 20

    private init() {
        // 上次 App 被收咗留低嘅：接手第一个（内容稍后会更新或者结束），其余收走。
        let existing = Activity<StreetWalkActivityAttributes>.activities
        if let a = existing.first { adopt(a) }
        for a in existing.dropFirst() { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        // 返前台：背景嗰阵开唔到嘅，而家开（或者补一次更新）
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    /// 由 App 嘅 store 提供「而家最紧要嘅状态」；Observation 一变就重算，另外每 30 秒（约会倒数）。
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
            // onChange 喺改值之前叫：下一轮先读新值
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
            // 啱啱启动（例如锁住机时系统喺背景重开 App）：等散步检测接返手先决定收唔收，
            // 接得返就喺背景继续更新同一个（背景唔准开新嘅）。
            let since = Date().timeIntervalSince(launchedAt)
            if since < Self.launchGrace {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.launchGrace - since + 0.5))
                    self?.refresh()
                }
                return
            }
            // 冇嘢进行紧：散步完就留「散步完成」喺锁屏一阵；其他（找人、约会）即刻收
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
            // 喺背景开唔到（ActivityAuthorizationError.visibility）：返前台再试（didBecomeActive → refresh）
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
                    // 用户扫走 / 系统收咗（超过 8 个钟）：今次唔再开
                    self.activity = nil
                    self.sent = nil
                    if state == .dismissed { self.userDismissed = true }
                }
            }
        }
    }

    /// 过期时间：约会 = 约定时间（之后小组件讲「夠鐘」，唔会倒数变「1 分鐘前」）；其他 20 分钟冇更新就当旧（锁屏提示「打開 App 更新」）。
    static func content(_ s: IslandStatus) -> ActivityContent<IslandStatus> {
        let stale: Date
        if s.kind == .meet, let t = s.target {
            stale = t
        } else {
            stale = Date().addingTimeInterval(20 * 60)
        }
        return ActivityContent(state: s, staleDate: s.finished ? nil : stale)
    }
}
