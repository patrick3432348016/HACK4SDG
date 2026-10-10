import SwiftUI

@main
struct UWBMeetApp: App {
    @StateObject private var model = MeetCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onChange(of: scenePhase) { phase in
                    if phase == .background { model.wentToBackground() }
                }
        }
    }
}

