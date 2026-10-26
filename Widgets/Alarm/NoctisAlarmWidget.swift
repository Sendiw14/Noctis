import ActivityKit
import AlarmKit
import AlarmShared
import SwiftUI
import WidgetKit

/// The alarm's own screen, for the one state the system leaves to the app: the countdown after
/// Snooze. AlarmKit hands this extension the alarm's state (`AlarmPresentationState`) and the
/// words NOCTIS gave it (`AlarmAttributes`); the extension only draws them. It starts nothing,
/// reads no data and has no network: it is a window onto an alarm the person set.
@main
struct NoctisAlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoctisAlarmLiveActivity()
    }
}

struct NoctisAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<NoctisAlarmMetadata>.self) { context in
            AlarmActivityView(attributes: context.attributes, state: context.state)
                .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm")
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    AlarmActivityView(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Image(systemName: "alarm").foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                AlarmCountdownText(state: context.state)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "alarm").foregroundStyle(context.attributes.tintColor)
            }
        }
    }
}

/// "Snoozed  8:42" while it counts down; the alarm's title when it rings.
struct AlarmActivityView: View {
    let attributes: AlarmAttributes<NoctisAlarmMetadata>
    let state: AlarmPresentationState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm")
                .font(.title2)
                .foregroundStyle(attributes.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                AlarmCountdownText(state: state)
                    .font(.title2.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
    }

    private var title: LocalizedStringResource {
        switch state.mode {
        case .countdown: attributes.presentation.countdown?.title ?? "Snoozed"
        case .paused: attributes.presentation.paused?.title ?? "Paused"
        case .alert: attributes.presentation.alert.title
        @unknown default: attributes.presentation.alert.title
        }
    }
}

/// The time left in a snooze, counting down by itself (the system redraws it every second).
struct AlarmCountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...max(countdown.fireDate, Date.now), countsDown: true)
                .monospacedDigit()
        case .paused, .alert:
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }
}
