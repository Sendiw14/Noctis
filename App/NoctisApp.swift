import SwiftUI
import AppRoot

@main
struct NoctisApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(initiallyOnboarded: container.model.isOnboarded)
                .environment(container.model)
                .environment(container.homeViewModel)
                .environment(container.sleepViewModel)
                .environment(container.recoveryViewModel)
                .environment(container.storeManager)
        }
    }
}
