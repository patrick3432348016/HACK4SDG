import SwiftUI

@main
struct StreetWalkApp: App {
    /// A background location launch has no UI; AppDelegate must connect location events immediately.
    @UIApplicationDelegateAdaptor(StreetWalkAppDelegate.self) private var appDelegate
    @State private var store = AppStore.launch()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        VoiceSettings.shared.followAppLanguage()   // Speech follows the UI language, including launch arguments and saved settings.
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                // On launch/foreground, fetch Observatory weather and enable real walk detection. Stop only on background, not transient inactive states such as calls or Control Center.
                .onChange(of: scenePhase, initial: true) { _, p in if p != .inactive { store.appActive(p == .active) } }
        }
        // Background refresh fetches outings, meetups, and finding requests from the real backend and posts local notifications for new events.
        .backgroundTask(.appRefresh(BackgroundRefresh.taskID)) { [store] in await store.backgroundRefresh() }
    }
}

/// Create AppStore and LocationMonitor immediately, including background location launches, so events have a receiver.
final class StreetWalkAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // SwiftUI background location launches may omit the .location option; also inspect the current background state.
        let background = launchOptions?[.location] != nil || application.applicationState == .background
        _ = AppStore.launch()
        if background { LocationMonitor.shared.noteLocationLaunch() }
        return true
    }
}

enum LaunchArgs {
    static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }
    static func value(_ flag: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static var hour: Double? { value("-hour").flatMap(Double.init) }
}
