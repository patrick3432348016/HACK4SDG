import SwiftUI

/// Initial iPhone 17 design at 402×874 pt: 16-pt margins, spacing in multiples of eight, and 18-pt card corners.
/// Standard title/body/secondary sizes: 34/24/20 pt. TextSize settings allow smaller/larger text; orange is the single accent.
enum DS {
    static let accent = Color(red: 0.847, green: 0.353, blue: 0.188)      // #D85A30
    static let accentSoft = Color(red: 0.847, green: 0.353, blue: 0.188).opacity(0.12)
    static let side: CGFloat = 16
    static let gap: CGFloat = 8
    static let radius: CGFloat = 18
    /// Read TextSize.sceneFraction from the SwiftUI body so the Today scene shrinks as text size grows.
    static var sceneFraction: CGFloat { TextSizeSetting.shared.current.sceneFraction }
    static let micSize: CGFloat = 68
    static let tabBarHeight: CGFloat = 83

    /// Shared spring animation for transitions, cards, and button feedback.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.68)

    /// Darker orange for small text, including AI labels, with contrast >= 4.5:1 on light/dark backgrounds.
    static let accentInk = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.604, blue: 0.431, alpha: 1)      // #FF9A6E
        : UIColor(red: 0.663, green: 0.267, blue: 0.122, alpha: 1) })  // #A9441F

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    /// Use a fade when Reduce Motion is enabled.
    static func motion(_ a: Animation) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : a }
    /// Slide and fade from the chosen edge; fade only under Reduce Motion.
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

    /// Adaptive light/dark card background with 18-pt corners.
    func dsCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

/// Primary button: orange with white text, minimum height 56, subtle press/rebound. At most one per view.
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

/// Secondary button: pale orange fill, orange border, dark-orange text. 10-18 feedback found gray-bordered white buttons hard to recognize.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ds(.button)
            .foregroundStyle(DS.accentInk)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DS.accent.opacity(0.55), lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.motion(DS.snappy), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var dsPrimary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var dsSecondary: SecondaryButtonStyle { .init() } }

/// Avatar matches the scene: capsule clothing, round face/skin tone, age-dependent hair, and walking stick/wheelchair/stroller options.
/// medal: previous month's winning-circle badge (F4).
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
        let k: CGFloat = age == .young ? 0.88 : 1           // Younger avatars have a slightly smaller body.
        let seated = mobility == .wheelchair
        let cx = u * (mobility == .stroller ? 0.40 : 0.5)
        let bottom = u * (seated ? 0.74 : 0.84)
        let w = u * 0.25 * k, h = u * (seated ? 0.27 : 0.37) * k
        let r = u * 0.13 * k
        let torso = CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h)
        let headC = CGPoint(x: cx, y: torso.minY - r * 0.95)
        let grey = Color(red: 0.56, green: 0.56, blue: 0.60)

        // Draw mobility aids behind the body first.
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
        // Draw larger, slightly raised hair before the face, leaving a visible cap.
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

/// Small scene capsules, such as return-home and demo controls.
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

/// Demo badge identifies simulated people, estate totals, and records. Use readable 20-pt secondary text in the body color.
struct DemoBadge: View {
    var text = L.t("示範", "示范", "Demo")
    var body: some View {
        if !LaunchArgs.videoClean { badge }
    }
    private var badge: some View {
        Label(text, systemImage: "sparkles")
            .ds(.captionBold)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            // Fix height only; allow long text to wrap at large sizes without widening the card beyond the screen.
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text == L.t("示範", "示范", "Demo") ? L.t("示範數據，係模擬嘅", "示范数据，是模拟的", "Demo data, simulated") : text)
    }
}

/// AI badge marks model-written/interpreted content, using 20-pt secondary text and darker orange for contrast.
struct AIBadge: View {
    var spoken = L.t("AI 寫嘅", "AI 写的", "Written by AI")
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

/// Settings Menu uses design-system title/value sizes instead of the system Form Picker's 17 pt; one-level selection.
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
            .frame(minHeight: 56)   // Use a full 56-pt row as the touch target for older users.
            .contentShape(Rectangle())
        }
        .tint(.primary)   // Form tints Menu labels; explicitly keep the title in the body-text color.
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }
}

/// One-line explanation that people/counts are local demo data rather than backend results.
struct DemoNote: View {
    var text: String
    var body: some View {
        if !LaunchArgs.videoClean { note }
    }
    private var note: some View {
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
    /// Render from resident appearance: clothing, mobility, skin tone, age, and medal.
    init(_ r: Resident, size: CGFloat = 52, medal: Bool = false) {
        self.init(color: r.color, mobility: r.mobility, size: size, skin: r.skinTone, age: r.ageGroup, medal: medal)
    }
}
