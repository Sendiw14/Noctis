import DesignSystem
import Foundation
import Observation
import SwiftUI

/// The current minute, for the few views that show it: the header's
/// bedtime countdown, the evening hero's countdown, the compact bar and the
/// tab bar accessory. Each of those reads `minute` in its own `body`, and
/// only those bodies run when it changes, once a minute: Home's root and its
/// cards never read it (APP_RULES.md R23). It replaces a `TimelineView`
/// around the whole tab view, which re-evaluated everything under it.
@Observable
public final class HomeClock {
    /// The start of the current minute.
    public private(set) var minute: Date

    private let now: () -> Date
    @ObservationIgnored private var ticker: Task<Void, Never>?

    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now
        minute = Self.startOfMinute(now())
    }

    public static func startOfMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    /// The next minute boundary after `date`.
    public static func nextMinute(after date: Date) -> Date {
        startOfMinute(date).addingTimeInterval(60)
    }

    /// Ticks at every minute boundary until `stop()`; a no-op when already
    /// running.
    public func start() {
        guard ticker == nil else { return }
        refresh()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let current = self.now()
                // A hair past the boundary, so the new minute is read.
                let wait = Self.nextMinute(after: current).timeIntervalSince(current) + 0.02
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
    }

    /// Re-reads the clock. Publishes only when the minute changed, so
    /// nothing re-evaluates for a second that didn't cross a boundary.
    public func refresh() {
        let current = Self.startOfMinute(now())
        if current != minute { minute = current }
    }
}

extension EnvironmentValues {
    /// The app's minute clock; nil outside the app (previews, render
    /// tests), where a view reads the time when it's built.
    @Entry public var homeClock: HomeClock? = nil
}

/// Sets an accessibility label that depends on the current minute, in a
/// modifier of its own: the minute re-runs this body and nothing else.
struct HomeClockLabel: ViewModifier {
    let label: (Date) -> String
    @Environment(\.homeClock) private var clock

    func body(content: Content) -> some View {
        content.accessibilityLabel(label(clock?.minute ?? .now))
    }
}

/// The header's one-sentence summary. Bedtime countdowns change every
/// minute, so this is the only part of the header that reads the clock.
struct HomeSummaryLine: View {
    let summary: HeaderSummary
    @Environment(\.homeClock) private var clock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        #if DEBUG
        let _ = HomeBodyProbe.hit("HomeSummaryLine")
        #endif
        let text = summary.text(at: clock?.minute ?? .now)
        Text(text)
            .noctisFont(17, relativeTo: .body)
            .foregroundStyle(.noctisInk2)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : NoctisMotion.settle, value: text)
    }
}
