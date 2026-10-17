import Foundation

// 碰一碰（F5）嘅进度同结果：BumpService（Contracts.swift）用。
// 2026-10-10 加：真机碰一碰要报距离、失败原因；结果可以係示範居民，或者后端配好嘅对方（LinkedPeer）。

/// 碰一碰嘅结果。
enum BumpMatch: Equatable {
    /// 演示模式：碰到一个示範街坊（SimulatedBumpService）。
    case demo(Resident)
    /// 真机 / 二维码：两部手机交咗同一个一次性码，后端（NeighborLinker）返回对方。
    case linked(LinkedPeer)
}

/// 碰一碰过程（界面用大字显示，语音讲重点）。
enum BumpUpdate: Equatable {
    /// 搵緊身邊部手機（Bonjour 广播 + 搜索）。
    case searching
    /// 等緊「本地網絡」权限（系统框未撳，或者撳咗唔允许）。继续等，时限到先算失败。
    case needsLocalNetwork
    /// 连上咗对方，量紧距离（米）；nil = 暂时量唔到。
    case ranging(Float?)
    /// 呢部手机已经够近，等对方部都够近。
    case nearMe
    /// 两部都够近，向伺服器登记（link(code:)）。
    case linking
    /// 配上咗（store 收到 onFound 后自己设，服务唔会发）。
    case paired
    case failed(BumpFailure)
}

/// 点解碰唔到。每一种都有一句广东话解释，界面同时提供「用二維碼」。
enum BumpFailure: Equatable {
    /// 部手机冇超宽带（iPhone 11 之前、SE、模拟器）。
    case unsupported
    /// 「本地網絡」被拒绝：搵唔到身边部手机。
    case localNetworkDenied
    /// 「附近互動」被拒绝：量唔到距离。
    case nearbyDenied
    /// 时限内搵唔到 / 未够近。
    case timeout
    /// App 去咗背景（超宽带只可以喺前台用）。
    case background
    /// 对方取消、断线或者离开咗。
    case peerLeft
    /// 冇后端（未接伺服器）。
    case noServer
    /// 伺服器配唔上（时限内对方冇交同一个码）。
    case linkFailed
    /// 网络有问题，问唔到伺服器。
    case network
    /// 其他（例如超宽带出错）。
    case other

    /// 大字标题。
    var title: String {
        switch self {
        case .unsupported: return L.t("呢部手機唔支援碰一碰", "这部手机不支持碰一碰", "This phone can’t tap")
        case .localNetworkDenied: return L.t("搵唔到身邊部手機", "找不到身边的手机", "Can’t find the other phone")
        case .nearbyDenied: return L.t("量唔到距離", "测不到距离", "Can’t measure distance")
        case .timeout: return L.t("未碰到", "还没碰到", "Not tapped yet")
        case .background: return L.t("碰一碰停咗", "碰一碰已停止", "Tap stopped")
        case .peerLeft: return L.t("對方停咗", "对方已停止", "They stopped")
        case .noServer: return L.t("未連到伺服器", "未连接服务器", "No server")
        case .linkFailed: return L.t("配對唔到", "配对失败", "Couldn’t pair")
        case .network: return L.t("網絡有問題", "网络有问题", "Network problem")
        case .other: return L.t("碰一碰出錯", "碰一碰出错", "Tap went wrong")
        }
    }

    /// 辅助说明（点样做）。
    var hint: String {
        switch self {
        case .unsupported: return L.t("要兩部 iPhone 11 或之後嘅型號先得。可以改用二維碼。", "需要两部 iPhone 11 或更新的机型。可以改用二维码。", "Needs two iPhone 11 or newer. You can use a QR code instead.")
        case .localNetworkDenied: return L.t("要允許「本地網絡」。去「設定」打開，或者改用二維碼。", "需要允许「本地网络」。去「设置」打开，或者改用二维码。", "Allow Local Network in Settings, or use a QR code instead.")
        case .nearbyDenied: return L.t("要允許「附近互動」。去「設定」打開，或者改用二維碼。", "需要允许「附近交互」。去「设置」打开，或者改用二维码。", "Allow Nearby Interactions in Settings, or use a QR code instead.")
        case .timeout: return L.t("兩部手機都要開住呢頁，並排或者背對背靠近，隔一個拳頭就得；Wi-Fi 同藍牙都要開（唔使連網絡）。可以再試，或者改用二維碼。",
                                  "两台手机都要打开这一页，并排或背对背靠近，隔一个拳头就行；Wi-Fi 和蓝牙都要打开（不用连网络）。可以再试，或者改用二维码。", "Keep this page open on both phones. Hold them side by side or back to back, a fist apart. Turn on Wi-Fi and Bluetooth (no internet needed). Try again, or use a QR code.")
        case .background: return L.t("碰一碰時要開住呢頁。如果彈出「隔空投送」，撳「取消」再試。", "碰一碰时要一直开着这一页。如果弹出「隔空投送」，点「取消」再试。", "Keep this page open while tapping. If AirDrop pops up, tap Cancel and try again.")
        case .peerLeft: return L.t("兩部手機一齊再試，或者改用二維碼。", "两部手机一起再试，或者改用二维码。", "Try again on both phones, or use a QR code.")
        case .noServer: return L.t("呢個版本未接伺服器，加唔到街坊。", "这个版本未接服务器，加不了邻居。", "This version has no server, so you can’t add neighbours.")
        case .linkFailed: return L.t("兩部手機一齊再試，或者改用二維碼。", "两部手机一起再试，或者改用二维码。", "Try again on both phones, or use a QR code.")
        case .network: return L.t("睇下有冇上網，再試一次。", "看看有没有联网，再试一次。", "Check you’re online and try again.")
        case .other: return L.t("再試一次，或者改用二維碼。", "再试一次，或者改用二维码。", "Try again, or use a QR code.")
        }
    }

    /// 要去「設定」改权限。
    var needsSettings: Bool { self == .localNetworkDenied || self == .nearbyDenied }
    /// 「再試」有冇用（唔支援、冇伺服器就冇用）。
    var canRetry: Bool { self != .unsupported && self != .noServer }
}

/// 二维码加街坊（唔支援超宽带、或者碰唔到时用）。
struct BumpQRState: Equatable {
    enum Mode: Equatable {
        /// 揀：出示 / 掃。
        case choose
        /// 出示二维码，等对方扫（code 係 PairCode）。
        case show(String)
        /// 开镜头扫对方。
        case scan
    }
    var mode: Mode
    /// 扫到 / 对方扫咗，等伺服器。
    var linking = false
    /// 配上咗。
    var paired = false
    /// 大字提示（例如「呢個唔係街坊行嘅二維碼」）。
    var note: String?
    /// 扫过但配唔到嘅码：镜头仲对住都唔再重试。
    var rejected: String?
}
