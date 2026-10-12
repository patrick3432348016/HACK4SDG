import SwiftUI
import Observation

/// 字体大小（设定页最上面「字體大小」）：App 内部用 `.dynamicTypeSize` 覆盖 iOS 文字大小（RootView），
/// 所有 `.ds(...)` 字体（@ScaledMetric）同系统控件一齐跟住变。字大时上面 3D 场景跟住缩（DS.sceneFraction）。
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

    /// 正文 / 辅助 / 标题：細 ≈21 / 17.5 / 32，標準 24 / 20 / 34，大 ≈27 / 22.5 / 36，特大 ≈32.5 / 27.5 / 40。
    /// 特大唔用无障碍档（正文 40）：场景缩到 22% 都只见到一张半卡。
    var dynamicType: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .xlarge: return .xxxLarge
        }
    }

    /// 设定页按钮上用嘅示范字号（固定，唔跟当前档变，个掣唔会郁来郁去）。
    var sampleSize: CGFloat {
        switch self {
        case .small: return 20
        case .standard: return 24
        case .large: return 28
        case .xlarge: return 32
        }
    }

    /// 上面 3D 场景占屏幕高度：字大就缩，内容区至少见到两张卡。標準 42% 係负责人定咗嘅，唔好郁。
    var sceneFraction: CGFloat {
        switch self {
        case .small, .standard: return 0.42
        case .large: return 0.30
        case .xlarge: return 0.22
        }
    }

    /// 未揀过（旧版本升级上嚟）：按 iOS 文字大小揀最接近嗰档。以前 App 跟 iOS 走、下限锁喺默认，所以细过默认都当標準。
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

    /// 用户揀咗嘅档；nil = 未揀过，跟 iOS 文字大小（system）。
    private(set) var saved: TextSize?
    /// iOS 设定入面嘅文字大小（applyToWindows 读 UIApplication 更新；唔可以读 SwiftUI 环境，嗰个已经俾我哋覆盖咗）。
    var system: DynamicTypeSize = .large

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        if let i = arguments.firstIndex(of: "-textSize"), i + 1 < arguments.count, let t = TextSize(rawValue: arguments[i + 1]) {
            saved = t   // 截图用：-textSize xlarge（唔存）
        } else {
            saved = defaults.string(forKey: Self.key).flatMap(TextSize.init(rawValue:))
        }
    }

    /// 而家用紧嘅档。
    var current: TextSize { saved ?? TextSize.matching(system) }

    /// 设定页揀：即时生效兼存低。
    func set(_ t: TextSize) {
        saved = t
        defaults.set(t.rawValue, forKey: Self.key)
    }

    /// 将而家嘅档写入每个 UIWindowScene 嘅 traitOverrides：半屏 / 全屏弹出页（设定、改网名、时间滑杆）同 UIKit 控件
    /// 唔跟 RootView 嘅 `.dynamicTypeSize`，要喺 UIKit 层一齐覆盖。RootView 出现、换档、iOS 文字大小改咗时叫。
    @MainActor func applyToWindows() {
        let s = DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory) ?? .large
        if system != s { system = s }
        let c = UIContentSizeCategory(current.dynamicType)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            // 未覆盖过就读 preferredContentSizeCategory 会断言失败，要先问 contains
            let o = scene.traitOverrides
            if !o.contains(UITraitPreferredContentSizeCategory.self) || o.preferredContentSizeCategory != c {
                scene.traitOverrides.preferredContentSizeCategory = c
            }
        }
    }
}

/// 设定页「字體大小」：四粒大掣（細 / 標準 / 大 / 特大），每粒用嗰档嘅示范字号写；揀中 = 橙底白字。
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
