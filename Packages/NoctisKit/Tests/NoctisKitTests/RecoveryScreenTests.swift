import Foundation
import Testing
@testable import DesignSystem
@testable import HealthProviding
@testable import HomeFeature
@testable import NoctisCore
@testable import RecoveryFeature
@testable import RecoveryKit
@testable import SleepKit

// The Recovery tab's wording and view model: the stacked bar's rows, the
// confidence card, the states, and the language rules. Numbers are the
// engines'; these pin how they're said.

private let now = Fixture.date(2026, 9, 24, 10)
private let locale = Locale(identifier: "en_US")

private func snapshot(_ scenario: MockScenario) async -> RecoverySnapshot {
    let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
    let clock = now
    return await RecoveryRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
}

private func screen(_ snap: RecoverySnapshot, segment: RecoverySegment = .today) -> RecoveryScreenContent {
    let selection = RecoverySelection(segment: segment)
    let model = RecoveryRenderModelBuilder.build(snap, selection: selection)
    return RecoveryScreenBuilder.build(snap, model: model, selection: selection, now: now, calendar: Fixture.calendar(), locale: locale)
}

struct RecoveryTodayContentTests {
    @Test func theBarHasARowPerFactorWithWholePointsThatAddUpToTheTotal() async throws {
        let snap = await snapshot(.full)
        let today = try #require(screen(snap).today)
        let build = today.build
        #expect(build.title == "How today's score was built")
        #expect(build.rows.map(\.name) == ["Sleep", "HRV", "Resting HR", "Consistency"])
        #expect(build.rows.allSatisfy { $0.pointsText.hasPrefix("+") })
        let points = build.rows.compactMap { Int($0.pointsText.dropFirst()) }
        #expect(points.reduce(0, +) == snap.contributions?.score, "the rows add up to the score shown")
        #expect(build.totalText == "= \(snap.contributions?.score ?? -1)")
        #expect(build.capNote == nil)
        // Each row sits where its segment does on the 100-point bar.
        var start = 0.0
        for row in build.rows {
            #expect(abs(row.start - start) < 1e-9)
            #expect(abs(row.width * 100 - Double(row.pointsText.dropFirst())!) < 1)
            start += row.width
        }
    }

    @Test func eachRowSaysHowFarFromUsualInPointsWithARealMinusSign() async throws {
        let snap = await snapshot(.full)
        let build = try #require(screen(snap).today?.build)
        for row in build.rows {
            let text = try #require(row.usualText)
            #expect(text.hasPrefix("vs usual: "))
            let number = text.dropFirst("vs usual: ".count)
            #expect(number.first == "+" || number.first == "\u{2212}" || number == "±0", "\(text)")
            #expect(!text.contains("-"))
        }
        #expect(build.accessibilityLabel.hasPrefix("How today's score was built: Sleep,"))
    }

    @Test func theCapRowNamesTheCapAndTheReason() throws {
        var history = Fixture.metrics(count: 19, endingOn: SleepNightKey(year: 2026, month: 9, day: 22)) { _ in (asleep: 480, bedtime: 660, wake: 1140, hrv: 50, resting: 55) }
        history.append(NightMetrics(night: SleepNightKey(year: 2026, month: 9, day: 23), wakeTime: Fixture.date(2026, 9, 24, 7), asleepMinutes: 480, bedtimeMinutes: 660, wakeMinutes: 1140, hrv: 40, restingHeartRate: 62))
        guard case .scored(let result) = RecoveryEngine.evaluate(history: history, needMinutes: 480, asOf: now) else { throw TestFailure() }
        let build = RecoveryScreenBuilder.build(RecoveryContributionEngine.contributions(for: result), render: nil)
        #expect(build.capNote == "Capped at 50: your heart rate and HRV are both well outside your normal range.")
        #expect(build.totalText == "= 50")
        #expect(build.accessibilityLabel.contains("Capped at 50"))
        // The rows still add up to what the score would have been.
        #expect(build.rows.compactMap { Int($0.pointsText.dropFirst()) }.reduce(0, +) > 50)
    }

    @Test func aCardPerScoredFactorWithHomesWording() async throws {
        let snap = await snapshot(.full)
        let today = try #require(screen(snap).today)
        #expect(today.factors.map(\.name) == ["Sleep", "HRV", "Resting HR", "Consistency"])
        #expect(today.factors.allSatisfy { $0.baseline.hasPrefix("baseline ") || $0.baseline.hasPrefix("usual ") })
        #expect(today.factors.allSatisfy { $0.sparkline != nil }, "a 14-night line with the normal range")
        #expect(today.factors.first { $0.kind == .hrv }?.value.plain.hasSuffix("ms") == true)
        #expect(today.scored.score == snap.result?.score)
        #expect(today.modelVersion == "Model recovery-v3")
        #expect(today.calculation.joined(separator: " ").contains("capped at 50"))
    }
}

struct RecoveryConfidenceContentTests {
    @Test func aFullFortnightIsHighWithNothingMissingAndNoNextStep() async throws {
        let content = try #require(screen(await snapshot(.full)).today?.confidence)
        #expect(content.tier == "High confidence")
        #expect(content.sentence == "Every signal was recorded, and today is compared with 14 nights of your own.")
        #expect(content.checklist.map(\.isUsed) == [true, true, true, true])
        #expect(content.checklist.allSatisfy { $0.reason == nil })
        #expect(content.basedOn == "Based on 14 nights")
        #expect(content.nextStep == nil)
    }

    @Test func aSleepOnlyScoreExplainsWhyItIsLowAndWhatWouldAddTheRest() async throws {
        let content = try #require(screen(await snapshot(.sleepOnly)).today?.confidence)
        #expect(content.tier == "Low confidence")
        #expect(content.sentence == "Built on 2 of 4 signals and 14 nights of your own, so it's a rough guide for now.")
        #expect(content.checklist.map(\.name) == ["Sleep", "HRV", "Resting HR", "Consistency"])
        #expect(content.checklist.map(\.isUsed) == [true, false, false, true])
        #expect(content.checklist[1].reason == "Not available from your sources")
        #expect(content.nextStep == "Wear your Apple Watch to sleep to add HRV and resting heart rate.")
        #expect(content.accessibilityLabel.contains("HRV missing: Not available from your sources"))
    }

    @Test func eachNextStepIsWordedFromItsFactsAlone() {
        #expect(RecoveryScreenBuilder.nextStep(.recordAgain(factors: [.hrv])) == "HRV wasn't recorded last night. Wearing your Apple Watch to sleep tonight would bring it back.")
        #expect(RecoveryScreenBuilder.nextStep(.recordAgain(factors: [.hrv, .restingHeartRate])) == "HRV and resting heart rate weren't recorded last night. Wearing your Apple Watch to sleep tonight would bring them back.")
        #expect(RecoveryScreenBuilder.nextStep(.keepTracking(nightsNeeded: 2)) == "2 more nights of tracking and the baselines that are still forming will be ready.")
        #expect(RecoveryScreenBuilder.nextStep(.keepTracking(nightsNeeded: 1)) == "1 more night of tracking and the baselines that are still forming will be ready.")
        #expect(RecoveryScreenBuilder.nextStep(.wearWatchToSleep(adding: [.hrv])) == "Wear your Apple Watch to sleep to add HRV.")
        #expect(RecoveryScreenBuilder.nextStep(.reachHigh(nightsNeeded: 5)) == "5 more nights and this reaches high confidence.")
    }

    @Test func eachMissingReasonHasItsOwnWords() {
        #expect(RecoveryScreenBuilder.reason(.unavailable) == "Not available from your sources")
        #expect(RecoveryScreenBuilder.reason(.notRecorded) == "Not recorded last night")
        #expect(RecoveryScreenBuilder.reason(.buildingBaseline) == "Baseline still forming")
    }
}

struct RecoveryStatesTests {
    @Test func everyDataStateHasHomesAndSleepsCopy() {
        func state(_ value: HomeDataState) -> RecoveryStateContent? { RecoveryScreenBuilder.stateContent(value) }
        #expect(state(.healthDataUnavailable) == .connect(title: "Your first night starts here.", message: "Apple Health isn't available on this device.", showsButton: false))
        #expect(state(.permissionRequired) == .connect(title: "Your first night starts here.", message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true))
        #expect(state(.empty) == .noSleepData(
            title: "No sleep data yet",
            message: "NOCTIS reads sleep from Apple Health. Track sleep with Apple Watch or set up Sleep in the Health app."
        ))
        #expect(state(.failed) == .failed(message: "We couldn't read your latest sleep data."))
        #expect(state(.ready) == nil && state(.noSleepLastNight) == nil && state(.learning(nightsSoFar: 3)) == nil)
        #expect(state(.stale(newestSample: now)) == nil, "stale still shows the nights, under a banner")
    }

    @Test func learningAndNoSleepLastNightHaveTheirOwnContent() async throws {
        let learning = screen(await snapshot(.learning))
        #expect(learning.learning == RecoveryLearningContent(nights: 3, required: 5, text: "3 of 5 nights"))
        #expect(learning.today == nil && learning.state == nil)
        let gap = screen(await snapshot(.gap))
        #expect(gap.noSleep?.title == "No sleep recorded last night.")
        #expect(gap.noSleep?.detail?.hasPrefix("Last recorded night ended ") == true)
        #expect(gap.today == nil)
        #expect(gap.noSleep?.opensHealth == false, "Health is in sync; there's nothing to open it for")
    }

    @Test func aStaleSnapshotSaysHealthHasntUpdatedInsteadOfClaimingNoSleep() async throws {
        let stale = screen(await snapshot(.stale))
        #expect(stale.today == nil)
        let message = try #require(stale.noSleep)
        #expect(message.title.hasPrefix("Apple Health hasn't updated since "))
        #expect(message.detail == "Open Health or pull to refresh.")
        #expect(message.opensHealth, "the message says to open Health, so it offers to")
        #expect(stale.banner == nil, "said once")
        #expect(!message.title.contains("No sleep"))
    }

    @Test func noPermissionNoDataAndFailureShowTheirStateAndNoScore() async {
        let empty = screen(await snapshot(.empty))
        #expect(empty.state != nil && empty.today == nil && empty.learning == nil)
    }
}

struct RecoveryLanguageTests {
    private static let forbidden = [
        "poor", "bad", "should rest", "you should", "you are recovered", "you're recovered", "you need to rest", "warning",
        "danger", "unhealthy", "worry", "alarm", "diagnos", "debt",
    ]

    @Test func nothingOnTheScreenJudgesANightOrAdvisesRest() async {
        for scenario in [MockScenario.full, .sleepOnly, .recoveryDip, .learning, .gap, .stale, .lateBedtime, .messyNight] {
            let snap = await snapshot(scenario)
            for segment in RecoverySegment.allCases {
                let text = String(describing: screen(snap, segment: segment)).lowercased()
                for word in Self.forbidden {
                    #expect(!text.contains(word), "\(scenario) \(segment): \"\(word)\"")
                }
            }
        }
    }

    @Test func aboveWithinAndBelowAreTheWordsForWhereAValueSits() async throws {
        let text = try #require(screen(await snapshot(.full)).today?.factors.map(\.sentence).joined(separator: " "))
        #expect(text.contains("Within your normal range") || text.contains("Above your normal range") || text.contains("Below your normal range"))
    }
}

@MainActor
struct RecoveryViewModelTests {
    private func model(scenario: MockScenario = .full, defaults: UserDefaults? = nil, reduceMotion: Bool = false) -> RecoveryViewModel {
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let time = now
        return RecoveryViewModel(
            repository: RecoveryRepository(provider: provider, timeZone: Fixture.newYork, clock: { time }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: defaults ?? UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard, key: RecoveryViewModel.introKey),
            reduceMotion: { reduceMotion }, lowPower: { false }, clock: { now }, calendar: Fixture.calendar(), locale: locale
        )
    }

    @Test func itStartsEmptyThenShowsTodaysScore() async throws {
        let model = model()
        #expect(model.screen == nil)
        await model.refresh()
        let today = try #require(model.screen?.today)
        #expect(today.scored.score == model.snapshot?.result?.score)
        #expect(model.selection == RecoverySelection())
    }

    @Test func choosingASegmentMovesTheSelectionAtOnceAndTheContentFollows() async throws {
        let model = model()
        await model.refresh()
        model.select(segment: .month)
        #expect(model.selection.segment == .month)
        _ = await waitFor { !(model.screen?.segment != .month) }
        #expect(model.screen?.segment == .month && model.screen?.today == nil)
        #expect(model.model?.chart != nil)
    }

    @Test func aFactorsDetailIsASelectionOnTheSameViewModel() async throws {
        let model = model()
        await model.refresh()
        model.select(factor: .hrv, range: .month)
        _ = await waitFor { !(model.model?.factor == nil) }
        #expect(model.model?.factor?.kind == .hrv && model.model?.factor?.values.count == 30)
        // The screen behind it is still Today.
        #expect(model.screen?.today != nil)
    }

    @Test func aDeepLinkBeforeTheFirstSnapshotStillLandsOnItsSegment() async throws {
        let model = model()
        model.open(segment: .week)
        await model.refresh()
        _ = await waitFor { !(model.screen?.segment != .week) }
        #expect(model.screen?.segment == .week)
    }

    @Test func theRevealPlaysOncePerDayOnTheFirstTodayOnScreenAndReduceMotionUsesTheDay() async throws {
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard
        let first = model(defaults: defaults)
        await first.onAppear()
        #expect(first.reveal == .pending)
        first.beginReveal()
        #expect(first.reveal == .playing && first.revealPlayed)
        first.skipReveal()
        #expect(first.reveal == .none)
        first.stopObserving()
        let second = model(defaults: defaults)
        await second.onAppear()
        #expect(second.reveal == .none, "the day was used")
        second.stopObserving()
        let reduced = model(defaults: UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard, reduceMotion: true)
        await reduced.onAppear()
        #expect(reduced.reveal == .none)
        reduced.stopObserving()
    }

    @Test func aTabThatIsntOnScreenHasNoRevealYet() async {
        let model = model()
        await model.refresh()
        #expect(model.reveal == .none)
    }

    @Test func theTabsOwnGateKeyIsSeparateFromHomesAndSleeps() {
        #expect(RecoveryViewModel.introKey == "noctis.recovery.lastIntroDay")
        #expect(RecoveryViewModel.introKey != HomeIntroGate.defaultsKey)
        #expect(RecoveryViewModel.introKey != "noctis.sleep.lastIntroDay")
    }

    @Test func learningAndEmptyScenariosBuildTheirStates() async {
        let learning = model(scenario: .learning)
        await learning.refresh()
        #expect(learning.screen?.learning != nil)
        let empty = model(scenario: .empty)
        await empty.refresh()
        #expect(empty.screen?.state != nil)
    }
}


private struct TestFailure: Error {}

struct RecoveryHistoryContentTests {
    private func history(_ snap: RecoverySnapshot, _ segment: RecoverySegment) throws -> RecoveryHistoryContent {
        try #require(screen(snap, segment: segment).history)
    }

    @Test func aRangeHasADayPerColumnAndAPillThatSaysWhatTheDayWas() async throws {
        let snap = await snapshot(.full)
        for (segment, days) in [(RecoverySegment.week, 7), (.month, 30), (.quarter, 90)] {
            let content = try history(snap, segment)
            #expect(content.points.count == days)
            #expect(content.points.map(\.night) == snap.history(segment.historyRange ?? .week)?.days.map(\.night))
        }
        let week = try history(snap, .week)
        let last = try #require(snap.scores.last)
        let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
        let weekday = format.weekday(last.night.adding(days: 1), width: .abbreviated)
        #expect(week.points.last?.detail == "\(weekday) · Recovery \(last.score) · Sleep \(HomeFormat.compactDuration(Int(last.asleepMinutes.rounded())))")
        #expect(week.points.last?.accessibilityLabel.hasPrefix(format.wideDate(last.night.adding(days: 1))) == true)
        // A longer range names the date.
        #expect(try history(snap, .month).points.last?.detail.hasPrefix("\(format.weekdayMonthDay(last.night.adding(days: 1))) · Recovery") == true)
    }

    @Test func theAxesAndTheLineStyleFollowTheRange() async throws {
        let snap = await snapshot(.full)
        let week = try history(snap, .week)
        #expect(week.yLabels.map(\.text) == ["100", "75", "50", "25", "0"])
        #expect(week.yLabels.map(\.position) == [0, 0.25, 0.5, 0.75, 1])
        #expect(week.xLabels.count == 7, "a weekday initial under each day")
        #expect(week.showsDots && !week.isSmoothed)
        let month = try history(snap, .month)
        #expect(month.xLabels.count == 3 && !month.showsDots && !month.isSmoothed)
        let quarter = try history(snap, .quarter)
        #expect(quarter.isSmoothed && !quarter.showsDots)
        #expect(quarter.caption.contains(" – ") && quarter.caption == quarter.caption.uppercased())
    }

    @Test func aTileForEachStatWithTheEnginesNumbers() async throws {
        let snap = await snapshot(.full)
        let month = try #require(snap.history(.month))
        let stats = month.stats
        let content = try history(snap, .month)
        #expect(content.tiles.map(\.id) == ["current", "average", "baseline", "high", "low", "trend"])
        func tile(_ id: String) throws -> RecoveryHistoryTile { try #require(content.tiles.first { $0.id == id }) }
        #expect(try tile("current").value.plain == "\(stats.current?.score ?? -1)")
        #expect(try tile("average").value.plain == "\(Int((stats.average ?? 0).rounded()))")
        #expect(try tile("baseline").value.plain == "\(Int((stats.baseline?.value ?? 0).rounded()))")
        #expect(try tile("baseline").note == "last 14 nights")
        #expect(try tile("high").value.plain == "\(stats.high?.score ?? -1)")
        #expect(try tile("low").value.plain == "\(stats.low?.score ?? -1)")
        let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
        #expect(try tile("high").note == format.shortDate(try #require(stats.high?.date)))
        #expect(try tile("average").note == "30 nights")
    }

    @Test func theTrendIsADirectionWithAnArrowAndANumberPerWeekNeverAWarning() {
        let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
        func trendTile(_ direction: RecoveryTrendDirection, _ slope: Double) -> RecoveryHistoryTile? {
            var stats = RecoveryHistoryEngine.emptyStats
            stats = RecoveryHistoryStats(
                current: nil, average: nil, baseline: nil, usualRange: nil, daysInUsualRange: nil, high: nil, low: nil,
                trend: RecoveryHistoryTrend(direction: direction, pointsPerWeek: slope), scoredDays: 7
            )
            return RecoveryScreenBuilder.historyTiles(stats, format: format).first { $0.id == "trend" }
        }
        let rising = trendTile(.rising, 2.14)
        #expect(rising?.value.plain == "+2.1 / wk" && rising?.note == "Rising" && rising?.symbol == "arrow.up.right")
        let steady = trendTile(.steady, -0.44)
        #expect(steady?.value.plain == "\u{2212}0.4 / wk" && steady?.note == "Steady" && steady?.symbol == "arrow.right")
        let lower = trendTile(.lower, -3.06)
        #expect(lower?.value.plain == "\u{2212}3.1 / wk" && lower?.note == "Lower than earlier" && lower?.symbol == "arrow.down.right")
        #expect(lower?.accessibilityLabel == "Trend: Lower than earlier, minus 3.1 points a week")
        #expect(RecoveryScreenBuilder.signedSlope(0.04) == "0.0" && RecoveryScreenBuilder.signedSlope(-0.04) == "0.0")
        #expect(RecoveryScreenBuilder.signedSlope(12) == "+12.0")
    }

    @Test func aStatWithNoValueIsNoTileNotADash() {
        let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
        let stats = RecoveryHistoryStats(current: nil, average: 80, baseline: nil, usualRange: nil, daysInUsualRange: nil, high: nil, low: nil, trend: nil, scoredDays: 3)
        #expect(RecoveryScreenBuilder.historyTiles(stats, format: format).map(\.id) == ["average"])
    }

    @Test func daysInTheUsualRangeAreCountedAndWorded() async throws {
        let snap = await snapshot(.full)
        let stats = try #require(snap.history(.week)?.stats)
        let content = try history(snap, .week)
        #expect(content.usualLine == "In your usual range on \(stats.daysInUsualRange ?? -1) of 7 days.")
        #expect(content.bandCaption?.hasPrefix("The shaded band is your usual range: ") == true)
    }

    @Test func aFactorRowPerFactorWithItsAverageOverTheRange() async throws {
        let snap = await snapshot(.full)
        let week = try history(snap, .week)
        #expect(week.factorRows.map(\.name) == ["Sleep", "HRV", "Resting HR", "Consistency"])
        #expect(week.factorRows.map(\.factorRange) == Array(repeating: .fortnight, count: 4), "7D opens the 14-night page")
        let series = try #require(snap.series(.hrv, .fortnight))
        let last7 = series.points.suffix(7).compactMap(\.value)
        let mean = last7.reduce(0, +) / Double(last7.count)
        #expect(week.factorRows[1].average?.plain == "\(Int(mean.rounded()))ms")
        #expect(try history(snap, .month).factorRows.first?.factorRange == .month)
        #expect(try history(snap, .quarter).factorRows.first?.factorRange == .quarter)
        #expect(week.factorRows[1].accessibilityLabel.hasPrefix("HRV, average "))
    }

    @Test func aHistoryShorterThanTheRangeDrawsWhatExistsAndSaysHowMany() async throws {
        let provider = MockHealthKitProvider(scenario: .full, historyDays: 12, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let clock = now
        let snap = await RecoveryRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        let month = try history(snap, .month)
        #expect(month.points.count == 8 && month.partialNote == "Showing 8 nights")
        #expect(try history(snap, .week).partialNote == nil)
    }

    @Test func underFiveScoredNightsIsTheLearningDotsNotAChart() async throws {
        let provider = MockHealthKitProvider(scenario: .full, historyDays: 8, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let clock = now
        let snap = await RecoveryRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        let content = screen(snap, segment: .month)
        #expect(content.history == nil)
        #expect(content.learning == RecoveryLearningContent(nights: 4, required: 5, text: "4 of 5 nights"))
    }

    @Test func everyRangeSaysTheSameNightsTodayDoesWhileTheBaselineForms() async throws {
        let learning = await snapshot(.learning)
        let today = screen(learning, segment: .today).learning
        #expect(today == RecoveryLearningContent(nights: 3, required: 5, text: "3 of 5 nights"))
        for segment in [RecoverySegment.week, .month, .quarter] {
            let content = screen(learning, segment: segment)
            #expect(content.history == nil)
            #expect(content.learning == today, "\(segment)")
        }
    }

    @Test func eachScoreDotSaysWhereItSitsAgainstTheUsualRange() async throws {
        let usual = 82.0...94.0
        #expect(RecoveryUsualPosition(score: 96, usual: usual) == .above)
        #expect(RecoveryUsualPosition(score: 94, usual: usual) == .within, "the edge is within")
        #expect(RecoveryUsualPosition(score: 82, usual: usual) == .within)
        #expect(RecoveryUsualPosition(score: 81, usual: usual) == .below)
        #expect([RecoveryUsualPosition.above, .within, .below].map(\.word) == ["Above", "Within", "Below"])
        // In the history, a day agrees with the count of days "in your usual range".
        let history = screen(await snapshot(.full), segment: .month).history
        let content = try #require(history)
        let within = content.points.filter { $0.position == .within }.count
        #expect(content.usualLine == "In your usual range on \(within) of \(content.points.filter { $0.position != nil }.count) days.")
        #expect(content.points.allSatisfy { $0.position != nil })
    }

    @Test func todayCarriesTheHighestInThirtyDaysMarkOnlyWhenTheEngineSaysSo() async throws {
        let today = try #require(screen(await snapshot(.full)).today)
        let snap = await snapshot(.full)
        let days = try #require(snap.history(.month)).days
        let engine = RecoveryHighlightEngine.highlight(days: days)
        #expect((today.highlight == "Highest in 30 days") == (engine == .highestIn30Days))
        // The mock's last night is a shorter one: not its highest.
        #expect(today.highlight == nil)
    }

    @Test func theHighsScenarioEarnsTheHighestInThirtyDays() async throws {
        let snap = await snapshot(.highs)
        let today = try #require(screen(snap).today)
        #expect(today.highlight == "Highest in 30 days")
        // The month's history agrees: today is its high, and no other day has that score.
        let history = try #require(snap.history(.month))
        #expect(history.stats.high?.score == today.scored.score)
        #expect(history.days.compactMap(\.score).filter { $0.score == today.scored.score }.count == 1)
    }

    @Test func aGapNightStillHasItsHistoryThoughNoScoreToday() async throws {
        let gap = screen(await snapshot(.gap), segment: .week)
        #expect(gap.history != nil && gap.noSleep == nil && gap.today == nil)
    }

    @Test func aStaleSnapshotShowsItsHistoryUnderABanner() async throws {
        let stale = screen(await snapshot(.stale), segment: .month)
        #expect(stale.history != nil)
        #expect(stale.banner?.detail == "Open Health or pull to refresh.")
    }
}
