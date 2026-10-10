import SwiftUI

// MARK: - 二维码加街坊（碰一碰全屏画面入面）

/// 唔支援超宽带、碰唔到、或者只有一部支援时用：一部出示，另一部掃。
/// 状态喺 store.bumpQR；流程见 AppStore+Bump。
struct BumpQRContent: View {
    @Environment(AppStore.self) private var store
    var qr: BumpQRState
    var demo: Bool

    var body: some View {
        VStack(spacing: 20) {
            if demo {
                DemoBadge(text: qr.mode == .scan ? "示範：掃到就當加咗示範街坊" : "示範：過幾秒當對方掃咗")
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

    // MARK: 揀

    private var chooser: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "qrcode")
                .font(.system(size: 84, weight: .semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("用二維碼加街坊")
                    .ds(.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("一部手機出示，另一部手機掃。")
                    .ds(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                choice("出示二維碼", symbol: "qrcode", filled: true) { store.bumpShowQR() }
                choice("掃二維碼", symbol: "camera.viewfinder", filled: false) { store.bumpScanQR() }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { store.beginBumpSearch() } label: { Text("返回碰一碰").frame(maxWidth: .infinity) }
                    .buttonStyle(.dsSecondary)
                cancelButton
            }
        }
    }

    /// 大格按钮：图标 + 字，两格并排。
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

    // MARK: 出示

    private func showing(_ code: String) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Text(qr.paired ? "成功！" : "請對方掃呢個二維碼")
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
            .accessibilityLabel(qr.paired ? "成功" : "加街坊用嘅二維碼")
            status(waiting: "等緊對方掃…")
            Spacer(minLength: 0)
            if qr.paired {
                Color.clear.frame(height: 56)
            } else {
                HStack(spacing: 8) {
                    Button { store.bumpScanQR() } label: { Text("改為掃對方").frame(maxWidth: .infinity) }
                        .buttonStyle(.dsSecondary)
                    cancelButton
                }
            }
        }
    }

    // MARK: 掃

    private var scanning: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Text(qr.paired ? "成功！" : "對住對方嘅二維碼")
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
                    Button { store.bumpShowQR() } label: { Text("改為出示").frame(maxWidth: .infinity) }
                        .buttonStyle(.dsSecondary)
                    cancelButton
                }
            }
        }
    }

    // MARK: 共用

    /// 一行状态：配对中 / 等对方 / 提示（大字）。
    @ViewBuilder
    private func status(waiting: String?) -> some View {
        if qr.paired {
            Text("你哋而家係街坊。").ds(.bodyBold).multilineTextAlignment(.center)
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
                Text("配對緊…").ds(.body)
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
        Button { store.cancelBump() } label: { Text("取消").frame(maxWidth: .infinity) }
            .buttonStyle(.dsSecondary)
    }
}

/// 二维码图：放大唔会模糊（interpolation none），黑码白底。
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
