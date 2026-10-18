import SwiftUI

// MARK: - QR neighbor pairing inside the full-screen bump flow

/// Fallback for unsupported or unsuccessful UWB: one phone displays a code and the other scans.
/// State lives in store.bumpQR; see AppStore+Bump for the flow.
struct BumpQRContent: View {
    @Environment(AppStore.self) private var store
    var qr: BumpQRState
    var demo: Bool

    var body: some View {
        VStack(spacing: 20) {
            if demo {
                DemoBadge(text: qr.mode == .scan ? L.t("示範：掃到就當加咗示範街坊", "演示：扫到就当加了演示邻居") : L.t("示範：過幾秒當對方掃咗", "演示：几秒后当对方扫了"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            switch qr.mode {
            case .choose: chooser
            case .show(let code): showing(code)
            case .scan: scanning
            }
        }
        .padding(.horizontal, DS.side)
        .padding(.bottom, 16)
        .animation(DS.motion(DS.spring), value: qr)
    }

    // MARK: Choice

    private var chooser: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "qrcode")
                .font(.system(size: 84, weight: .semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(L.t("用二維碼加街坊", "用二维码加邻居"))
                    .ds(.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(L.t("一部手機出示，另一部手機掃。", "一部手机出示，另一部手机扫。"))
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                choice(L.t("出示二維碼", "出示二维码"), symbol: "qrcode", filled: true) { store.bumpShowQR() }
                choice(L.t("掃二維碼", "扫二维码"), symbol: "camera.viewfinder", filled: false) { store.bumpScanQR() }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { store.beginBumpSearch() } label: { Text(L.t("返回碰一碰", "返回碰一碰")).frame(maxWidth: .infinity) }
                    .buttonStyle(.dsSecondary)
                cancelButton
            }
        }
    }

    /// Two side-by-side large icon-and-label buttons.
    private func choice(_ title: String, symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 44, weight: .semibold))
                Text(title).ds(.button).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(filled ? Color.white : DS.accentInk)
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(.vertical, 8)
            .background(filled ? DS.accent : DS.accentSoft, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(DS.accent.opacity(filled ? 0 : 0.5), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Display

    private func showing(_ code: String) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Text(qr.paired ? L.t("成功！", "成功！") : L.t("請對方掃呢個二維碼", "请对方扫这个二维码"))
                .ds(.title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ZStack {
                QRCodeImage(text: PairCode.qrPayload(code))
                    .opacity(qr.paired ? 0.15 : 1)
                if qr.paired {
                    BumpPopSymbol(name: "checkmark.circle.fill", size: 110, color: DS.accent)
                }
            }
            .frame(width: 264, height: 264)
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(qr.paired ? L.t("成功", "成功") : L.t("加街坊用嘅二維碼", "加邻居用的二维码"))
            status(waiting: L.t("等緊對方掃…", "在等对方扫…"))
            Spacer(minLength: 0)
            if qr.paired {
                Color.clear.frame(height: 56)
            } else {
                HStack(spacing: 8) {
                    Button { store.bumpScanQR() } label: { Text(L.t("改為掃對方", "改为扫对方")).frame(maxWidth: .infinity) }
                        .buttonStyle(.dsSecondary)
                    cancelButton
                }
            }
        }
    }

    // MARK: Scan

    private var scanning: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Text(qr.paired ? L.t("成功！", "成功！") : L.t("對住對方嘅二維碼", "对准对方的二维码"))
                .ds(.title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ZStack {
                QRScannerView { store.qrScanned($0) }
                if qr.linking || qr.paired {
                    Rectangle().fill(.regularMaterial)
                    if qr.paired {
                        BumpPopSymbol(name: "checkmark.circle.fill", size: 110, color: DS.accent)
                    } else {
                        ProgressView().controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(DS.accent, lineWidth: 3))
            status(waiting: nil)
            Spacer(minLength: 0)
            if qr.paired {
                Color.clear.frame(height: 56)
            } else {
                HStack(spacing: 8) {
                    Button { store.bumpShowQR() } label: { Text(L.t("改為出示", "改为出示")).frame(maxWidth: .infinity) }
                        .buttonStyle(.dsSecondary)
                    cancelButton
                }
            }
        }
    }

    // MARK: Shared components

    /// Large status line for pairing, waiting or guidance.
    @ViewBuilder
    private func status(waiting: String?) -> some View {
        if qr.paired {
            Text(L.t("你哋而家係街坊。", "你们现在是邻居了。")).ds(.bodyBold).multilineTextAlignment(.center)
        } else if let note = qr.note {
            Label {
                Text(note).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DS.accent)
            }
            .ds(.bodyBold)
            .transition(DS.slide(.bottom))
        } else if qr.linking {
            HStack(spacing: 12) {
                ProgressView()
                Text(L.t("配對緊…", "配对中…")).ds(.body)
            }
            .accessibilityElement(children: .combine)
        } else if let waiting {
            HStack(spacing: 12) {
                ProgressView()
                Text(waiting).ds(.body).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var cancelButton: some View {
        Button { store.cancelBump() } label: { Text(L.t("取消", "取消")).frame(maxWidth: .infinity) }
            .buttonStyle(.dsSecondary)
    }
}

/// Black-on-white QR image with no interpolation to preserve sharp scaling.
struct QRCodeImage: View {
    var text: String

    var body: some View {
        if let img = QRImage.make(text) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode").font(.system(size: 120)).foregroundStyle(.black)
        }
    }
}
