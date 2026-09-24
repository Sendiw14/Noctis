import Foundation

/// The main app's tabs (APP_RULES.md R7), in tab-bar order.
public enum AppTab: String, Sendable, CaseIterable, Identifiable {
    case home
    case sleep
    case recovery
    case insights
    case coach

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .sleep: "Sleep"
        case .recovery: "Recovery"
        case .insights: "Insights"
        case .coach: "Coach"
        }
    }

    /// The tab bar fills these automatically when selected.
    public var systemImage: String {
        switch self {
        case .home: "house"
        case .sleep: "moon.zzz"
        case .recovery: "heart"
        case .insights: "lightbulb"
        case .coach: "sparkles"
        }
    }
}
