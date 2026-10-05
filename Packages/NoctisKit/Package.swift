// swift-tools-version: 6.2
import PackageDescription

let noctisSwiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("ExistentialAny"),
]

/// The pure engine modules are nonisolated by default: `HomeRepository`
/// runs them on its own actor, off the main thread (APP_RULES.md R20).
let engineSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "NoctisKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "HealthProviding", targets: ["HealthProviding"]),
        .library(name: "SleepKit", targets: ["SleepKit"]),
        .library(name: "RecoveryKit", targets: ["RecoveryKit"]),
        .library(name: "InsightsKit", targets: ["InsightsKit"]),
        .library(name: "SleepAnalysisKit", targets: ["SleepAnalysisKit"]),
        .library(name: "NoctisCore", targets: ["NoctisCore"]),
        .library(name: "OnboardingFeature", targets: ["OnboardingFeature"]),
        .library(name: "HomeFeature", targets: ["HomeFeature"]),
        .library(name: "SleepFeature", targets: ["SleepFeature"]),
        .library(name: "RecoveryFeature", targets: ["RecoveryFeature"]),
        .library(name: "InsightsFeature", targets: ["InsightsFeature"]),
        .library(name: "CoachKit", targets: ["CoachKit"]),
        .library(name: "CoachFeature", targets: ["CoachFeature"]),
        .library(name: "AlarmShared", targets: ["AlarmShared"]),
        .library(name: "NoctisWidgetKit", targets: ["NoctisWidgetKit"]),
        .library(name: "NoctisWatchKit", targets: ["NoctisWatchKit"]),
        .library(name: "NoctisIntentKit", targets: ["NoctisIntentKit"]),
        .library(name: "SoundCatalog", targets: ["SoundCatalog"]),
        .library(name: "SoundKit", targets: ["SoundKit"]),
        .library(name: "BreathingKit", targets: ["BreathingKit"]),
        .library(name: "PremiumKit", targets: ["PremiumKit"]),
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
        .library(name: "NightKit", targets: ["NightKit"]),
        .library(name: "NightFeature", targets: ["NightFeature"]),
        .library(name: "JournalKit", targets: ["JournalKit"]),
        .library(name: "ProfileFeature", targets: ["ProfileFeature"]),
        .library(name: "AppRoot", targets: ["AppRoot"]),
    ],
    targets: [
        .target(name: "DesignSystem", swiftSettings: noctisSwiftSettings),
        .target(name: "HealthProviding", swiftSettings: noctisSwiftSettings),
        .target(name: "SleepKit", dependencies: ["HealthProviding"], swiftSettings: engineSwiftSettings),
        .target(name: "RecoveryKit", dependencies: ["HealthProviding", "SleepKit"], swiftSettings: engineSwiftSettings),
        .target(name: "InsightsKit", dependencies: ["SleepKit", "RecoveryKit", "SleepAnalysisKit"], swiftSettings: engineSwiftSettings),
        .target(name: "SleepAnalysisKit", dependencies: ["HealthProviding", "SleepKit", "RecoveryKit"], swiftSettings: engineSwiftSettings),
        // What the app and its alarm widget extension both have to agree on
        // (the alarm's metadata type). Nothing else, so the extension stays small.
        .target(name: "AlarmShared", swiftSettings: engineSwiftSettings),
        // What the widgets read and draw (APP_RULES.md R44, R45): the `WidgetSnapshot` the app writes into the App Group, its
        // store, the pure timeline and display builders and the flat widget views. It depends on the design tokens and on
        // nothing that reads Health, SwiftData or Coach, so a widget extension (and a Watch app later) can link it and
        // cannot reach them (and on `PremiumKit`, which depends on nothing: the snapshot carries the tier, and the widgets ask the one feature table what the
        // tier includes, APP_RULES.md R59). Nonisolated like the engines; the views are main-actor through `View`.
        .target(name: "NoctisWidgetKit", dependencies: ["DesignSystem", "PremiumKit"], swiftSettings: engineSwiftSettings),
        // What the Apple Watch app does with what the iPhone sends (APP_RULES.md R50, R51): the inbox that stores the snapshot and applies the data
        // epoch, and the pure builders of every page and state. It builds for watchOS and iOS (the tests run on iOS), depends on the widget kit
        // (the snapshot and its rules) and the design tokens through it, and on nothing that reads Health, SwiftData or Coach: the Watch runs no engines.
        .target(name: "NoctisWatchKit", dependencies: ["NoctisWidgetKit", "DesignSystem", "BreathingKit"], swiftSettings: engineSwiftSettings),
        // Siri, Shortcuts, Control Center and the wind-down Live Activity's buttons (APP_RULES.md R47, R48, R49): the App Intents, their
        // entities, and what an intent asks of the running app. It depends on the widget kit (the snapshot and the spoken words) and the
        // sound list, and on nothing that reads Health, SwiftData or Coach, so the widget extension can link it for its controls.
        .target(name: "NoctisIntentKit", dependencies: ["NoctisWidgetKit", "SoundCatalog"], swiftSettings: engineSwiftSettings),
        // The names of the six sleep sounds and nothing else: no audio, no player, no storage. The intents, and the widgets extension that links
        // them, name a sound through this; SoundKit re-exports it.
        .target(name: "SoundCatalog", swiftSettings: engineSwiftSettings),
        // Sleep sounds: synthesized in code, played through AVAudioEngine. No audio files, no UI.
        // Nonisolated like the other engines; the player alone is main-actor (APP_RULES.md R31).
        .target(name: "SoundKit", dependencies: ["SoundCatalog"], swiftSettings: engineSwiftSettings),
        // Tonight's bedtime recommendation, the alarm's state machine and the
        // service that wraps AlarmKit. No UI; nonisolated like the other engines.
        // The breathing patterns and schedule, with no dependencies: the iPhone's breathing and the Apple Watch's both draw them.
        .target(name: "BreathingKit", swiftSettings: engineSwiftSettings),
        // The feature table, the entitlement rules, the free Coach questions' arithmetic and which sounds a plan includes: pure, with no dependency but the sound names, so the
        // widgets, the Watch and the intents can link it.
        .target(name: "PremiumKit", dependencies: ["SoundCatalog"], swiftSettings: engineSwiftSettings),
        // The weekly and monthly reviews (APP_RULES.md R39): their periods, the engine that builds a record from the nights and the previous period, and the one
        // builder of their words. Pure and nonisolated like the other engines; it reuses the baseline, history and ranking engines and reads nothing itself.
        .target(name: "ReviewKit", dependencies: ["SleepKit", "RecoveryKit", "SleepAnalysisKit", "InsightsKit"], swiftSettings: engineSwiftSettings),
        .target(
            name: "NightKit",
            dependencies: ["SleepKit", "RecoveryKit", "SleepAnalysisKit", "AlarmShared", "BreathingKit"],
            swiftSettings: engineSwiftSettings
        ),
        .target(
            name: "NoctisCore",
            dependencies: ["HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit", "SleepAnalysisKit", "NightKit", "SoundKit", "DesignSystem", "NoctisWidgetKit", "PremiumKit", "ReviewKit"],
            swiftSettings: noctisSwiftSettings
        ),
        .target(name: "OnboardingFeature", dependencies: ["DesignSystem", "NoctisCore"], swiftSettings: noctisSwiftSettings),
        .target(
            name: "HomeFeature",
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit", "NoctisWidgetKit"],
            swiftSettings: noctisSwiftSettings
        ),
        .target(
            name: "SleepFeature",
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "SleepAnalysisKit", "HomeFeature"],
            swiftSettings: noctisSwiftSettings
        ),
        .target(
            name: "RecoveryFeature",
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "HomeFeature"],
            swiftSettings: noctisSwiftSettings
        ),
        .target(
            name: "InsightsFeature",
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit", "HomeFeature", "ReviewKit"],
            swiftSettings: noctisSwiftSettings
        ),
        // Coach's foundation: the router, facts and context, the validator, the providers
        // and the service. No UI. Nonisolated like the other engines.
        .target(
            name: "CoachKit",
            dependencies: [
                "DesignSystem", "NoctisCore", "HomeFeature", "HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit", "SleepAnalysisKit",
            ],
            resources: [.process("Resources")],
            swiftSettings: engineSwiftSettings
        ),
        // The Coach tab: the hub, the conversation, History and the privacy sheet. It reads
        // only `CoachViewModel`, which asks `AIService` (APP_RULES.md R20, R29).
        .target(
            name: "CoachFeature",
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "InsightsKit", "HomeFeature", "CoachKit"],
            swiftSettings: noctisSwiftSettings
        ),
        // The journal's model and store (APP_RULES.md R35): what a person chose to note about a day. Only
        // NightFeature (the Reflect screens) and AppRoot (the wiring) depend on it, so nothing that reads
        // sleep, recovery, insights, Coach or analytics can see it; a test holds the package to that.
        .target(
            name: "JournalKit",
            dependencies: ["NoctisCore"],
            swiftSettings: engineSwiftSettings
        ),
        // The Tonight screen: the bedtime window, why that time, the wake alarm.
        // It reads only `TonightViewModel` (APP_RULES.md R20, R30).
        .target(
            name: "NightFeature",
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "SleepAnalysisKit", "NightKit", "SoundKit", "HomeFeature", "JournalKit", "NoctisWidgetKit"],
            resources: [.process("Resources")],
            swiftSettings: noctisSwiftSettings
        ),
        // Profile (and, next to it, Settings): what the person told NOCTIS about their sleep, the status of Health,
        // notifications and the subscription, and every setting that works (APP_RULES.md R36). It edits the profile
        // and the preferences; it never reads Health samples beyond the one status check.
        .target(
            name: "ProfileFeature",
            dependencies: [
                "DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "SleepAnalysisKit", "NightKit", "SoundKit",
                "NightFeature", "HomeFeature", "OnboardingFeature",
            ],
            resources: [.process("Resources")],
            swiftSettings: noctisSwiftSettings
        ),
        .target(
            name: "AppRoot",
            dependencies: [
                "DesignSystem", "HealthProviding", "NoctisCore", "OnboardingFeature", "HomeFeature", "SleepFeature", "RecoveryFeature",
                "InsightsFeature", "CoachKit", "CoachFeature", "NightKit", "NightFeature", "SoundKit", "JournalKit", "ProfileFeature",
                "NoctisIntentKit", "NoctisWidgetKit",
            ],
            swiftSettings: noctisSwiftSettings
        ),
        .testTarget(
            name: "NoctisKitTests",
            dependencies: [
                "SleepKit", "RecoveryKit", "InsightsKit", "SleepAnalysisKit", "HealthProviding", "DesignSystem",
                "NoctisCore", "OnboardingFeature", "HomeFeature", "SleepFeature", "RecoveryFeature", "InsightsFeature", "CoachKit", "CoachFeature",
                "NightKit", "NightFeature", "AlarmShared", "SoundKit", "JournalKit", "ProfileFeature", "AppRoot", "NoctisWidgetKit", "NoctisIntentKit", "NoctisWatchKit",
                "BreathingKit", "PremiumKit", "ReviewKit",
            ],
            swiftSettings: noctisSwiftSettings
        ),
    ]
)
