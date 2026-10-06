import SwiftUI

// 占位：由子代理 A 替换。
struct RootView: View {
    @Environment(AppStore.self) private var store
    var body: some View { MainView() }
}
