import Foundation

/// 成员 A：ShadeProviding 的实现。按"地标 + 15 分钟时段"缓存。
final class ShadeService: ShadeProviding {
    private let calc: ShadeCalculator
    private let center: GeoPoint
    private let map: MapModel
    private var landmarks: [String: Vec2]
    private var cache: [String: Double] = [:]

    /// 太阳低于这个高度（度）就当已经落山：没有日晒，不能说"有樓遮"。与 ShadeCalculator 一致。
    static let sunUpElevation = 2.0

    init(map: MapModel, landmarks: [Landmark]) {
        calc = ShadeCalculator(map: map)
        center = map.center
        self.map = map
        self.landmarks = Dictionary(landmarks.map { ($0.id, $0.pos) }, uniquingKeysWith: { a, _ in a })
    }

    func shade(landmarkID: String, at date: Date) -> Double {
        guard let pos = landmarks[landmarkID] else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SolarPosition.hongKong
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let slot = ((c.hour ?? 0) * 60 + (c.minute ?? 0)) / 15
        let key = "\(landmarkID)|\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)|\(slot)"
        if let v = cache[key] { return v }
        let slotDate = cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: slot / 4, minute: (slot % 4) * 15)) ?? date
        let v = calc.shade(at: pos, sun: map.localSun(SolarPosition.at(slotDate, lat: center.lat, lon: center.lon)))
        cache[key] = v
        return v
    }

    /// 那个时刻太阳是否还在天上。日落后遮荫按 100% 计（排序用），但文案要说"已經日落"，不能说"有樓遮"。
    func isSunUp(at date: Date) -> Bool {
        SolarPosition.at(date, lat: center.lat, lon: center.lon).elevation > Self.sunUpElevation
    }

    /// 某地标当天从几点开始有遮荫（下午优先），用于天气提示。
    /// 只计太阳高于 5° 的钟点（天黑不算"有樓遮"）；19 点后没有可选的就返回 nil。
    func shadedFromHour(landmarkID: String, day: Date, after hour: Int) -> Int? {
        guard hour <= 18 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SolarPosition.hongKong
        let start = cal.startOfDay(for: day)
        for h in stride(from: max(hour, 0), through: 18, by: 1) {
            let t = start.addingTimeInterval(Double(h) * 3600)
            guard SolarPosition.at(t, lat: center.lat, lon: center.lon).elevation > 5 else { continue }
            if shade(landmarkID: landmarkID, at: t) >= 0.6 { return h }
        }
        return nil
    }

    /// 天气提示用：有櫈的地标里哪个最早有楼遮；都没有就选第一个有櫈的（时段为 nil，提示不讲钟点）。
    func shadeTip(_ landmarks: [Landmark], day: Date, after hour: Int) -> (landmark: Landmark, shadedFrom: Int?)? {
        let seats = landmarks.filter(\.hasSeat)
        let best = seats.compactMap { l in shadedFromHour(landmarkID: l.id, day: day, after: hour).map { (l, $0) } }.min { $0.1 < $1.1 }
        if let best { return (best.0, best.1) }
        return seats.first.map { ($0, nil) }
    }
}
