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
                .environment(container.insightsViewModel)
                .environment(container.coachViewModel)
                .environment(container.tonightViewModel)
                .environment(container.soundsViewModel)
                .environment(container.windDownViewModel)
                .environment(container.breathingViewModel)
                .environment(container.meditationViewModel)
                .environment(container.journalViewModel)
                .environment(container.preferences)
                .environment(\.appPreferences, container.preferences)
                .environment(container.notificationCoordinator)
                .environment(\.notificationCoordinator, container.notificationCoordinator)
                .environment(container.storeManager)
        }
    }
}
