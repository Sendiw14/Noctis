import DesignSystem
import SwiftUI

// The wind-down Live Activity's presentations (APP_RULES.md R49): the Lock Screen and the Dynamic Island's compact, minimal and expanded
// forms. Flat fills, the night palette the wind-down screen uses, `noctisFont` text that scales with Dynamic Type, no text under 12pt, and
// a 44pt End button. They draw a `ContentState` and decide nothing; the extension puts them in an `ActivityConfiguration` and gives the End
// button its intent (the kit cannot name the intent: it is the other way round), and the debug gallery draws the same views with a plain label.


/// The countdown: "14:32", frozen while paused. The system keeps it ticking with no help from the app.
public struct WindDownTimerText: View {
    let state: WindDownActivityAttributes.ContentState

    public init(state: WindDownActivityAttributes.ContentState) {
        self.state = state
    }

    public var body: some View {
        Text(timerInterval: state.windowStart...state.windowEnd, pauseTime: state.pausedAt, countsDown: true, showsHours: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/// How far through the session it is: moving by itself while it runs, standing still while paused.
public struct WindDownActivityProgress: View {
    let state: WindDownActivityAttributes.ContentState

    public init(state: WindDownActivityAttributes.ContentState) {
        self.state = state
    }

    public var body: some View {
        Group {
            if state.phase == .running {
                ProgressView(timerInterval: state.windowStart...state.windowEnd, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: state.progress(at: state.pausedAt ?? state.windowEnd))
            }
        }
        .progressViewStyle(.linear)
        .tint(NoctisNight.lavender)
        .accessibilityHidden(true)
    }
}

/// The End button's face: a flat capsule at least 44pt tall. The extension wraps it in a `Button(intent:)`.
public struct WindDownEndLabel: View {
    public init() {}

    public var body: some View {
        Text(WindDownActivityCopy.end)
            .noctisFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(NoctisNight.ivory)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule(style: .continuous).fill(NoctisNight.ivory.opacity(0.14)))
            .contentShape(Capsule(style: .continuous))
            .accessibilityLabel(WindDownActivityCopy.endAccessibility)
    }
}

private struct WindDownHeading: View {
    let attributes: WindDownActivityAttributes
    let state: WindDownActivityAttributes.ContentState
    let isStale: Bool
    /// In the expanded island the heading shares its row with the time and is a little smaller, so the name is never cut short.
    var island = false

    var body: some View {
        HStack(spacing: island ? 8 : 10) {
            Image(systemName: "moon.stars.fill")
                .noctisFont(island ? 20 : 22, .semibold, relativeTo: .title3, maxScale: 1.3)
                .foregroundStyle(NoctisNight.lavender)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(WindDownActivityCopy.title)
                    .noctisFont(island ? 15 : 17, .semibold, relativeTo: .body, maxScale: 1.3)
                    .foregroundStyle(NoctisNight.ivory)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(WindDownActivityCopy.status(state, plannedMinutes: attributes.plannedMinutes, isStale: isStale))
                    .noctisFont(island ? 13 : 14, .regular, relativeTo: .subheadline, maxScale: 1.3)
                    .foregroundStyle(NoctisNight.ivory2)
                    .lineLimit(1)
            }
        }
    }
}

/// Whether the countdown is drawn: not once the session is over, and not when the system says the time ran out with the app away.
private func showsTimer(_ state: WindDownActivityAttributes.ContentState, isStale: Bool) -> Bool {
    state.phase != .ending && !isStale
}

/// The Lock Screen (and the banner): the moon and its name, the time left, how far through, and End.
public struct WindDownLockScreenView<End: View>: View {
    let attributes: WindDownActivityAttributes
    let state: WindDownActivityAttributes.ContentState
    let isStale: Bool
    let end: End

    public init(attributes: WindDownActivityAttributes, state: WindDownActivityAttributes.ContentState, isStale: Bool = false, @ViewBuilder end: () -> End) {
        self.attributes = attributes
        self.state = state
        self.isStale = isStale
        self.end = end()
    }

    public var body: some View {
        let timer = showsTimer(state, isStale: isStale)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                WindDownHeading(attributes: attributes, state: state, isStale: isStale)
                Spacer(minLength: 8)
                if timer {
                    WindDownTimerText(state: state)
                        .noctisFont(34, .heavy, relativeTo: .largeTitle, maxScale: 1.4)
                        .foregroundStyle(state.isPaused ? NoctisNight.ivory2 : NoctisNight.ivory)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            if timer {
                WindDownActivityProgress(state: state)
                end
            }
        }
        .padding(16)
        .accessibilityElement(children: .contain)
    }
}

// MARK: Dynamic Island

/// The compact island, left of the camera: the moon.
public struct WindDownIslandCompactLeading: View {
    public init() {}

    public var body: some View {
        Image(systemName: "moon.stars.fill")
            .foregroundStyle(NoctisNight.lavender)
            .accessibilityLabel(WindDownActivityCopy.title)
    }
}

/// The compact island, right of the camera: the time left (the pause glyph's dimmer figure while paused).
public struct WindDownIslandCompactTrailing: View {
    let state: WindDownActivityAttributes.ContentState
    let isStale: Bool

    public init(state: WindDownActivityAttributes.ContentState, isStale: Bool = false) {
        self.state = state
        self.isStale = isStale
    }

    public var body: some View {
        Group {
            if showsTimer(state, isStale: isStale) {
                WindDownTimerText(state: state)
                    .noctisFont(14, .semibold, relativeTo: .footnote, maxScale: 1.2)
                    .foregroundStyle(state.isPaused ? NoctisNight.ivory2 : NoctisNight.ivory)
                    .frame(maxWidth: 52)
            } else {
                Image(systemName: "checkmark")
                    .foregroundStyle(NoctisNight.lavender)
                    .accessibilityLabel(WindDownActivityCopy.complete)
            }
        }
    }
}

/// The minimal island, when another Live Activity shares it: the moon.
public struct WindDownIslandMinimal: View {
    public init() {}

    public var body: some View {
        Image(systemName: "moon.stars.fill")
            .foregroundStyle(NoctisNight.lavender)
            .accessibilityLabel(WindDownActivityCopy.title)
    }
}

/// The expanded island, its leading and trailing regions: the name and the length (or "Paused"), and the time left.
public struct WindDownIslandExpandedLeading: View {
    let attributes: WindDownActivityAttributes
    let state: WindDownActivityAttributes.ContentState
    let isStale: Bool

    public init(attributes: WindDownActivityAttributes, state: WindDownActivityAttributes.ContentState, isStale: Bool = false) {
        self.attributes = attributes
        self.state = state
        self.isStale = isStale
    }

    public var body: some View {
        WindDownHeading(attributes: attributes, state: state, isStale: isStale, island: true)
    }
}

public struct WindDownIslandExpandedTrailing: View {
    let state: WindDownActivityAttributes.ContentState
    let isStale: Bool

    public init(state: WindDownActivityAttributes.ContentState, isStale: Bool = false) {
        self.state = state
        self.isStale = isStale
    }

    public var body: some View {
        if showsTimer(state, isStale: isStale) {
            WindDownTimerText(state: state)
                .noctisFont(26, .heavy, relativeTo: .title, maxScale: 1.3)
                .foregroundStyle(state.isPaused ? NoctisNight.ivory2 : NoctisNight.ivory)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// The expanded island, bottom: how far through, and End.
public struct WindDownIslandExpandedBottom<End: View>: View {
    let state: WindDownActivityAttributes.ContentState
    let isStale: Bool
    let end: End

    public init(state: WindDownActivityAttributes.ContentState, isStale: Bool = false, @ViewBuilder end: () -> End) {
        self.state = state
        self.isStale = isStale
        self.end = end()
    }

    public var body: some View {
        if showsTimer(state, isStale: isStale) {
            VStack(spacing: 10) {
                WindDownActivityProgress(state: state)
                end
            }
        }
    }
}

/// The Live Activity's three colors, from the night palette the wind-down screen uses, so the extension names no color of its own.
public enum WindDownActivityStyle {
    public static var background: Color { NoctisNight.night }
    public static var foreground: Color { NoctisNight.ivory }
    public static var tint: Color { NoctisNight.lavender }
}
