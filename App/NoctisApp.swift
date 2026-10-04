import SwiftUI
import AppRoot
import NoctisCore

@main
struct NoctisApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(initiallyOnboarded: container.model.isOnboarded)
                // A new container after "Delete all NOCTIS data": every screen is made again, and the app starts over at onboarding.
                .id(container.generation)
                .environment(\.restartApp, RestartAction { container = AppContainer(restarted: true) })
                .environment(container.model)
                .environment(container.homeViewModel)
                .environment(container.sleepViewModel)
                .environment(container.recoveryViewModel)
                .environment(container.insightsViewModel)
                .environment(container.coachViewModel)
                .environment(container.tonightViewModel)
                .environment(container.profileViewModel)
                .environment(container.settingsViewModel)
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
