import Foundation

/// 太阳位置（NOAA 简化公式）。同一个结果既驱动场景里的太阳光，也用来算遮荫，所以画面上的影子和遮荫百分比一致。
struct SolarPosition {
    /// 高度角（度），地平线以上为正。
    var elevation: Double
    /// 方位角（度），从正北顺时针。
    var azimuth: Double

    /// 指向太阳的单位向量（东、北、上）。
    var direction: (east: Double, north: Double, up: Double) {
        let el = elevation * .pi / 180, az = azimuth * .pi / 180
        return (cos(el) * sin(az), cos(el) * cos(az), sin(el))
    }

    static let hongKong = TimeZone(identifier: "Asia/Hong_Kong")!

    static func at(_ date: Date, lat: Double, lon: Double, timeZone: TimeZone = hongKong) -> SolarPosition {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .hour, .minute, .second], from: date)
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let hour = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        let tzHours = Double(timeZone.secondsFromGMT(for: date)) / 3600

        let γ = 2 * Double.pi / 365 * (dayOfYear - 1 + (hour - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(γ) - 0.032077 * sin(γ) - 0.014615 * cos(2 * γ) - 0.040849 * sin(2 * γ))
        let decl = 0.006918 - 0.399912 * cos(γ) + 0.070257 * sin(γ) - 0.006758 * cos(2 * γ)
            + 0.000907 * sin(2 * γ) - 0.002697 * cos(3 * γ) + 0.00148 * sin(3 * γ)

        let trueSolarMinutes = hour * 60 + eqTime + 4 * lon - 60 * tzHours
        let hourAngle = (trueSolarMinutes / 4 - 180) * .pi / 180
        let φ = lat * .pi / 180

        let cosZenith = sin(φ) * sin(decl) + cos(φ) * cos(decl) * cos(hourAngle)
        let zenith = acos(max(-1, min(1, cosZenith)))
        let elevation = 90 - zenith * 180 / .pi

        var azimuth = atan2(sin(hourAngle), cos(hourAngle) * sin(φ) - tan(decl) * cos(φ)) * 180 / .pi + 180
        azimuth = azimuth.truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }
        return SolarPosition(elevation: elevation, azimuth: azimuth)
    }
}
