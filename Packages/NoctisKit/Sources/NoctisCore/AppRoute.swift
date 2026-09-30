import Foundation
import InsightsKit
import RecoveryKit

/// Every main-app destination, so widgets and notifications can deep-link
/// (`noctis://recovery`) and the app can open one in code.
///
/// Sleep carries where in Sleep to land: `noctis://sleep?range=week&night=2026-09-28T23:04:00Z`.
/// Recovery carries a range and a factor: `noctis://recovery?range=30d&factor=hrv`.
/// Insights carries a chip: `noctis://insights?category=sleep`; one insight's
/// page is `noctis://insight?id=sleepDurationShift-3fa9c2d1`.
public nonisolated enum AppRoute: Sendable, Hashable {
    case home
    /// Sleep on `range`, ending on the night that contains `night` (any
    /// moment of it: its bedtime, its waking, or noon of its evening); the
    /// newest night when nil.
    case sleep(night: Date? = nil, range: SleepRange = .day)
    /// Recovery on `range` (Today, 7D, 30D or 90D); with a `factor`, that
    /// factor's page over the matching number of nights (14 for Today and
    /// 7D, then 30 and 90).
    case recovery(range: RecoverySegment = .today, factor: RecoveryFactorKind? = nil)
    /// Insights on a chip (All when nil).
    case insights(category: InsightCategory? = nil)
    /// One insight's page over the Insights tab.
    case insight(id: String)
    case coach
    case profile

    public static let urlScheme = "noctis"

    /// Every destination, Sleep on its newest night.
    public static let destinations: [AppRoute] = [.home, .sleep(), .recovery(), .insights(), .coach, .profile]

    /// "home", "sleep", "recovery"…: the URL's host.
    public var name: String {
        switch self {
        case .home: "home"
        case .sleep: "sleep"
        case .recovery: "recovery"
        case .insights: "insights"
        case .insight: "insight"
        case .coach: "coach"
        case .profile: "profile"
        }
    }

    /// A route by its name. Sleep and Recovery also take their range after
    /// a colon ("sleep:week", "recovery:30d"), for launch arguments.
    public init?(name: String) {
        let parts = name.lowercased().split(separator: ":", maxSplits: 1).map(String.init)
        // An insight's id keeps its case ("bedtimeShift-3fa9c2d1").
        let argument = name.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
        switch parts.first {
        case "home": self = .home
        case "sleep": self = .sleep(night: nil, range: parts.dropFirst().first.flatMap(SleepRange.init(rawValue:)) ?? .day)
        case "recovery": self = .recovery(range: parts.dropFirst().first.flatMap(RecoverySegment.init(token:)) ?? .today, factor: nil)
        case "insights": self = .insights(category: parts.dropFirst().first.flatMap(Self.category(named:)))
        case "insight":
            guard let argument, Self.isInsightID(argument) else { return nil }
            self = .insight(id: argument)
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
        guard url.scheme?.lowercased() == Self.urlScheme, let host = url.host()?.lowercased() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if host == "insight" {
            // An id is the type and a hash of the evidence: "bedtimeShift-3fa9c2d1". Anything else is no insight.
            guard let id = value("id"), Self.isInsightID(id) else { return nil }
            self = .insight(id: id)
            return
        }
        guard let route = AppRoute(name: host) else { return nil }
        switch route {
        case .sleep:
            let range = value("range").flatMap { SleepRange(rawValue: $0.lowercased()) } ?? .day
            self = .sleep(night: value("night").flatMap(Self.parseNight), range: range)
        case .recovery:
            let range = value("range").flatMap(RecoverySegment.init(token:)) ?? .today
            let factor = value("factor").flatMap { text in RecoveryFactorKind.allCases.first { $0.rawValue.lowercased() == text.lowercased() } }
            self = .recovery(range: range, factor: factor)
        case .insights:
            self = .insights(category: value("category").flatMap(Self.category(named:)))
        default:
            self = route
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = name
        var items: [URLQueryItem] = []
        switch self {
        case .sleep(let night, let range):
            if range != .day { items.append(URLQueryItem(name: "range", value: range.rawValue)) }
            if let night { items.append(URLQueryItem(name: "night", value: night.formatted(.iso8601))) }
        case .recovery(let range, let factor):
            if range != .today { items.append(URLQueryItem(name: "range", value: range.token)) }
            if let factor { items.append(URLQueryItem(name: "factor", value: factor.rawValue)) }
        case .insights(let category):
            if let category { items.append(URLQueryItem(name: "category", value: category.rawValue)) }
        case .insight(let id):
            items.append(URLQueryItem(name: "id", value: id))
        default:
            break
        }
        if !items.isEmpty { components.queryItems = items }
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// The tab that shows this route. Profile opens from Home's avatar
    /// button, so it lands on Home.
    public var tab: AppTab {
        switch self {
        case .home, .profile: .home
        case .sleep: .sleep
        case .recovery: .recovery
        case .insights, .insight: .insights
        case .coach: .coach
        }
    }

    /// A chip by its name ("sleep", "longTerm", "long-term"), case aside.
    static func category(named name: String) -> InsightCategory? {
        let key = name.lowercased().replacingOccurrences(of: "-", with: "")
        return InsightCategory.allCases.first { $0.rawValue.lowercased() == key }
    }

    /// "bedtimeShift-3fa9c2d1": a known type, a dash and 8 hex digits.
    static func isInsightID(_ id: String) -> Bool {
        let parts = id.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, InsightType(rawValue: parts[0]) != nil, parts[1].count == 8 else { return false }
        return parts[1].allSatisfy { $0.isHexDigit }
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
