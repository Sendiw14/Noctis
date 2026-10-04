import SwiftUI

/// The NOCTIS Watch app (APP_RULES.md R50, R51): it shows the summary the person's iPhone sends, and nothing it works out itself. It has no HealthKit
/// entitlement and no usage string, runs no engine and reads no Health.
@main
struct NOCTISWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
        }
        // The iPhone's update arrived while the app was not running: the system wakes it for the delivery, and the task is completed when this returns.
        .backgroundTask(.watchConnectivity) { [model] in
            await model.receiver?.finishPendingContent()
        }
    }
}
