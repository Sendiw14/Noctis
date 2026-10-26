import NoctisWatchKit
import NoctisWidgetKit
import RelevanceKit
import SwiftUI
import WidgetKit

/// The Watch's complications (APP_RULES.md R50, R51, R54): four kinds, each in the circular, rectangular, inline and corner families. Like the Watch app
/// they read ONLY the summary the iPhone sent (`WatchInbox`, in the App Group's container on the Watch): no Health, no engine, no network. The words and
/// numbers are `WatchComplications`'; this file asks the system for them at the right moments.
@main
struct NOCTISWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NoctisRecoveryWatchWidget()
        NoctisSleepWatchWidget()
        NoctisBedtimeWatchWidget()
        NoctisQualityWatchWidget()
    }
}

// MARK: - Timeline

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let kind: WatchComplicationKind
    let snapshot: WidgetSnapshot?
    let score: WidgetRelevanceScore

    var relevance: TimelineEntryRelevance? { TimelineEntryRelevance(score: score.score, duration: score.duration) }
}

/// One provider for the four kinds: the same summary, the same moments of change, each kind's own relevance.
struct WatchComplicationProvider: TimelineProvider {
    let kind: WatchComplicationKind

    private var calendar: Calendar { .autoupdatingCurrent }

    /// What the Watch holds, or nothing: the complications never draw a number that is not the person's (R13). Before the first summary arrives they say
    /// "Open NOCTIS on your iPhone".
    private func held() -> WidgetSnapshot? { WatchInbox()?.load()?.snapshot }

    private func entry(at date: Date, snapshot: WidgetSnapshot?) -> WatchComplicationEntry {
        WatchComplicationEntry(
            date: date, kind: kind, snapshot: snapshot, score: WatchComplicationSchedule.relevance(kind, at: date, snapshot: snapshot, calendar: calendar)
        )
    }

    func placeholder(in context: Context) -> WatchComplicationEntry { entry(at: .now, snapshot: held()) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchComplicationEntry) -> Void) {
        completion(entry(at: .now, snapshot: held()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchComplicationEntry>) -> Void) {
        let snapshot = held()
        let plan = WatchComplicationSchedule.dates(snapshot: snapshot, now: .now, calendar: calendar)
        let entries = plan.entries.map { entry(at: $0.date, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(plan.reloadAfter)))
    }

    /// For the Smart Stack: the system's own wake-up for the morning kinds and its bedtime for Bedtime, and the window around the person's usual wake time
    /// or bedtime from the summary. `RelevantContext` is in RelevanceKit.
    func relevance() async -> WidgetRelevance<Void> {
        var attributes = [WidgetRelevanceAttribute(context: RelevantContext.sleep(kind == .bedtime ? .bedtime : .wakeup))]
        if let window = WatchComplicationSchedule.window(kind, snapshot: held(), from: .now, calendar: calendar) {
            attributes.append(WidgetRelevanceAttribute(context: RelevantContext.date(interval: window, kind: .default)))
        }
        return WidgetRelevance(attributes)
    }
}

// MARK: - View

struct WatchComplicationEntryView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var widgetFamily

    private var family: WatchComplicationFamily {
        switch widgetFamily {
        case .accessoryCircular: .circular
        case .accessoryRectangular: .rectangular
        case .accessoryCorner: .corner
        default: .inline
        }
    }

    var body: some View {
        let content = WatchComplications.content(entry.kind, input: WatchPageInput(snapshot: entry.snapshot, now: entry.date))
        WatchComplicationView(content: content, family: family)
            .widgetURL(content.link.url)
            .containerBackground(for: .widget) {
                switch family {
                case .circular, .rectangular: AccessoryWidgetBackground()
                case .inline, .corner: Color.clear
                }
            }
    }
}

// MARK: - Widgets

private let allFamilies: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]

struct NoctisRecoveryWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationKind.recovery.rawValue, provider: WatchComplicationProvider(kind: .recovery)) {
            WatchComplicationEntryView(entry: $0)
        }
        .configurationDisplayName(WatchComplicationKind.recovery.displayName)
        .description(WatchComplicationKind.recovery.summary)
        .supportedFamilies(allFamilies)
    }
}

struct NoctisSleepWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationKind.sleep.rawValue, provider: WatchComplicationProvider(kind: .sleep)) {
            WatchComplicationEntryView(entry: $0)
        }
        .configurationDisplayName(WatchComplicationKind.sleep.displayName)
        .description(WatchComplicationKind.sleep.summary)
        .supportedFamilies(allFamilies)
    }
}

struct NoctisBedtimeWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationKind.bedtime.rawValue, provider: WatchComplicationProvider(kind: .bedtime)) {
            WatchComplicationEntryView(entry: $0)
        }
        .configurationDisplayName(WatchComplicationKind.bedtime.displayName)
        .description(WatchComplicationKind.bedtime.summary)
        .supportedFamilies(allFamilies)
    }
}

struct NoctisQualityWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationKind.quality.rawValue, provider: WatchComplicationProvider(kind: .quality)) {
            WatchComplicationEntryView(entry: $0)
        }
        .configurationDisplayName(WatchComplicationKind.quality.displayName)
        .description(WatchComplicationKind.quality.summary)
        .supportedFamilies(allFamilies)
    }
}
