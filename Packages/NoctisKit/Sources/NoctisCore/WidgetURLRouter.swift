import Foundation
import NoctisWidgetKit

/// The only way a URL from outside the app becomes a destination (APP_RULES.md R44). `noctis://` is registered with the system, so
/// any app, web page or message can open it; this accepts exactly the five links a widget carries and ignores everything else.
/// Nothing here starts anything: a link only opens a screen (the wind-down opens, it is never started from a URL).
public nonisolated enum WidgetURLRouter {
    /// The destination for `url`, or nil when it is not one of the widgets' links.
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
