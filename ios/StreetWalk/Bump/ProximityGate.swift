import Foundation

// Adapted from B's ios/UWBMeetDemo/Core/ProximityGate.swift; the original file remains unchanged.
// Centralize thresholds/durations in BumpTuning and add UI progress/hints.

/// Pairing tuning values; validate on physical devices and adjust here.
enum BumpTuning {
    /// Proximity threshold in metres. Original F5 proposed <= 10 cm as TBD; B's prototype used 0.30 m without device validation.
    /// Very close UWB measurements are affected by centimetre-scale error, phone orientation, and hand occlusion.
    /// 2026-10-17 device feedback D-2/D-4: 20 cm required near-contact that triggered AirDrop; widen to 30 cm, roughly a fist apart.
    static let nearDistance: Float = 0.30
    /// Treat this band above the threshold as jitter: neither accumulate nor reset; reset beyond it.
    static let slack: Float = 0.10
    /// Required sustained proximity prevents pairing while merely passing. Increase dwell slightly with the wider threshold; B used 0.5 s.
    static let dwell: TimeInterval = 0.8
    /// Reset only after this gap in close readings; B's 0.35 s was too strict when close-range readings dropped.
    static let maxGap: TimeInterval = 1.0
    /// UI threshold separating approach guidance from the final move-closer prompt.
    static let closerHint: Float = 0.6
    /// Distance in metres at which the progress ring begins filling.
    static let ringFrom: Float = 1.2
    /// Overall discovery/approach timeout. D-6: 60 seconds was too long after the peer left.
    static let searchTimeout: TimeInterval = 30
    /// Minimum approach time after connecting, in seconds.
    static let rangingGrace: TimeInterval = 15
    /// Silence duration after a valid reading before treating the peer as gone and rediscovering.
    static let peerSilence: TimeInterval = 10
    /// Maximum silent restarts within the deadline and pause between attempts.
    static let maxRestarts = 3
    static let restartPause: TimeInterval = 1
    /// After this discovery delay, emphasize QR fallback and explain Wi-Fi/Bluetooth checks (D-6).
    static let slowSearch: TimeInterval = 12
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
        guard let d = distance, d.isFinite else { return L.t("量緊距離…", "正在测距离…", "Measuring…") }
        if d <= nearDistance { return L.t("好！拎穩唔好郁", "好！拿稳别动", "Good! Hold still") }
        if d <= closerHint { return L.t("再近啲", "再近一点", "A bit closer") }
        return L.t("靠近啲", "靠近一点", "Move closer")
    }
}

/// Feed actual UWB readings only. Trigger once after distance remains <= threshold for dwell seconds.
/// 2026-10-17 D-2: tolerate brief nil/NaN/negative readings; reset only when the gap between close readings exceeds maxGap.
/// Reset immediately above threshold + slack. Within the jitter band, neither accumulate nor reset.
struct ProximityGate {
    var threshold: Float
    var dwell: TimeInterval
    var maxGap: TimeInterval
    var slack: Float
    private(set) var triggered = false
    private var began: TimeInterval?
    private var previous: TimeInterval?

    init(threshold: Float = BumpTuning.nearDistance, dwell: TimeInterval = BumpTuning.dwell, maxGap: TimeInterval = BumpTuning.maxGap,
         slack: Float = BumpTuning.slack) {
        self.threshold = threshold
        self.dwell = dwell
        self.maxGap = maxGap
        self.slack = slack
    }

    mutating func update(distance: Float?, at now: TimeInterval) -> Bool {
        guard !triggered else { return false }
        // Reset if time moves backwards or the gap between close readings is too long.
        if let previous, now < previous || now - previous > maxGap { began = nil; self.previous = nil }
        guard let distance, distance.isFinite, distance >= 0 else { return false }
        if distance > threshold + slack { began = nil; previous = nil; return false }
        guard distance <= threshold else { return false }
        if began == nil { began = now }
        previous = now
        if let began, now - began >= dwell {
            triggered = true
            return true
        }
        return false
    }

    mutating func reset() { self = ProximityGate(threshold: threshold, dwell: dwell, maxGap: maxGap, slack: slack) }
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
