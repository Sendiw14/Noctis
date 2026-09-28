import Foundation
import Testing
@testable import HealthProviding
@testable import HomeFeature
@testable import NoctisCore
@testable import SleepKit

/// Day and evening modes, tonight's countdown and the header summary.
/// Default profile: wake 7:00 AM, 8h need, so bedtime 11:00 PM and
/// evening from 8:00 PM to 4:00 AM (New York, en_US).
struct HomeModeTests {
    private let calendar = Fixture.calendar()
    private let locale = Locale(identifier: "en_US")
    private let plan = TonightPlan(profile: UserProfileSnapshot())

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Fixture.date(2026, 9, day, hour, minute)
    }

    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func mode(_ date: Date, plan: TonightPlan? = nil) -> HomeMode {
        HomeScreenBuilder.mode(now: date, plan: plan ?? self.plan, calendar: calendar)
    }

    // MARK: - Modes

    @Test(arguments: [
        (12, 0, HomeMode.day), (19, 59, .day), (20, 0, .evening), (23, 30, .evening),
        (3, 59, .evening), (4, 0, .day), (6, 0, .day), (7, 0, .day),
    ])
    func eveningRunsFromThreeHoursBeforeBedtimeUntil4AM(hour: Int, minute: Int, expected: HomeMode) {
        #expect(mode(at(24, hour, minute)) == expected)
    }

    @Test func aBedtimeAfterMidnightMovesTheEveningLater() {
        var profile = UserProfileSnapshot()
        profile.typicalWakeMinutes = 8 * 60 + 30
        let late = TonightPlan(profile: profile) // bedtime 12:30 AM, evening from 9:30 PM
        #expect(mode(at(24, 21, 29), plan: late) == .day)
        #expect(mode(at(24, 21, 30), plan: late) == .evening)
        #expect(mode(at(25, 0, 15), plan: late) == .evening)
        #expect(mode(at(25, 4, 0), plan: late) == .day)
    }

    @Test func theNextFlipIsTheNearestBoundary() {
        #expect(HomeScreenBuilder.nextModeChange(after: at(24, 10), plan: plan, calendar: calendar) == at(24, 20))
        #expect(HomeScreenBuilder.nextModeChange(after: at(24, 21), plan: plan, calendar: calendar) == at(25, 4))
        #expect(HomeScreenBuilder.nextModeChange(after: at(25, 3), plan: plan, calendar: calendar) == at(25, 4))
        #expect(HomeScreenBuilder.nextModeChange(after: at(24, 20), plan: plan, calendar: calendar) == at(25, 4))
    }

    // MARK: - Tonight

    private func times(_ now: Date, plan: TonightPlan? = nil) -> TonightTimes {
        HomeScreenBuilder.tonightTimes(now: now, plan: plan ?? self.plan, format: HomeFormat(calendar: calendar, locale: locale))
    }

    @Test func theCountdownRunsToTonightsBedtime() {
        let tonight = times(at(24, 20, 46))
        #expect(tonight.bedtime == at(24, 23))
        #expect(tonight.countdown(at: at(24, 20, 46)) == "in 2h 14m")
        #expect(tonight.summary(at: at(24, 20, 46)) == "Bedtime in 2h 14m.")
        #expect(tonight.countdown(at: at(24, 22, 15)) == "in 45m")
        #expect(tonight.minutesLeft(at: at(24, 22, 15)) == 45)
    }

    @Test func afterBedtimeThereIsNoCountdown() {
        let tonight = times(at(24, 23, 30))
        #expect(tonight.countdown(at: at(24, 23)) == nil)
        #expect(plain(tonight.passedText) == "Bedtime was 11:00 PM")
        #expect(plain(tonight.summary(at: at(24, 23, 30))) == "Bedtime was 11:00 PM.")
        // After midnight it's still the same night.
        #expect(times(at(25, 1)).bedtime == at(24, 23))
        #expect(times(at(25, 5)).bedtime == at(25, 23))
    }

    @Test func aBedtimeAfterMidnightCountsDownAcrossIt() {
        var profile = UserProfileSnapshot()
        profile.typicalWakeMinutes = 8 * 60 + 30
        let late = times(at(24, 23), plan: TonightPlan(profile: profile))
        #expect(late.bedtime == at(25, 0, 30))
        #expect(late.countdown(at: at(24, 23)) == "in 1h 30m")
    }

    @Test func theNightStripRuns6PMTo10AM() {
        let tonight = times(at(24, 21))
        #expect(tonight.windowStart == at(24, 18))
        #expect(tonight.windowEnd == at(25, 10))
        #expect(abs(tonight.bedtimeFraction - 5.0 / 16) < 1e-9)
        #expect(abs(tonight.wakeFraction - 13.0 / 16) < 1e-9)
        #expect(abs((tonight.nowFraction(at: at(24, 21)) ?? -1) - 3.0 / 16) < 1e-9)
        #expect(tonight.nowFraction(at: at(24, 12)) == nil)
    }

    @Test func theEveningHeroSplitsTheTimeAndLabelsTheStrip() {
        let format = HomeFormat(calendar: calendar, locale: locale)
        let hero = HomeScreenBuilder.eveningHero(times(at(24, 21)), plan: plan, format: format)
        #expect(hero.time.parts == [.number("11:00"), .unit("PM")])
        #expect(plain(hero.time.spoken) == "11:00 PM")
        #expect(plain(hero.detail) == "Wake 7:00 AM · 8h need")
        #expect(hero.stripLabels.map { plain($0.text) } == ["6 PM", "12 AM", "6 AM", "10 AM"])
        #expect(hero.stripLabels.map(\.position) == [0, 6.0 / 16, 12.0 / 16, 1])
        #expect(plain(hero.stripAccessibilityLabel) == "Tonight's sleep window, 11:00 PM to 7:00 AM.")
        #expect(HomeFormat(calendar: calendar, locale: Locale(identifier: "en_GB")).splitClock("23:00") == ("23:00", ""))
    }

    // MARK: - Screens

    private func screen(_ scenario: MockScenario, at date: Date, authorized: Bool = true, available: Bool = true, fails: Bool = false,
                        override: HomeMode? = nil) async -> HomeScreen {
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: date, calendar: calendar,
                                             startAuthorized: authorized, isHealthDataAvailable: available, failsQueries: fails)
        let snapshot = await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { date }).refresh(profile: UserProfileSnapshot())
        return HomeScreenBuilder.build(snapshot, now: date, calendar: calendar, locale: locale, modeOverride: override)
    }

    @Test func eveningScreensLeadWithTonight() async {
        let evening = await screen(.full, at: at(24, 21))
        #expect(evening.mode == .evening)
        #expect(evening.header.mode == .evening)
        #expect(evening.header.summary.text(at: at(24, 21)) == "Bedtime in 2h.")
        #expect(evening.nextModeChange == at(25, 4))
        // States keep the Tonight hero in the evening too.
        let empty = await screen(.empty, at: at(24, 21))
        #expect(empty.mode == .evening)
        #expect(empty.header.summary.text(at: at(24, 21)) == "Bedtime in 2h.")
    }

    @Test func theModeCanBePinned() async {
        #expect(await screen(.full, at: at(24, 10), override: .evening).mode == .evening)
        #expect(await screen(.full, at: at(24, 21), override: .day).mode == .day)
    }

    @Test func dayHeadersCarryADateCaptionAndOneSentence() async throws {
        let day = await screen(.full, at: at(24, 10))
        #expect(day.mode == .day)
        #expect(day.header.dateCaption == "THURSDAY, SEPTEMBER 24")
        let sentence = day.header.summary.text(at: at(24, 10))
        guard case .scored(let scored) = day.recovery else { Issue.record("expected a score"); return }
        let slept = try #require(day.lastNight?.duration)
        #expect(sentence == "You slept \(slept.plain). Recovery is \(scored.score).")
    }

    @Test func everyStateHasAnHonestSentence() async {
        func sentence(_ screen: HomeScreen) -> String { screen.header.summary.text(at: at(24, 10)) }
        #expect(sentence(await screen(.learning, at: at(24, 10))) == "We're still learning your pattern.")
        #expect(sentence(await screen(.gap, at: at(24, 10))) == "No sleep was recorded last night.")
        #expect(sentence(await screen(.stale, at: at(24, 10))) == "Apple Health hasn't synced recently.")
        #expect(sentence(await screen(.empty, at: at(24, 10))) == "No sleep data yet.")
        #expect(sentence(await screen(.full, at: at(24, 10), authorized: false)) == "Connect Apple Health to see your nights.")
        #expect(sentence(await screen(.full, at: at(24, 10), available: false)) == "Apple Health isn't available on this device.")
        #expect(sentence(await screen(.full, at: at(24, 10), fails: true)) == "We couldn't read your sleep data.")
    }

    // MARK: - View model

    @Test func theViewModelFlipsModeWhenTheClockCrossesTheBoundary() async {
        // Read by the repository's actor; the test only moves it between awaits.
        final class Clock: @unchecked Sendable {
            nonisolated(unsafe) var now: Date
            nonisolated init(_ now: Date) { self.now = now }
        }
        let clock = Clock(at(24, 19, 59))
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: at(24, 10), calendar: calendar, startAuthorized: true)
        let model = HomeViewModel(
            repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { [clock] in clock.now }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard),
            reduceMotion: { true },
            clock: { clock.now }, calendar: calendar, locale: locale
        )
        #expect(model.header.mode == .day)
        await model.refresh()
        #expect(model.screen?.mode == .day)
        #expect(model.scheduledModeChange == at(24, 20))
        clock.now = at(24, 20, 0)
        model.updateClock()
        #expect(model.screen?.mode == .evening)
        #expect(model.scheduledModeChange == at(25, 4))
        model.stopObserving()
    }

    @Test func theLoadingHeaderAlreadyKnowsTheMode() {
        let model = HomeViewModel(
            repository: HomeRepository(provider: MockHealthKitProvider(scenario: .empty), timeZone: Fixture.newYork, clock: { Date() }),
            profile: { UserProfileSnapshot() },
            clock: { Fixture.date(2026, 9, 24, 21) }, calendar: calendar, locale: locale
        )
        #expect(model.screen == nil)
        #expect(model.header.mode == .evening)
        #expect(model.header.summary.text(at: Fixture.date(2026, 9, 24, 21)) == "Bedtime in 2h.")
    }
}
