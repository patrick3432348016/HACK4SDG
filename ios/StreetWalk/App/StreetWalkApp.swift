import SwiftUI

@main
struct StreetWalkApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

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

enum LaunchArgs {
    static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }
    static func value(_ flag: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static var hour: Double? { value("-hour").flatMap(Double.init) }
}
