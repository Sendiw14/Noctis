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
    }

    @Test func aStaleSnapshotSaysHealthHasntUpdatedInsteadOfClaimingNoSleep() async throws {
        let stale = screen(await snapshot(.stale))
        #expect(stale.today == nil)
        let message = try #require(stale.noSleep)
        #expect(message.title.hasPrefix("Apple Health hasn't updated since "))
        #expect(message.detail == "Open Health or pull to refresh.")
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
            let text = String(describing: screen(snap)).lowercased()
            for word in Self.forbidden {
                #expect(!text.contains(word), "\(scenario): \"\(word)\"")
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
        for _ in 0..<100 where model.screen?.segment != .month { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.screen?.segment == .month && model.screen?.today == nil)
        #expect(model.model?.chart != nil)
    }

    @Test func aFactorsDetailIsASelectionOnTheSameViewModel() async throws {
        let model = model()
        await model.refresh()
        model.select(factor: .hrv, range: .month)
        for _ in 0..<100 where model.model?.factor == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.model?.factor?.kind == .hrv && model.model?.factor?.values.count == 30)
        // The screen behind it is still Today.
        #expect(model.screen?.today != nil)
    }

    @Test func aDeepLinkBeforeTheFirstSnapshotStillLandsOnItsSegment() async throws {
        let model = model()
        model.open(segment: .week)
        await model.refresh()
        for _ in 0..<100 where model.screen?.segment != .week { try await Task.sleep(for: .milliseconds(20)) }
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
