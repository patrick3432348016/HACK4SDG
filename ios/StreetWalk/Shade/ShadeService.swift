import Foundation

/// 成员 A：ShadeProviding 的实现。按"地标 + 15 分钟时段"缓存。
final class ShadeService: ShadeProviding {
    private let calc: ShadeCalculator
    private let center: GeoPoint
    private let map: MapModel
    private var landmarks: [String: Vec2]
    private var cache: [String: Double] = [:]

    init(map: MapModel, landmarks: [Landmark]) {
        calc = ShadeCalculator(map: map)
        center = map.center
        self.map = map
        self.landmarks = Dictionary(uniqueKeysWithValues: landmarks.map { ($0.id, $0.pos) })
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

    /// 某地标当天从几点开始有遮荫（下午优先），用于天气提示。
    func shadedFromHour(landmarkID: String, day: Date, after hour: Int) -> Int? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SolarPosition.hongKong
        let start = cal.startOfDay(for: day)
        for h in hour...18 {
            if shade(landmarkID: landmarkID, at: start.addingTimeInterval(Double(h) * 3600)) >= 0.6 { return h }
        }
        return nil
    }
}
