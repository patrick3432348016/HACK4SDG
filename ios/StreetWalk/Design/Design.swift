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

    /// 小字用的深一档橙（浅底 / 深底对比度都 ≥ 4.5:1）：AI 标签等文字。
    static let accentInk = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.604, blue: 0.431, alpha: 1)      // #FF9A6E
        : UIColor(red: 0.663, green: 0.267, blue: 0.122, alpha: 1) })  // #A9441F

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    /// 减少动态效果时改成淡入淡出。
    static func motion(_ a: Animation) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : a }
    /// 从某边滑入 + 淡入；减少动态效果时只淡入淡出。
    static func slide(_ edge: Edge) -> AnyTransition { reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity) }
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

/// 小人头像：同场景里的小人一样——胶囊身（衫色）+ 圆头（肤色）+ 头发（長者白），加行动方式（拐杖、轮椅、BB 车）。
/// medal：上个月圈对圈赢了（F4 卡通标记）。
struct AvatarBadge: View {
    var color: Color
    var mobility: Mobility
    var size: CGFloat = 52
    var skin = 1
    var age: AgeGroup = .adult
    var medal = false

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, u: sz.width) }
            .frame(width: size, height: size)
            .background(Circle().fill(Color(.tertiarySystemFill)))
            .overlay(alignment: .bottomTrailing) {
                if medal {
                    Image(systemName: "rosette")
                        .font(.system(size: size * 0.24, weight: .bold))
                        .foregroundStyle(Color(red: 0.80, green: 0.55, blue: 0.0))
                        .frame(width: size * 0.4, height: size * 0.4)
                        .background(Circle().fill(Color(red: 1.0, green: 0.85, blue: 0.35)))
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: max(1.5, size * 0.04)))
                        .offset(x: size * 0.06, y: size * 0.06)
                }
            }
            .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, u: CGFloat) {
        let k: CGFloat = age == .young ? 0.88 : 1           // 後生身形小一点
        let seated = mobility == .wheelchair
        let cx = u * (mobility == .stroller ? 0.40 : 0.5)
        let bottom = u * (seated ? 0.74 : 0.84)
        let w = u * 0.25 * k, h = u * (seated ? 0.27 : 0.37) * k
        let r = u * 0.13 * k
        let torso = CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h)
        let headC = CGPoint(x: cx, y: torso.minY - r * 0.95)
        let grey = Color(red: 0.56, green: 0.56, blue: 0.60)

        // 行动方式：在身后的先画
        if mobility == .stroller {
            let cart = CGRect(x: u * 0.56, y: u * 0.55, width: u * 0.24, height: u * 0.18)
            var handle = Path(); handle.move(to: CGPoint(x: torso.maxX - w * 0.1, y: torso.minY + h * 0.35)); handle.addLine(to: CGPoint(x: cart.minX + u * 0.02, y: cart.minY))
            ctx.stroke(handle, with: .color(grey), style: StrokeStyle(lineWidth: u * 0.035, lineCap: .round))
            ctx.fill(Path(roundedRect: cart, cornerRadius: u * 0.06), with: .color(Color(red: 0.55, green: 0.65, blue: 0.78)))
            for x in [cart.minX + u * 0.05, cart.maxX - u * 0.05] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - u * 0.035, y: cart.maxY, width: u * 0.07, height: u * 0.07)), with: .color(grey))
            }
        }
        ctx.fill(Path(roundedRect: torso, cornerRadius: w / 2), with: .color(color))
        // 头发先画（大少少、偏上），再画面，露出一块发盖。
        ctx.fill(Path(ellipseIn: CGRect(x: headC.x - r * 1.08, y: headC.y - r * 1.2, width: r * 2.16, height: r * 1.9)),
                 with: .color(Color(Palette.hairUI(age))))
        if age == .elder {
            ctx.stroke(Path(ellipseIn: CGRect(x: headC.x - r * 1.08, y: headC.y - r * 1.2, width: r * 2.16, height: r * 1.9)),
                       with: .color(.primary.opacity(0.18)), lineWidth: max(0.75, u * 0.012))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: headC.x - r * 0.9, y: headC.y - r * 0.62, width: r * 1.8, height: r * 1.62)),
                 with: .color(Palette.skin(skin)))
        switch mobility {
        case .cane:
            var cane = Path(); cane.move(to: CGPoint(x: torso.maxX + u * 0.06, y: torso.minY + h * 0.3)); cane.addLine(to: CGPoint(x: torso.maxX + u * 0.09, y: bottom + u * 0.02))
            ctx.stroke(cane, with: .color(grey), style: StrokeStyle(lineWidth: u * 0.04, lineCap: .round))
        case .wheelchair:
            let wr = u * 0.15
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - wr + u * 0.03, y: bottom - wr * 1.1, width: wr * 2, height: wr * 2)),
                       with: .color(grey), lineWidth: u * 0.045)
        case .walk, .stroller:
            break
        }
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

/// 「示範」小标签：标明这块数据是单机演示模拟的（圈里其他人、全邨汇总、示範纪录）。辅助字号 20、正文色，老人看得清。
struct DemoBadge: View {
    var text = "示範"
    var body: some View {
        Label(text, systemImage: "sparkles")
            .ds(.captionBold)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            // 只固定高度：大字号时长句可以换行，不会把整张卡撑出屏幕
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text == "示範" ? "示範數據，係模擬嘅" : text)
    }
}

/// 「AI」小标签：表示这句是 AI 写 / 理解的。辅助字号 20，深一档橙保证对比度。
struct AIBadge: View {
    var spoken = "AI 寫嘅"
    var body: some View {
        Text("AI")
            .ds(.captionBold)
            .foregroundStyle(DS.accentInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(DS.accentSoft, in: Capsule())
            .fixedSize()
            .accessibilityLabel(spoken)
    }
}

/// 设置页用的选项：系统 Picker 在表单里的值只有 17pt，不合设计规范；这里用 Menu，标题和值都用规范字号，一层选完。
struct DSMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(label(selection)).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .ds(.body)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .tint(.primary)   // 表单里 Menu 的 label 会被染成强调色，标题要用正文色
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
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

extension AvatarBadge {
    /// 按居民资料画（色、行动方式、肤色、年龄、奖牌）。
    init(_ r: Resident, size: CGFloat = 52, medal: Bool = false) {
        self.init(color: r.color, mobility: r.mobility, size: size, skin: r.skinTone, age: r.ageGroup, medal: medal)
    }
}
