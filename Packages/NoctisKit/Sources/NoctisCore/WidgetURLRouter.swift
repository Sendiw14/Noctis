import Foundation
import NoctisWidgetKit
import PremiumKit

/// The only way a URL from outside the app becomes a destination (APP_RULES.md R44). `noctis://` is registered with the system, so
/// any app, web page or message can open it; this accepts exactly the five links a widget carries and ignores everything else.
/// Nothing here starts anything: a link only opens a screen (the wind-down opens, it is never started from a URL). The one other thing a link can do is open the paywall
/// sheet (`noctis://premium`, R62), which only shows what Premium includes.
public nonisolated enum WidgetURLRouter {
    /// What an outside URL opens: a screen, or the paywall sheet naming a context.
    public enum Destination: Equatable, Sendable {
        case screen(AppRoute)
        case paywall(PaywallContext)
    }

    /// What `url` opens, or nil when it is not exactly one of the links NOCTIS itself makes.
    public static func destination(for url: URL) -> Destination? {
        if let link = PremiumLink(url: url) { return .paywall(link.context) }
        return route(for: url).map(Destination.screen)
    }

    /// The screen for `url`, or nil when it is not one of the five screen links (the paywall link is a `destination`, not a route).
    public static func route(for url: URL) -> AppRoute? {
        guard let link = WidgetLink(url: url) else { return nil }
        return route(for: link)
    }

    public static func route(for link: WidgetLink) -> AppRoute {
        switch link {
        case .recovery: .recovery()
        case .sleep: .sleep()
        // Tonight is where the bedtime is explained and the alarm set.
        case .tonight, .bedtime: .tonight
        case .windDown: .windDown(autostart: false)
        }
    }
}
