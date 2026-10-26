import AppIntents
import Foundation
import SwiftData
import Testing

@testable import AppRoot
@testable import CoachFeature
@testable import CoachKit
@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import NightFeature
@testable import NightKit
@testable import NoctisCore
@testable import NoctisIntentKit
@testable import NoctisWidgetKit
@testable import PremiumKit
@testable import SoundKit

// Siri, Shortcuts and Control Center by plan (APP_RULES.md R62): recovery, sleep, bedtime and the alarm are free (free hears the one bedtime, Premium the window); starting a
// wind-down by voice is Premium and on the free plan opens the paywall sheet and starts nothing; a Premium sound on the free plan plays nothing and says what is free; Coach's
// free questions are the app's count. The plan is read from the App Group's snapshot, and a missing snapshot is free.

private let gateCalendar = Fixture.calendar()
private let gateMorning = Fixture.date(2026, 9, 24, 10)
private let gateFormat = WidgetFormat(calendar: gateCalendar, locale: Locale(identifier: "en_US"))

private func gateSnapshot(_ tier: Tier, state: WidgetDataState = .full) -> WidgetSnapshot {
    var value = WidgetSamples.snapshot(state, now: gateMorning, calendar: gateCalendar, tier: tier)
    value.forDay = WidgetDay(year: 2026, month: 9, day: 24)
    return value
}

private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
}

@MainActor
private final class GateHost: IntentHost {
    var calls: [String] = []
    var lastSleepSound: SoundKind?
    var refusesSounds = false
    var coachLimited = false

    func open(_ destination: IntentDestination) { calls.append("open \(destination)") }
    func startWindDown(minutes: Int?) { calls.append("windDown \(minutes.map(String.init) ?? "nil")") }
    func playSleepSounds(_ kind: SoundKind) -> Bool {
        calls.append("play \(kind.rawValue)")
        guard !refusesSounds else { return false }
        lastSleepSound = kind
        return true
    }
    func stopSleepSounds() { calls.append("stop") }
    func endWindDown() { calls.append("end") }
    func setTonightAlarm(minutes: Int) async -> AlarmIntentOutcome {
        calls.append("alarm \(minutes)")
        return .set(minutes: minutes)
    }
    func askCoach(_ text: String) -> AskCoachOutcome {
        calls.append(coachLimited ? "coach limit" : "coach")
        return coachLimited ? .limitReached : .asked
    }
}

private nonisolated final class Reloads: @unchecked Sendable {
    private let lock = NSLock()
    private var kinds: [String] = []
    func add(_ kind: String) { lock.withLock { kinds.append(kind) } }
    var all: [String] { lock.withLock { kinds } }
}

@MainActor
private func runtime(_ snapshot: WidgetSnapshot?, host: GateHost, reloads: Reloads = Reloads()) -> IntentRuntime {
    let (now, calendar, format) = (gateMorning, gateCalendar, gateFormat)
    return IntentRuntime(
        environment: IntentEnvironment(snapshot: { snapshot }, now: { now }, calendar: { calendar }, format: { format }, reloadControl: { reloads.add($0) }),
        host: host
    )
}

@MainActor
private func perform<I: AppIntent>(_ intent: I, under runtime: IntentRuntime) async throws {
    _ = try await IntentRuntime.$override.withValue(runtime) { try await intent.perform() }
}

// MARK: - The decisions

struct IntentGateDecisionTests {
    @Test func theTierIsTheSnapshotsAndAMissingSnapshotIsFree() {
        let nothing = IntentEnvironment(snapshot: { nil })
        #expect(nothing.tier() == .free)
        for tier in Tier.allCases {
            let snapshot = gateSnapshot(tier)
            #expect(IntentEnvironment(snapshot: { snapshot }).tier() == tier)
        }
    }

    @Test func startingAWindDownByVoiceIsThePlansAndNothingElses() {
        #expect(!IntentGate.includesStartWindDown(in: .free) && IntentGate.includesStartWindDown(in: .premium))
        for tier in Tier.allCases { #expect(IntentGate.includesStartWindDown(in: tier) == FeatureTable.isIncluded(.siriStartWindDown, in: tier)) }
    }

    @Test func aNamedSoundPlaysIfThePlanIncludesItAndOtherwiseNothingPlays() {
        for kind in SoundKind.allCases {
            let free = IntentGate.soundChoice(requested: kind, last: nil, tier: .free)
            #expect(free == (SoundAccess.freeKinds.contains(kind) ? .play(kind) : .premiumNeeded(kind)), Comment(rawValue: kind.rawValue))
            #expect(IntentGate.soundChoice(requested: kind, last: .wind, tier: .premium) == .play(kind), "premium has all six")
        }
        #expect([SoundKind.wind, .fireplace, .ambient].allSatisfy { IntentGate.soundChoice(requested: $0, last: .rain, tier: .free) == .premiumNeeded($0) })
    }

    @Test func noSoundNamedPlaysTheLastOneThePlanStillIncludesAndBrownNoiseIfNot() {
        #expect(IntentGate.soundChoice(requested: nil, last: nil, tier: .free) == .play(.rain), "Rain before any")
        #expect(IntentGate.soundChoice(requested: nil, last: nil, tier: .premium) == .play(.rain))
        for kind in SoundAccess.freeKinds { #expect(IntentGate.soundChoice(requested: nil, last: kind, tier: .free) == .play(kind)) }
        for kind in [SoundKind.wind, .fireplace, .ambient] {
            #expect(IntentGate.soundChoice(requested: nil, last: kind, tier: .free) == .play(.brown), "\(kind.rawValue) is no longer included: Brown noise")
            #expect(IntentGate.soundChoice(requested: nil, last: kind, tier: .premium) == .play(kind))
        }
        #expect(SoundAccess.fallback == .brown)
    }

    @Test func theFreeSoundsAreOneListEverywhere() {
        #expect(Set(SoundAccess.spokenFreeOrder) == Set(SoundAccess.freeKinds) && SoundAccess.spokenFreeOrder.count == SoundAccess.freeKinds.count)
        #expect(FeatureGate.sounds(for: .free) == SoundAccess.kinds(for: .free) && FeatureGate.freeSounds == SoundAccess.freeKinds)
        #expect(SoundAccess.kinds(for: .premium) == SoundKind.allCases)
        #expect(FeatureTable.isIncluded(.soundsFree, in: .free) && !FeatureTable.isIncluded(.soundsPremium, in: .free))
    }

    @Test func theWordsAreTheOnesWritten() {
        #expect(IntentGate.premiumSoundDialog(.wind) == "Wind is part of NOCTIS Premium. Rain, Brown noise and Ocean are free.")
        #expect(IntentGate.premiumSoundDialog(.fireplace) == "Fireplace is part of NOCTIS Premium. Rain, Brown noise and Ocean are free.")
        #expect(IntentGate.premiumSoundDialog(.ambient) == "Ambient is part of NOCTIS Premium. Rain, Brown noise and Ocean are free.")
        #expect(IntentGate.startWindDownLocked == "Wind-down sessions are part of NOCTIS Premium. I've opened NOCTIS.")
        #expect(IntentGate.coachLimitReached == "\(CoachQuota.usedUpTitle) \(CoachQuota.usedUpDetail) I've opened Coach.")
        for text in [IntentGate.startWindDownLocked, IntentGate.coachLimitReached] + SoundKind.allCases.map({ IntentGate.premiumSoundDialog($0) }) {
            #expect(LockedCopy.pressure(in: text).isEmpty, Comment(rawValue: text))
            #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: text))
        }
    }
}

// MARK: - What each intent does, for both plans

@MainActor
struct IntentGatePerformTests {
    @Test func recoverySleepAndBedtimeAreFreeAndSayTheSameThingsOnBothPlansExceptTheBedtimesWindow() async throws {
        for tier in Tier.allCases {
            let host = GateHost()
            let under = runtime(gateSnapshot(tier), host: host)
            try await perform(ShowMyRecoveryIntent(), under: under)
            try await perform(ShowMySleepIntent(), under: under)
            try await perform(ShowRecommendedBedtimeIntent(), under: under)
            #expect(host.calls == ["open recovery", "open sleep", "open bedtime"], Comment(rawValue: "\(tier)"))
            #expect(ShowMyRecoveryIntent.answer(under) == "Your recovery is 70. Sleep was 6 hours 42 minutes.")
            #expect(ShowMySleepIntent.answer(under) == "You slept 6 hours 42 minutes. Sleep quality was 81.")
        }
    }

    @Test func freeHearsTheOneBedtimeAndPremiumTheWindow() {
        let free = plain(WidgetSpoken.bedtime(gateSnapshot(.free), format: gateFormat))
        #expect(free == "Your bedtime tonight is 11:00 PM.", Comment(rawValue: free))
        let premium = plain(WidgetSpoken.bedtime(gateSnapshot(.premium), format: gateFormat))
        #expect(premium == "Your bedtime window tonight is 10:45 to 11:15 PM.", Comment(rawValue: premium))
        // A Premium snapshot with no window (too few nights to build one) says the one bedtime, as before.
        var single = gateSnapshot(.premium)
        single.plan.windowStartMinutes = nil
        single.plan.windowEndMinutes = nil
        #expect(plain(WidgetSpoken.bedtime(single, format: gateFormat)) == "Your bedtime tonight is 11:00 PM.")
    }

    @Test func aFreeWindDownByVoiceStartsNothingAndOpensThePaywallSheet() async throws {
        for snapshot in [gateSnapshot(.free), nil] {
            let host = GateHost()
            try await perform(StartWindDownIntent(length: .twentyMinutes), under: runtime(snapshot, host: host))
            try await perform(StartWindDownIntent(), under: runtime(snapshot, host: host))
            let opened = "open \(IntentDestination.paywall(.windDown))"
            #expect(host.calls == [opened, opened], "nothing is started, with a snapshot or without one")
            #expect(!host.calls.contains { $0.hasPrefix("windDown") })
        }
        let host = GateHost()
        try await perform(StartWindDownIntent(length: .thirtyMinutes), under: runtime(gateSnapshot(.premium), host: host))
        #expect(host.calls == ["windDown 30"], "Premium starts it as it always did")
    }

    @Test func aPremiumSoundOnTheFreePlanPlaysNothing() async throws {
        let host = GateHost()
        let under = runtime(gateSnapshot(.free), host: host)
        for kind in [SoundKind.wind, .fireplace, .ambient] { try await perform(PlaySleepSoundsIntent(sound: SoundEntity(kind)), under: under) }
        #expect(host.calls.isEmpty, "the player is never asked")
        for kind in SoundAccess.freeKinds { try await perform(PlaySleepSoundsIntent(sound: SoundEntity(kind)), under: under) }
        #expect(host.calls == ["play brown", "play rain", "play ocean"])
    }

    @Test func premiumPlaysAnySound() async throws {
        let host = GateHost()
        let under = runtime(gateSnapshot(.premium), host: host)
        for kind in SoundKind.allCases { try await perform(PlaySleepSoundsIntent(sound: SoundEntity(kind)), under: under) }
        #expect(host.calls == SoundKind.allCases.map { "play \($0.rawValue)" })
    }

    @Test func noSoundNamedPlaysTheLastOneThePlanIncludes() async throws {
        let free = GateHost()
        free.lastSleepSound = .wind
        try await perform(PlaySleepSoundsIntent(), under: runtime(gateSnapshot(.free), host: free))
        #expect(free.calls == ["play brown"], "Wind is no longer included: Brown noise")
        let premium = GateHost()
        premium.lastSleepSound = .wind
        try await perform(PlaySleepSoundsIntent(), under: runtime(gateSnapshot(.premium), host: premium))
        #expect(premium.calls == ["play wind"])
        let fresh = GateHost()
        try await perform(PlaySleepSoundsIntent(), under: runtime(nil, host: fresh))
        #expect(fresh.calls == ["play rain"], "no snapshot is free, and Rain is the first sound")
    }

    @Test func theAppsOwnGuardHasTheLastWordOnASound() async throws {
        // The snapshot says Premium but the app refuses (a lapse the snapshot has not caught up with yet): nothing is claimed to have played.
        let host = GateHost()
        host.refusesSounds = true
        try await perform(PlaySleepSoundsIntent(sound: SoundEntity(.wind)), under: runtime(gateSnapshot(.premium), host: host))
        #expect(host.calls == ["play wind"], "it asked once, was refused, and stopped there")
    }

    @Test func theAlarmIsFreeOnBothPlans() async throws {
        for snapshot in [gateSnapshot(.free), gateSnapshot(.premium), nil] {
            let host = GateHost()
            try await perform(SetTonightAlarmIntent(time: DateComponents(hour: 6, minute: 30)), under: runtime(snapshot, host: host))
            #expect(host.calls == ["alarm 390"])
        }
    }

    @Test func coachIsAskedOnBothPlansAndAtTheLimitOpensOnItsCard() async throws {
        for tier in Tier.allCases {
            let host = GateHost()
            try await perform(AskCoachIntent(question: "Why was my sleep short?"), under: runtime(gateSnapshot(tier), host: host))
            #expect(host.calls == ["coach"])
        }
        let limited = GateHost()
        limited.coachLimited = true
        try await perform(AskCoachIntent(question: "Why was my sleep short?"), under: runtime(gateSnapshot(.free), host: limited))
        #expect(limited.calls == ["coach limit"])
    }

    @Test func theControlsToggleStartsTheLastSoundThePlanIncludesAndAlwaysRereadsTheTruth() async throws {
        let reloads = Reloads()
        let free = GateHost()
        free.lastSleepSound = .fireplace
        let underFree = runtime(gateSnapshot(.free), host: free, reloads: reloads)
        try await perform(SleepSoundsToggleIntent(value: true), under: underFree)
        try await perform(SleepSoundsToggleIntent(value: false), under: underFree)
        #expect(free.calls == ["play brown", "stop"], "Fireplace is no longer included: Brown noise")
        let premium = GateHost()
        premium.lastSleepSound = .fireplace
        let underPremium = runtime(gateSnapshot(.premium), host: premium, reloads: reloads)
        try await perform(SleepSoundsToggleIntent(value: true), under: underPremium)
        #expect(premium.calls == ["play fireplace"])
        #expect(reloads.all == Array(repeating: ControlKind.sleepSounds, count: 3), "the control is told to read the truth after every flip")
    }

    @Test func theWindDownControlRunsTheSameIntentSoItOpensThePaywallSheetForTheFreePlan() throws {
        let controls = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Widgets/Home/NoctisControls.swift"), encoding: .utf8)
        #expect(RawDefaultsTests.code(controls).contains("ControlWidgetButton(action: StartWindDownIntent())"), "one intent, one gate")
        #expect(
            !RawDefaultsTests.code(controls).contains("StoreKit") && !RawDefaultsTests.code(controls).contains("FeatureTable"),
            "the control decides nothing itself")
    }
}

// MARK: - Entities, routing and the app's side

@MainActor
struct IntentGateAppTests {
    private struct Bench {
        let host: AppIntentHost
        let model: AppModel
        let sounds: SoundsViewModel
        let player: PlayerBench

        init(tier: Tier, coach: CoachViewModel? = nil) throws {
            let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
            let gate = FeatureGate(tier: tier, quotaStore: .inMemory(), calendar: { Fixture.calendar() }, clock: { gateMorning })
            model.featureGate = gate
            let preferences = AppPreferences(defaults: UserDefaults(suiteName: "noctis.intent.\(UUID().uuidString)") ?? .standard)
            let player = PlayerBench.make()
            let sounds = SoundsViewModel(player: player.player, haptic: {}, isIncluded: { gate.isUnlocked($0) })
            let alarm = AlarmService(backend: MockAlarmBackend(mode: .authorized), store: MemoryAlarmStore(), defaultMinutes: { 7 * 60 })
            self.model = model
            self.sounds = sounds
            self.player = player
            host = AppIntentHost(model: model, preferences: preferences, player: player.player, sounds: sounds, alarm: alarm, coach: coach)
        }
    }

    @Test func theSoundListIsTheSamePerPlanAndTheEntityQueryStillOffersAllSix() async throws {
        let query = SoundEntityQuery()
        let suggested = try await query.suggestedEntities()
        #expect(suggested.compactMap(\.kind) == SoundKind.allCases, "Siri can name any sound; the intent says which are free")
        let matched = try await query.entities(matching: "wind")
        #expect(matched.compactMap(\.kind) == [.wind])
        let byID = try await query.entities(for: ["ocean", "nonsense"])
        #expect(byID.compactMap(\.kind) == [.ocean])
    }

    @Test func aPaywallDestinationIsNotAScreenAndTheHostOpensTheSheetOnlyForTheFreePlan() async throws {
        #expect(IntentRouting.destination(for: .paywall(.windDown)) == .paywall(.windDown))
        #expect(IntentRouting.route(for: .paywall(.windDown)) == nil)
        #expect(IntentRouting.destination(for: .recovery) == .screen(WidgetURLRouter.route(for: .recovery)))
        let free = try Bench(tier: .free)
        free.host.open(.paywall(.windDown))
        #expect(free.model.paywall == nil, "never before setup is finished (R58)")
        await free.model.completeOnboarding(UserProfileSnapshot())
        free.host.open(.paywall(.windDown))
        #expect(free.model.paywall == .windDown, "the sheet names what was asked for")
        let premium = try Bench(tier: .premium)
        await premium.model.completeOnboarding(UserProfileSnapshot())
        premium.host.open(.paywall(.windDown))
        #expect(premium.model.paywall == nil, "nothing to sell to someone who already has it")
    }

    @Test func theHostRefusesAPremiumSoundOnTheFreePlanAndPlaysAFreeOne() throws {
        let free = try Bench(tier: .free)
        #expect(!free.host.playSleepSounds(.wind) && free.player.player.state.phase == .stopped && free.host.lastSleepSound == nil)
        #expect(free.host.playSleepSounds(.ocean) && free.player.player.state.kind == .ocean && free.host.lastSleepSound == .ocean)
        let premium = try Bench(tier: .premium)
        #expect(premium.host.playSleepSounds(.wind) && premium.player.player.state.kind == .wind)
    }

    @Test func coachAtTheLimitOpensItsCardAndTheQuestionIsNeitherAskedNorKept() throws {
        let gate = FeatureGate(tier: .free, quotaStore: .inMemory(), calendar: { Fixture.calendar() }, clock: { gateMorning })
        for _ in 0..<3 { gate.recordCoachAnswer() }
        let defaults = UserDefaults(suiteName: "noctis.coach.\(UUID().uuidString)") ?? .standard
        let coach = CoachViewModel(
            service: StubAnswering(), dataSource: StaticCoachDataSource(CoachSnapshots()), history: nil, profile: { CoachFixture.profile },
            firstRun: CoachFirstRunGate(defaults: defaults), washGate: HomeIntroGate(defaults: defaults, key: CoachViewModel.washKey),
            clock: { gateMorning }, calendar: Fixture.calendar(), locale: CoachFixture.locale, minimumLoading: .zero, reduceMotion: { true }, gate: gate
        )
        let bench = try Bench(tier: .free, coach: coach)
        #expect(coach.isLimited)
        #expect(bench.host.askCoach("Why was my sleep short?") == .limitReached)
        #expect(bench.model.selectedTab == .coach)
        let destination = try #require(bench.model.takeCoachDestination())
        #expect(destination.text == nil && destination.question == nil, "the words were not kept")
        // A question that is never gated (medical, fixed words) still goes through.
        #expect(bench.host.askCoach("do I have sleep apnea") == .asked)
    }

    @Test func withMoreQuestionsLeftCoachIsAskedAsBefore() throws {
        let gate = FeatureGate(tier: .free, quotaStore: .inMemory(), calendar: { Fixture.calendar() }, clock: { gateMorning })
        let defaults = UserDefaults(suiteName: "noctis.coach.\(UUID().uuidString)") ?? .standard
        let coach = CoachViewModel(
            service: StubAnswering(), dataSource: StaticCoachDataSource(CoachSnapshots()), history: nil, profile: { CoachFixture.profile },
            firstRun: CoachFirstRunGate(defaults: defaults), washGate: HomeIntroGate(defaults: defaults, key: CoachViewModel.washKey),
            clock: { gateMorning }, calendar: Fixture.calendar(), locale: CoachFixture.locale, minimumLoading: .zero, reduceMotion: { true }, gate: gate
        )
        let bench = try Bench(tier: .free, coach: coach)
        #expect(bench.host.askCoach("Why was my sleep short?") == .asked)
        #expect(bench.model.takeCoachDestination()?.text == "Why was my sleep short?")
    }

    @Test func theIntentsAndTheControlNeverCallStoreKitAndTheRunnerCoversBothPlans() throws {
        for folder in ["Packages/NoctisKit/Sources/NoctisIntentKit", "Widgets/Home"] {
            for file in RawDefaultsTests.swiftFiles(under: [folder]) {
                #expect(!file.text.contains("import StoreKit"), Comment(rawValue: "\(file.path) imports StoreKit"))
            }
        }
        let runner = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/IntentRunner.swift"), encoding: .utf8)
        #expect(runner.contains("-intentRunnerTier") && runner.contains("IntentGate.premiumSoundDialog") && runner.contains("IntentGate.coachLimitReached"))
    }
}
