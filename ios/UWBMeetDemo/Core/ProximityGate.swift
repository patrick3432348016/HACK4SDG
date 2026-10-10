import Foundation

/// Only real NI measurements feed this gate in the app. Values are initial test parameters.
struct ProximityGate {
    var threshold: Float = 0.30
    var dwell: TimeInterval = 0.50
    var maxGap: TimeInterval = 0.35
    private(set) var triggered = false
    private var began: TimeInterval?
    private var previous: TimeInterval?

    mutating func update(distance: Float?, at now: TimeInterval) -> Bool {
        guard !triggered else { return false }
        guard let distance, distance.isFinite, distance >= 0, distance <= threshold else {
            began = nil
            previous = nil
            return false
        }
        if let previous, now < previous || now - previous > maxGap { began = nil }
        if began == nil { began = now }
        previous = now
        if let began, now - began >= dwell {
            triggered = true
            return true
        }
        return false
    }

    mutating func reset() { self = ProximityGate(threshold: threshold, dwell: dwell, maxGap: maxGap) }
}

