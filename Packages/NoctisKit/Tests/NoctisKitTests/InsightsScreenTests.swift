import DesignSystem
import Foundation
import HealthProviding
import Testing

@testable import HomeFeature
@testable import InsightsFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import SleepKit

/// The Insights tab's content: the words, order and grouping come from the
/// builder, so every rule of the screen is a unit test.
struct InsightsScreenTests {
    typealias R = InsightRecordFixture
    private let now = Fixture.date(2026, 9, 24, 10)
    private let last = InsightFixture.last

    private func snapshot(
        _ records: [InsightRecord], featured: InsightRecord? = nil, state: HomeDataState = .ready, nights: Int = 40,
        standing: [StandingRecord] = [], new: Int? = nil
    ) -> InsightsSnapshot {
        var library = InsightLibrary()
        library.merge(records)
        let stored = library.visible
        return InsightsSnapshot(
            dataState: state, night: last, nightsRecorded: nights, featured: featured, recent: library.recent(on: last),
            all: stored, newThisWeek: new ?? library.newThisWeek(on: last).count, records: standing, lastUpdated: now
        )
    }

    private func screen(_ snapshot: InsightsSnapshot, filter: InsightCategory? = nil) -> InsightsScreenContent {
        InsightsScreenBuilder.build(snapshot, filter: filter, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
    }

    private var mixed: [InsightRecord] {
        [
            R.duration(delta: -70), R.bedtime(delta: 55), R.balance(), R.pattern(on: last.adding(days: -1)),
            R.weekend(on: last.adding(days: -9)), R.heart(.hrv, on: last.adding(days: -12)),
        ]
    }

    // MARK: - The field

    @Test func theCaptionIsTheDateInCapitals() {
        #expect(screen(snapshot(mixed)).dateCaption == "THURSDAY, SEPTEMBER 24")
    }

    @Test func theSummaryCountsWhatIsNewThisWeek() {
        #expect(screen(snapshot(mixed, new: 3)).summary == "3 new this week")
        #expect(screen(snapshot(mixed, new: 1)).summary == "1 new this week")
        #expect(screen(snapshot(mixed, new: 0)).summary == "You're all caught up.")
    }

    @Test func learningSaysWeAreStillLearning() {
        let content = screen(snapshot([], state: .learning(nightsSoFar: 4), nights: 4))
        #expect(content.summary == "We're still learning your pattern.")
    }

    @Test func thereAreNoBadgesAnywhere() {
        // A count is words in the summary; nothing else carries one.
        let content = screen(snapshot(mixed))
        #expect(content.chips.allSatisfy { !$0.title.contains(where: \.isNumber) })
    }

    // MARK: - The chips

    @Test func chipsAreAllThenEachCategoryInOrder() {
        #expect(screen(snapshot(mixed)).chips.map(\.title) == ["All", "Sleep", "Recovery", "Timing", "Consistency", "Heart", "Long-term"])
        #expect(screen(snapshot(mixed)).chips.map(\.category) == [nil] + InsightCategory.allCases.map { Optional($0) })
    }

    // MARK: - Featured and Recent

    @Test func theFeaturedStoryLeadsAndTheListDoesNotRepeatIt() throws {
        let featured = R.duration(delta: -70)
        let content = screen(snapshot(mixed, featured: featured))
        let story = try #require(content.featured)
        #expect(story.id == featured.id)
        #expect(story.title == "Shorter night than usual")
        #expect(story.numbers.map(\.value.plain) == ["7h", "5h 50m"])
        #expect(story.join == .arrow)
        #expect(story.interpretation.hasPrefix("Your recent data suggests"))
        #expect(story.chart != nil)
        #expect(!content.groups.flatMap(\.rows).contains { $0.id == featured.id })
    }

    @Test func recentIsGroupedThisWeekAndEarlier() {
        let content = screen(snapshot(mixed))
        #expect(content.groups.map(\.title) == ["This week", "Earlier"])
        // 2 and 3 nights ago, and last night: this week; 9 and 12 nights ago: earlier.
        #expect(content.groups[0].rows.count == 4)
        #expect(content.groups[1].rows.count == 2)
    }

    @Test func aRowHasACategoryATitleAndOneEvidenceLine() throws {
        let content = screen(snapshot([R.bedtime(delta: 55)]))
        let row = try #require(content.groups.first?.rows.first)
        #expect(row.category == .timing)
        #expect(row.title == "Later bedtime than usual")
        #expect(row.line.contains("55 min later"))
        #expect(row.accessibilityLabel.hasPrefix(row.title))
    }

    @Test func aFilterKeepsItsCategoryOnly() throws {
        let snap = snapshot(mixed, featured: R.duration(delta: -70))
        let sleep = screen(snap, filter: .sleep)
        #expect(sleep.featured?.category == .sleep, "the featured story stays when it fits the chip")
        #expect(sleep.groups.flatMap(\.rows).allSatisfy { $0.category == .sleep })
        let timing = screen(snap, filter: .timing)
        #expect(timing.featured == nil, "another category: no story")
        #expect(timing.groups.flatMap(\.rows).map(\.category).allSatisfy { $0 == .timing })
        #expect(timing.groups.flatMap(\.rows).count == 3, "the bedtime shift, the pattern and the weekend shift")
    }

    @Test func aFilterWithNothingSaysSo() throws {
        let content = screen(snapshot([R.bedtime(delta: 55)]), filter: .heart)
        let note = try #require(content.note)
        #expect(note.title == "No heart insights yet")
        #expect(content.featured == nil && content.groups.isEmpty)
    }

    @Test func aQuietDayHasANote() throws {
        let content = screen(snapshot([]))
        #expect(content.note?.title == "Nothing new today")
        #expect(content.chips.count == 7, "the chips stay")
    }

    @Test func noSleepLastNightIsSaidAndTheRestStays() throws {
        let content = screen(snapshot([R.pattern(on: last.adding(days: -2))], state: .noSleepLastNight))
        #expect(content.note?.title == "No sleep recorded last night")
        #expect(content.groups.flatMap(\.rows).count == 1)
    }

    // MARK: - Your records

    @Test func recordsAreTheThreeTilesThatExist() {
        let standing = [
            StandingRecord(type: .recordHighestRecovery, night: last.adding(days: -20), value: 91, nightsInWindow: 88),
            StandingRecord(type: .recordLongestNight, night: last.adding(days: -3), value: 512, nightsInWindow: 88),
            StandingRecord(type: .recordLowestRestingHeartRate, night: last.adding(days: -40), value: 49, nightsInWindow: 88),
        ]
        let tiles = screen(snapshot(mixed, standing: standing)).records
        #expect(tiles.map(\.title) == ["Longest night", "Highest recovery"], "resting heart rate isn't one of the three; best consistency doesn't exist")
        #expect(tiles.map(\.tone) == [.sage, .butter])
        #expect(tiles[0].value.plain == "8h 32m")
        #expect(tiles[0].date == "Sep 20")
        #expect(tiles[1].value.plain == "91")
        #expect(tiles[1].accessibilityLabel == "Highest recovery: 91 out of 100, Sep 3.")
    }

    @Test func allThreeRecordsAreSageLavenderButterInOrder() {
        let standing = [
            StandingRecord(type: .recordBestConsistency, night: last, value: 9, nightsInWindow: 60),
            StandingRecord(type: .recordHighestRecovery, night: last, value: 91, nightsInWindow: 60),
            StandingRecord(type: .recordLongestNight, night: last, value: 512, nightsInWindow: 60),
        ]
        let tiles = screen(snapshot(mixed, standing: standing)).records
        #expect(tiles.map(\.title) == ["Longest night", "Best consistency", "Highest recovery"])
        #expect(tiles.map(\.tone) == [.sage, .lavender, .butter])
    }

    @Test func recordsOnlyShowUnderAllAndLongTerm() {
        let standing = [StandingRecord(type: .recordLongestNight, night: last, value: 512, nightsInWindow: 60)]
        let snap = snapshot(mixed, standing: standing)
        #expect(screen(snap).records.count == 1)
        #expect(screen(snap, filter: .longTerm).records.count == 1)
        #expect(screen(snap, filter: .sleep).records.isEmpty)
    }

    // MARK: - Learning

    @Test func learningHasThreeMilestonesWithProgress() throws {
        let content = screen(snapshot([], state: .learning(nightsSoFar: 4), nights: 4))
        let learning = try #require(content.learning)
        #expect(learning.title == "Insights unlock as we learn your nights")
        #expect(learning.detail == "4 nights recorded so far.")
        #expect(learning.rows.map(\.milestone) == [7, 14, 30])
        #expect(learning.rows.map(\.title) == ["Timing insights", "Patterns", "Trends"])
        // 4 of 7 = 5 of 10 dots; 4 of 14 = 2; 4 of 30 = 1.
        #expect(learning.rows.map(\.filled) == [5, 2, 1])
        #expect(learning.rows.allSatisfy { $0.dots == 10 && !$0.reached })
        #expect(learning.rows[0].accessibilityLabel == "Timing insights unlock at 7 nights. 4 of 7 nights.")
        #expect(content.chips.isEmpty, "no chips until there's something to filter")
        #expect(content.featured == nil && content.groups.isEmpty && content.records.isEmpty)
    }

    @Test func aReachedMilestoneIsFullAndUnlocked() {
        let learning = InsightsScreenBuilder.learning(nights: 9)
        #expect(learning.rows[0].reached && learning.rows[0].filled == 10)
        #expect(!learning.rows[1].reached)
        #expect(learning.rows[0].accessibilityLabel.hasSuffix("Unlocked."))
        #expect(InsightsScreenBuilder.learning(nights: 1).detail == "1 night recorded so far.")
    }

    // MARK: - States reuse the app's copy

    @Test func statesUseTheSameCopyAsHomeSleepAndRecovery() {
        #expect(
            screen(InsightsSnapshot.placeholder(.permissionRequired, now: now)).state
                == .connect(
                    title: "Your first night starts here.", message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true
                ))
        #expect(
            screen(InsightsSnapshot.placeholder(.healthDataUnavailable, now: now)).state
                == .connect(
                    title: "Your first night starts here.", message: "Apple Health isn't available on this device.", showsButton: false
                ))
        #expect(
            screen(InsightsSnapshot.placeholder(.empty, now: now)).state
                == .noSleepData(
                    title: "No sleep data yet",
                    message: "NOCTIS reads sleep from Apple Health. Track sleep with Apple Watch or set up Sleep in the Health app."
                ))
        #expect(screen(InsightsSnapshot.placeholder(.failed, now: now)).state == .failed(message: "We couldn't read your latest sleep data."))
        #expect(screen(InsightsSnapshot.placeholder(.learning(nightsSoFar: 0), now: now)).state != nil)
        for state in [HomeDataState.permissionRequired, .healthDataUnavailable, .empty, .failed] {
            let content = screen(InsightsSnapshot.placeholder(state, now: now))
            #expect(content.chips.isEmpty && content.featured == nil && content.learning == nil)
        }
    }

    @Test func aReadySnapshotHasNoState() {
        #expect(screen(snapshot(mixed)).state == nil)
    }

    // MARK: - The number count-up

    @Test func numbersCountUpFromZeroToThemselves() {
        let value = HomeFormat.durationMetric(5 * 60 + 50)
        #expect(value.counting(0).plain == "0h 0m")
        #expect(value.counting(1) == value)
        #expect(value.counting(0.5).plain == "3h 25m")
        #expect(value.counting(1).spoken == value.spoken)
        // A clock time doesn't count: it isn't a whole number.
        let clock = NoctisMetricValue(parts: [.number("11:55"), .unit("PM")], spoken: "11:55 PM")
        #expect(clock.counting(0) == clock)
        // Out of range clamps.
        #expect(value.counting(2) == value)
        #expect(value.counting(-1).plain == "0h 0m")
    }

    // MARK: - Through the repository

    @Test func theFullScenarioBuildsAWholeTab() async throws {
        let clock = now
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let repository = InsightsRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock })
        let snap = await repository.refresh(profile: UserProfileSnapshot())
        let content = screen(snap)
        let story = try #require(content.featured)
        #expect(!story.numbers.isEmpty)
        #expect(content.summary == "\(snap.newThisWeek) new this week")
        #expect(content.groups.flatMap(\.rows).count == snap.recent.count - 1, "everything but the featured story")
        for filter in InsightCategory.allCases {
            let filtered = screen(snap, filter: filter)
            #expect(filtered.groups.flatMap(\.rows).allSatisfy { $0.category == filter })
        }
    }
}

/// The view model: a filter moves the list, the day's reveal is once.
struct InsightsViewModelTests {
    private let now = Fixture.date(2026, 9, 24, 10)

    private func viewModel(
        _ scenario: MockScenario = .full, defaults: UserDefaults? = nil, reduceMotion: Bool = false, store: InsightStore = InsightStore()
    ) -> InsightsViewModel {
        let clock = now
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let repository = InsightsRepository(provider: provider, store: store, timeZone: Fixture.newYork, clock: { clock })
        let suite = defaults ?? UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)")!
        return InsightsViewModel(
            repository: repository, profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: suite, key: InsightsViewModel.introKey),
            washGate: HomeIntroGate(defaults: suite, key: InsightsViewModel.washKey),
            reduceMotion: { reduceMotion }, lowPower: { false }, clock: { clock }, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"),
            revealSleep: held
        )
    }

    @Test func nothingUntilTheFirstSnapshotThenTheScreen() async {
        let model = viewModel()
        #expect(model.screen == nil)
        await model.onAppear()
        #expect(model.screen?.featured != nil)
        #expect(model.snapshot?.dataState == .ready)
    }

    @Test func selectingAChipFiltersTheScreen() async {
        let model = viewModel()
        await model.onAppear()
        model.select(filter: .heart)
        #expect(model.filter == .heart)
        #expect(model.screen?.groups.flatMap(\.rows).allSatisfy { $0.category == .heart } == true)
        model.select(filter: nil)
        #expect(model.screen?.featured != nil)
    }

    @Test func dismissingRemovesItFromTheScreenAndKeepsItInTheSnapshotForHistory() async throws {
        let model = viewModel()
        await model.onAppear()
        let id = try #require(model.screen?.featured?.id)
        await model.dismiss(id: id)
        #expect(model.screen?.featured == nil)
        #expect(model.insight(id: id)?.state == .dismissed)
    }

    @Test func hidingATypeRemovesItAndItsStoredInsights() async throws {
        let model = viewModel()
        await model.onAppear()
        let stored = try #require(model.snapshot?.recent.first)
        await model.hide(stored.record.type)
        #expect(model.insight(id: stored.id) == nil)
        #expect(model.screen?.groups.flatMap(\.rows).contains { $0.id == stored.id } != true)
    }

    @Test func openingAnInsightMarksItSeen() async throws {
        let model = viewModel()
        await model.onAppear()
        let id = try #require(model.snapshot?.recent.first?.id)
        #expect(model.insight(id: id)?.state == .new)
        model.markSeen(id: id)
        // The write goes through the repository actor.
        #expect(await waitFor { model.insight(id: id)?.state == .seen })
    }

    @Test func theRevealPlaysOncePerDayAndNeverUnderReduceMotion() async {
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)")!
        let first = viewModel(defaults: defaults)
        await first.onAppear()
        #expect(first.reveal == .pending)
        first.beginReveal()
        #expect(first.reveal == .playing)
        first.skipReveal()
        #expect(first.reveal == .none)
        #expect(first.revealSkips == 1)
        let second = viewModel(defaults: defaults)
        await second.onAppear()
        #expect(second.reveal == .none, "today's reveal is used up")
        let reduced = viewModel(reduceMotion: true)
        await reduced.onAppear()
        #expect(reduced.reveal == .none)
    }

    @Test func theFieldWashesOncePerDay() {
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)")!
        let first = viewModel(defaults: defaults)
        #expect(first.fieldEntrance == .wash)
        first.fieldEntered()
        #expect(first.fieldEntrance == .none)
        #expect(viewModel(defaults: defaults).fieldEntrance == .fade)
    }

    @Test func aStateSnapshotHasNoRevealToPlay() async {
        let model = viewModel(.empty)
        await model.onAppear()
        #expect(model.screen?.state != nil)
        #expect(model.reveal == .none)
    }
}

/// The evidence charts, in unit space.
struct InsightChartDataTests {
    typealias R = InsightRecordFixture
    private let format = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))

    private func chart(_ record: InsightRecord) -> InsightChartData? {
        InsightChartBuilder.chart(for: record, format: format)
    }

    @Test func everyKindOfEvidenceHasAChartExceptAMilestone() {
        for record in R.everyVariant {
            if record.type == .milestone {
                #expect(chart(record) == nil)
            } else {
                #expect(chart(record) != nil, "\(record.type.rawValue)")
            }
        }
    }

    @Test func durationIsTwoBarsScaledToTheLonger() throws {
        guard case .bars(let bars)? = chart(R.duration(delta: -70)) else {
            Issue.record("expected bars")
            return
        }
        #expect(bars.bars.map(\.label) == ["Last night", "Usual"])
        #expect(bars.bars.map(\.valueText) == ["5h 50m", "7h"])
        #expect(bars.bars[1].fraction == 1)
        #expect(abs(bars.bars[0].fraction - 350.0 / 420) < 1e-9)
        #expect(bars.bars[0].emphasized && !bars.bars[1].emphasized)
    }

    @Test func balanceIsSevenNightsAgainstTheNeed() throws {
        guard case .bars(let bars)? = chart(R.balance(behind: true)) else {
            Issue.record("expected bars")
            return
        }
        #expect(bars.bars.count == 7)
        #expect(bars.reference?.label == "Need 8h")
        #expect(bars.bars.allSatisfy { $0.reachesReference == false }, "457 minutes is under 480")
        #expect(bars.bars.last?.emphasized == true)
        let position = try #require(bars.reference?.position)
        #expect(position > 0 && position < 1)
        guard case .bars(let ahead)? = chart(R.balance(behind: false)) else {
            Issue.record("expected bars")
            return
        }
        #expect(ahead.bars.allSatisfy { $0.reachesReference == true })
    }

    @Test func bedtimeIsATimelineWithTwoMarksAndAUsualBand() throws {
        guard case .timeline(let timeline)? = chart(R.bedtime(delta: 55)) else {
            Issue.record("expected a timeline")
            return
        }
        #expect(timeline.marks.map(\.label) == ["Usual", "Last night"])
        #expect(timeline.marks.map(\.timeText).map { $0.replacingOccurrences(of: "\u{202F}", with: " ") } == ["11:00 PM", "11:55 PM"])
        // The axis runs 10 PM to 1 AM: whole hours with half an hour of room either side.
        #expect(timeline.ticks.map(\.label).map { $0.replacingOccurrences(of: "\u{202F}", with: " ") } == ["10 PM", "11 PM", "12 AM", "1 AM"])
        #expect(timeline.marks.allSatisfy { (0...1).contains($0.position) })
        #expect(timeline.marks[1].position > timeline.marks[0].position)
        #expect(timeline.band.lowerBound < timeline.marks[0].position && timeline.marks[0].position < timeline.band.upperBound)
        #expect(timeline.bandLabel == "Usual ± 30 min")
    }

    @Test func aStreakIsFourteenDots() throws {
        guard case .dots(let dots)? = chart(R.streak(nights: 6)) else {
            Issue.record("expected dots")
            return
        }
        #expect(dots.dots.count == 14)
        #expect(dots.dots.suffix(6).allSatisfy { $0.within == true })
        #expect(dots.dots.first?.within == false)
        #expect(dots.caption == "Last 14 nights")
    }

    @Test func thePatternIsTwoColumnsWithMeansAndSampleSizes() throws {
        guard case .groups(let groups)? = chart(R.pattern(earlier: true, early: 16, late: 17)) else {
            Issue.record("expected groups")
            return
        }
        #expect(groups.groups.map(\.label) == ["Earlier nights", "Later nights"])
        #expect(groups.groups.map(\.countText) == ["16 nights", "17 nights"])
        #expect(groups.groups.map(\.meanText) == ["Average 92", "Average 66"])
        #expect(groups.groups.map(\.dots.count) == [16, 17])
        #expect(groups.groups[0].meanY > groups.groups[1].meanY)
        for group in groups.groups {
            #expect(group.dots.allSatisfy { (0.15...0.85).contains($0.x) && (0...1).contains($0.y) })
        }
        // The same every time.
        #expect(chart(R.pattern(earlier: true, early: 16, late: 17)) == chart(R.pattern(earlier: true, early: 16, late: 17)))
    }

    @Test func heartIsALineWithItsNormalRange() throws {
        let record = R.record(
            .hrvBelowRange,
            .heartSignal(
                HeartSignalEvidence(
                    night: R.night, signal: .hrv, consecutiveNights: 3, value: 41, baseline: 52, rangeLow: 47, rangeHigh: 57, baselineNights: 14,
                    recentValues: [52, 51, nil, 53, 50, 52, 54, 51, 52, 50, 44, 42, 41, 41]
                )), confidence: .moderate)
        guard case .line(let line)? = chart(record) else {
            Issue.record("expected a line")
            return
        }
        #expect(line.segments.count == 2, "the missing night breaks the line")
        #expect(line.band != nil && line.bandLabel == "Normal range")
        #expect(line.latest?.valueText == "41 ms")
        #expect(line.rolling.count > 5)
        #expect(line.rollingLabel == "3-night average")
        let band = try #require(line.band)
        #expect(band.lowerBound < band.upperBound && (0...1).contains(band.lowerBound) && (0...1).contains(band.upperBound))
        #expect(line.xTicks.count == 3)
    }

    @Test func aRollingAverageStartsWhenHalfAWindowIsThere() {
        let series: [Double?] = [10, nil, nil, 20, 30, 40]
        let points = InsightChartBuilder.rolling(series, window: 3, y: { $0 / 100 }, text: { "\(Int($0))" })
        // Index 0: one of three present: under half. Index 3: 20 alone in its window of [nil, nil, 20]: 1 of 3.
        // Index 4: [nil, 20, 30] = 25; index 5: [20, 30, 40] = 30.
        #expect(points.map(\.valueText) == ["25", "30"])
    }

    @Test func recordsCompareNowAgainstThePreviousBest() throws {
        guard case .bars(let bars)? = chart(R.standingRecord(.recordLongestNight)) else {
            Issue.record("expected bars")
            return
        }
        #expect(bars.bars.map(\.label) == ["Now", "Previous best"])
        #expect(bars.bars.map(\.valueText) == ["8h 30m", "8h 12m"])
        guard case .bars(let low)? = chart(R.standingRecord(.recordLowestRestingHeartRate)) else {
            Issue.record("expected bars")
            return
        }
        #expect(low.bars.map(\.valueText) == ["49 bpm", "51 bpm"])
    }
}
