import SwiftUI
import Observation

/// In-app text sizing overrides iOS dynamicTypeSize in RootView.
/// All ds fonts (@ScaledMetric) and system controls scale together; DS.sceneFraction shrinks the scene for larger text.
enum TextSize: String, CaseIterable, Codable, Sendable {
    case small, standard, large, xlarge

    var label: String {
        switch self {
        case .small: return L.t("細", "小")
        case .standard: return L.t("標準", "标准")
        case .large: return "大"
        case .xlarge: return "特大"
        }
    }

    /// Body/secondary/title sizes: small about 21/17.5/32; standard 24/20/34; large about 27/22.5/36; extra-large about 32.5/27.5/40.
    /// Avoid the accessibility category with 40-pt body text: even a 22% scene leaves only one-and-a-half cards visible.
    var dynamicType: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .xlarge: return .xxxLarge
        }
    }

    /// Use fixed sample sizes on setting buttons so the buttons do not move when the selected size changes.
    var sampleSize: CGFloat {
        switch self {
        case .small: return 20
        case .standard: return 24
        case .large: return 28
        case .xlarge: return 32
        }
    }

    /// Today scene only. The 10-12 decision used about 25%; 10-16 feedback increased it to about 38% below Dynamic Island. Shrink for large text; pull down to enlarge (MainLayout).
    var sceneFraction: CGFloat {
        switch self {
        case .small, .standard: return 0.38
        case .large: return 0.34
        case .xlarge: return 0.30
        }
    }

    /// On upgrade without a saved choice, select the closest iOS size. Treat sizes below default as standard to preserve the earlier lower bound.
    static func matching(_ system: DynamicTypeSize) -> TextSize {
        if system <= .large { return .standard }
        if system <= .xLarge { return .large }
        return .xlarge
    }
}

@Observable
final class TextSizeSetting: @unchecked Sendable {
    static let shared = TextSizeSetting()
    static let key = "app.textSize"

    /// Saved selection; nil follows the system until the user chooses.
    private(set) var saved: TextSize?
    /// Read the actual iOS text category through UIApplication in applyToWindows; SwiftUI's environment already contains our override.
    var system: DynamicTypeSize = .large

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        if let i = arguments.firstIndex(of: "-textSize"), i + 1 < arguments.count, let t = TextSize(rawValue: arguments[i + 1]) {
            saved = t   // Screenshots: -textSize xlarge applies without persistence.
        } else {
            saved = defaults.string(forKey: Self.key).flatMap(TextSize.init(rawValue:))
        }
    }

    /// Currently effective size.
    var current: TextSize { saved ?? TextSize.matching(system) }

    /// Settings selection takes effect immediately and is saved.
    func set(_ t: TextSize) {
        saved = t
        defaults.set(t.rawValue, forKey: Self.key)
    }

    /// Apply traitOverrides to every UIWindowScene so sheets/full-screen presentations and UIKit controls also use the selected category.
    /// They do not inherit RootView.dynamicTypeSize. Apply on RootView appearance, app-size changes, and system-size changes.
    @MainActor func applyToWindows() {
        let s = DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory) ?? .large
        if system != s { system = s }
        let c = UIContentSizeCategory(current.dynamicType)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            // Check contains before reading preferredContentSizeCategory; reading an unset override asserts.
            let o = scene.traitOverrides
            if !o.contains(UITraitPreferredContentSizeCategory.self) || o.preferredContentSizeCategory != c {
                scene.traitOverrides.preferredContentSizeCategory = c
            }
        }
    }
}

/// Four large text-size buttons: small, standard, large, extra-large. Each previews its size; selected uses orange with white text.
struct TextSizePicker: View {
    var body: some View {
        let setting = TextSizeSetting.shared
        let current = setting.current
        HStack(spacing: 8) {
            ForEach(TextSize.allCases, id: \.self) { t in
                let on = t == current
                Button {
                    guard !on else { return }
                    setting.set(t)
                    Haptics.select()
                } label: {
                    Text(t.label)
                        .font(.system(size: t.sampleSize, weight: on ? .bold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(on ? DS.accent : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("字體\(t.label)", "字体\(t.label)"))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
