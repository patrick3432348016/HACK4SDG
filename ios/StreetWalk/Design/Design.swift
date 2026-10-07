import SwiftUI

/// 设计规范（按 iPhone 17 402×874 pt，第一版草图）：侧边距 16，间距 8 的倍数，卡片圆角 18；
/// 字号三档 标题 34 / 正文 24 / 辅助 20，随动态字体只放大；单一强调色橙。
enum DS {
    static let accent = Color(red: 0.847, green: 0.353, blue: 0.188)      // #D85A30
    static let accentSoft = Color(red: 0.847, green: 0.353, blue: 0.188).opacity(0.12)
    static let side: CGFloat = 16
    static let gap: CGFloat = 8
    static let radius: CGFloat = 18
    static let sceneFraction: CGFloat = 0.42
    static let micSize: CGFloat = 68
    static let tabBarHeight: CGFloat = 83

    /// 统一弹簧：界面切换、卡片出入、按钮反馈。
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.68)

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    /// 减少动态效果时改成淡入淡出。
    static func motion(_ a: Animation) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : a }
}

enum DSFont {
    case title, body, bodyBold, caption, captionBold, button

    var size: CGFloat {
        switch self {
        case .title: return 34
        case .body, .bodyBold, .button: return 24
        case .caption, .captionBold: return 20
        }
    }
    var weight: Font.Weight {
        switch self {
        case .title: return .bold
        case .bodyBold, .button, .captionBold: return .semibold
        default: return .regular
        }
    }
    var textStyle: Font.TextStyle {
        switch self {
        case .title: return .largeTitle
        case .caption, .captionBold: return .callout
        default: return .body
        }
    }
}

private struct ScaledFont: ViewModifier {
    @ScaledMetric var size: CGFloat
    let weight: Font.Weight
    init(_ f: DSFont) {
        _size = ScaledMetric(wrappedValue: f.size, relativeTo: f.textStyle)
        weight = f.weight
    }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight)) }
}

extension View {
    func ds(_ f: DSFont) -> some View { modifier(ScaledFont(f)) }

    /// 白底卡片（深色模式自动变色），圆角 18。
    func dsCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// 主按钮：橙底白字，最小高 56，按下微缩回弹。一个视图里最多一个。
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ds(.button)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(DS.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.motion(DS.snappy), value: configuration.isPressed)
    }
}

/// 次按钮：描边。
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ds(.button)
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(Color(.systemBackground).opacity(0.001), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.motion(DS.snappy), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var dsPrimary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var dsSecondary: SecondaryButtonStyle { .init() } }

/// 小人头像：与场景里的小人同色、同行动方式。
struct AvatarBadge: View {
    var color: Color
    var mobility: Mobility
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().fill(Color(.tertiarySystemFill))
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(color)
            if mobility == .cane {
                // 系统没有拐杖图标：在走路的人旁边画一根拐杖。
                Capsule()
                    .fill(color)
                    .frame(width: max(2, size * 0.055), height: size * 0.4)
                    .rotationEffect(.degrees(-10))
                    .offset(x: size * 0.2, y: size * 0.07)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    var symbol: String {
        switch mobility {
        case .walk: return "figure.walk"
        case .cane: return "figure.walk"
        case .wheelchair: return "figure.roll"
        case .stroller: return "stroller.fill"
        }
    }
}

/// 场景上的小胶囊（左上「回到我屋企」、右上「演示」等）。
struct SceneChip<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label
    var body: some View {
        Button(action: action) {
            label
                .ds(.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

/// 「示範」小标签：标明这块数据是单机演示模拟的（圈里其他人、全邨汇总、示範纪录）。
struct DemoBadge: View {
    var text = "示範"
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 15
    var body: some View {
        Label(text, systemImage: "sparkles")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .fixedSize()
            .accessibilityLabel("示範數據，係模擬嘅")
    }
}

/// 一行说明：这一页的人 / 数字是示範（单机演示，未接后端）。
struct DemoNote: View {
    var text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .ds(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
