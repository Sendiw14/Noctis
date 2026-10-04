import AppIntents
import NoctisIntentKit

/// The App Shortcuts' source lives in the app target: the intents themselves are in `NoctisIntentKit`, which the widget extension links too
/// (its controls use them), so the app names that package here (APP_RULES.md R47).
struct NoctisAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [NoctisIntentKitPackage.self] }
}

/// The spoken phrases (each says the app's name) and the Shortcuts gallery's tiles. The phrases are keys in `AppShortcuts.xcstrings`, so each
/// can be translated; `AppShortcutsTests` holds the provider, the catalog and the intents' flags to the same list.
struct NoctisShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .orange }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowMyRecoveryIntent(),
            phrases: ["Show my recovery in \(.applicationName)"],
            shortTitle: "Recovery", systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: ShowMySleepIntent(),
            phrases: ["Show my sleep in \(.applicationName)"],
            shortTitle: "Sleep", systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: StartWindDownIntent(),
            phrases: ["Start my wind-down in \(.applicationName)"],
            shortTitle: "Wind down", systemImageName: "moon.stars.fill"
        )
        AppShortcut(
            intent: ShowRecommendedBedtimeIntent(),
            phrases: ["What time should I sleep in \(.applicationName)"],
            shortTitle: "Bedtime", systemImageName: "bed.double.fill"
        )
        AppShortcut(
            intent: PlaySleepSoundsIntent(),
            phrases: ["Start my sleep sounds in \(.applicationName)"],
            shortTitle: "Sleep sounds", systemImageName: "waveform"
        )
        AppShortcut(
            intent: AskCoachIntent(),
            phrases: ["Ask Coach in \(.applicationName)"],
            shortTitle: "Ask Coach", systemImageName: "sparkles"
        )
    }
}
