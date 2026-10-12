import SwiftUI

/// 根视图：首次使用 → 主界面。两者之间用弹簧做淡入 + 轻微缩放（减少动态效果时只淡入淡出）。
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Bindable private var locator = LocationMonitor.shared

    private var isOnboarding: Bool {
        if case .onboarding = store.phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            if isOnboarding {
                // 首次使用的提示由 OnboardingFlow 放在进度点下面（选楼页放在说明卡下面），不再叠一层压住进度点。
                OnboardingFlow()
                    .transition(DS.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            } else {
                MainView()
                    .transition(DS.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(DS.motion(DS.spring), value: isOnboarding)
        // 完成首次使用后：点解要「始终允许」定位（LocationViews）
        .sheet(isPresented: $locator.showAlwaysAsk) {
            AlwaysAskSheet().environment(store)
        }
        // 字号由设定页「字體大小」决定（細 / 標準 / 大 / 特大），覆盖 iOS 文字大小；未揀过就按 iOS 揀最接近嗰档。
        // 弹出页唔跟呢度嘅环境，所以 UIWindowScene 都覆盖埋（applyToWindows）。
        .dynamicTypeSize(TextSizeSetting.shared.current.dynamicType)
        .onChange(of: TextSizeSetting.shared.current, initial: true) { TextSizeSetting.shared.applyToWindows() }
        .onReceive(NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)) { _ in
            TextSizeSetting.shared.applyToWindows()
        }
    }
}
