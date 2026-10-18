import Foundation

// Adapted from B's ios/UWBMeetDemo/Core/ProximityGate.swift; the original file remains unchanged.
// Centralize thresholds/durations in BumpTuning and add UI progress/hints.

/// Pairing tuning values; validate on physical devices and adjust here.
enum BumpTuning {
    /// Proximity threshold in metres. Original F5 proposed <= 10 cm as TBD; B's prototype used 0.30 m without device validation.
    /// UWB readings at very short range can vary with phone orientation and hand obstruction.
    /// This historical prototype starts at 20 cm; tune using real-device evidence rather than treating the threshold as measured accuracy.
    static let nearDistance: Float = 0.20
    /// Required sustained proximity in seconds prevents accidental pairing while passing. B's prototype used 0.5 s; this version shortens the hold.
    static let dwell: TimeInterval = 0.4
    /// Restart timing when the gap between readings exceeds this duration in seconds, inherited from B's prototype.
    static let maxGap: TimeInterval = 0.35
    /// UI threshold separating approach guidance from the final move-closer prompt.
    static let closerHint: Float = 0.5
    /// Distance in metres at which the progress ring begins filling.
    static let ringFrom: Float = 1.0
    /// Overall timeout in seconds for discovering and approaching another phone.
    static let searchTimeout: TimeInterval = 60
    /// Backend pairing polls every 1.5 seconds for up to 20 seconds, within NeighborLinking.swift's 1–2-second contract.
    static let linkInterval: TimeInterval = 1.5
    static let linkTimeout: TimeInterval = 20
    /// QR codes expire after two minutes; the displaying phone refreshes them every 100 seconds.
    static let qrRotate: TimeInterval = 100

    /// Ring progress: 0 at ringFrom metres, 1 at nearDistance or closer.
    static func progress(_ distance: Float?) -> Double {
        guard let d = distance, d.isFinite else { return 0 }
        let p = (ringFrom - d) / (ringFrom - nearDistance)
        return Double(min(max(p, 0), 1))
    }

    /// Large-text guidance.
    static func hint(_ distance: Float?) -> String {
        guard let d = distance, d.isFinite else { return L.t("量緊距離…", "正在测距离…") }
        if d <= nearDistance { return L.t("好！拎穩唔好郁", "好！拿稳别动") }
        if d <= closerHint { return L.t("再近啲", "再近一点") }
        return L.t("靠近啲", "靠近一点")
    }
}

/// Feed actual UWB readings only. Trigger once after distance remains <= threshold for dwell seconds.
/// Reset on invalid readings (nil, NaN, negative), gaps above maxGap, or excessive distance.
struct ProximityGate {
    var threshold: Float
    var dwell: TimeInterval
    var maxGap: TimeInterval
    private(set) var triggered = false
    private var began: TimeInterval?
    private var previous: TimeInterval?

    init(threshold: Float = BumpTuning.nearDistance, dwell: TimeInterval = BumpTuning.dwell, maxGap: TimeInterval = BumpTuning.maxGap) {
        self.threshold = threshold
        self.dwell = dwell
        self.maxGap = maxGap
    }

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

/// Both sides must confirm proximity before exchanging the code; a peer claim cannot replace local ranging (adapted from B's ExchangeState).
/// Product decision: starting pairing and approaching expresses consent; no separate confirmation card/contact exchange, only mutual proximity and cancellation.
struct BumpAgreement {
    private(set) var localNear = false
    private(set) var peerNear = false
    private(set) var code: String?
    private(set) var cancelled = false

    var bothNear: Bool { localNear && peerNear && !cancelled }
    mutating func markLocalNear() { if !cancelled { localNear = true } }
    mutating func markPeerNear() { if !cancelled { peerNear = true } }
    /// Generate/accept the code only when both sides are close and no code is already set.
    mutating func accept(code: String) -> Bool {
        guard bothNear, self.code == nil, PairCode.isValid(code) else { return false }
        self.code = code
        return true
    }
    mutating func cancel() { cancelled = true }
}
