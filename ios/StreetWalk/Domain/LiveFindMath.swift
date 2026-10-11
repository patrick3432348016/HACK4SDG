import Foundation

/// 「查找」式找人（真街坊）嘅计算：GPS 距离、方位、箭咀角度、远 / 近模式、几时算「見到」。纯函数，单元测试用。
/// 远：GPS 方位 − 指南针方向；近（≤ 10 m）：超宽带精确距离同方向；≤ 3 m 或者撳「見到喇」就结束。
enum LiveFindMath {
    enum Mode: Equatable { case waiting, far, near }

    /// ≤ 呢个距离用近距离画面（超宽带箭咀）。
    static let nearDistance = 10.0
    /// ≤ 呢个距离自动「見到喇」。
    static let metDistance = 3.0
    /// GPS 话 ≤ 呢个距离就交换超宽带令牌（GPS 有误差，早少少准备好）。
    static let niStartDistance = 30.0
    /// 每隔几秒传一次位置。
    static let sendInterval = 3.0
    /// 对方位置旧过呢个秒数就当暂时收唔到。
    static let staleAfter = 30.0
    /// 超宽带读数旧过呢个秒数就唔用。
    static let niFresh = 2.0
    /// 箭咀同前面差唔多 ±呢个角度就当「对正咗」（转绿 + 震）。
    static let facingTolerance = 15.0
    /// 长者步速（米 / 分钟，同约会估时间一致）。
    static let metersPerMinute = 70.0
    /// 指南针误差大过呢个角度就叫用户将手机放平。
    static let headingMaxError = 35.0

    /// 两点距离（米，haversine）。
    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let r = 6_371_000.0
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180
        let dφ = (b.lat - a.lat) * .pi / 180, dλ = (b.lon - a.lon) * .pi / 180
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * r * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    /// a 望去 b 嘅方位角（度，正北 0、顺时针，0..<360）。
    static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180, dλ = (b.lon - a.lon) * .pi / 180
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 角度收窄到 -180...180。
    static func normalize(_ deg: Double) -> Double {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d <= -180 { d += 360 }
        return d
    }

    /// 箭咀相对手机顶嘅角度（顺时针为正）= 方位 − 手机指住嘅方向。冇指南针就当手机顶向正北。
    static func arrowAngle(bearing: Double, heading: Double?) -> Double { normalize(bearing - (heading ?? 0)) }

    /// 指南针用唔用得（CLHeading.headingAccuracy：负数 = 无效）。
    static func headingUsable(accuracy: Double?) -> Bool {
        guard let a = accuracy else { return false }
        return a >= 0 && a <= headingMaxError
    }

    /// 大约几多分钟行到（至少 1 分钟；到咗就 0）。
    static func etaMinutes(_ meters: Double) -> Int {
        meters <= metDistance ? 0 : max(1, Int((meters / metersPerMinute).rounded(.up)))
    }

    /// 远 / 近：有新鲜超宽带读数（佢只喺几米到十几米内先有）就近；否则按 GPS。
    static func mode(gps: Double?, ni: Double?) -> Mode {
        if let ni, ni <= nearDistance * 1.5 { return .near }
        guard let gps else { return .waiting }
        return gps <= nearDistance ? .near : .far
    }

    /// 自动「見到喇」：超宽带 ≤ 3 m；冇超宽带读数时 GPS ≤ 3 m。
    static func isMet(gps: Double?, ni: Double?) -> Bool {
        if let ni { return ni <= metDistance }
        if let gps { return gps <= metDistance }
        return false
    }

    /// 超宽带方向（手机坐标：x 向右、y 向上、−z 向机背前面）→ 水平角（度，向右为正）。
    static func niAzimuth(x: Float, z: Float) -> Double { Double(atan2(x, -z)) * 180 / .pi }

    /// 对正咗（箭咀差唔多向前）。
    static func isFacing(_ angle: Double) -> Bool { abs(normalize(angle)) <= facingTolerance }
}
