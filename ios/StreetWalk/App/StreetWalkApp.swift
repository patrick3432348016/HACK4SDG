import SwiftUI

@main
struct StreetWalkApp: App {
    /// 系统喺背景开 App（离开屋企、到访、大范围移动）时冇画面：靠 AppDelegate 一启动就接好定位事件。
    @UIApplicationDelegateAdaptor(StreetWalkAppDelegate.self) private var appDelegate
    @State private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 第一次开：按 iOS 系统语言揀界面语言（简体 → 普通话）；要喺 AppStore.launch 之前（佢一建就用到 L.t）
        AppLanguage.prepareForLaunch()
        _store = State(initialValue: AppStore.launch())
        VoiceSettings.shared.followAppLanguage()   // 播报语言跟界面语言（-lang cmn / 设定页揀过）
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                // 启动和回到前台：拉天文台天气、开真机散步检测；后台才停（控制中心、来电等 .inactive 不理）
                .onChange(of: scenePhase, initial: true) { _, p in if p != .inactive { store.appActive(p == .active) } }
        }
        // 后台刷新（真后端）：系统叫醒时拉一次街坊出门、约会、找人询问，有新嘢出本地通知（AppStore+Backend）
        .backgroundTask(.appRefresh(BackgroundRefresh.taskID)) { [store] in await store.backgroundRefresh() }
    }
}

/// 一启动（包括 iOS 喺背景为定位事件开 App）就建好 AppStore 同 LocationMonitor，事件先唔会冇人接。
final class StreetWalkAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 系统喺背景开（定位事件）：SwiftUI App 未必带 .location，所以都睇埋而家係唔係喺背景
        let background = launchOptions?[.location] != nil || application.applicationState == .background
        AppLanguage.prepareForLaunch()   // 通常 StreetWalkApp.init 已经做咗（已揀过就唔郁）
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
    /// 录宣传片：收起「示範」标签、演示说明同演示菜单（功能照旧系演示模式）。
    static let videoClean = has("-videoClean")
}
