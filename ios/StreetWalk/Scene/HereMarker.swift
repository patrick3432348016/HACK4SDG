import SwiftUI

/// Distance wording for the current-location label.
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

/// Current-location marker: blue dot with white border/pulse and a label; place at GPS position or clamp to the model edge.
/// Use a zero-size bottom-aligned frame at item.point so the dot centre matches the ground point.
struct HereMarkerView: View {
    let text: String
    /// Place text below the dot to avoid home labels above; top-align the outer container.
    var below = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 4) {
            if below { dot }
            if !text.isEmpty { label }
            if !below { dot }
        }
        // Dot centre matches the location.
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

/// Draw only the current-location marker; home selection has no other scene labels.
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

/// Show reset after gesture zoom/pan/rotation; restore original angle/scale like double-tap.
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
