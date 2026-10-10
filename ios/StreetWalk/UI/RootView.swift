import SwiftUI

/// 根视图：首次使用 → 主界面。两者之间用弹簧做淡入 + 轻微缩放（减少动态效果时只淡入淡出）。
struct RootView: View {
    @Environment(AppStore.self) private var store

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
        // 正文基准已经是 24pt：系统字号调小也不缩（下限 .large = 基准）；大过无障碍第 2 档排不下，所以封顶。
        .dynamicTypeSize(.large ... .accessibility2)
    }
}
