import CoreLocation
import CoreMotion
import Foundation

/// 真机散步检测：Core Motion 判断开始 / 停止行路，只在行路（或正在记录）时开定位（使用期间、前台）。
/// 锁屏 / 背景冇定位：返前台时用 Core Motion 嘅活动纪录同计步器补记（AppStore.backfill）。
/// 精确位置只在手机上换算成场景坐标，不上传、不存盘。模拟器和演示模式不启用，继续用演示散步。
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

    /// 用到先建（一建就可能弹「运动与健身」权限框，要等同意页之后、真机先建）。
    private lazy var motion = CMMotionActivityManager()
    private lazy var pedometer = CMPedometer()
    private var countingSteps = false
    private let location = CLLocationManager()
    private(set) var running = false
    private var locating = false
    private var stillTask: Task<Void, Never>?

    /// 硬件够（真机、有动作感应）。演示模式由 AppStore.startWalkDetection 判断。
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return CMMotionActivityManager.isActivityAvailable()
        #endif
    }

    /// 演示模式嘅默认值：模拟器开，真机关（真机装好就检测散步；设置里改过就按改过的）。
    static var demoByDefault: Bool {
        #if targetEnvironment(simulator)
        return true
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
        if recording && !catchingUp { setLocating(true) }
        motion.startActivityUpdates(to: .main) { [weak self] a in
            guard let self, let a, a.confidence != .low || self.seated else { return }
            let stepping = a.walking || a.running
            let riding = (a.automotive || a.cycling) && !(self.seated && self.lastSpeed <= 4)
            let moving = self.seated ? !a.stationary && !riding : stepping
            let still = a.stationary && !stepping && !riding
            self.watchStill(still)
            if riding {
                self.moving = false
                self.onEvent?(.riding)
            } else if moving {
                if !self.moving { self.movingSince = a.startDate }
                self.moving = true
                self.onEvent?(.walking(true))
            } else if still {
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
        if countingSteps { pedometer.stopUpdates(); countingSteps = false }
    }

    func stop() {
        guard running else { return }
        running = false
        moving = false
        motion.stopActivityUpdates()
        stillTask?.cancel()
        stillTask = nil
        stillSince = nil
        setLocating(false)
    }

    /// 只在需要时开定位，省电。
    func setLocating(_ on: Bool) {
        guard on != locating else { return }
        locating = on
        if on {
            if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
            location.startUpdatingLocation()
        } else {
            location.stopUpdatingLocation()
        }
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
        guard Self.isAvailable else { return nil }
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
            self.lastFixAt = at
            self.lastFix = (p, acc)
            self.lastSpeed = speed
            self.onEvent?(.location(p, accuracy: acc))
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
