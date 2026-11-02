import AppRoot
import NoctisCore
import SwiftUI

@main
struct NoctisApp: App {
    @State private var container: AppContainer

    init() {
        // Made when the process starts, not when the first screen is drawn: an intent that starts the app in the background (the Sleep sounds
        // control, a Health wake) runs with no screen at all, and still needs the app's host, its sound player and its observers (R46, R47, R48).
        _container = State(initialValue: AppContainer())
        // The app switcher's picture of NOCTIS is a plain screen, never a recovery score or a Journal entry (SEC-05).
        PrivacyShield.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // `-widgetGallery`: every widget family at its real size, in every state (a DEBUG screenshot aid, R45).
            if let request = WidgetGalleryRequest(arguments: ProcessInfo.processInfo.arguments) {
                WidgetGalleryView(request: request)
            } else if let part = ActivityGalleryRequest.requested(ProcessInfo.processInfo.arguments) {
                // `-activityGallery`: the wind-down Live Activity's Lock Screen and Dynamic Island presentations (R49).
                WindDownActivityGalleryView(part: part)
            } else if IntentRunnerRequest.requested(ProcessInfo.processInfo.arguments) {
                // `-intentRunner`: what each intent says and does, for each data state (R47).
                IntentRunnerView()
            } else {
                root
            }
            #else
            root
            #endif
        }
    }

    private var root: some View {
        #if DEBUG
        // `-noctisEnvironmentProbe`: what the app reads of the device's settings, for the QA matrix (R67).
        rootContent.debugEnvironmentProbe()
        #else
        rootContent
        #endif
    }

    private var rootContent: some View {
        Group {
            RootView(initiallyOnboarded: container.model.isOnboarded)
                // A new container after "Delete all NOCTIS data": every screen is made again, and the app starts over at onboarding.
                .id(container.generation)
                .environment(\.restartApp, RestartAction { container = AppContainer(restarted: true) })
                .environment(container.model)
                .environment(container.accountStore)
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
                .environment(\.featureGate, container.featureGate)
                .environment(container.notificationCoordinator)
                .environment(\.notificationCoordinator, container.notificationCoordinator)
                .environment(container.storeManager)
        }
    }
}
