import Foundation

/// Every main-app destination, so widgets and notifications can deep-link
/// (`noctis://recovery`) and the app can open one in code.
public nonisolated enum AppRoute: String, Sendable, CaseIterable, Hashable {
    case home
    case sleep
    case recovery
    case insights
    case coach
    case profile

    public static let urlScheme = "noctis"

    /// `noctis://<route>`; nil for any other scheme or an unknown route.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme,
              let host = url.host()?.lowercased(),
              let route = AppRoute(rawValue: host) else { return nil }
        self = route
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = rawValue
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// The tab that shows this route. Profile opens from Home's avatar
    /// button, so it lands on Home.
    public var tab: AppTab {
        switch self {
        case .home, .profile: .home
        case .sleep: .sleep
        case .recovery: .recovery
        case .insights: .insights
        case .coach: .coach
        }
    }
}
