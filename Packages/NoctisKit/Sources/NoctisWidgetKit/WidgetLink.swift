import Foundation
import PremiumKit

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

/// The one link that opens the paywall from outside the app (APP_RULES.md R62): `noctis://premium`, or `noctis://premium?context=<name>` where the name is one of a short
/// whitelist of paywall contexts. Nothing else is accepted: no other query item, no repeated or empty or percent-encoded value, no path, fragment, port or credentials.
/// Opening it only ever opens the paywall sheet (and only for a person who is not Premium, after onboarding); it never buys, starts or changes anything.
public nonisolated struct PremiumLink: Equatable, Sendable {
    public static let host = "premium"
    /// The contexts a surface outside the app may name: widgets, the Watch, Siri, the wind-down, the sounds and Coach's questions, and the general one.
    public static let allowedContexts: [PaywallContext] = [.general, .widgets, .watch, .siri, .windDown, .sounds, .coachQuestions]

    public let context: PaywallContext

    /// A context that is not on the whitelist is the general one.
    public init(context: PaywallContext) {
        self.context = Self.allowedContexts.contains(context) ? context : .general
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = WidgetLink.scheme
        components.host = Self.host
        if context != .general { components.queryItems = [URLQueryItem(name: "context", value: context.rawValue)] }
        return components.url ?? URL(string: "\(WidgetLink.scheme)://\(Self.host)")!
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == WidgetLink.scheme,
              components.percentEncodedHost?.lowercased() == Self.host,
              components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/"
        else { return nil }
        // No query is the general context; the only query is exactly `context=<a whitelisted name>`, as written.
        guard let query = components.percentEncodedQuery else {
            self.init(context: .general)
            return
        }
        let pair = query.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard pair.count == 2, pair[0] == "context",
              let context = Self.allowedContexts.first(where: { $0.rawValue == pair[1] }), context != .general
        else { return nil }
        self.init(context: context)
    }
}
