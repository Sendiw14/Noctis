import SwiftUI
import WidgetKit

/// The Watch's complications (APP_RULES.md R50, part 2 of the Watch work). Empty for now: the target exists, links the widget kit and the App Group, and
/// offers nothing. Like the Watch app it reads no Health: it will draw the snapshot the iPhone sent and nothing else.
@main
struct NOCTISWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NOCTISWatchPlaceholder()
    }
}

/// A widget that is not offered (no families), so the extension has something to build and nothing to show.
struct NOCTISWatchPlaceholder: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NOCTISWatchPlaceholder", provider: PlaceholderProvider()) { _ in
            EmptyView()
        }
        .configurationDisplayName("NOCTIS")
        .description("Coming soon.")
        .supportedFamilies([])
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}
