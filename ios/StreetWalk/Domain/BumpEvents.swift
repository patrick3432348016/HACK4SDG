import Foundation

// F5 pairing progress/results used by BumpService in Contracts.swift.
// Added 2026-10-10: real-device distance/failure reporting; results can be a demo Resident or backend LinkedPeer.

/// Pairing result.
enum BumpMatch: Equatable {
    /// Demo mode: a simulated neighbor from SimulatedBumpService.
    case demo(Resident)
    /// Device/QR: both phones submit the same single-use code; NeighborLinker returns the peer.
    case linked(LinkedPeer)
}

/// Pairing progress: large visual prompts and concise speech.
enum BumpUpdate: Equatable {
    /// Discovering a nearby phone through Bonjour advertising/browsing.
    case searching
    /// Waiting for Local Network permission, whether unanswered or denied; fail only at the deadline.
    case needsLocalNetwork
    /// Connected and ranging in metres; nil means no current measurement.
    case ranging(Float?)
    /// Local proximity confirmed; waiting for the peer's measurement.
    case nearMe
    /// Mutual proximity confirmed; register through link(code:).
    case linking
    /// Paired state set by the store after onFound, not emitted by the service.
    case paired
    case failed(BumpFailure)
}

/// Every failure has a Cantonese explanation and a QR fallback in the UI.
enum BumpFailure: Equatable {
    /// UWB unavailable on this device/simulator.
    case unsupported
    /// Local Network denied; nearby discovery is blocked.
    case localNetworkDenied
    /// Nearby Interaction denied; ranging is blocked.
    case nearbyDenied
    /// Peer not found or not close enough before timeout.
    case timeout
    /// App backgrounded; UWB requires foreground operation.
    case background
    /// Peer cancelled, disconnected, or left.
    case peerLeft
    /// Backend is not connected/configured.
    case noServer
    /// Backend pairing timed out without the peer submitting the same code.
    case linkFailed
    /// Network failure prevented contacting the backend.
    case network
    /// Other failure, such as a UWB error.
    case other

    /// Large-text title.
    var title: String {
        switch self {
        case .unsupported: return L.t("呢部手機唔支援碰一碰", "这部手机不支持碰一碰")
        case .localNetworkDenied: return L.t("搵唔到身邊部手機", "找不到身边的手机")
        case .nearbyDenied: return L.t("量唔到距離", "测不到距离")
        case .timeout: return L.t("未碰到", "还没碰到")
        case .background: return L.t("碰一碰停咗", "碰一碰已停止")
        case .peerLeft: return L.t("對方停咗", "对方已停止")
        case .noServer: return L.t("未連到伺服器", "未连接服务器")
        case .linkFailed: return L.t("配對唔到", "配对失败")
        case .network: return L.t("網絡有問題", "网络有问题")
        case .other: return L.t("碰一碰出錯", "碰一碰出错")
        }
    }

    /// Supporting guidance explaining what to do.
    var hint: String {
        switch self {
        case .unsupported: return L.t("要兩部 iPhone 11 或之後嘅型號先得。可以改用二維碼。", "需要两部 iPhone 11 或更新的机型。可以改用二维码。")
        case .localNetworkDenied: return L.t("要允許「本地網絡」。去「設定」打開，或者改用二維碼。", "需要允许「本地网络」。去「设置」打开，或者改用二维码。")
        case .nearbyDenied: return L.t("要允許「附近互動」。去「設定」打開，或者改用二維碼。", "需要允许「附近交互」。去「设置」打开，或者改用二维码。")
        case .timeout: return L.t("兩部手機都要開住呢頁，貼埋一齊。可以再試，或者改用二維碼。", "两部手机都要开着这页，贴在一起。可以再试，或者改用二维码。")
        case .background: return L.t("碰一碰時要開住呢頁。再試一次就得。", "碰一碰时要开着这页。再试一次就行。")
        case .peerLeft: return L.t("兩部手機一齊再試，或者改用二維碼。", "两部手机一起再试，或者改用二维码。")
        case .noServer: return L.t("呢個版本未接伺服器，加唔到街坊。", "这个版本未接服务器，加不了邻居。")
        case .linkFailed: return L.t("兩部手機一齊再試，或者改用二維碼。", "两部手机一起再试，或者改用二维码。")
        case .network: return L.t("睇下有冇上網，再試一次。", "看看有没有联网，再试一次。")
        case .other: return L.t("再試一次，或者改用二維碼。", "再试一次，或者改用二维码。")
        }
    }

    /// Permission must be changed in Settings.
    var needsSettings: Bool { self == .localNetworkDenied || self == .nearbyDenied }
    /// Whether retry can help; unsupported hardware or missing backend cannot be fixed by retrying.
    var canRetry: Bool { self != .unsupported && self != .noServer }
}

/// QR neighbor pairing when UWB is unsupported or unsuccessful.
struct BumpQRState: Equatable {
    enum Mode: Equatable {
        /// Choose to display or scan a code.
        case choose
        /// Display a PairCode QR and wait for scanning.
        case show(String)
        /// Open the camera to scan the peer.
        case scan
    }
    var mode: Mode
    /// Code scanned; waiting for the backend.
    var linking = false
    /// Paired successfully.
    var paired = false
    /// Large guidance text, for example when a QR code is not a StreetWalk code.
    var note: String?
    /// Do not retry a previously scanned failed code while the camera remains pointed at it.
    var rejected: String?
}
