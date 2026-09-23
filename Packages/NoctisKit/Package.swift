// swift-tools-version: 6.2
import PackageDescription

let noctisSwiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
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
        .library(name: "SleepFeature", targets: ["SleepFeature"]),
        .library(name: "RecoveryFeature", targets: ["RecoveryFeature"]),
        .library(name: "InsightsFeature", targets: ["InsightsFeature"]),
        .library(name: "CoachFeature", targets: ["CoachFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
        .library(name: "AppRoot", targets: ["AppRoot"]),
    ],
    targets: [
        .target(name: "DesignSystem", swiftSettings: noctisSwiftSettings),
        .target(name: "HealthProviding", swiftSettings: noctisSwiftSettings),
        .target(name: "SleepKit", dependencies: ["HealthProviding"], swiftSettings: noctisSwiftSettings),
        .target(name: "RecoveryKit", dependencies: ["HealthProviding", "SleepKit"], swiftSettings: noctisSwiftSettings),
        .target(name: "InsightsKit", dependencies: ["SleepKit", "RecoveryKit"], swiftSettings: noctisSwiftSettings),
        .target(
            name: "NoctisCore",
            dependencies: ["HealthProviding", "SleepKit", "RecoveryKit", "InsightsKit", "DesignSystem"],
            swiftSettings: noctisSwiftSettings
        ),
        .target(name: "OnboardingFeature", dependencies: ["DesignSystem", "NoctisCore"], swiftSettings: noctisSwiftSettings),
        .target(name: "SettingsFeature", dependencies: ["DesignSystem", "NoctisCore", "HealthProviding"], swiftSettings: noctisSwiftSettings),
        .target(
            name: "HomeFeature",
            dependencies: ["DesignSystem", "NoctisCore", "SettingsFeature", "SleepKit", "RecoveryKit", "InsightsKit"],
            swiftSettings: noctisSwiftSettings
        ),
        .target(name: "SleepFeature", dependencies: ["DesignSystem", "NoctisCore", "SleepKit", "HealthProviding"], swiftSettings: noctisSwiftSettings),
        .target(name: "RecoveryFeature", dependencies: ["DesignSystem", "NoctisCore", "RecoveryKit", "InsightsKit"], swiftSettings: noctisSwiftSettings),
        .target(name: "InsightsFeature", dependencies: ["DesignSystem", "NoctisCore", "InsightsKit"], swiftSettings: noctisSwiftSettings),
        .target(name: "CoachFeature", dependencies: ["DesignSystem", "NoctisCore"], swiftSettings: noctisSwiftSettings),
        .target(
            name: "AppRoot",
            dependencies: [
                "DesignSystem", "NoctisCore",
                "OnboardingFeature", "HomeFeature", "SleepFeature",
                "RecoveryFeature", "InsightsFeature", "CoachFeature", "SettingsFeature",
            ],
            swiftSettings: noctisSwiftSettings
        ),
        .testTarget(
            name: "NoctisKitTests",
            dependencies: ["SleepKit", "RecoveryKit", "InsightsKit", "HealthProviding", "DesignSystem", "NoctisCore", "OnboardingFeature"],
            swiftSettings: noctisSwiftSettings
        ),
    ]
)
