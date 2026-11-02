import Foundation
import Testing

@testable import HealthProviding
@testable import NoctisCore
@testable import OnboardingFeature

// Stage 1A, audit PRIV-01 / X-26: onboarding asks Apple Health for three kinds, and the screens used to wait for an "asked" answer about all five, so a
// person who had just answered onboarding's sheet looked like someone who had not been asked. HealthKit never says whether a read type was allowed, so
// `.authorized` here means "the system's question has been asked", and a declined or unasked type is only ever a type with no data.
@MainActor
struct HealthAuthorizationFlowTests {
    private let now = Fixture.date(2026, 9, 24, 10)

    private func provider(_ scenario: MockScenario = .full, startAuthorized: Bool = false) -> MockHealthKitProvider {
        MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: startAuthorized)
    }

    // MARK: What onboarding asks for

    @Test func onboardingAsksForTheCoreKindsAndNothingMore() {
        #expect(HealthStepFacts.requestedKinds == HealthDataKind.core)
        #expect(HealthDataKind.core == [.sleepAnalysis, .heartRate, .hrv])
        #expect(!HealthDataKind.core.contains(.restingHeartRate) && !HealthDataKind.core.contains(.respiratoryRate))
        #expect(Set(HealthDataKind.core).isSubset(of: Set(HealthDataKind.allCases)))
    }

    // MARK: After onboarding

    @Test func afterOnboardingAnswersTheCoreQuestionTheScreensAreNotWaitingForAnotherOne() async {
        let health = provider()
        #expect(await health.authorizationStatus() == .notDetermined, "before anything is asked")
        _ = await health.requestAuthorization(for: HealthStepFacts.requestedKinds)
        #expect(await health.authorizationStatus() == .authorized, "the three kinds onboarding asked for are asked: the data screens load")
        #expect(await health.authorizationStatus(for: HealthDataKind.allCases) == .notDetermined, "two kinds have still not been asked")
    }

    @Test func homeSleepRecoveryAndInsightsLoadAfterOnboardingAloneNotAConnectPrompt() async {
        let health = provider()
        _ = await health.requestAuthorization(for: HealthStepFacts.requestedKinds)
        let profile = UserProfileSnapshot()
        let home = await HomeRepository(provider: health, timeZone: Fixture.newYork, clock: { now }).refresh(profile: profile)
        let sleep = await SleepRepository(provider: health, timeZone: Fixture.newYork, clock: { now }).refresh(profile: profile)
        let recovery = await RecoveryRepository(provider: health, timeZone: Fixture.newYork, clock: { now }).refresh(profile: profile)
        let insights = await InsightsRepository(provider: health, timeZone: Fixture.newYork, clock: { now }).refresh(profile: profile)
        #expect(home.dataState != .permissionRequired, "Home would otherwise show Connect Apple Health right after the sheet was answered")
        #expect(sleep.dataState != .permissionRequired)
        #expect(recovery.dataState != .permissionRequired)
        #expect(insights.dataState != .permissionRequired)
    }

    @Test func theReviewsAreNotBlockedByAnUnaskedOptionalKindEither() async {
        let health = provider()
        _ = await health.requestAuthorization(for: HealthStepFacts.requestedKinds)
        let zone = Fixture.newYork
        let moment = now
        let repository = ReviewRepository(provider: health, store: ReviewStore(), insights: InsightStore(), timeZone: { zone }, clock: { moment })
        let outcome = await repository.review(repository.latestWeekly(weekday: 1), profile: UserProfileSnapshot())
        #expect(outcome != .noAccess && outcome != .unavailable, "asked for the core kinds: a review is made or says why not, never 'no access'")
        let counts = await repository.nightCounts(for: [repository.latestWeekly(weekday: 1)], profile: UserProfileSnapshot())
        #expect(counts != nil)
    }

    @Test func aKindThatWasNeverAskedForThrowsUnauthorizedLikeRealHealthKitAndTheOptionalReadersTurnThatIntoNoData() async throws {
        let health = provider()
        _ = await health.requestAuthorization(for: HealthDataKind.core)
        let start = now.addingTimeInterval(-30 * 86_400)
        #expect(try await health.fetchSleepSamples(from: start, to: now).isEmpty == false, "asked: its data is there")
        // Real HealthKit (checked on the simulator) throws for a kind never asked for, as the mock now does.
        await #expect(throws: HealthProviderError.unauthorized) { try await health.fetchRestingHeartRate(from: start, to: now) }
        await #expect(throws: HealthProviderError.unauthorized) { try await health.fetchRespiratorySamples(from: start, to: now) }
        // The optional readers the screens use turn that into "no data".
        #expect(try await health.restingHeartRateIfAsked(from: start, to: now).isEmpty)
        #expect(try await health.respiratorySamplesIfAsked(from: start, to: now).isEmpty)
        // The core reads are not softened: a person who was never asked about sleep still has a missing permission (see the skipped-Health test).
        let none = provider()
        await #expect(throws: HealthProviderError.unauthorized) { try await none.fetchSleepSamples(from: start, to: now) }
    }

    @Test func theOptionalReadersReturnTheDataOnceTheKindIsAsked() async throws {
        let health = provider(startAuthorized: true)
        let start = now.addingTimeInterval(-30 * 86_400)
        #expect(try await health.restingHeartRateIfAsked(from: start, to: now).isEmpty == false)
        #expect(try await health.respiratorySamplesIfAsked(from: start, to: now).isEmpty == false)
    }

    @Test func theHealthPageStillOffersTheTwoKindsOnboardingDidNotAsk() async {
        let health = provider()
        _ = await health.requestAuthorization(for: HealthDataKind.core)
        let status = await HealthDataStatusReader(provider: health).read(now: now, calendar: Fixture.calendar())
        #expect(status.hasAnyData, "the screens load")
        #expect(status.canRequestAccess, "Connect Apple Health is still there for resting heart rate and respiratory rate, which nothing has asked for")
        #expect(status.kinds.first { $0.kind == .restingHeartRate }?.hasData == false)
        #expect(status.kinds.first { $0.kind == .sleepAnalysis }?.hasData == true)
    }

    @Test func connectingFromTheHealthPageAsksOnlyForWhatIsLeftAndThenStopsOffering() async {
        let health = provider()
        _ = await health.requestAuthorization(for: HealthDataKind.core)
        _ = await health.requestAuthorization(for: HealthDataKind.allCases)
        #expect(await health.authorizationStatus(for: HealthDataKind.allCases) == .authorized)
        let status = await HealthDataStatusReader(provider: health).read(now: now, calendar: Fixture.calendar())
        #expect(!status.canRequestAccess, "asked for all five: the sheet is never offered again")
        #expect(status.kinds.first { $0.kind == .restingHeartRate }?.hasData == true)
    }

    // MARK: Skipping Health, no data, and unavailable

    @Test func aPersonWhoSkippedHealthStillSeesTheConnectFlowAndTheNoPermissionState() async {
        let health = provider()
        let home = await HomeRepository(provider: health, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        #expect(home.dataState == .permissionRequired)
        let status = await HealthDataStatusReader(provider: health).read(now: now, calendar: Fixture.calendar())
        #expect(status.canRequestAccess && !status.hasAnyData && status.kinds.allSatisfy { !$0.couldNotCheck })
    }

    @Test func anAnsweredQuestionWithNoDataIsEmptyNeverPermissionRequiredAndNeverDenied() async {
        let health = provider(.empty)
        _ = await health.requestAuthorization(for: HealthStepFacts.requestedKinds)
        let home = await HomeRepository(provider: health, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        #expect(home.dataState == .empty, "asked, and nothing there: the empty state, not a prompt to connect")
        #expect(await health.authorizationStatus() != .denied, "HealthKit cannot say denied, so neither can NOCTIS")
    }

    @Test func healthBeingUnavailableIsStillItsOwnStateAfterTheChange() async {
        let health = MockHealthKitProvider(
            scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true, isHealthDataAvailable: false)
        let home = await HomeRepository(provider: health, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        #expect(home.dataState == .healthDataUnavailable)
    }

    // MARK: The seam

    private struct OldStyleProvider: HealthDataProviding {
        var isHealthDataAvailable: Bool { true }
        var sourceName: String { "Old" }
        func authorizationStatus() async -> HealthAuthorizationStatus { .authorized }
        func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus { .authorized }
        func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] { [] }
        func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] { [] }
        func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] { [] }
        func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] { [] }
        func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] { [] }
        func sampleChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    }

    @Test func aProviderThatCannotTellKindsApartAnswersWithItsOneStatus() async {
        #expect(await OldStyleProvider().authorizationStatus(for: HealthDataKind.allCases) == .authorized)
    }

    // MARK: The real provider (HealthKit's own answer is device-only, so the code is held to the rule)

    @Test func theRealProviderAsksTheSystemAboutTheCoreKindsAndNeverWritesToHealth() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/HealthProviding/HealthKitProvider.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(text)
        #expect(code.contains("authorizationStatus(for: HealthDataKind.core)"), "the default status question is about the core kinds, not all five")
        #expect(!code.contains("readTypes(for: HealthDataKind.allCases)"), "no status check may ask about every kind again")
        let shares = code.components(separatedBy: "toShare:").count - 1
        #expect(shares >= 2 && shares == code.components(separatedBy: "toShare: []").count - 1, "read-only: every request names an empty share set")
    }
}
