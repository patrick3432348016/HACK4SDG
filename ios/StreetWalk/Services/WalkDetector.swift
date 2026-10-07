import CoreLocation
import CoreMotion
import Foundation

/// 真机散步检测：Core Motion 判断开始 / 停止行路，只在行路（或正在记录）时开定位（使用期间、前台）。
/// 精确位置只在手机上换算成场景坐标，不上传、不存盘。模拟器和演示模式不启用，继续用演示散步。
@MainActor
final class WalkDetector: NSObject, CLLocationManagerDelegate {
    enum Event {
        case walking(Bool)          // Core Motion：开始 / 停止行路
        case riding                 // 坐车 / 踩单车：不算散步
        case location(GeoPoint, accuracy: Double)   // 精度 ≤100 m 的定位（>30 m 只用来判断返到屋企）
        case still                  // 停低超过 stillAfter
    }

    static let stillAfter: TimeInterval = 5 * 60

    var onEvent: ((Event) -> Void)?
    /// 当前这次散步是真机记录的（不是演示）。
    var recording = false
    /// 真机记录到的轨迹（场景坐标）。
    var trail: [Vec2] = []
    /// 最后一个定位点的时间和位置：散步分钟数按这个算，退到后台再返嚟时用来收尾。
    private(set) var lastFixAt: Date?
    private(set) var lastFix: (GeoPoint, accuracy: Double)?

    private let motion = CMMotionActivityManager()
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

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 3
        location.activityType = .fitness
    }

    func start() {
        guard Self.isAvailable, !running else { return }
        running = true
        // 记录中退过后台：返嚟即刻重开定位，唔使等下一次行路事件
        if recording { setLocating(true) }
        motion.startActivityUpdates(to: .main) { [weak self] a in
            guard let self, let a, a.confidence != .low else { return }
            let still = a.stationary && !(a.walking || a.running || a.automotive || a.cycling)
            self.watchStill(still)
            if a.automotive || a.cycling { self.onEvent?(.riding) }
            else if a.walking || a.running { self.onEvent?(.walking(true)) }
            else if still { self.onEvent?(.walking(false)) }
        }
    }

    /// 停低够久就报一次 .still（定位有 distanceFilter，企定唔郁就唔会再有新点）。
    private func watchStill(_ still: Bool) {
        guard still else { stillTask?.cancel(); stillTask = nil; return }
        guard stillTask == nil else { return }
        stillTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.stillAfter))
            guard let self, !Task.isCancelled else { return }
            self.stillTask = nil
            self.onEvent?(.still)
        }
    }

    /// 一次散步收尾：清轨迹和最后定位。
    func reset() {
        recording = false
        trail = []
        lastFixAt = nil
        lastFix = nil
    }

    func stop() {
        guard running else { return }
        running = false
        motion.stopActivityUpdates()
        stillTask?.cancel()
        stillTask = nil
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

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 超过 100 m 的点不要；30–100 m 的（屋企楼里常见）只用来判断返到屋企，不画轨迹。
        let ok = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 100 }
        guard let l = ok.last else { return }
        let p = GeoPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude), acc = l.horizontalAccuracy, at = l.timestamp
        Task { @MainActor in
            self.lastFixAt = at
            self.lastFix = (p, acc)
            self.onEvent?(.location(p, accuracy: acc))
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
