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
        .library(name: "AppRoot", targets: ["AppRoot"]),
    ],
    targets: [
        .target(name: "DesignSystem", swiftSettings: noctisSwiftSettings),
        .target(name: "HealthProviding", swiftSettings: noctisSwiftSettings),
        .target(name: "SleepKit", dependencies: ["HealthProviding"], swiftSettings: engineSwiftSettings),
        .target(name: "RecoveryKit", dependencies: ["HealthProviding", "SleepKit"], swiftSettings: engineSwiftSettings),
        .target(name: "InsightsKit", dependencies: ["SleepKit", "RecoveryKit", "SleepAnalysisKit"], swiftSettings: engineSwiftSettings),
        .target(name: "SleepAnalysisKit", dependencies: ["HealthProviding", "SleepKit", "RecoveryKit"], swiftSettings: engineSwiftSettings),
        .target(
            name: "NoctisCore",
            dependencies: ["HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit", "SleepAnalysisKit", "DesignSystem"],
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
            name: "AppRoot",
            dependencies: ["DesignSystem", "HealthProviding", "NoctisCore", "OnboardingFeature", "HomeFeature", "SleepFeature", "RecoveryFeature"],
            swiftSettings: noctisSwiftSettings
        ),
        .testTarget(
            name: "NoctisKitTests",
            dependencies: [
                "SleepKit", "RecoveryKit", "InsightsKit", "SleepAnalysisKit", "HealthProviding", "DesignSystem",
                "NoctisCore", "OnboardingFeature", "HomeFeature", "SleepFeature", "RecoveryFeature", "AppRoot",
            ],
            swiftSettings: noctisSwiftSettings
        ),
    ]
)
