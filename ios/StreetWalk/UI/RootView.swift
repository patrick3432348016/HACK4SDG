import SwiftUI

/// Root transitions from onboarding to main with fade and slight spring scale, or fade only under Reduce Motion.
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
                // OnboardingFlow positions notices below progress or the selection explanation, avoiding another overlapping overlay.
                OnboardingFlow()
                    .transition(DS.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            } else {
                MainView()
                    .transition(DS.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(DS.motion(DS.spring), value: isOnboarding)
        // After onboarding, explain Always location permission through LocationViews.
        .sheet(isPresented: $locator.showAlwaysAsk) {
            AlwaysAskSheet().environment(store)
        }
        // Settings' four text sizes override iOS text size; initially choose the nearest system size.
        // Sheets do not inherit this environment reliably, so applyToWindows also updates UIWindowScene.
        .dynamicTypeSize(TextSizeSetting.shared.current.dynamicType)
        .onChange(of: TextSizeSetting.shared.current, initial: true) { TextSizeSetting.shared.applyToWindows() }
        .onReceive(NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)) { _ in
            TextSizeSetting.shared.applyToWindows()
        }
    }
}
