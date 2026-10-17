import SwiftUI

/// 「你喺呢度」标签用嘅距离字眼。
enum HereText {
    static func distance(_ m: Double) -> String {
        if m < 1000 {
            let r = max(10, Int((m / 10).rounded()) * 10)
            return L.t(" \(r) 米", " \(r) 米", "\(r) m")
        }
        let f = m < 10_000 ? "%.1f" : "%.0f"
        return String(format: L.t(" \(f) 公里", " \(f) 公里", "\(f) km"), m / 1000)
    }
}

/// 场景上「你喺呢度」：蓝色小圆点（白边、慢慢一呼一吸）+ 上面一个小标签。点落喺 GPS 位置（超出模型就贴边）。
/// 用法：.frame(width: 0, height: 0, alignment: .bottom).position(item.point)，圆点中心对住地面。
struct HereMarkerView: View {
    let text: String
    /// 字摆喺圆点下面（上面撞到「你屋企」等名牌）；外层按顶部对齐。
    var below = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 4) {
            if below { dot }
            if !text.isEmpty { label }
            if !below { dot }
        }
        // 圆点中心对住位置
        .offset(y: below ? -15 : 15)
        .allowsHitTesting(false)
        .onAppear {
            guard !DS.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.isEmpty ? L.t("你喺屋企", "你在家", "You're at home") : text)
    }

    private var label: some View {
        Text(text)
            .ds(.caption)
            .lineLimit(1)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Self.blue.opacity(0.6), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }

    private var dot: some View {
        ZStack {
            Circle()
                .fill(Self.blue.opacity(0.25))
                .frame(width: 30, height: 30)
                .scaleEffect(pulse ? 1.15 : 0.7)
                .opacity(pulse ? 0.2 : 0.8)
            Circle()
                .fill(Self.blue)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: 30, height: 30)
    }

    static let blue = Color(red: 0.16, green: 0.47, blue: 0.96)
}

/// 只画「你喺呢度」（选楼画面冇其他场景标签）。
struct HereMarkerLayer: View {
    let overlay: OverlayModel

    var body: some View {
        let here = overlay.items.first { $0.kind == .here }
        ZStack(alignment: .topLeading) {
            if let here {
                HereMarkerView(text: here.text)
                    .fixedSize()
                    .frame(width: 0, height: 0, alignment: .bottom)
                    .position(here.point)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// 「回正」：用手指放大、移动、转动过之后出现，撳一下返原来嘅角度同大细（同双击一样）。
struct MapResetButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L.t("回正", "回正", "Reset"), systemImage: "location.north.line.fill")
                .ds(.captionBold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityHint(L.t("地圖返原來嘅角度同大細", "地图回到原来的角度和大小", "Puts the map back to its normal angle and size"))
    }
}
