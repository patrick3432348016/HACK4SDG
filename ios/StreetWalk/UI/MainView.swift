import SwiftUI

// 占位：由子代理 A 替换。
struct MainView: View {
    @Environment(AppStore.self) private var store
    var body: some View { DioramaView(controller: store.scene) }
}
