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
    platforms: [.iOS(.v26)],
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
        .library(name: "SoundKit", targets: ["SoundKit"]),
        .library(name: "NightKit", targets: ["NightKit"]),
        .library(name: "NightFeature", targets: ["NightFeature"]),
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
        // Sleep sounds: synthesized in code, played through AVAudioEngine. No audio files, no UI.
        // Nonisolated like the other engines; the player alone is main-actor (APP_RULES.md R31).
        .target(name: "SoundKit", swiftSettings: engineSwiftSettings),
        // Tonight's bedtime recommendation, the alarm's state machine and the
        // service that wraps AlarmKit. No UI; nonisolated like the other engines.
        .target(
            name: "NightKit",
            dependencies: ["SleepKit", "RecoveryKit", "SleepAnalysisKit", "AlarmShared"],
            swiftSettings: engineSwiftSettings
        ),
        .target(
            name: "NoctisCore",
            dependencies: ["HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit", "SleepAnalysisKit", "NightKit", "DesignSystem"],
            swiftSettings: noctisSwiftSettings
        ),
        .target(name: "OnboardingFeature", dependencies: ["DesignSystem", "NoctisCore"], swiftSettings: noctisSwiftSettings),
        .target(
            name: "HomeFeature",
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit"],
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
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit", "HomeFeature"],
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
        // The Tonight screen: the bedtime window, why that time, the wake alarm.
        // It reads only `TonightViewModel` (APP_RULES.md R20, R30).
        .target(
            name: "NightFeature",
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "SleepAnalysisKit", "NightKit", "SoundKit", "HomeFeature"],
            resources: [.process("Resources")],
            swiftSettings: noctisSwiftSettings
        ),
        .target(
            name: "AppRoot",
            dependencies: [
                "DesignSystem", "HealthProviding", "NoctisCore", "OnboardingFeature", "HomeFeature", "SleepFeature", "RecoveryFeature",
                "InsightsFeature", "CoachKit", "CoachFeature", "NightKit", "NightFeature", "SoundKit",
            ],
            swiftSettings: noctisSwiftSettings
        ),
        .testTarget(
            name: "NoctisKitTests",
            dependencies: [
                "SleepKit", "RecoveryKit", "InsightsKit", "SleepAnalysisKit", "HealthProviding", "DesignSystem",
                "NoctisCore", "OnboardingFeature", "HomeFeature", "SleepFeature", "RecoveryFeature", "InsightsFeature", "CoachKit", "CoachFeature",
                "NightKit", "NightFeature", "AlarmShared", "SoundKit", "AppRoot",
            ],
            swiftSettings: noctisSwiftSettings
        ),
    ]
)
