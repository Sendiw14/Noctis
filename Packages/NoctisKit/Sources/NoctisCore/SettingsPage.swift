import Foundation

/// The pages of Settings, pushed over Home's stack: the list itself, and one page for each thing in it that
/// has more to say than a row can. A status row on Profile, a gear, and a state on another screen that has
/// somewhere to send the person ("Notifications are off", "No Health data") all land on one of these.
public nonisolated enum SettingsPage: String, Sendable, Hashable, CaseIterable, Codable {
    /// The grouped list.
    case root
    case notifications
    case healthData = "health-data"
    case appearance
    case subscription
    case windDown = "wind-down"
    case sounds
    case help
    case about
    case privacyCenter = "privacy-center"
    case dataManagement = "data-management"
    case appleWatch = "apple-watch"

    /// The page's name in a URL or a launch argument: `noctis://settings?section=notifications`.
    public var token: String { rawValue }

    public init?(token: String) {
        let key = token.lowercased().replacingOccurrences(of: "_", with: "-")
        guard let page = Self.allCases.first(where: { $0.rawValue == key || $0.rawValue.replacingOccurrences(of: "-", with: "") == key }) else { return nil }
        self = page
    }

    /// The page's title, the navigation bar's and the accessibility label's.
    public var title: String {
        switch self {
        case .root: "Settings"
        case .notifications: "Notifications"
        case .healthData: "Health data"
        case .appearance: "Appearance"
        case .subscription: "Subscription"
        case .windDown: "Wind-down"
        case .sounds: "Sleep sounds"
        case .help: "Help"
        case .about: "About"
        case .privacyCenter: "Privacy Center"
        case .dataManagement: "Data management"
        case .appleWatch: "Apple Watch"
        }
    }
}

/// One change to what the person told NOCTIS about themselves (their name, their sleep need, their wake time,
/// their goals), applied to the profile in one place so every editor says the same thing.
public nonisolated enum ProfileEdit: Sendable, Equatable {
    /// The longest name kept.
    public static let nameLimit = 40
    /// How many goals can be chosen.
    public static let goalLimit = 2

    case name(String)
    case need(minutes: Int)
    case wake(minutes: Int)
    case goals([PrimaryGoal])

    public func apply(to profile: inout UserProfileSnapshot) {
        switch self {
        case .name(let text):
            profile.name = Self.cleaned(name: text)
        case .need(let minutes):
            profile.needMinutes = minutes
            profile.sleepGoalHours = Double(minutes) / 60
        case .wake(let minutes):
            profile.typicalWakeMinutes = minutes
        case .goals(let goals):
            let kept = Self.limited(goals)
            profile.selectedGoals = kept
            profile.primaryGoal = kept.first ?? .betterSleep
            profile.secondaryGoal = kept.count > 1 ? kept[1] : nil
        }
    }

    /// Trimmed, on one line, and no longer than the limit. Empty means no name.
    public static func cleaned(name: String) -> String {
        let oneLine = name.split(whereSeparator: \.isNewline).joined(separator: " ")
        return String(oneLine.trimmingCharacters(in: .whitespaces).prefix(nameLimit)).trimmingCharacters(in: .whitespaces)
    }

    /// At most two goals, without repeats, the earliest chosen kept.
    public static func limited(_ goals: [PrimaryGoal]) -> [PrimaryGoal] {
        var seen: [PrimaryGoal] = []
        for goal in goals where !seen.contains(goal) { seen.append(goal) }
        return Array(seen.prefix(goalLimit))
    }

    /// A tap on `goal` in the goals editor: off if it was chosen; on otherwise, where a third replaces the
    /// oldest (onboarding's rule).
    public static func toggled(_ goal: PrimaryGoal, in goals: [PrimaryGoal]) -> [PrimaryGoal] {
        if let index = goals.firstIndex(of: goal) {
            var next = goals
            next.remove(at: index)
            return next
        }
        var next = goals
        if next.count >= goalLimit { next.removeFirst() }
        next.append(goal)
        return next
    }
}
