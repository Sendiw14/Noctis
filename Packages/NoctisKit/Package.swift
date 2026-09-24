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
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "HealthProviding", targets: ["HealthProviding"]),
        .library(name: "SleepKit", targets: ["SleepKit"]),
        .library(name: "RecoveryKit", targets: ["RecoveryKit"]),
        .library(name: "InsightsKit", targets: ["InsightsKit"]),
        .library(name: "NoctisCore", targets: ["NoctisCore"]),
        .library(name: "OnboardingFeature", targets: ["OnboardingFeature"]),
        .library(name: "HomeFeature", targets: ["HomeFeature"]),
        .library(name: "AppRoot", targets: ["AppRoot"]),
    ],
    targets: [
        .target(name: "DesignSystem", swiftSettings: noctisSwiftSettings),
        .target(name: "HealthProviding", swiftSettings: noctisSwiftSettings),
        .target(name: "SleepKit", dependencies: ["HealthProviding"], swiftSettings: engineSwiftSettings),
        .target(name: "RecoveryKit", dependencies: ["HealthProviding", "SleepKit"], swiftSettings: engineSwiftSettings),
        .target(name: "InsightsKit", dependencies: ["SleepKit", "RecoveryKit"], swiftSettings: engineSwiftSettings),
        .target(
            name: "NoctisCore",
            dependencies: ["HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit", "DesignSystem"],
            swiftSettings: noctisSwiftSettings
        ),
        .target(name: "OnboardingFeature", dependencies: ["DesignSystem", "NoctisCore"], swiftSettings: noctisSwiftSettings),
        .target(
            name: "HomeFeature",
            dependencies: ["DesignSystem", "NoctisCore", "HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit"],
            swiftSettings: noctisSwiftSettings
        ),
        .target(
            name: "AppRoot",
            dependencies: ["DesignSystem", "HealthProviding", "NoctisCore", "OnboardingFeature", "HomeFeature"],
            swiftSettings: noctisSwiftSettings
        ),
        .testTarget(
            name: "NoctisKitTests",
            dependencies: [
                "SleepKit", "RecoveryKit", "InsightsKit", "HealthProviding", "DesignSystem",
                "NoctisCore", "OnboardingFeature", "HomeFeature", "AppRoot",
            ],
            swiftSettings: noctisSwiftSettings
        ),
    ]
)
