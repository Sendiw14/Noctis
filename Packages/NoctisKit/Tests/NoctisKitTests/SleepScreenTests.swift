import Foundation
import Testing
@testable import DesignSystem
@testable import HealthProviding
@testable import HomeFeature
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepFeature
@testable import SleepKit

// The Sleep tab's presentation: wording, the picker, the details grid and
// the view model that drives them.

private nonisolated let now: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 10)) ?? Date()
}()

private let locale = Locale(identifier: "en_US")

private func snapshot(_ scenario: MockScenario) async -> SleepSnapshot {
    let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
    return await SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
}

private func screen(_ snap: SleepSnapshot, night: SleepNightKey? = nil, range: SleepRange = .day) -> SleepScreen {
    let selection = SleepSelection(night: night ?? snap.defaultNight, range: range)
    let model = SleepRenderModelBuilder.build(snap, selection: selection)
    return SleepScreenBuilder.build(snap, model: model, selection: selection, now: now, calendar: Fixture.calendar(), locale: locale)
}

/// A snapshot built from `samples` (no Health data beyond sleep).
private func snapshot(samples: [RawSleepSample]) -> SleepSnapshot {
    SleepSnapshotBuilder.build(
        HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: []),
        profile: UserProfileSnapshot(), now: Fixture.date(2026, 9, 24, 10), timeZone: Fixture.newYork
    )
}

struct SleepDayContentTests {
    @Test func theHeroSaysHowLongWhenAndTheCaptionNamesLastNight() async throws {
        let snap = await snapshot(.full)
        let day = try #require(screen(snap).day)
        let record = try #require(snap.record(snap.defaultNight))
        #expect(day.caption == "LAST NIGHT")
        #expect(day.minutes == Int(record.metrics.asleepMinutes.rounded()))
        #expect(day.duration.spoken == HomeFormat.spokenDuration(day.minutes))
        #expect(day.timeRange.contains(" – "))
        #expect(day.accessibilityLabel.hasPrefix("Last Night, slept"))
        // An earlier night carries its date instead.
        let earlier = snap.records[snap.records.count - 4].night
        #expect(try #require(screen(snap, night: earlier).day).caption != "LAST NIGHT")
    }

    @Test func theQualityRingCarriesTheScoreAndTheTypicalTick() async throws {
        let snap = await snapshot(.full)
        let day = try #require(screen(snap).day)
        let record = try #require(snap.record(snap.defaultNight))
        let ring = try #require(day.ring)
        #expect(ring.score == record.quality.score)
        #expect(ring.fraction == Double(record.quality.score) / 100)
        #expect(ring.typicalText == record.quality.usual.map { "typical \(Int($0.rounded()))" })
        #expect(ring.arc.tickDegrees != nil)
        #expect(ring.accessibilityLabel.hasPrefix("Sleep quality \(record.quality.score), typical"))
    }

    @Test func theStageRowsAreLaneOrderedWithSharesAndUsualBars() async throws {
        let day = try #require(screen(await snapshot(.full)).day)
        let stages = try #require(day.stages)
        #expect(stages.rows.map(\.name) == ["Awake", "REM", "Core", "Deep"])
        #expect(stages.rows.allSatisfy { $0.shareText.hasSuffix("%") })
        #expect(stages.rows.allSatisfy { $0.usualText?.hasPrefix("usual ") == true }, "a 14-night baseline exists")
        #expect(stages.rows[3].accessibilityLabel.hasPrefix("Deep "))
    }

    @Test func theQualityCardHasFourFactorBarsAWhatChangedLineAndTheModelName() async throws {
        let day = try #require(screen(await snapshot(.full)).day)
        let card = try #require(day.quality)
        #expect(card.factors.map(\.name) == ["Duration", "Continuity", "Consistency", "Stages"])
        #expect(card.factors.allSatisfy { !$0.sentence.isEmpty && (0...1).contains($0.fraction) })
        #expect(!card.whatChanged.isEmpty)
        #expect(card.modelVersion == "Model sleep-quality-v1")
        #expect(card.calculation.count == 3)
        #expect(card.confidence.contains("confidence"))
    }

    @Test func detailTilesAreOmittedNotDashedWhenAValueIsMissing() {
        // Stages only, no awake stage and no in-bed record: no efficiency, awakenings or time awake.
        let bare = SleepFixture.night(SleepNightKey(year: 2026, month: 9, day: 23), blocks: [(.core, 250), (.deep, 80), (.rem, 100)])
        let day = screen(snapshot(samples: bare)).day
        let tiles = day?.details.map(\.id)
        #expect(tiles == ["inBed", "bedtime", "wake"])
        #expect(day?.details.allSatisfy { !$0.value.parts.isEmpty } == true)
        // With an in-bed record and awake time: all six.
        let full = SleepFixture.night(SleepNightKey(year: 2026, month: 9, day: 23), blocks: [(.awake, 8), (.core, 250), (.awake, 12), (.deep, 80), (.rem, 100)], inBed: true)
        #expect(screen(snapshot(samples: full)).day?.details.map(\.id) == ["inBed", "efficiency", "bedtime", "wake", "awakenings", "awake"])
    }

    @Test func detailValuesAreTheEnginesNumbers() async throws {
        let snap = await snapshot(.full)
        let day = try #require(screen(snap).day)
        let record = try #require(snap.record(snap.defaultNight))
        let tiles = Dictionary(uniqueKeysWithValues: day.details.map { ($0.id, $0) })
        #expect(tiles["inBed"]?.value.spoken == HomeFormat.spokenDuration(Int(record.metrics.timeInBedMinutes.rounded())))
        #expect(tiles["awakenings"]?.value.spoken.hasPrefix("\(record.metrics.awakenings) awakening") == true)
        #expect(tiles["awake"]?.note == "after falling asleep")
        if let efficiency = record.metrics.efficiency {
            #expect(tiles["efficiency"]?.value.spoken == "\(Int((efficiency * 100).rounded())) percent")
        }
    }

    @Test func aNightWithoutStagesShowsTheSingleBarVariantAndDropsStageRows() throws {
        // Six unstaged nights, so the tab is out of its learning state.
        let last = SleepNightKey(year: 2026, month: 9, day: 23)
        let unstaged = (0..<6).flatMap { index in
            SleepFixture.night(last.adding(days: index - 5), blocks: [(.unspecified, 420)], inBed: true)
        }
        let day = try #require(screen(snapshot(samples: unstaged)).day)
        #expect(day.chart.caption == "Stages aren't available from your current sources.")
        #expect(!day.chart.hasStages)
        #expect(day.stages == nil)
        // Quality still exists, without the stage factor.
        let card = try #require(day.quality)
        #expect(!card.factors.map(\.name).contains("Stages"))
        #expect(card.omitted.contains { $0.hasPrefix("Stages aren't counted") })
    }

    @Test func aLearningStateSwapsTheRingForDotsAndDropsTheQualityCard() async throws {
        let day = try #require(screen(await snapshot(.learning)).day)
        #expect(day.learning?.nights == 3)
        #expect(day.learning?.text == "3 of 5 nights")
        #expect(day.ring == nil && day.quality == nil)
        #expect(day.stages != nil && !day.details.isEmpty, "the facts of the night remain")
    }

    @Test func sleepOnlyHasAPanelWithoutHeartRate() async throws {
        let day = try #require(screen(await snapshot(.sleepOnly)).day)
        #expect(day.chart.heart == nil)
        #expect(day.chart.hasStages)
    }

    @Test func theMessyNightKeepsItsEightPlusRuns() async throws {
        let day = try #require(screen(await snapshot(.messyNight)).day)
        #expect(day.chart.spans.filter { $0.stage == .awake }.count == 11)
    }
}

struct SleepPickerTests {
    @Test func fourteenNightsOldestFirstEndingOnTheDefaultNight() async throws {
        let snap = await snapshot(.full)
        let picker = screen(snap).picker
        #expect(picker.count == 14)
        #expect(picker.last?.night == snap.defaultNight)
        #expect(picker.map(\.night) == picker.map(\.night).sorted())
        #expect(picker.allSatisfy { $0.hasData })
        #expect(picker.allSatisfy { $0.initial.count == 1 && Int($0.day) != nil })
        #expect(picker.last?.accessibilityLabel.contains("slept") == true)
    }

    @Test func aGapNightIsInTheStripWithoutData() async throws {
        let snap = await snapshot(.gap)
        let screen = screen(snap)
        #expect(screen.picker.last?.hasData == false)
        #expect(screen.picker.last?.accessibilityLabel.hasSuffix("no sleep recorded") == true)
        #expect(screen.selection.night == snap.anchorNight)
        #expect(screen.day == nil)
        #expect(screen.noNight?.title == "No sleep recorded last night.")
        #expect(screen.noNight?.detail?.hasPrefix("Last recorded night ended") == true)
    }

    @Test func theCaptionIsTodayInCapitals() async {
        #expect(screen(await snapshot(.full)).dateCaption == "THURSDAY, SEPTEMBER 24")
    }
}

struct SleepStateContentTests {
    @Test func everyDataStateHasHomesCopy() {
        #expect(SleepScreenBuilder.stateContent(.permissionRequired) == .connect(
            title: "Your first night starts here.", message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true))
        #expect(SleepScreenBuilder.stateContent(.healthDataUnavailable) == .connect(
            title: "Your first night starts here.", message: "Apple Health isn't available on this device.", showsButton: false))
        #expect(SleepScreenBuilder.stateContent(.empty) == .noSleepData(
            title: "No sleep data yet",
            message: "NOCTIS reads sleep from Apple Health. Track sleep with Apple Watch or set up Sleep in the Health app."))
        #expect(SleepScreenBuilder.stateContent(.failed) == .failed(message: "We couldn't read your latest sleep data."))
        for state in [HomeDataState.ready, .noSleepLastNight, .learning(nightsSoFar: 2), .stale(newestSample: now)] {
            #expect(SleepScreenBuilder.stateContent(state) == nil, "\(state) still shows the nights")
        }
    }

    @Test func aStaleSnapshotShowsANightsBannerAndStillShowsTheNights() async throws {
        let snap = await snapshot(.stale)
        let screen = screen(snap)
        #expect(screen.banner?.title.hasPrefix("Apple Health hasn't updated since") == true)
        #expect(screen.banner?.detail == "Open Health or pull to refresh.")
        #expect(screen.state == nil && !screen.picker.isEmpty)
    }

    @Test func noPermissionNoDataAndFailureShowNoPicker() async {
        for scenario in [MockScenario.empty] {
            let screen = screen(await snapshot(scenario))
            #expect(screen.state != nil && screen.picker.isEmpty && screen.day == nil)
        }
        let unauthorized = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: false)
        let snap = await SleepRepository(provider: unauthorized, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        #expect(screen(snap).state != nil)
    }
}

struct SleepWordingTests {
    @Test func durationAndContinuitySentences() {
        #expect(SleepScreenBuilder.durationSentence(asleep: 402, need: 480) == "You slept 6h 42m of your 8h need.")
        #expect(SleepScreenBuilder.durationSentence(asleep: 495, need: 480) == "You met your 8h sleep need.")
        #expect(SleepScreenBuilder.continuitySentence(awakenings: 3, awake: 31) == "3 awakenings, 31 min awake after falling asleep.")
        #expect(SleepScreenBuilder.continuitySentence(awakenings: 1, awake: 6) == "1 awakening, 6 min awake after falling asleep.")
        #expect(SleepScreenBuilder.continuitySentence(awakenings: 0, awake: 0) == "No awakenings recorded.")
    }

    @Test func stageSentencesNameTheStageFurthestOutsideItsRange() {
        func balance(_ basis: StageBalance.Basis, deep: Double, core: Double, rem: Double) -> StageBalance {
            StageBalance(basis: basis, rows: [
                StageBalanceRow(stage: .deep, share: deep, low: 0.13, high: 0.23, score: 100),
                StageBalanceRow(stage: .core, share: core, low: 0.45, high: 0.55, score: 100),
                StageBalanceRow(stage: .rem, share: rem, low: 0.20, high: 0.25, score: 100),
            ], score: 100)
        }
        #expect(SleepScreenBuilder.stagesSentence(balance(.typical, deep: 0.18, core: 0.53, rem: 0.22)).hasSuffix("all within the typical range."))
        #expect(SleepScreenBuilder.stagesSentence(balance(.personal(nights: 9), deep: 0.18, core: 0.53, rem: 0.22)).hasSuffix("all within your usual range."))
        #expect(SleepScreenBuilder.stagesSentence(balance(.typical, deep: 0.08, core: 0.56, rem: 0.22)) == "Deep was 8%, under the typical range of 13–23%.")
        #expect(SleepScreenBuilder.stagesSentence(balance(.personal(nights: 9), deep: 0.30, core: 0.50, rem: 0.20)) == "Deep was 30%, above your usual range of 13–23%.")
        #expect(SleepScreenBuilder.stagesSentence(nil) == "Stages aren't available from your current sources.")
    }

    @Test func whatChangedFollowsTheContributorsMeasureAndDirection() {
        func result(_ measure: SleepQualityContributor.Measure, difference: Double, baselineNights: Int = 14) -> SleepQualityResult {
            SleepQualityResult(
                night: SleepNightKey(year: 2026, month: 9, day: 23), score: 70, factors: [], confidence: .high, baselineNights: baselineNights,
                modelVersion: "sleep-quality-v1", missingFactors: [:], stageBalance: nil,
                topContributor: SleepQualityContributor(factor: .duration, measure: measure, difference: difference, standardDeviations: 3, weightedDeviation: 1)
            )
        }
        #expect(SleepScreenBuilder.whatChanged(result(.duration, difference: -70)) == "Sleep was 1h 10m shorter than usual.")
        #expect(SleepScreenBuilder.whatChanged(result(.duration, difference: 35)) == "Sleep was 35 min longer than usual.")
        #expect(SleepScreenBuilder.whatChanged(result(.bedtime, difference: 45)) == "Bedtime was 45 min later than usual.")
        #expect(SleepScreenBuilder.whatChanged(result(.bedtime, difference: -20)) == "Bedtime was 20 min earlier than usual.")
        #expect(SleepScreenBuilder.whatChanged(result(.awakeTime, difference: 25)) == "You were awake 25 min longer than usual after falling asleep.")
        #expect(SleepScreenBuilder.whatChanged(result(.deepShare, difference: -0.05)) == "Deep sleep was a smaller share of the night than usual.")
        #expect(SleepScreenBuilder.whatChanged(result(.remShare, difference: 0.05)) == "REM sleep was a larger share of the night than usual.")
        #expect(SleepScreenBuilder.whatChanged(result(.duration, difference: -70, baselineNights: 3)) == "There aren't enough nights yet to compare with your usual.")
        let steady = SleepQualityResult(
            night: SleepNightKey(year: 2026, month: 9, day: 23), score: 90, factors: [], confidence: .high, baselineNights: 14,
            modelVersion: "sleep-quality-v1", missingFactors: [:], stageBalance: nil, topContributor: nil
        )
        #expect(SleepScreenBuilder.whatChanged(steady) == "Nothing stood out: this night was in line with your usual.")
    }

    @Test func confidenceLinesUseRecoverysTierNames() {
        func result(_ confidence: RecoveryConfidence, nights: Int) -> SleepQualityResult {
            SleepQualityResult(night: SleepNightKey(year: 2026, month: 9, day: 23), score: 80, factors: [], confidence: confidence, baselineNights: nights,
                               modelVersion: "sleep-quality-v1", missingFactors: [:], stageBalance: nil, topContributor: nil)
        }
        #expect(SleepScreenBuilder.confidenceLine(result(.high, nights: 14)) == "High confidence · built on 14 nights of your own sleep")
        #expect(SleepScreenBuilder.confidenceLine(result(.moderate, nights: 9)) == "Moderate confidence · built on 9 nights of your own sleep")
        #expect(SleepScreenBuilder.confidenceLine(result(.low, nights: 3)) == "Low confidence · it firms up as more nights arrive")
    }

    @Test func nothingReadsAsClinicalOrAlarming() async throws {
        let snap = await snapshot(.full)
        let day = try #require(screen(snap).day)
        let card = try #require(day.quality)
        let text = ([card.whatChanged, card.confidence] + card.calculation + card.factors.map(\.sentence) + card.omitted).joined(separator: " ").lowercased()
        for word in ["debt", "diagnos", "disorder", "insomnia", "apnea", "danger", "warning", "unhealthy", "sick", "disease"] {
            #expect(!text.contains(word), "\(word)")
        }
        // The one place that says what the score isn't.
        #expect(card.calculation[0].contains("isn't a medical measurement"))
    }

    @Test func theCalculationNamesTheWeightsFromTheModelConfig() async throws {
        let card = try #require(screen(await snapshot(.full)).day?.quality)
        #expect(card.calculation[1].contains("duration (35 of 100), continuity (25), consistency (20) and stages (20)"))
    }
}

@MainActor
struct SleepViewModelTests {
    private func model(scenario: MockScenario = .full, defaults: UserDefaults? = nil, reduceMotion: Bool = false) -> SleepViewModel {
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        return SleepViewModel(
            repository: SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: defaults ?? UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard, key: SleepViewModel.introKey),
            reduceMotion: { reduceMotion }, lowPower: { false }, clock: { now }, calendar: Fixture.calendar(), locale: locale
        )
    }

    @Test func itStartsEmptyThenShowsTheNewestNightOnDay() async throws {
        let model = model()
        #expect(model.screen == nil && model.selection == nil)
        await model.refresh()
        let snap = try #require(model.snapshot)
        #expect(model.selection == SleepSelection(night: snap.defaultNight, range: .day))
        #expect(model.screen?.day?.night == snap.defaultNight)
    }

    @Test func choosingANightMovesTheSelectionAtOnceAndTheContentFollows() async throws {
        let model = model()
        await model.refresh()
        let snap = try #require(model.snapshot)
        let earlier = snap.records[snap.records.count - 3].night
        model.select(night: earlier)
        #expect(model.selection?.night == earlier, "the picker moves before the content")
        _ = await waitFor { !(model.screen?.day?.night != earlier) }
        #expect(model.screen?.day?.night == earlier)
        #expect(model.screen?.selection.night == earlier)
    }

    @Test func choosingARangeKeepsTheNightAndAsksForThatRangesModel() async throws {
        let model = model()
        await model.refresh()
        let night = try #require(model.selection?.night)
        model.select(range: .week)
        #expect(model.selection == SleepSelection(night: night, range: .week))
        _ = await waitFor { !(model.model?.selection.range != .week) }
        #expect(model.model?.week != nil)
    }

    @Test func aDeepLinkBeforeTheFirstSnapshotIsAppliedWhenItArrives() async throws {
        let model = model()
        model.open(night: nil, range: .month)
        await model.refresh()
        #expect(model.selection?.range == .month)
        #expect(model.selection?.night == model.snapshot?.defaultNight)
    }

    @Test func aDeepLinkToANightSelectsThatNightAndRange() async throws {
        let model = model()
        await model.refresh()
        let snap = try #require(model.snapshot)
        let target = snap.records[snap.records.count - 5].night
        model.open(night: target, range: .day)
        #expect(model.selection == SleepSelection(night: target, range: .day))
    }

    @Test func aRouteDestinationOpensTheNightContainingItsMomentOnItsRange() async throws {
        let model = model()
        await model.refresh()
        let snap = try #require(model.snapshot)
        let target = snap.records[snap.records.count - 5]
        // Any moment of the night: its bedtime, or its waking the next morning.
        model.open(SleepDestination(night: target.session.wakeTime, range: .week, serial: 1))
        #expect(model.selection == SleepSelection(night: target.night, range: .week))
        model.open(SleepDestination(night: target.session.bedtime, range: .day, serial: 2))
        #expect(model.selection == SleepSelection(night: target.night, range: .day))
        // No night: the newest, on the range asked for.
        model.open(SleepDestination(night: nil, range: .month, serial: 3))
        #expect(model.selection == SleepSelection(night: snap.defaultNight, range: .month))
    }

    @Test func theRevealPlaysOncePerDayOnTheFirstDayViewOnScreen() async throws {
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard
        let first = model(defaults: defaults)
        await first.onAppear()
        #expect(first.reveal == .pending)
        first.beginReveal()
        #expect(first.reveal == .playing && first.revealPlayed)
        first.skipReveal()
        #expect(first.reveal == .none && first.revealSkips == 1)
        first.stopObserving()
        // The same day, another launch: none.
        let second = model(defaults: defaults)
        await second.onAppear()
        #expect(second.reveal == .none)
        second.stopObserving()
    }

    @Test func reduceMotionSkipsTheRevealButUsesTheDay() async throws {
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard
        let calm = model(defaults: defaults, reduceMotion: true)
        await calm.onAppear()
        #expect(calm.reveal == .none)
        calm.stopObserving()
        let later = model(defaults: defaults)
        await later.onAppear()
        #expect(later.reveal == .none, "the day was used up")
        later.stopObserving()
    }

    @Test func aTabThatIsntOnScreenHasNoRevealYet() async throws {
        let model = model()
        await model.refresh()
        #expect(model.reveal == .none, "nothing is on screen until the tab appears")
    }

    @Test func theTabsOwnGateKeyIsSeparateFromHomes() {
        #expect(SleepViewModel.introKey == "noctis.sleep.lastIntroDay")
        #expect(SleepViewModel.introKey != HomeIntroGate.defaultsKey)
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard
        let home = HomeIntroGate(defaults: defaults)
        let sleep = HomeIntroGate(defaults: defaults, key: SleepViewModel.introKey)
        #expect(home.claim(now: now, calendar: Fixture.calendar()))
        #expect(!sleep.isClaimed(now: now, calendar: Fixture.calendar()), "each tab plays once a day of its own")
        #expect(sleep.claim(now: now, calendar: Fixture.calendar()))
    }

    @Test func sleepOnlyAndEmptyScenariosBuildTheirStates() async throws {
        let sleepOnly = model(scenario: .sleepOnly)
        await sleepOnly.refresh()
        #expect(sleepOnly.screen?.day?.chart.heart == nil)
        let empty = model(scenario: .empty)
        await empty.refresh()
        #expect(empty.screen?.state != nil)
    }
}
