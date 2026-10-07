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
                OnboardingFlow()
                    // 首次使用时也可能有提示（例如"請揀一座住宅樓"），放在顶部，不挡底部大按钮。
                    .overlay(alignment: .top) { ToastView().padding(.top, DS.gap) }
                    .transition(DS.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            } else {
                MainView()
                    .transition(DS.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(DS.motion(DS.spring), value: isOnboarding)
        // 正文基准已经是 24pt；再大过无障碍第 2 档就排唔落，所以封顶。
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
