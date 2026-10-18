import Foundation

/// A's ShadeProviding implementation caches by landmark and fifteen-minute interval.
final class ShadeService: ShadeProviding {
    private let calc: ShadeCalculator
    private let center: GeoPoint
    private let map: MapModel
    private var landmarks: [String: Vec2]
    private var cache: [String: Double] = [:]

    /// Below this elevation, treat the sun as set; do not attribute darkness to building shade. Match ShadeCalculator.
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

    /// After sunset, full shade is a ranking convention; display sunset rather than building shade.
    func isSunUp(at date: Date) -> Bool {
        SolarPosition.at(date, lat: center.lat, lon: center.lon).elevation > Self.sunUpElevation
    }

    /// Find when a landmark becomes shaded that day, preferring afternoon, for weather guidance.
    /// Only consider hours with sun elevation above five degrees; return nil when no valid hour remains after 19:00.
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

    /// Choose the earliest shaded seated landmark; otherwise the first seated landmark with no time claim.
    func shadeTip(_ landmarks: [Landmark], day: Date, after hour: Int) -> (landmark: Landmark, shadedFrom: Int?)? {
        let seats = landmarks.filter(\.hasSeat)
        let best = seats.compactMap { l in shadedFromHour(landmarkID: l.id, day: day, after: hour).map { (l, $0) } }.min { $0.1 < $1.1 }
        if let best { return (best.0, best.1) }
        return seats.first.map { ($0, nil) }
    }
}
