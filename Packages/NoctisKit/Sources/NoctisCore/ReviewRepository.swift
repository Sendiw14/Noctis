import Foundation
import HealthProviding
import InsightsKit
import ReviewKit
import SleepKit

/// Reads Health, runs `ReviewEngine` and keeps the result in the `ReviewStore`: the one door every review (the Home card, the review screens, the notification's
/// route) comes through, so they cannot disagree about what a week said.
public actor ReviewRepository {
    private let provider: any HealthDataProviding
    private let store: ReviewStore
    private let insights: InsightStore
    private let timeZone: @Sendable () -> TimeZone
    private let clock: @Sendable () -> Date

    public init(
        provider: any HealthDataProviding, store: ReviewStore = ReviewStore(), insights: InsightStore = InsightStore(),
        timeZone: @escaping @Sendable () -> TimeZone = { .autoupdatingCurrent }, clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.store = store
        self.insights = insights
        self.timeZone = timeZone
        self.clock = clock
    }

    /// Dates in the Gregorian calendar the nights are keyed in, on the clock of the zone the person is in now.
    public func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone()
        return calendar
    }

    /// The most recent week whose review day (`weekday`, 1 = Sunday) has begun.
    public func latestWeekly(weekday: Int) -> ReviewPeriod {
        ReviewPeriod.latestWeekly(now: clock(), weekday: weekday, calendar: calendar())
    }

    /// The previous calendar month.
    public func latestMonthly() -> ReviewPeriod {
        ReviewPeriod.latestMonthly(now: clock(), calendar: calendar())
    }

    public func review(_ period: ReviewPeriod, profile: UserProfileSnapshot) async -> ReviewOutcome {
        let now = clock()
        let calendar = calendar()
        let zone = calendar.timeZone
        let provider = provider
        let insights = insights
        return await store.review(for: period, now: now, calendar: calendar) {
            guard await provider.isHealthDataAvailable, await provider.authorizationStatus() == .authorized else { return nil }
            // Reach back 18 hours more so the oldest night is seen whole.
            let start = now.addingTimeInterval(-Double(ReviewInputsBuilder.historyDays) * 86_400 - 18 * 3600)
            do {
                async let sleep = provider.fetchSleepSamples(from: start, to: now)
                async let hrv = provider.fetchHRVSamples(from: start, to: now)
                async let resting = provider.fetchRestingHeartRate(from: start, to: now)
                let samples = try await (sleep, hrv, resting)
                let nights = ReviewInputsBuilder.nights(
                    sleep: samples.0, hrv: samples.1, restingHeartRate: samples.2, needMinutes: Double(profile.needMinutes), now: now, timeZone: zone
                )
                let library = await insights.snapshot()
                return ReviewEngine.build(
                    period: period, nights: nights, needMinutes: profile.needMinutes, insights: ReviewInputsBuilder.insights(from: library), now: now, calendar: calendar
                )
            } catch {
                return nil
            }
        }
    }

    /// The person opened a review.
    public func markSeen(_ id: ReviewID) async {
        await store.markSeen(id)
    }

    public func stored(_ id: ReviewID) async -> StoredReview? {
        await store.stored(id)
    }

    public func library() async -> ReviewLibrary {
        await store.snapshot()
    }
}
