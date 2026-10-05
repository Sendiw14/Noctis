import DesignSystem
import NoctisWatchKit
import NoctisWidgetKit
import SwiftUI

// The Watch app's pages (APP_RULES.md R50, R51): flat shapes on black, the app's palette, `NoctisMetric` units, no text under 12pt. They draw what
// `WatchPages` built and decide nothing. Every Health number is `privacySensitive` and is replaced by a lock glyph where the system redacts it.

enum WatchTheme {
    static let ink = NoctisNight.ivory
    static let quiet = NoctisNight.ivory2

    /// The flat accent capsule behind each page's title, with cocoa text on it.
    static func accent(_ page: WatchPage) -> Color {
        switch page {
        case .recovery: NoctisAppColor.blockLavender
        case .sleep: NoctisAppColor.blockSage
        case .heart: NoctisAppColor.orange
        case .tonight: NoctisAppColor.fieldApricot
        case .settings: NoctisAppColor.fieldSand
        }
    }

    /// A factor's color as a dot beside its row.
    static func dot(_ kind: WidgetFactorKind) -> Color {
        switch kind {
        case .sleepDuration: NoctisAppColor.sage
        case .hrv: NoctisAppColor.lavender
        case .restingHeartRate: NoctisAppColor.orange
        case .sleepConsistency: NoctisAppColor.butter
        }
    }

    static func stage(_ stage: WidgetStageKind) -> Color {
        switch stage {
        case .deep: NoctisAppColor.stageDeep
        case .core: NoctisAppColor.stageCore
        case .rem: NoctisAppColor.stageREM
        }
    }
}

/// A Health value: replaced by a lock where the Watch is locked and the system redacts, and marked private for the system's own redaction.
struct WatchPrivate<Content: View>: View {
    @Environment(\.redactionReasons) private var reasons
    let sensitivity: WidgetSensitivity
    let content: Content

    init(_ sensitivity: WidgetSensitivity = .health, @ViewBuilder content: () -> Content) {
        self.sensitivity = sensitivity
        self.content = content()
    }

    var body: some View {
        if sensitivity == .health, reasons.contains(.privacy) {
            Image(systemName: "lock.fill")
                .noctisFont(16, .semibold, relativeTo: .body)
                .foregroundStyle(WatchTheme.quiet)
                .accessibilityLabel("Unlock to see")
        } else {
            content.privacySensitive(sensitivity == .health)
        }
    }
}

/// The page's title: a flat capsule in the page's accent, cocoa text on it, 13pt (12pt is the floor).
struct WatchPageTitle: View {
    let page: WatchPage

    var body: some View {
        Text(page.title)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .foregroundStyle(NoctisAppColor.blockInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(WatchTheme.accent(page)))
            .accessibilityAddTraits(.isHeader)
    }
}

/// What a state says when there are no numbers.
struct WatchMessageView: View {
    let message: WatchMessage

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: message.glyph)
                .noctisFont(26, .semibold, relativeTo: .title2)
                .foregroundStyle(WatchTheme.quiet)
                .accessibilityHidden(true)
            Text(message.title)
                .noctisFont(15, .semibold, relativeTo: .body)
                .foregroundStyle(WatchTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = message.detail {
                Text(detail)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(WatchTheme.quiet)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct WatchQuietLine: View {
    let text: String

    var body: some View {
        Text(text)
            .noctisFont(13, relativeTo: .footnote)
            .foregroundStyle(WatchTheme.quiet)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Recovery

struct RecoveryPageView: View {
    let content: WatchRecoveryPage

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchPageTitle(page: .recovery)
                // Old numbers say how old they are before anything else (never as today's).
                if let stale = content.staleLine { WatchQuietLine(text: stale) }
                if let message = content.message {
                    WatchMessageView(message: message)
                } else {
                    ZStack {
                        WidgetRingView(segments: content.ring, lineWidth: 12)
                        WatchPrivate(content.sensitivity) {
                            NoctisMetric(
                                NoctisMetricValue(parts: [.number("\(content.score ?? 0)")], spoken: "\(content.score ?? 0)"), size: 40, weight: .heavy,
                                relativeTo: .largeTitle, tone: .nightPanel
                            )
                        }
                    }
                    .frame(width: 120, height: 120)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(content.accessibilityLabel)
                    if let delta = content.delta {
                        WatchPrivate(content.sensitivity) {
                            Text(delta.text)
                                .noctisFont(13, .semibold, relativeTo: .footnote)
                                .foregroundStyle(WatchTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.14)))
                        }
                    }
                    if let confidence = content.confidence { WatchQuietLine(text: confidence) }
                    VStack(spacing: 6) {
                        ForEach(content.factors) { row in
                            HStack(spacing: 8) {
                                Circle().fill(WatchTheme.dot(row.kind)).frame(width: 8, height: 8).accessibilityHidden(true)
                                Text(row.name).noctisFont(15, relativeTo: .body).foregroundStyle(WatchTheme.ink)
                                Spacer(minLength: 4)
                                WatchPrivate(content.sensitivity) {
                                    Text("\(row.score)").noctisFont(15, .semibold, relativeTo: .body).foregroundStyle(WatchTheme.ink)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

// MARK: Sleep

struct SleepPageView: View {
    let content: WatchSleepPage

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchPageTitle(page: .sleep)
                if let stale = content.staleLine { WatchQuietLine(text: stale) }
                if let message = content.message {
                    WatchMessageView(message: message)
                } else if let duration = content.duration {
                    WatchQuietLine(text: content.caption)
                    WatchPrivate(content.sensitivity) {
                        NoctisMetric(duration, size: 36, weight: .heavy, relativeTo: .largeTitle, tone: .nightPanel)
                    }
                    if let times = content.times {
                        WatchPrivate(content.sensitivity) { Text(times).noctisFont(13, relativeTo: .footnote).foregroundStyle(WatchTheme.quiet) }
                    }
                    if let stages = content.stages {
                        WatchPrivate(content.sensitivity) { WidgetStageStrip(stages: stages, height: 12) }
                    }
                    if let quality = content.quality {
                        WatchPrivate(content.sensitivity) { Text(quality).noctisFont(15, .semibold, relativeTo: .body).foregroundStyle(WatchTheme.ink) }
                    }
                }
            }
            .padding(.horizontal, 6)
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: Heart

struct HeartPageView: View {
    let content: WatchHeartPage

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchPageTitle(page: .heart)
                if let stale = content.staleLine { WatchQuietLine(text: stale) }
                if let message = content.message {
                    WatchMessageView(message: message)
                } else {
                    ForEach(content.tiles) { tile in
                        VStack(spacing: 2) {
                            Text(tile.name).noctisFont(13, .semibold, relativeTo: .footnote).foregroundStyle(WatchTheme.quiet)
                            WatchPrivate(content.sensitivity) {
                                NoctisMetric(tile.value, size: 32, weight: .heavy, relativeTo: .title, tone: .nightPanel)
                            }
                            if let baseline = tile.baseline {
                                WatchPrivate(content.sensitivity) { Text(baseline).noctisFont(13, relativeTo: .footnote).foregroundStyle(WatchTheme.quiet) }
                            }
                            if let sentence = tile.sentence {
                                WatchPrivate(content.sensitivity) {
                                    Text(sentence).noctisFont(13, .semibold, relativeTo: .footnote).foregroundStyle(WatchTheme.ink).multilineTextAlignment(.center)
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

// MARK: Tonight

struct TonightPageView: View {
    let content: WatchTonightPage
    let systemDate: (Date) -> Date
    let breathe: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchPageTitle(page: .tonight)
                if let message = content.message {
                    WatchMessageView(message: message)
                } else {
                    if let window = content.windowText {
                        Text(window).noctisFont(24, .heavy, relativeTo: .title2).foregroundStyle(WatchTheme.ink).minimumScaleFactor(0.7).lineLimit(1)
                    } else if let bedtime = content.bedtime {
                        NoctisMetric(bedtime, size: 28, weight: .heavy, relativeTo: .title2, tone: .nightPanel)
                    }
                    switch content.countdown {
                    case .until(let date):
                        Text(systemDate(date), style: .timer)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(WatchTheme.ink)
                            .monospacedDigit()
                            .accessibilityLabel("Bedtime in")
                    case .passed(let text):
                        WatchQuietLine(text: text)
                    case .none:
                        EmptyView()
                    }
                    if let wake = content.wakeLine { WatchQuietLine(text: wake) }
                    if let alarm = content.alarmLine { WatchQuietLine(text: alarm) }
                }
                // Breathing needs nothing from the iPhone, so it is there in every state.
                Button(action: breathe) {
                    Text(WatchBreathCopy.button)
                        .noctisFont(15, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.blockInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule(style: .continuous).fill(WatchTheme.accent(.tonight)))
                }
                .buttonStyle(.plain)
                .accessibilityHint(WatchBreathCopy.tagline)
            }
            .padding(.horizontal, 6)
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: Settings

struct SettingsPageView: View {
    let content: WatchSettingsPage
    let isPhoneReachable: Bool
    let askResult: String?
    let ask: () -> Void
    @Binding var hapticsOn: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchPageTitle(page: .settings)
                Text(content.status)
                    .noctisFont(15, .semibold, relativeTo: .body)
                    .foregroundStyle(WatchTheme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let updated = content.updated { WatchQuietLine(text: updated) }
                Button(action: ask) {
                    Text(WatchCopy.askButton)
                        .noctisFont(15, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.blockInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule(style: .continuous).fill(NoctisAppColor.blockLavender))
                }
                .buttonStyle(.plain)
                .accessibilityHint(isPhoneReachable ? "Asks your iPhone to refresh." : WatchCopy.unreachable)
                if let askResult { WatchQuietLine(text: askResult) }
                Toggle(WatchBreathCopy.hapticsToggle, isOn: $hapticsOn)
                    .tint(NoctisAppColor.sage)
                    .noctisFont(14, .semibold, relativeTo: .footnote)
                    .foregroundStyle(WatchTheme.ink)
                    .frame(minHeight: 44)
                WatchQuietLine(text: content.about)
                WatchQuietLine(text: content.version)
            }
            .padding(.horizontal, 6)
        }
    }
}
