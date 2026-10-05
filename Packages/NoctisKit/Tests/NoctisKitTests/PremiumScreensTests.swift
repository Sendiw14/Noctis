import Foundation
import SwiftData
import Testing

@testable import CoachFeature
@testable import CoachKit
@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsFeature
@testable import InsightsKit
@testable import NightFeature
@testable import NightKit
@testable import NoctisCore
@testable import PremiumKit
@testable import RecoveryFeature
@testable import SleepFeature
@testable import SleepKit
@testable import SoundKit

// What each screen does with the plan (APP_RULES.md R57 to R61), asked through the view models and builders and never through a view: every gating
// decision is `FeatureTable`'s, a locked choice leaves the previous one in place, a lapse puts a locked one back, the sounds, the bedtime and the reminders
// say what each plan includes.

private nonisolated func gatingDate(_ hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: hour)) ?? Date()
}

private nonisolated let gatingNow = gatingDate(10)
private nonisolated let gatingEvening = gatingDate(20)
private let gatingLocale = Locale(identifier: "en_US")
private let gatingFormat = HomeFormat(calendar: Fixture.calendar(), locale: gatingLocale)

private func unlocked(_ tier: Tier) -> (Feature) -> Bool {
    { FeatureTable.isIncluded($0, in: tier) }
}

/// The clock's spaces (U+202F before AM and PM) as plain ones.
private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

private func scratchDefaults() -> UserDefaults {
    UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard
}

// MARK: - Recovery

@MainActor
struct RecoveryGatingTests {
    private func model(_ tier: Tier, startsOn: RecoverySegment = .today) -> RecoveryViewModel {
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: gatingNow, calendar: Fixture.calendar(), startAuthorized: true)
        let time = gatingNow
        return RecoveryViewModel(
            repository: RecoveryRepository(provider: provider, timeZone: Fixture.newYork, clock: { time }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: scratchDefaults(), key: RecoveryViewModel.introKey),
            reduceMotion: { true }, lowPower: { false }, clock: { time }, calendar: Fixture.calendar(), locale: gatingLocale,
            isUnlocked: unlocked(tier)
        )
    }

    @Test func eachSegmentAndTheFactorDetailFollowTheTable() {
        for tier in [Tier.free, .premium] {
            let model = model(tier)
            #expect((model.lockedFeature(for: .today) == nil) == FeatureTable.isIncluded(.recoveryToday, in: tier))
            #expect((model.lockedFeature(for: .week) == nil) == FeatureTable.isIncluded(.recovery7D, in: tier))
            #expect((model.lockedFeature(for: .month) == nil) == FeatureTable.isIncluded(.recovery30D, in: tier))
            #expect((model.lockedFeature(for: .quarter) == nil) == FeatureTable.isIncluded(.recovery90D, in: tier))
            #expect(model.canOpenFactorDetail == FeatureTable.isIncluded(.recoveryFactorDetail, in: tier))
        }
        let free = model(.free)
        #expect(free.lockedFeature(for: .month) == .recovery30D && free.lockedFeature(for: .quarter) == .recovery90D)
        #expect(free.lockedFeature(for: .today) == nil && free.lockedFeature(for: .week) == nil)
    }

    @Test func aLockedSegmentKeepsThePreviousSelection() async {
        let model = model(.free)
        await model.refresh()
        model.select(segment: .week)
        let before = model.selection
        model.select(segment: .month)
        model.select(segment: .quarter)
        #expect(model.selection == before, "30 and 90 days change nothing for a free person: the paywall is the caller's")
        #expect(model.selection.segment == .week)
        model.select(factor: .hrv, range: .fortnight)
        #expect(model.selection.factor == nil, "a factor's page does not open either")
    }

    @Test func premiumMovesToTheLongRangesAndAFactor() async {
        let model = model(.premium)
        await model.refresh()
        model.select(segment: .quarter)
        #expect(model.selection.segment == .quarter)
        model.select(factor: .hrv, range: .fortnight)
        #expect(model.selection.factor == .hrv)
    }

    @Test func aLapseWhileTheLongRangeIsOpenPutsTheWeekBack() async {
        var tier = Tier.premium
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: gatingNow, calendar: Fixture.calendar(), startAuthorized: true)
        let time = gatingNow
        let model = RecoveryViewModel(
            repository: RecoveryRepository(provider: provider, timeZone: Fixture.newYork, clock: { time }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: scratchDefaults(), key: RecoveryViewModel.introKey),
            reduceMotion: { true }, lowPower: { false }, clock: { time }, calendar: Fixture.calendar(), locale: gatingLocale,
            isUnlocked: { FeatureTable.isIncluded($0, in: tier) }
        )
        await model.refresh()
        model.select(segment: .quarter)
        model.select(factor: .hrv, range: .fortnight)
        tier = .free
        model.tierChanged()
        #expect(model.selection.segment == .week && model.selection.factor == nil)
    }
}

// MARK: - Sleep

@MainActor
struct SleepGatingTests {
    private func model(_ tier: Tier) -> SleepViewModel {
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: gatingNow, calendar: Fixture.calendar(), startAuthorized: true)
        let time = gatingNow
        return SleepViewModel(
            repository: SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { time }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: scratchDefaults(), key: SleepViewModel.introKey),
            reduceMotion: { true }, lowPower: { false }, clock: { time }, calendar: Fixture.calendar(), locale: gatingLocale,
            isUnlocked: unlocked(tier)
        )
    }

    @Test func rangesQualityFactorsAndDetailSheetsFollowTheTable() {
        for tier in [Tier.free, .premium] {
            let model = model(tier)
            #expect(model.lockedFeature(for: .day) == nil, "Day is free: the score, last night's stages")
            #expect((model.lockedFeature(for: .week) == nil) == FeatureTable.isIncluded(.sleepWeek, in: tier))
            #expect((model.lockedFeature(for: .month) == nil) == FeatureTable.isIncluded(.sleepMonth, in: tier))
            #expect(model.showsQualityFactors == FeatureTable.isIncluded(.sleepQualityFactors, in: tier))
            #expect(model.opensDetailSheets == FeatureTable.isIncluded(.sleepConsistencyBalanceTimingDetails, in: tier))
        }
        #expect(model(.free).lockedFeature(for: .month) == .sleepMonth)
        #expect(model(.premium).lockedFeature(for: .month) == nil)
    }

    @Test func aFreePersonCanOpenTheNewestThreeNightsAndNoOlderOne() async throws {
        let free = model(.free)
        await free.refresh()
        let snapshot = try #require(free.snapshot)
        let newest = snapshot.nights(endingAt: snapshot.defaultNight, count: 14).map(\.night).reversed().map { $0 }
        try #require(newest.count >= 5)
        #expect(newest.first == snapshot.defaultNight)
        for (index, night) in newest.enumerated() {
            let wanted: Feature? = index < 3 ? nil : .sleepNightPicker14
            #expect(free.lockedFeature(forNight: night) == wanted, Comment(rawValue: "night \(index + 1)"))
        }
        let premium = model(.premium)
        await premium.refresh()
        for night in newest { #expect(premium.lockedFeature(forNight: night) == nil) }
    }

    @Test func aLockedNightOrRangeKeepsThePreviousSelection() async throws {
        let model = model(.free)
        await model.refresh()
        let snapshot = try #require(model.snapshot)
        let before = try #require(model.selection)
        let old = try #require(snapshot.nights(endingAt: snapshot.defaultNight, count: 14).map(\.night).reversed().dropFirst(5).first)
        model.select(night: old)
        model.select(range: .month)
        #expect(model.selection == before, "nights 4 to 14 and Month change nothing for a free person: the paywall is the caller's")
    }

    @Test func aLinkToAMonthOrAnOldNightLandsOnWhatIsFree() async throws {
        let model = model(.free)
        await model.refresh()
        let snapshot = try #require(model.snapshot)
        model.open(night: nil, range: .month)
        #expect(model.selection?.range != .month)
        let old = try #require(snapshot.nights(endingAt: snapshot.defaultNight, count: 14).map(\.night).reversed().dropFirst(6).first)
        model.open(night: old, range: .day)
        #expect(model.selection?.night == snapshot.defaultNight)
    }
}

// MARK: - Insights

@MainActor
struct InsightsGatingTests {
    private func model(_ tier: Tier) -> InsightsViewModel {
        let time = gatingNow
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: gatingNow, calendar: Fixture.calendar(), startAuthorized: true)
        let repository = InsightsRepository(provider: provider, store: InsightStore(), timeZone: Fixture.newYork, clock: { time })
        let suite = scratchDefaults()
        return InsightsViewModel(
            repository: repository, profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: suite, key: InsightsViewModel.introKey), washGate: HomeIntroGate(defaults: suite, key: InsightsViewModel.washKey),
            reduceMotion: { true }, lowPower: { false }, clock: { time }, calendar: Fixture.calendar(), locale: gatingLocale,
            revealSleep: { _ in try? await Task.sleep(for: .seconds(3600)) }, isUnlocked: unlocked(tier)
        )
    }

    @Test func chipsHistoryAndEverythingFollowTheTable() {
        for tier in [Tier.free, .premium] {
            let model = model(tier)
            #expect((model.lockedFeature(forFilter: nil) == nil), "All is always free")
            #expect((model.lockedFeature(forFilter: .heart) == nil) == FeatureTable.isIncluded(.insightCategoryFilters, in: tier))
            #expect(model.canOpenHistory == FeatureTable.isIncluded(.insightHistory, in: tier))
            #expect(model.showsEverything == FeatureTable.isIncluded(.insightAll, in: tier))
        }
    }

    @Test func aFreePersonSeesTheFeaturedStoryAndOneMoreAndNoRecords() async {
        let free = model(.free)
        await free.onAppear()
        let premium = model(.premium)
        await premium.onAppear()
        let freeRows = free.screen?.groups.flatMap(\.rows).count ?? 0
        let allRows = premium.screen?.groups.flatMap(\.rows).count ?? 0
        #expect(free.screen?.featured != nil && premium.screen?.featured != nil)
        #expect(freeRows <= 1, "the single most recent other insight")
        #expect(allRows >= freeRows)
        #expect(free.screen?.records.isEmpty == true, "the records row is Premium")
        #expect(free.screen?.showsInsights == true, "there is a list for the one locked card to speak for")
    }

    @Test func aLockedChipKeepsTheCurrentFilter() async {
        let model = model(.free)
        await model.onAppear()
        model.select(filter: .heart)
        #expect(model.filter == nil, "a category chip does nothing for a free person: the paywall is the caller's")
        model.openHistory()
        #expect(model.historyFilter == nil)
    }

    @Test func aLapseWhileAChipIsChosenPutsAllBack() async {
        var tier = Tier.premium
        let time = gatingNow
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: gatingNow, calendar: Fixture.calendar(), startAuthorized: true)
        let suite = scratchDefaults()
        let model = InsightsViewModel(
            repository: InsightsRepository(provider: provider, store: InsightStore(), timeZone: Fixture.newYork, clock: { time }), profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: suite, key: InsightsViewModel.introKey), washGate: HomeIntroGate(defaults: suite, key: InsightsViewModel.washKey),
            reduceMotion: { true }, lowPower: { false }, clock: { time }, calendar: Fixture.calendar(), locale: gatingLocale,
            revealSleep: { _ in try? await Task.sleep(for: .seconds(3600)) }, isUnlocked: { FeatureTable.isIncluded($0, in: tier) }
        )
        await model.onAppear()
        model.select(filter: .heart)
        #expect(model.filter == .heart)
        tier = .free
        model.tierChanged()
        #expect(model.filter == nil)
    }
}

// MARK: - Coach

@MainActor
struct CoachGatingTests {
    private func gate(_ tier: Tier = .free, at date: Date = gatingNow) -> FeatureGate {
        FeatureGate(tier: tier, quotaStore: .inMemory(), calendar: { Fixture.calendar() }, clock: { date })
    }

    private func model(_ service: StubAnswering, gate: FeatureGate?) -> CoachViewModel {
        let store = scratchDefaults()
        return CoachViewModel(
            service: service, dataSource: StaticCoachDataSource(CoachSnapshots()), history: nil, profile: { CoachFixture.profile },
            firstRun: CoachFirstRunGate(defaults: store), washGate: HomeIntroGate(defaults: store, key: CoachViewModel.washKey),
            clock: { gatingNow }, calendar: Fixture.calendar(), locale: CoachFixture.locale, minimumLoading: .zero, reduceMotion: { true }, gate: gate
        )
    }

    private func settle(_ model: CoachViewModel) async {
        // By the clock, with room: the whole suite shares the main actor, so a turn can take far longer than its sleep.
        let deadline = ContinuousClock.now + .seconds(120)
        while model.isSending, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private static let scripted = CoachResult(
        answer: CoachAnswer(sourceKind: .scripted, intent: .medicalOutOfScope, summary: "That's a question for a clinician.", confidence: .high, footer: "Coach isn't medical advice."),
        outcome: .scripted(.medical)
    )

    @Test func eachRealAnswerUsesOneOfTheThreeAndTheHubSaysHowManyAreLeft() async {
        let gate = gate()
        let service = StubAnswering()
        let model = model(service, gate: gate)
        #expect(model.freeQuestionsRemaining == 3 && model.quotaLine == "3 of 3 free questions left today")
        for left in [2, 1, 0] {
            #expect(model.startConversation(asking: "How did I sleep?"))
            await settle(model)
            #expect(model.freeQuestionsRemaining == left)
        }
        #expect(model.quotaLine == "0 of 3 free questions left today")
        #expect(model.isLimited)
    }

    @Test func atZeroTheInputIsOffAndNothingIsSentButAFollowUpOrANewQuestionIsStillRefusedPolitely() async {
        let gate = gate()
        let service = StubAnswering()
        let model = model(service, gate: gate)
        for _ in 0..<3 {
            model.startConversation(asking: "How did I sleep?")
            await settle(model)
        }
        let asked = service.questions.count
        model.setDraft("Why is my HRV low?")
        #expect(!model.canSend, "the send button is off, with the card saying why")
        #expect(!model.startConversation(asking: "Why is my HRV low?"))
        #expect(!model.followUp("And yesterday?"))
        #expect(service.questions.count == asked, "nothing reached the service")
        #expect(model.followUpQuestions.isEmpty, "no suggestions to tap while limited")
    }

    @Test func aMedicalOrCrisisQuestionIsNeverGatedAndNeverCounts() async {
        let gate = gate()
        let service = StubAnswering()
        let model = model(service, gate: gate)
        for _ in 0..<3 {
            model.startConversation(asking: "How did I sleep?")
            await settle(model)
        }
        #expect(model.isLimited)
        service.result = Self.scripted
        for question in ["do I have sleep apnea", "I want to die"] {
            #expect(model.mayAsk(question), Comment(rawValue: question))
            #expect(model.startConversation(asking: question), Comment(rawValue: question))
            await settle(model)
            #expect(model.freeQuestionsRemaining == 0, "a fixed reply costs nothing")
        }
    }

    @Test func aFixedReplyOrAFailureBeforeTheLimitDoesNotCountEither() async {
        let gate = gate()
        let service = StubAnswering()
        let model = model(service, gate: gate)
        service.result = Self.scripted
        model.startConversation(asking: "do I have sleep apnea")
        await settle(model)
        #expect(model.freeQuestionsRemaining == 3)
        service.result = CoachResult(
            answer: Self.scripted.answer, outcome: .unavailable
        )
        model.startConversation(asking: "How did I sleep?")
        await settle(model)
        #expect(model.freeQuestionsRemaining == 3, "an answer that failed is not a question used")
    }

    @Test func premiumHasNoLimitAndNoCounter() async {
        let gate = gate(.premium)
        let service = StubAnswering()
        let model = model(service, gate: gate)
        #expect(model.freeQuestionsRemaining == nil && model.quotaLine == nil)
        for _ in 0..<5 {
            #expect(model.startConversation(asking: "How did I sleep?"))
            await settle(model)
        }
        #expect(!model.isLimited)
    }

    @Test func withNoGateNothingIsLimited() async {
        let model = model(StubAnswering(), gate: nil)
        #expect(model.freeQuestionsRemaining == nil && !model.isLimited && model.mayAsk("anything"))
    }

    @Test func theQuestionsComeBackAtMidnight() async {
        let evening = Fixture.date(2026, 9, 24, 23, 30)
        let store = CoachQuotaStore.inMemory()
        let first = FeatureGate(tier: .free, quotaStore: store, calendar: { Fixture.calendar() }, clock: { evening })
        for _ in 0..<3 { first.recordCoachAnswer() }
        #expect(first.coachQuestionsRemaining == 0 && !first.canAskCoach)
        let morning = FeatureGate(tier: .free, quotaStore: store, calendar: { Fixture.calendar() }, clock: { Fixture.date(2026, 9, 25, 0, 5) })
        #expect(morning.coachQuestionsRemaining == 3 && morning.canAskCoach)
    }
}

// MARK: - Tonight, Home and the wind-down

@MainActor
struct TonightGatingTests {
    private func model(_ tier: Tier) -> TonightViewModel {
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: gatingEvening, calendar: Fixture.calendar(), startAuthorized: true)
        let time = gatingEvening
        let sleep = SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { time })
        let service = AlarmService(backend: MockAlarmBackend(mode: .authorized), store: MemoryAlarmStore(nil), defaultMinutes: { 7 * 60 })
        return TonightViewModel(
            sleep: sleep, alarm: service, profile: { UserProfileSnapshot(typicalWakeMinutes: 7 * 60, needMinutes: 8 * 60) },
            format: gatingFormat, timeZone: Fixture.newYork, clock: { time }, isUnlocked: unlocked(tier)
        )
    }

    @Test func theWindowAndTheSessionFollowTheTable() {
        for tier in [Tier.free, .premium] {
            let model = model(tier)
            #expect(model.showsWindow == FeatureTable.isIncluded(.tonightPersonalizedWindow, in: tier))
            #expect(model.windDownLocked == !FeatureTable.isIncluded(.windDownSession, in: tier))
        }
    }

    @Test func aFreePersonGetsTheOneBedtimeFromTheWakeTimeAndTheNeedAndNoReasonsAreSaid() async throws {
        let free = model(.free)
        await free.refreshBedtime()
        let content = try #require(free.content)
        #expect(!content.isPersonalized && !content.isWindow)
        #expect(plain(content.hero.spoken) == "11:00 PM", "7:00 AM less 8 hours")
        #expect(content.heroCaption == "BEDTIME" && content.confidence == nil)
        #expect(content.note == "Your wake time less the sleep you need.", "not 'still learning': nothing about the person's own nights is used")
        #expect(plain(content.summary) == "Bedtime around 11:00 PM")
    }

    @Test func premiumGetsTheWindowAroundItWhenThereAreNightsToBuildItOn() async throws {
        let premium = model(.premium)
        await premium.refreshBedtime()
        let content = try #require(premium.content)
        #expect(content.isPersonalized && content.isWindow)
        #expect(content.summary.hasPrefix("Bedtime window "))
        #expect(content.confidence != nil && !content.reasons.isEmpty)
    }

    @Test func aChangeOfTierBuildsTheBedtimeAgain() async throws {
        var tier = Tier.free
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: gatingEvening, calendar: Fixture.calendar(), startAuthorized: true)
        let time = gatingEvening
        let model = TonightViewModel(
            sleep: SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { time }),
            alarm: AlarmService(backend: MockAlarmBackend(mode: .authorized), store: MemoryAlarmStore(nil), defaultMinutes: { 7 * 60 }),
            profile: { UserProfileSnapshot(typicalWakeMinutes: 7 * 60, needMinutes: 8 * 60) }, format: gatingFormat, timeZone: Fixture.newYork, clock: { time },
            isUnlocked: { FeatureTable.isIncluded($0, in: tier) }
        )
        await model.refreshBedtime()
        #expect(model.content?.isWindow == false)
        tier = .premium
        await model.tierChanged()
        #expect(model.content?.isWindow == true)
        tier = .free
        await model.tierChanged()
        #expect(model.content?.isWindow == false)
    }

    @Test func theAlarmIsFreeForEveryone() {
        for feature in [Feature.alarm, .breathing, .reflectJournal, .tonightSingleBedtime, .soundsFree] {
            #expect(FeatureTable.isIncluded(feature, in: .free), Comment(rawValue: "\(feature)"))
        }
    }

    @Test func homeDrawsTheWindowForPremiumAndTheOneBedtimeOtherwise() {
        let plan = TonightPlan(profile: UserProfileSnapshot(typicalWakeMinutes: 7 * 60, needMinutes: 8 * 60))
        let times = HomeScreenBuilder.tonightTimes(now: gatingEvening, plan: plan, format: gatingFormat)
        let window = HomeBedtimeWindow(startMinutes: 22 * 60 + 45, endMinutes: 23 * 60 + 15, centerMinutes: 23 * 60)

        let free = HomeScreenBuilder.tonightCard(plan, window: nil, format: gatingFormat)
        #expect(free.bedtimeLead == "Bedtime around" && plain(free.bedtime.spoken) == "11:00 PM")
        let freeHero = HomeScreenBuilder.eveningHero(times, plan: plan, window: nil, format: gatingFormat)
        #expect(!freeHero.isWindow && freeHero.caption == "BEDTIME" && plain(freeHero.time.spoken) == "11:00 PM")

        let premium = HomeScreenBuilder.tonightCard(plan, window: window, format: gatingFormat)
        #expect(premium.bedtimeLead == "Bedtime window" && plain(premium.bedtime.spoken) == "10:45 to 11:15 PM")
        let premiumHero = HomeScreenBuilder.eveningHero(times, plan: plan, window: window, format: gatingFormat)
        #expect(premiumHero.isWindow && premiumHero.caption == "BEDTIME WINDOW" && plain(premiumHero.time.spoken) == "10:45 to 11:15 PM")
        #expect(premiumHero.detail == freeHero.detail, "the wake line is the same on both")
    }

    @Test func aWindowMovesTheCountdownToItsCentreAndLeavesTheWakeTimeAlone() {
        // Premium's recommendation can be earlier than the wake time less the need (a catch-up): the countdown runs to it, and waking is still 7:00 AM.
        let plan = TonightPlan(bedtimeMinutes: 22 * 60 + 30, wakeMinutes: 7 * 60, needMinutes: 8 * 60)
        let times = HomeScreenBuilder.tonightTimes(now: gatingEvening, plan: plan, format: gatingFormat)
        #expect(plain(times.bedtimeText) == "10:30 PM")
        #expect(times.wake.timeIntervalSince(times.bedtime) == 8.5 * 3600, "from 10:30 PM to 7:00 AM")
        let own = HomeScreenBuilder.tonightTimes(now: gatingEvening, plan: TonightPlan(profile: UserProfileSnapshot(typicalWakeMinutes: 7 * 60, needMinutes: 8 * 60)), format: gatingFormat)
        #expect(own.wake.timeIntervalSince(own.bedtime) == 8 * 3600, "unchanged without a window")
    }

    @Test func theFreeRecommendationIsTheEnginesBaseAndPremiumsIsBuiltOnTheNights() async throws {
        let snapshot = await SleepRepository(
            provider: MockHealthKitProvider(scenario: .full, referenceDate: gatingEvening, calendar: Fixture.calendar(), startAuthorized: true),
            timeZone: Fixture.newYork, clock: { gatingEvening }
        ).refresh(profile: UserProfileSnapshot())
        func recommendation(personalized: Bool) -> BedtimeRecommendation {
            BedtimeInputsBuilder.recommendation(
                wakeMinutes: 7 * 60, needMinutes: 8 * 60, timing: snapshot.timing, balance: snapshot.balance, consistency: snapshot.consistency,
                now: gatingEvening, timeZone: Fixture.newYork, personalized: personalized
            )
        }
        let free = recommendation(personalized: false)
        #expect(free.kind == .single && free.window == nil && free.centerMinutes == 23 * 60 && free.nights == 0)
        #expect(free.catchUpMinutes == 0 && !free.isGradual, "no catch-up and no limit on how fast it moves: those use the person's nights")
        let premium = recommendation(personalized: true)
        #expect(premium.kind == .window && premium.window != nil)
    }
}

// MARK: - Sounds

@MainActor
struct SoundsGatingTests {
    @Test func theSoundListsPerTier() {
        #expect(FeatureGate.sounds(for: .free) == [.brown, .rain, .ocean])
        #expect(Set(FeatureGate.sounds(for: .premium)) == Set(SoundKind.allCases) && FeatureGate.sounds(for: .premium).count == 6)
        for kind in [SoundKind.wind, .fireplace, .ambient] {
            #expect(!FeatureGate(tier: .free).isUnlocked(kind) && FeatureGate(tier: .premium).isUnlocked(kind))
        }
        for kind in [SoundKind.brown, .rain, .ocean] { #expect(FeatureGate(tier: .free).isUnlocked(kind)) }
        #expect(FeatureTable.isIncluded(.soundsFree, in: .free) && !FeatureTable.isIncluded(.soundsPremium, in: .free))
    }

    private func model(_ tier: Tier) -> (SoundsViewModel, PlayerBench) {
        let bench = PlayerBench.make()
        let gate = FeatureGate(tier: tier)
        let model = SoundsViewModel(player: bench.player, now: { bench.time.now }, haptic: {}, isIncluded: { gate.isUnlocked($0) }, sleeper: { await bench.time.sleep($0) })
        return (model, bench)
    }

    @Test func aFreePersonsTilesLockTheThreePremiumSoundsAndOnlyThose() {
        let (free, _) = model(.free)
        #expect(free.tiles.filter(\.isLocked).map(\.kind) == [.wind, .fireplace, .ambient])
        for tile in free.tiles where tile.isLocked {
            #expect(tile.stateText == "Premium" && tile.accessibilityLabel.hasSuffix("Premium") && !tile.isPlaying)
            #expect(tile.accessibilityHint == "Opens what Premium includes.")
        }
        let (premium, _) = model(.premium)
        #expect(premium.tiles.allSatisfy { !$0.isLocked })
        #expect(premium.tiles.count == 6 && free.tiles.count == 6)
    }

    @Test func aLockedSoundNeverPlaysFromATapOrARequestAndAFreeOneDoes() {
        let (free, _) = model(.free)
        free.tap(.fireplace)
        #expect(free.state.phase == .stopped)
        free.play(.wind)
        #expect(free.state.phase == .stopped, "Siri, Shortcuts and a control cannot start one either")
        free.tap(.rain)
        #expect(free.state.kind == .rain && free.state.phase == .playing)
    }

    @Test func aSoundPlayingWhenThePlanLapsKeepsPlayingUntilItIsStopped() {
        let bench = PlayerBench.make()
        var tier = Tier.premium
        let model = SoundsViewModel(player: bench.player, now: { bench.time.now }, haptic: {}, isIncluded: { FeatureGate.sounds(for: tier).contains($0) }, sleeper: { await bench.time.sleep($0) })
        model.tap(.fireplace)
        #expect(model.state.kind == .fireplace && model.state.phase == .playing)
        tier = .free
        #expect(model.state.phase == .playing, "nothing is cut off")
        let tile = model.tiles.first { $0.kind == .fireplace }
        #expect(tile?.isLocked == false && tile?.isPlaying == true, "the one that plays is not shown as locked, and its pause still works")
        model.tap(.fireplace)
        #expect(model.state.phase == .paused)
    }
}

// MARK: - Routes

@MainActor
struct WindDownGatingTests {
    private func appModel(_ tier: Tier?) throws -> AppModel {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        model.featureGate = tier.map { FeatureGate(tier: $0) }
        return model
    }

    @Test func aLinkOrANotificationOpensTheSessionForPremiumAndTonightForFree() throws {
        let premium = try appModel(.premium)
        premium.open(.windDown(autostart: false))
        #expect(premium.homePath == [.tonight, .windDown(autostart: false)])
        let free = try appModel(.free)
        free.open(.windDown(autostart: true))
        #expect(free.homePath == [.tonight], "no session for a free person, and no paywall: nothing was tapped")
        #expect(free.paywall == nil)
        let open = try appModel(nil)
        open.open(.windDown(autostart: false))
        #expect(open.homePath == [.tonight, .windDown(autostart: false)], "with no gate (a test) everything is open")
    }

    @Test func aSessionAlreadyRunningIsNeverShutOutByALapse() throws {
        let free = try appModel(.free)
        free.isWindDownRunning = { true }
        free.open(.windDown(autostart: false))
        #expect(free.homePath == [.tonight, .windDown(autostart: false)], "a session that began while it was included finishes")
        free.homePath = [.tonight]
        free.push(.windDown(autostart: false))
        #expect(free.homePath.last == .windDown(autostart: false) && free.paywall == nil)
    }

    @Test func aTapOnStartWindDownFromAFreePlanOpensThePaywallAndPushesNothing() throws {
        let free = try appModel(.free)
        free.homePath = [.tonight]
        free.push(.windDown(autostart: false))
        #expect(free.paywall == .windDown && free.homePath == [.tonight])
    }

    @Test func theNotificationsWordsAndRoutePerTier() {
        #expect(NotificationPlan.windDownBody(leadMinutes: 20, tier: .premium) == "Your wind-down window starts in 20 minutes.")
        #expect(NotificationPlan.windDownBody(leadMinutes: 20, tier: .free) == "Your bedtime window starts in 20 minutes.")
        #expect(NotificationPlan.windDownBody(leadMinutes: 45, tier: .free) == "Your bedtime window starts in 45 minutes.")
        #expect(NoctisNotification.route(for: NoctisNotification.windDown, tier: .premium) == .windDown(autostart: false))
        #expect(NoctisNotification.route(for: NoctisNotification.windDown, tier: .free) == .tonight)
        for tier in [Tier.free, .premium] {
            #expect(NoctisNotification.route(for: NoctisNotification.weeklyReview, tier: tier) == nil)
            #expect(NoctisNotification.route(for: NoctisNotification.morningSummary, tier: tier) == nil)
        }
    }

    @Test func thePlanSaysTheTiersWordsAndLeavesTheOtherRemindersAlone() {
        let preferences = NotificationPreferences()
        func plan(_ tier: Tier) -> [ScheduledNotification] {
            NotificationPlan.make(preferences: preferences, wakeMinutes: 7 * 60, bedtimeCenterMinutes: 23 * 60, tier: tier)
        }
        let free = plan(.free)
        let premium = plan(.premium)
        #expect(free.count == premium.count)
        for (a, b) in zip(free, premium) {
            #expect(a.identifier == b.identifier && a.components == b.components, "when each fires does not depend on the plan")
            if a.identifier == NoctisNotification.windDown {
                #expect(a.body == "Your bedtime window starts in 20 minutes." && b.body == "Your wind-down window starts in 20 minutes.")
            } else {
                #expect(a == b, "the morning and weekly reminders are the same on both plans")
            }
        }
    }

    @Test func theRemindersAreRebuiltWhenThePlanChanges() async {
        var tier = Tier.free
        let name = "tier-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer { defaults.removePersistentDomain(forName: name) }
        let center = InMemoryNotificationCenter(authorization: .allowed)
        let coordinator = NotificationCoordinator(
            scheduler: NotificationScheduler(center: center), preferences: AppPreferences(defaults: defaults),
            profile: { UserProfileSnapshot(typicalWakeMinutes: 7 * 60, needMinutes: 8 * 60) }, bedtimeCenter: { _, _ in 23 * 60 }, tier: { tier }
        )
        coordinator.reschedule()
        await coordinator.settled()
        #expect(center.pendingNotifications.first { $0.identifier == NoctisNotification.windDown }?.body == "Your bedtime window starts in 20 minutes.")
        tier = .premium
        coordinator.reschedule()
        await coordinator.settled()
        #expect(center.pendingNotifications.first { $0.identifier == NoctisNotification.windDown }?.body == "Your wind-down window starts in 20 minutes.")
        #expect(center.pendingNotifications.count == 3, "nothing doubled and nothing lost")
    }

    @Test func theContainerRebuildsTheRemindersOnAChangeOfTierAndTheRouterAsksTheModelForIt() throws {
        let container = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"), encoding: .utf8)
        #expect(container.contains("onTierChange") && container.contains("coordinator.reschedule()") && container.contains("tier: { gate.tier }"))
        let router = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/NotificationRouter.swift"), encoding: .utf8)
        #expect(router.contains("route(for: identifier, tier: model.tier)"))
    }
}
