import Foundation

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

    public var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .sleep: "moon.stars.fill"
        case .recovery: "heart.fill"
        case .insights: "lightbulb.fill"
        case .coach: "sparkles"
        }
    }
}
