import Foundation

/// Pure live-finding calculations: GPS distance/bearing, arrow angle, far/near mode, and arrival detection; unit-testable.
/// Far: GPS bearing minus heading. Near (<= 10 m): UWB distance/direction. End within 3 m or on explicit found confirmation.
enum LiveFindMath {
    enum Mode: Equatable { case waiting, far, near }

    /// Distance threshold for the close-range UWB-arrow screen.
    static let nearDistance = 10.0
    /// Distance threshold for automatic found confirmation.
    static let metDistance = 3.0
    /// Exchange UWB tokens below this GPS distance, allowing early setup despite GPS error.
    static let niStartDistance = 30.0
    /// Location transmission interval in seconds.
    static let sendInterval = 3.0
    /// Maximum peer-location age before treating it as unavailable.
    static let staleAfter = 30.0
    /// Maximum usable UWB-reading age.
    static let niFresh = 2.0
    /// Angular tolerance around straight ahead for green-arrow/haptic alignment feedback.
    static let facingTolerance = 15.0
    /// Walking speed in metres per minute, matching meetup estimates for older residents.
    static let metersPerMinute = 70.0
    /// Heading-error threshold above which the user is asked to hold the phone flat.
    static let headingMaxError = 35.0

    /// Haversine distance between two points in metres.
    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let r = 6_371_000.0
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180
        let dφ = (b.lat - a.lat) * .pi / 180, dλ = (b.lon - a.lon) * .pi / 180
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * r * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    /// Bearing from a to b, clockwise from north in 0..<360 degrees.
    static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180, dλ = (b.lon - a.lon) * .pi / 180
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Normalize to -180...180 degrees.
    static func normalize(_ deg: Double) -> Double {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d <= -180 { d += 360 }
        return d
    }

    /// Clockwise arrow angle relative to the phone top = bearing minus heading. Assume north-up without a compass.
    static func arrowAngle(bearing: Double, heading: Double?) -> Double { normalize(bearing - (heading ?? 0)) }

    /// Validate CLHeading.headingAccuracy; a negative value is invalid.
    static func headingUsable(accuracy: Double?) -> Bool {
        guard let a = accuracy else { return false }
        return a >= 0 && a <= headingMaxError
    }

    /// Estimated walking minutes: at least one while travelling, zero on arrival.
    static func etaMinutes(_ meters: Double) -> Int {
        meters <= metDistance ? 0 : max(1, Int((meters / metersPerMinute).rounded(.up)))
    }

    /// Use near mode with a fresh UWB reading; otherwise fall back to GPS.
    static func mode(gps: Double?, ni: Double?) -> Mode {
        if let ni, ni <= nearDistance * 1.5 { return .near }
        guard let gps else { return .waiting }
        return gps <= nearDistance ? .near : .far
    }

    /// Automatic arrival: UWB <= 3 m, or GPS <= 3 m when no UWB reading exists.
    static func isMet(gps: Double?, ni: Double?) -> Bool {
        if let ni { return ni <= metDistance }
        if let gps { return gps <= metDistance }
        return false
    }

    /// Convert the UWB phone-coordinate direction (x right, y up, -z forward) to horizontal degrees, positive right.
    static func niAzimuth(x: Float, z: Float) -> Double { Double(atan2(x, -z)) * 180 / .pi }

    /// Whether the arrow is approximately straight ahead.
    static func isFacing(_ angle: Double) -> Bool { abs(normalize(angle)) <= facingTolerance }
}
