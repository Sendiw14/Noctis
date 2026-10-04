import Foundation

/// The only links a widget carries (APP_RULES.md R44). Each is `noctis://<name>` and nothing more: no path, no query. The app's
/// `WidgetURLRouter` accepts exactly these and ignores every other URL.
public nonisolated enum WidgetLink: String, Sendable, CaseIterable, Equatable {
    case recovery
    case sleep
    case tonight
    case windDown = "wind-down"
    case bedtime

    /// The one URL scheme the app registers.
    public static let scheme = "noctis"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = rawValue
        return components.url ?? URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    /// The link a URL is, if it is exactly one of them: the scheme, one of the five hosts, no path, query, fragment, port or
    /// credentials. Anything else is nil.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              // The host as written, not as decoded: "%72ecovery" is not "recovery".
              let host = components.percentEncodedHost?.lowercased(),
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/",
              let link = WidgetLink(rawValue: host)
        else { return nil }
        self = link
    }
}
