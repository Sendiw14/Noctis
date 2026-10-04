import NoctisWidgetKit
import RelevanceKit
import SwiftUI
import WidgetKit

/// NOCTIS's widgets (APP_RULES.md R44, R45): one Home Screen widget and one Lock Screen widget, and its two controls (R48, in
/// `NoctisControls.swift`). The widgets read ONLY the `WidgetSnapshot` file the
/// app writes into the App Group: no HealthKit, no SwiftData, no Coach, no network. Not configurable in this pass.
@main
struct NoctisWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NoctisTodayWidget()
        NoctisLockWidget()
        NoctisWindDownControl()
        NoctisSleepSoundsControl()
    }
}

// MARK: - Timeline

/// One entry of either widget's timeline: the resolved model, with its Smart Stack relevance.
struct NoctisEntry: TimelineEntry {
    let model: WidgetEntryModel

    var date: Date { model.date }

    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: model.relevance.score, duration: model.relevance.duration)
    }
}

/// Builds both widgets' timelines from the snapshot file, with `WidgetTimelineBuilder` (pure, and tested there).
struct NoctisTimelineProvider: TimelineProvider {
    private var calendar: Calendar { .autoupdatingCurrent }

    /// What the system draws while the widget loads, and in the gallery before it is added: sample numbers, tagged as such (R13).
    func placeholder(in context: Context) -> NoctisEntry {
        NoctisEntry(model: sample(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NoctisEntry) -> Void) {
        if context.isPreview {
            completion(NoctisEntry(model: sample(at: .now)))
            return
        }
        let plan = WidgetTimelineBuilder.build(snapshot: WidgetSnapshotStore()?.load(), now: .now, calendar: calendar)
        completion(NoctisEntry(model: plan.entries[0]))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NoctisEntry>) -> Void) {
        let plan = WidgetTimelineBuilder.build(snapshot: WidgetSnapshotStore()?.load(), now: .now, calendar: calendar)
        completion(Timeline(entries: plan.entries.map(NoctisEntry.init(model:)), policy: .after(plan.reloadAfter)))
    }

    /// For the Smart Stack: the morning (the system's own wake-up) and the evening (its bedtime), and the windows around the usual
    /// wake time and bedtime from the snapshot. `RelevantContext` is in RelevanceKit; `RelevanceConfiguration` is watchOS only.
    func relevance() async -> WidgetRelevance<Void> {
        var attributes = [
            WidgetRelevanceAttribute(context: RelevantContext.sleep(.wakeup)),
            WidgetRelevanceAttribute(context: RelevantContext.sleep(.bedtime)),
        ]
        if let snapshot = WidgetSnapshotStore()?.load() {
            for window in WidgetClock.relevanceWindows(snapshot.plan, from: .now, calendar: calendar) {
                attributes.append(WidgetRelevanceAttribute(context: RelevantContext.date(interval: window, kind: .default)))
            }
        }
        return WidgetRelevance(attributes)
    }

    /// The gallery shows the morning face (the recovery ring), whatever time it is: it is the widget's main face, and the "Sample" tag
    /// has a free corner there.
    private func sample(at date: Date) -> WidgetEntryModel {
        let morning = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date
        return WidgetTimelineBuilder.previewEntry(WidgetSamples.snapshot(.full, now: morning, calendar: calendar), at: morning, calendar: calendar)
    }
}

// MARK: - Widgets

struct NoctisTodayWidget: Widget {
    static let kind = "NoctisToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NoctisTimelineProvider()) { entry in
            NoctisTodayEntryView(entry: entry)
        }
        .configurationDisplayName("NOCTIS Today")
        .description("Your recovery in the morning and tonight's bedtime in the evening.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NoctisTodayEntryView: View {
    let entry: NoctisEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NoctisTodayWidgetView(entry: entry.model, family: family)
            .containerBackground(for: .widget) { WidgetBackground(mode: entry.model.mode) }
    }
}

struct NoctisLockWidget: Widget {
    static let kind = "NoctisLock"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NoctisTimelineProvider()) { entry in
            NoctisLockEntryView(entry: entry)
        }
        .configurationDisplayName("NOCTIS Lock Screen")
        .description("Recovery and bedtime on your Lock Screen. Health numbers stay hidden until you unlock.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NoctisLockEntryView: View {
    let entry: NoctisEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NoctisLockWidgetView(entry: entry.model, family: family)
            .containerBackground(for: .widget) {
                if family == .accessoryInline { Color.clear } else { AccessoryWidgetBackground() }
            }
    }
}
