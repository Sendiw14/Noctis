import Foundation

/// Every main-app destination, so widgets and notifications can deep-link
/// (`noctis://recovery`) and the app can open one in code.
///
/// Sleep carries where in Sleep to land: `noctis://sleep?range=week&night=2026-09-28T23:04:00Z`.
public nonisolated enum AppRoute: Sendable, Hashable {
    case home
    /// Sleep on `range`, ending on the night that contains `night` (any
    /// moment of it: its bedtime, its waking, or noon of its evening); the
    /// newest night when nil.
    case sleep(night: Date? = nil, range: SleepRange = .day)
    case recovery
    case insights
    case coach
    case profile

    public static let urlScheme = "noctis"

    /// Every destination, Sleep on its newest night.
    public static let destinations: [AppRoute] = [.home, .sleep(), .recovery, .insights, .coach, .profile]

    /// "home", "sleep", "recovery"…: the URL's host.
    public var name: String {
        switch self {
        case .home: "home"
        case .sleep: "sleep"
        case .recovery: "recovery"
        case .insights: "insights"
        case .coach: "coach"
        case .profile: "profile"
        }
    }

    /// A route by its name. Sleep also takes its range after a colon
    /// ("sleep:week"), for launch arguments.
    public init?(name: String) {
        let parts = name.lowercased().split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "home": self = .home
        case "sleep": self = .sleep(night: nil, range: parts.dropFirst().first.flatMap(SleepRange.init(rawValue:)) ?? .day)
        case "recovery": self = .recovery
        case "insights": self = .insights
        case "coach": self = .coach
        case "profile": self = .profile
        default: return nil
        }
    }

    /// `noctis://<route>`; nil for any other scheme or an unknown route. A
    /// Sleep URL may carry `range` (day, week, month) and `night` (an
    /// ISO 8601 date and time, or a plain date for that evening's night);
    /// anything it can't read is left out, and Sleep opens on its newest
    /// night.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme,
              let host = url.host()?.lowercased(),
              let route = AppRoute(name: host) else { return nil }
        guard case .sleep = route else {
            self = route
            return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let range = items.first { $0.name == "range" }?.value.flatMap { SleepRange(rawValue: $0.lowercased()) } ?? .day
        let night = items.first { $0.name == "night" }?.value.flatMap(Self.parseNight)
        self = .sleep(night: night, range: range)
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = name
        if case .sleep(let night, let range) = self {
            var items: [URLQueryItem] = []
            if range != .day { items.append(URLQueryItem(name: "range", value: range.rawValue)) }
            if let night { items.append(URLQueryItem(name: "night", value: night.formatted(.iso8601))) }
            if !items.isEmpty { components.queryItems = items }
        }
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

    /// "2026-09-28T23:04:00Z", or "2026-09-28" (noon that day, on the
    /// current calendar: the night that evening starts).
    private static func parseNight(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
