import Foundation
import HealthProviding
@testable import CoachKit
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore

/// Coach's inputs for every mock scenario, built end to end: mock provider →
/// repositories → snapshots → context. The clock and zone are fixed: 10:00 AM
/// on Thursday, Sep 24, 2026, New York, English (US).
/// English (US), usable from a test double that isn't on the main actor.
nonisolated let coachTestLocale = Locale(identifier: "en_US")

extension String {
    /// The text with the narrow and no-break spaces the clock formats use ("11:00\u{202F}PM") as plain spaces, for comparing.
    var plain: String { replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") }

    /// Whether any character is a number (of any script).
    var hasDigit: Bool { contains { $0.isNumber } }
}

enum CoachFixture {
    static let now = Fixture.date(2026, 9, 24, 10)
    static let locale = coachTestLocale
    static let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
    /// A profile with a name and a second goal, so a leak would show.
    static let profile = UserProfileSnapshot(
        name: "Alex Tester", primaryGoal: .betterRecovery, secondaryGoal: .betterConsistency, selectedGoals: [.betterRecovery, .betterConsistency],
        typicalWakeMinutes: 7 * 60, needMinutes: 8 * 60, sleepGoalHours: 8, onboardingComplete: true, healthAuthorizationRequested: true
    )

    static func provider(_ scenario: MockScenario) -> MockHealthKitProvider {
        MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
    }

    /// The mock is deterministic, so a scenario is built once.
    private actor Cache {
        var built: [MockScenario: CoachSnapshots] = [:]
        func value(_ scenario: MockScenario) async -> CoachSnapshots {
            if let existing = built[scenario] { return existing }
            let made = await CoachFixture.build(scenario)
            built[scenario] = made
            return made
        }
    }

    private static let cache = Cache()

    static func snapshots(_ scenario: MockScenario) async -> CoachSnapshots {
        await cache.value(scenario)
    }

    fileprivate static func build(_ scenario: MockScenario) async -> CoachSnapshots {
        let clock = now
        let provider = provider(scenario)
        let insights = InsightsRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock })
        let home = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }, insights: insights)
        let sleep = SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock })
        let recovery = RecoveryRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock })
        async let h = home.refresh(profile: profile)
        async let s = sleep.refresh(profile: profile)
        async let r = recovery.refresh(profile: profile)
        async let i = insights.refresh(profile: profile)
        return await CoachSnapshots(home: h, sleep: s, recovery: r, insights: i)
    }

    static func context(
        _ intent: CoachIntent, _ direction: CoachDirection? = nil, scenario: MockScenario = .full
    ) async -> CoachContext {
        CoachContextBuilder(format: format).build(intent: intent, direction: direction, snapshots: await snapshots(scenario), profile: profile)
    }

    /// A small context made by hand: only what a test lists.
    static func handmade(
        intent: CoachIntent = .recoveryChange, direction: CoachDirection? = nil, facts: [CoachFact] = [], state: CoachDataState = .ready,
        nights: Int = 20, ceiling: CoachConfidence = .high
    ) -> CoachContext {
        CoachContext(
            intent: intent, direction: direction, facts: facts, insights: [], availableFactors: ["sleepDuration", "hrv"], missingFactors: [],
            nightsOfHistory: nights, dataState: state, goalIDs: ["betterSleep"], sleepNeedMinutes: 480, confidenceCeiling: ceiling
        )
    }

    static func fact(_ id: String, _ value: Double, _ unit: CoachUnit, magnitude: Bool = false) -> CoachFact {
        CoachFactFormatter(format: format).fact(id, "Label of \(id)", value, unit, source: "TestEngine", magnitude: magnitude)
    }

    /// The scenarios Coach's answers are checked against.
    static let scenarios: [MockScenario] = [.full, .sleepOnly, .learning, .gap, .recoveryDip, .earlyBird, .empty, .stale, .hrvDip, .weekendShift, .steady, .lateBedtime]
}
