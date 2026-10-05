import ActivityKit
import AppIntents
import NoctisIntentKit
import NoctisWidgetKit
import SwiftUI
import WidgetKit

/// The wind-down's Live Activity (APP_RULES.md R49): the Lock Screen presentation and the Dynamic Island's compact, minimal and expanded ones.
/// The extension only composes the views `NoctisWidgetKit` draws and gives the End button its intent; the countdown ticks by itself
/// (`Text(timerInterval:)`), so nothing here is told the time. The app starts, updates and ends the activity; the extension decides nothing.
struct NoctisWindDownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WindDownActivityAttributes.self) { context in
            WindDownActivityContent(context: context) { endButton }
                .activityBackgroundTint(WindDownActivityStyle.background)
                .activitySystemActionForegroundColor(WindDownActivityStyle.foreground)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 2) {
                    WindDownIslandExpandedLeading(attributes: context.attributes, state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.trailing, priority: 1) {
                    WindDownIslandExpandedTrailing(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WindDownIslandExpandedBottom(state: context.state, isStale: context.isStale) { endButton }
                }
            } compactLeading: {
                WindDownIslandCompactLeading()
            } compactTrailing: {
                WindDownIslandCompactTrailing(state: context.state, isStale: context.isStale)
            } minimal: {
                WindDownIslandMinimal()
            }
            .keylineTint(WindDownActivityStyle.tint)
        }
        // The Apple Watch's Smart Stack shows the activity from the paired iPhone; `.small` is the presentation made for it (R56).
        .supplementalActivityFamilies([.small])
    }

    /// End: a button on the activity that runs `EndWindDownIntent` in the app.
    private var endButton: some View {
        Button(intent: EndWindDownIntent()) { WindDownEndLabel() }
            .buttonStyle(.plain)
    }
}

/// The Lock Screen's presentation, or the Apple Watch's small one when the system asks for that family.
struct WindDownActivityContent<End: View>: View {
    let context: ActivityViewContext<WindDownActivityAttributes>
    let end: End
    @Environment(\.activityFamily) private var family

    init(context: ActivityViewContext<WindDownActivityAttributes>, @ViewBuilder end: () -> End) {
        self.context = context
        self.end = end()
    }

    var body: some View {
        switch family {
        case .small:
            WindDownWatchView(state: context.state, isStale: context.isStale)
        default:
            WindDownLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale) { end }
        }
    }
}
