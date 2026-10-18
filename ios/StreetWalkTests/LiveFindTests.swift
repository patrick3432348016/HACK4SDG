import Foundation
import Testing
@testable import StreetWalk

// Live-finding tests: GPS distance/bearing, arrow angles, modes, meeting, wire format and demo exclusion.
struct LiveFindMathTests {
    let a = GeoPoint(lat: 22.5044, lon: 114.1563)

    @Test func 距离同方位() {
        // Roughly 200 m north.
        let north = GeoPoint(lat: a.lat + 200 / 111_000, lon: a.lon)
        #expect(abs(LiveFindMath.distance(a, north) - 200) < 3)
        #expect(abs(LiveFindMath.bearing(from: a, to: north)) < 1 || abs(LiveFindMath.bearing(from: a, to: north) - 360) < 1)
        // East.
        let east = GeoPoint(lat: a.lat, lon: a.lon + 0.001)
        #expect(abs(LiveFindMath.bearing(from: a, to: east) - 90) < 1)
        #expect(abs(LiveFindMath.bearing(from: east, to: a) - 270) < 1)
    }

    @Test func 箭咀等于方位减手机方向() {
        #expect(LiveFindMath.arrowAngle(bearing: 90, heading: 0) == 90)
        #expect(LiveFindMath.arrowAngle(bearing: 90, heading: 90) == 0)
        #expect(LiveFindMath.arrowAngle(bearing: 10, heading: 350) == 20)
        #expect(LiveFindMath.arrowAngle(bearing: 350, heading: 10) == -20)
        #expect(LiveFindMath.arrowAngle(bearing: 45, heading: nil) == 45)
        #expect(LiveFindMath.isFacing(10) && LiveFindMath.isFacing(-350) && !LiveFindMath.isFacing(40))
    }

    @Test func 指南针准唔准() {
        #expect(LiveFindMath.headingUsable(accuracy: 10))
        #expect(!LiveFindMath.headingUsable(accuracy: -1))
        #expect(!LiveFindMath.headingUsable(accuracy: 90))
        #expect(!LiveFindMath.headingUsable(accuracy: nil))
    }

    @Test func 远近模式同見到() {
        #expect(LiveFindMath.mode(gps: nil, ni: nil) == .waiting)
        #expect(LiveFindMath.mode(gps: 200, ni: nil) == .far)
        #expect(LiveFindMath.mode(gps: 8, ni: nil) == .near)
        #expect(LiveFindMath.mode(gps: 25, ni: 6) == .near)        // Use near mode when UWB provides a measurement.
        #expect(LiveFindMath.isMet(gps: 2, ni: nil))
        #expect(!LiveFindMath.isMet(gps: 2, ni: 5))                 // Prefer UWB when available.
        #expect(LiveFindMath.isMet(gps: 12, ni: 2.5))
        #expect(!LiveFindMath.isMet(gps: nil, ni: nil))
    }

    @Test func 几耐到() {
        #expect(LiveFindMath.etaMinutes(2) == 0)
        #expect(LiveFindMath.etaMinutes(40) == 1)
        #expect(LiveFindMath.etaMinutes(200) == 3)
    }

    @Test func 超宽带方向() {
        #expect(abs(LiveFindMath.niAzimuth(x: 0, z: -1)) < 0.01)          // Straight ahead.
        #expect(abs(LiveFindMath.niAzimuth(x: 1, z: 0) - 90) < 0.01)      // Right.
        #expect(abs(LiveFindMath.niAzimuth(x: -0.5, z: -0.5) + 45) < 0.01)
    }

    @MainActor @Test func 位置讯息来回() {
        let f = LiveFindSession.Fix(geo: GeoPoint(lat: 22.5, lon: 114.15), accuracy: 6.4, at: Date())
        let back = LiveFindSession.fix(from: LiveFindSession.locPayload(f))
        #expect(back?.geo == f.geo)
        #expect(back?.accuracy == 6)
        #expect(LiveFindSession.fix(from: .object(["lat": .number(200), "lon": .number(0)])) == nil)
        #expect(LiveFindSession.fix(from: .object(["lat": .string("x")])) == nil)
    }
}
