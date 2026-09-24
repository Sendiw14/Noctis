import Foundation
import HealthProviding
import Testing
@testable import RecoveryKit
@testable import SleepKit

struct BaselineEngineTests {
    private let target = SleepNightKey(year: 2026, month: 9, day: 23)

    /// Nights on the evenings before `target`, `offsets` nights back.
    private func nights(back offsets: [Int], asleep: (Int) -> Double = { _ in 420 }, hrv: (Int) -> Double? = { _ in 50 }, resting: (Int) -> Double? = { _ in 55 }) -> [NightMetrics] {
        offsets.map { offset in
            NightMetrics(
                night: target.adding(days: -offset),
                wakeTime: .distantPast,
                asleepMinutes: asleep(offset),
                bedtimeMinutes: 660,
                wakeMinutes: 1140,
                hrv: hrv(offset),
                restingHeartRate: resting(offset)
            )
        }
    }

    @Test func windowIsTheFourteenNightsBeforeTheNightJudged() {
        let history = nights(back: Array(0...20))
        let window = BaselineEngine.window(for: target, in: history)
        #expect(window.count == 14)
        #expect(window.map(\.night).min() == target.adding(days: -14))
        #expect(window.map(\.night).max() == target.adding(days: -1))
        #expect(!window.contains { $0.night == target })
    }

    @Test func noBaselineBelowFiveValidNights() {
        let baselines = BaselineEngine.baselines(for: target, history: nights(back: [1, 2, 3, 4]))
        #expect(baselines.sleepDuration == nil && baselines.bedtime == nil && baselines.wakeTime == nil)
        #expect(baselines.hrv == nil && baselines.restingHeartRate == nil)
        // The nights that do have values are still counted.
        #expect(baselines.hrvNights == 4)
        #expect(baselines.restingHeartRateNights == 4)
    }

    @Test func fiveValidNightsMakeABaseline() {
        let baselines = BaselineEngine.baselines(for: target, history: nights(back: [1, 2, 3, 4, 5]))
        #expect(baselines.sleepDuration == Baseline(value: 420, nights: 5))
        #expect(baselines.bedtime == Baseline(value: 660, nights: 5))
        #expect(baselines.wakeTime == Baseline(value: 1140, nights: 5))
        #expect(baselines.hrv == Baseline(value: 50, nights: 5))
        #expect(baselines.restingHeartRate == Baseline(value: 55, nights: 5))
    }

    @Test func nightsOutsideTheWindowNeverCount() {
        // Five nights, but two are 15+ nights back: only three count.
        let baselines = BaselineEngine.baselines(for: target, history: nights(back: [1, 2, 3, 15, 16]))
        #expect(baselines.sleepDuration == nil && baselines.hrv == nil)
        #expect(baselines.hrvNights == 3)
    }

    @Test func baselineIsTheMeanOfTheWindow() {
        let history = nights(back: Array(1...14), asleep: { Double(400 + $0 * 2) })
        // 402, 404, …, 428: mean 415, sample SD √70.
        let baseline = BaselineEngine.baselines(for: target, history: history).sleepDuration
        #expect(baseline?.value == 415)
        #expect(baseline?.nights == 14)
        #expect(abs((baseline?.standardDeviation ?? 0) - 70.0.squareRoot()) < 1e-9)
    }

    @Test func hrvAndRestingCountOnlyNightsThatHaveThem() {
        let history = nights(back: Array(1...7), hrv: { $0 <= 4 ? 50 : nil }, resting: { $0 <= 5 ? 55 : nil })
        let baselines = BaselineEngine.baselines(for: target, history: history)
        #expect(baselines.sleepDuration?.nights == 7)
        #expect(baselines.hrv == nil)
        #expect(baselines.restingHeartRate == Baseline(value: 55, nights: 5))
    }

    @Test func bedtimesEitherSideOfMidnightAverageToMidnight() {
        // 11:30 PM (690) and 12:30 AM (750), minutes after noon.
        let history = (1...6).map { offset in
            NightMetrics(night: target.adding(days: -offset), wakeTime: .distantPast, asleepMinutes: 420,
                         bedtimeMinutes: offset.isMultiple(of: 2) ? 690 : 750, wakeMinutes: 1140, hrv: nil, restingHeartRate: nil)
        }
        #expect(BaselineEngine.baselines(for: target, history: history).bedtime?.value == 720)
    }
}

struct NightMetricsBuilderTests {
    private let tz = Fixture.newYork

    private func session() throws -> SleepSession {
        let samples = [Fixture.sample(Fixture.date(2026, 9, 1, 23), Fixture.date(2026, 9, 2, 7))]
        return try #require(SleepSessionEngine.history(from: samples, asOf: Fixture.date(2026, 9, 3, 12), timeZone: tz).nights.first)
    }

    @Test func hrvIsTheMeanFromBedtimeUntilHalfAnHourAfterWaking() throws {
        let hrv = [
            HRVSample(date: Fixture.date(2026, 9, 1, 22), sdnnMilliseconds: 99), // before bed
            HRVSample(date: Fixture.date(2026, 9, 2, 2), sdnnMilliseconds: 40),
            HRVSample(date: Fixture.date(2026, 9, 2, 5), sdnnMilliseconds: 50),
            HRVSample(date: Fixture.date(2026, 9, 2, 7, 20), sdnnMilliseconds: 60),
            HRVSample(date: Fixture.date(2026, 9, 2, 8), sdnnMilliseconds: 99), // too late
        ]
        let metrics = NightMetricsBuilder.metrics(for: try session(), hrv: hrv, restingHeartRate: [])
        #expect(metrics.hrv == 50)
        #expect(metrics.restingHeartRate == nil)
    }

    @Test func restingHeartRateIsTakenUpToFourHoursAfterWaking() throws {
        let resting = [
            HeartRateSample(date: Fixture.date(2026, 9, 2, 9), bpm: 54, sourceName: "Watch"),
            HeartRateSample(date: Fixture.date(2026, 9, 2, 13), bpm: 70, sourceName: "Watch"),
        ]
        let metrics = NightMetricsBuilder.metrics(for: try session(), hrv: [], restingHeartRate: resting)
        #expect(metrics.restingHeartRate == 54)
    }

    @Test func sleepValuesComeFromTheSession() throws {
        let metrics = NightMetricsBuilder.metrics(for: try session(), hrv: [], restingHeartRate: [])
        #expect(metrics.asleepMinutes == 480)
        #expect(metrics.bedtimeMinutes == 660)
        #expect(metrics.wakeMinutes == 1140)
        #expect(metrics.night == SleepNightKey(year: 2026, month: 9, day: 1))
    }
}
