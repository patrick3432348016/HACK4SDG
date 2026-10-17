import CoreLocation
import CoreMotion
import Foundation
import UIKit

/// 真机散步检测：Core Motion 判断开始 / 停止行路，只在行路（或正在记录）时开准确定位。
/// 记录紧散步时锁机 / 退后台都继续定位（allowsBackgroundLocationUpdates）；有「始终允许」时，
/// 离开屋企由 LocationMonitor 喺背景叫醒 App 再开（AppStore+Location）。
/// 其余背景时段（例如 App 被扫走）：返前台时用 Core Motion 嘅活动纪录同计步器补记（AppStore.backfill）。
/// 精确位置只在手机上换算成场景坐标，不上传、不存盘。模拟器和演示模式不启用，继续用演示散步；
/// 模拟器加启动参数 -simWalk 就只靠定位速度判断行路（冇 Core Motion，开发测试用）。
/// 测试反馈 C-1：App 喺前台（亮住屏）时一直开准确定位，唔等 Core Motion 先开；只有「使用 App 期间」权限都认到出门。
/// 唔会喺街上弹定位权限框：权限喺首次使用后嘅解释页问（AlwaysAskSheet），或者自己撳「现在出去走走」时先问。
@MainActor
final class WalkDetector: NSObject, CLLocationManagerDelegate {
    enum Event {
        case walking(Bool)          // Core Motion：开始 / 停止行路
        case riding                 // 坐车 / 踩单车：不算散步
        case location(GeoPoint, accuracy: Double)   // 精度 ≤100 m、10 秒内嘅定位（>30 m 只用来判断返到屋企）
        case still(since: Date)     // 停低咗 2、5、10 分钟各报一次
        case steps(Int, cadence: Double?)           // 计步器：今次散步嘅步数、而家步频（步/秒）

        var isSteps: Bool { if case .steps = self { return true } else { return false } }
    }

    /// 停低几耐报一次 .still：2 分钟（落脚点）、5 分钟（喺屋企附近就收尾）、10 分钟（喺外面都收尾）。
    static let stillMarks: [TimeInterval] = [2 * 60, 5 * 60, 10 * 60]

    var onEvent: ((Event) -> Void)?
    /// 当前这次散步是真机记录的（不是演示）。
    var recording = false
    /// 真机记录到的轨迹（场景坐标）。
    var trail: [Vec2] = []
    /// 坐轮椅：iPhone 认唔到推轮椅，唔係「肯定停低」就当郁紧；坐车要定位速度 >4 m/s 先算。
    /// 唔开计步器（步数≈0 唔公平），按分钟估算。
    var seated = false { didSet { if seated && countingSteps { pedometer.stopUpdates(); countingSteps = false } } }
    /// 开始 / 收尾判断（未开始时要两个好点先算出门）。
    var gate = LiveWalkGate()
    /// 背景补记嘅最后一段（仲行紧 / 啱啱停）：等定位接手，接唔到就停低后补记。
    var pendingWalk: PendingWalk?
    /// 返前台睇紧活动纪录（AppStore.resumeLiveWalk / backfill）：呢段时间唔开定位、唔开始、唔收尾。
    var catchUps = 0
    var catchingUp: Bool { catchUps > 0 }
    /// Core Motion 而家判断喺行路，同埋呢段行路由几时开始（散步开始时间用佢，唔用第一个定位点）。
    private(set) var moving = false
    private(set) var movingSince: Date?
    private(set) var stillSince: Date?
    /// 最后一个定位点的时间和位置：散步分钟数按这个算，退到后台再返嚟时用来收尾。
    private(set) var lastFixAt: Date?
    private(set) var lastFix: (GeoPoint, accuracy: Double)?
    private var lastSpeed = -1.0
    /// Core Motion 最近一次话坐车 / 踩单车：之后 2 分钟唔信定位速度当行路。
    private var ridingAt: Date?

    /// 而家当行紧路：Core Motion 话行紧，或者定位速度似行路（0.4–3 m/s，啱啱坐过车唔算）。
    /// Core Motion 有时慢几十秒先报、或者「运动与健身」冇开，靠定位速度补。
    var stepping: Bool {
        if moving { return true }
        if let r = ridingAt, Date().timeIntervalSince(r) < 120 { return false }
        // 10-18：Core Motion 话停低紧（坐低）就唔信定位速度（GPS 漂移都会有 0.5 m/s）
        if stillSince != nil, !Self.locationOnly { return false }
        return lastSpeed >= 0.4 && lastSpeed <= 3
    }

    /// App 喺前台（包括弹紧系统框）。
    static var inForeground: Bool { UIApplication.shared.applicationState != .background }

    /// 用到先建（一建就可能弹「运动与健身」权限框，要等同意页之后、真机先建）。
    private lazy var motion = CMMotionActivityManager()
    private lazy var pedometer = CMPedometer()
    private var countingSteps = false
    private let location = CLLocationManager()
    private(set) var running = false
    private var stillTask: Task<Void, Never>?

    // 后台出门检测（AppStore+Location）
    /// 定位档：关、粗略（只係保持 App 喺背景醒住，等 Core Motion 话行紧路）、准确（行紧路 / 记录紧）。
    private enum Mode { case off, coarse, fine }
    private var mode = Mode.off
    private var wantFine = false
    private var locating: Bool { mode == .fine }
    /// 背景保持清醒（粗略定位，几乎唔用 GPS）：离开屋企后等开始行路、喺外面停低咗。
    /// 背景冇任何定位时 iOS 会暂停 App，Core Motion 都收唔到。
    var keepAlive = false { didSet { if keepAlive != oldValue { applyMode() } } }
    /// 区域监察报离开屋企嘅时间（之后冇坐车）：期间放宽「出门」距离（TriggerRules.maxStart）。
    var leftHomeAt: Date?
    /// 叫醒后等开始行路 / 喺外面停低嘅计时（AppStore+Location）。
    var watchTask: Task<Void, Never>?
    /// 退后台都唔停：记录紧散步、等紧开始行路、喺外面停低等再行。
    var staysAwakeInBackground: Bool { recording || watchTask != nil }
    /// 开始散步最远几远（由屋企行出去放宽）。
    var maxStart: Double { TriggerRules.maxStart(leftHomeAt: leftHomeAt, now: Date()) }
    /// 模拟器 -simWalk：上一个定位（用嚟计速度）。
    private var simLast: (GeoPoint, Date)?

    /// 硬件够（真机、有动作感应；或者模拟器加 -simWalk）。演示模式由 AppStore.startWalkDetection 判断。
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return locationOnly
        #else
        return CMMotionActivityManager.isActivityAvailable()
        #endif
    }

    /// 只靠定位速度判断行路（模拟器 + 启动参数 -simWalk；冇 Core Motion、冇计步器）。只供开发测试。
    /// iOS 喺背景重新开 App（离开屋企）时冇启动参数：沿用上次用参数启动时记低嘅设定。
    static var locationOnly: Bool {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-simWalk") || (args.count == 1 && UserDefaults.standard.bool(forKey: "simWalk"))
        #else
        return false
        #endif
    }

    /// 模拟器：用参数启动时记低有冇 -simWalk（俾之后冇参数嘅背景重开用）。
    static func rememberSimWalk() {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if args.count > 1 { UserDefaults.standard.set(args.contains("-simWalk"), forKey: "simWalk") }
        #endif
    }

    /// 演示模式嘅默认值：模拟器开（-simWalk 测真机流程时关），真机关（真机装好就检测散步；设置里改过就按改过的）。
    static var demoByDefault: Bool {
        #if targetEnvironment(simulator)
        return !locationOnly
        #else
        return false
        #endif
    }

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 3
        location.activityType = .fitness
    }

    /// 记录中退过后台（catchingUp）：等 AppStore 睇完活动纪录先决定继续定位定收尾。
    func start() {
        guard Self.isAvailable, !running else { return }
        running = true
        // 前台：即刻开准确定位（出门 50 m 就认到）；后台：记录紧先开
        if !catchingUp { setLocating(recording) }
        // -simWalk：冇 Core Motion，一直开定位睇速度
        if Self.locationOnly { setLocating(true); return }
        motion.startActivityUpdates(to: .main) { [weak self] a in
            guard let self, let a, a.confidence != .low || self.seated else { return }
            let stepping = a.walking || a.running
            let riding = (a.automotive || a.cycling) && !(self.seated && self.lastSpeed <= 4)
            let moving = self.seated ? !a.stationary && !riding : stepping
            let still = a.stationary && !stepping && !riding
            self.watchStill(still)
            if riding {
                self.moving = false
                self.ridingAt = Date()
                self.leftHomeAt = nil      // 坐咗车：之后唔再当係由屋企行出去
                self.onEvent?(.riding)
            } else if moving {
                if !self.moving { self.movingSince = a.startDate }
                self.moving = true
                self.onEvent?(.walking(true))
            } else if still || self.moving {
                // 10-18：明确话唔係行路（静止 / 唔知）就当停咗，唔好一直当行紧（以前只有「静止」先停，坐低报「唔知」就卡住）
                self.moving = false
                self.onEvent?(.walking(false))
            }
        }
    }

    /// 停低够耐就报 .still（定位有 distanceFilter，企定唔郁就唔会再有新点）。
    private func watchStill(_ still: Bool) {
        guard still else { stillTask?.cancel(); stillTask = nil; stillSince = nil; return }
        guard stillTask == nil else { return }
        let since = Date()
        stillSince = since
        stillTask = Task { @MainActor [weak self] in
            var waited: TimeInterval = 0
            for mark in Self.stillMarks {
                try? await Task.sleep(for: .seconds(mark - waited))
                waited = mark
                guard let self, !Task.isCancelled else { return }
                self.onEvent?(.still(since: since))
            }
        }
    }

    /// 一次散步收尾：清轨迹和最后定位，停计步。
    func reset() {
        recording = false
        trail = []
        lastFixAt = nil
        lastFix = nil
        gate = LiveWalkGate()
        gate.quiet(until: Date().addingTimeInterval(LiveWalkGate.restartGap))   // 啱啱收尾：唔好即刻又开始
        if countingSteps { pedometer.stopUpdates(); countingSteps = false }
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
        keepAlive = false
        guard running else { return }
        running = false
        moving = false
        if !Self.locationOnly { motion.stopActivityUpdates() }
        stillTask?.cancel()
        stillTask = nil
        stillSince = nil
        simLast = nil
        wantFine = false
        applyMode()
    }

    /// 只在需要时开准确定位，省电（-simWalk 运行期间一直开；App 喺前台、检测开紧都一直开）。
    func setLocating(_ on: Bool) {
        wantFine = on || (running && (Self.locationOnly || Self.inForeground))
        applyMode()
    }

    /// 自己撳「现在出去走走」：未问过定位就问（使用 App 期间）。自动检测唔会喺街上弹框。
    func requestWhenInUseIfNeeded() {
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
    }

    /// 准确：行紧路 / 记录紧；粗略：keepAlive（背景醒住等行路）；否则关。
    /// 两档都容许背景继续（记录紧散步锁机都照记；「始终允许」时可以喺背景开）。
    private func applyMode() {
        let m: Mode = wantFine ? .fine : keepAlive ? .coarse : .off
        guard m != mode else { return }
        mode = m
        guard m != .off else { location.stopUpdatingLocation(); return }
        // 未允许定位唔开（唔好喺街上弹权限框）；之后允许咗由 locationManagerDidChangeAuthorization 再开
        guard location.authorizationStatus != .notDetermined else { return }
        location.desiredAccuracy = m == .fine ? kCLLocationAccuracyBest : kCLLocationAccuracyThreeKilometers
        location.distanceFilter = m == .fine ? 3 : 500
        location.pausesLocationUpdatesAutomatically = false
        location.allowsBackgroundLocationUpdates = true
        // 记录散步时状态栏显示蓝色定位标记（知道佢喺度记录）；粗略保持清醒时唔显示
        location.showsBackgroundLocationIndicator = m == .fine
        location.startUpdatingLocation()
    }

    // MARK: - 计步器（A85：真机步数；F9：步频）

    func startSteps(from start: Date) {
        guard Self.isAvailable, !seated, CMPedometer.isStepCountingAvailable() else { return }
        countingSteps = true
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            guard let data else { return }
            let n = data.numberOfSteps.intValue, cadence = data.currentCadence?.doubleValue
            Task { @MainActor in self?.onEvent?(.steps(n, cadence: cadence)) }
        }
    }

    func steps(from: Date, to: Date) async -> Int? {
        guard Self.isAvailable, !seated, CMPedometer.isStepCountingAvailable() else { return nil }
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: from, to: to) { data, _ in cont.resume(returning: data?.numberOfSteps.intValue) }
        }
    }

    /// 背景期间嘅活动纪录（系统保留 7 日）。冇权限 / 冇纪录返回 nil。
    func activities(from: Date, to: Date) async -> [WalkBackfill.Sample]? {
        guard Self.isAvailable, !Self.locationOnly else { return nil }
        let seated = seated
        return await withCheckedContinuation { cont in
            motion.queryActivityStarting(from: from, to: to, to: .main) { list, _ in
                // 补记唔睇位置：低可信度嘅唔要（轮椅都一样）
                let s = list?.filter { $0.confidence != .low }.map {
                    WalkBackfill.Sample(start: $0.startDate, moving: WalkBackfill.isMoving(
                        walking: $0.walking, running: $0.running, stationary: $0.stationary, automotive: $0.automotive,
                        cycling: $0.cycling, unknown: $0.unknown, seated: seated))
                }
                cont.resume(returning: s)
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 超过 100 m 的点不要；30–100 m 的（屋企楼里常见）只用来判断返到屋企，不画轨迹。
        // 开定位后系统可能先俾一个旧嘅缓存点：10 秒前嘅唔要。
        let ok = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 100 && abs($0.timestamp.timeIntervalSinceNow) < 10 }
        guard let l = ok.last else { return }
        let p = GeoPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude), acc = l.horizontalAccuracy, at = l.timestamp, speed = l.speed
        Task { @MainActor in
            // 粗略档（keepAlive）只係保持醒住，啲点唔用
            guard self.mode == .fine else { return }
            if Self.locationOnly { self.simMotion(p, speed: speed, at: at) }
            self.lastFixAt = at
            self.lastFix = (p, acc)
            self.lastSpeed = speed
            self.onEvent?(.location(p, accuracy: acc))
        }
    }

    /// -simWalk：速度 ≥0.5 m/s 当行紧路（冇速度就用两点距离计）；停低就照样计 2、5、10 分钟。
    private func simMotion(_ p: GeoPoint, speed: Double, at: Date) {
        var v = speed
        if v < 0, let (q, t) = simLast, at.timeIntervalSince(t) > 0.5 {
            v = LocalProjection(origin: q).toLocal(p).length / at.timeIntervalSince(t)
        }
        simLast = (p, at)
        let walking = v >= 0.5
        watchStill(!walking)
        if walking {
            if !moving { movingSince = at }
            moving = true
            onEvent?(.walking(true))
        } else if moving {
            moving = false
            onEvent?(.walking(false))
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}

    /// 喺解释页 / 设定允许咗定位：要定位嘅话即刻开。
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            let s = self.location.authorizationStatus
            guard self.mode != .off, s == .authorizedWhenInUse || s == .authorizedAlways else { return }
            self.mode = .off        // 当未开过，重新开
            self.applyMode()
        }
    }
}
