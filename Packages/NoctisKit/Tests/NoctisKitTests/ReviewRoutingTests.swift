import Foundation
import SwiftData
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import PremiumKit
@testable import ReviewKit
@testable import SleepKit

// Reviews, routing (APP_RULES.md R63): the three features and what each plan sees, the card on Home (when it appears, when it goes, that it is never made up), what a
// link or the notification lands on, and the pages standing in until the screens exist. Mock provider -> repository -> store -> cards, with a fixed clock and zone.

private nonisolated let nyZone = TimeZone(identifier: "America/New_York") ?? .gmt

private nonisolated func calendar(_ zone: TimeZone = nyZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

private nonisolated func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
    calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
}

private nonisolated func key(_ year: Int, _ month: Int, _ day: Int) -> SleepNightKey { SleepNightKey(year: year, month: month, day: day) }

/// Counts how many times Health was read, whatever it answers.
private nonisolated final class CountingProvider: HealthDataProviding, @unchecked Sendable {
    private let base: MockHealthKitProvider
    private let lock = NSLock()
    private var reads = 0
    var sleepReads: Int { lock.withLock { reads } }

    init(_ base: MockHealthKitProvider) { self.base = base }

    var isHealthDataAvailable: Bool { base.isHealthDataAvailable }
    var sourceName: String { base.sourceName }
    func authorizationStatus() async -> HealthAuthorizationStatus { await base.authorizationStatus() }
    func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus { await base.requestAuthorization(for: kinds) }
    func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        lock.withLock { reads += 1 }
        return try await base.fetchSleepSamples(from: start, to: end)
    }
    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] { try await base.fetchHeartRateSamples(from: start, to: end) }
    func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] { try await base.fetchRestingHeartRate(from: start, to: end) }
    func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] { try await base.fetchHRVSamples(from: start, to: end) }
    func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] { try await base.fetchRespiratorySamples(from: start, to: end) }
    func sampleChanges() -> AsyncStream<Void> { base.sampleChanges() }
}

/// A clock a test moves.
private nonisolated final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var moment: Date
    init(_ moment: Date) { self.moment = moment }
    var now: Date { lock.withLock { moment } }
    func set(_ next: Date) { lock.withLock { moment = next } }
}

private struct Rig {
    let provider: CountingProvider
    let store: ReviewStore
    let repository: ReviewRepository
    let cardProvider: ReviewCardProvider
    let clock: Clock

    /// `scenario`'s nights as of `reference`, read on `moment` (a test moves the clock without moving the nights).
    init(_ scenario: MockScenario = .full, reference: Date = at(2026, 9, 28), now moment: Date? = nil, retryAfter: TimeInterval = 600) {
        let clock = Clock(moment ?? reference)
        let provider = CountingProvider(MockHealthKitProvider(scenario: scenario, referenceDate: reference, calendar: calendar(), startAuthorized: true))
        let store = ReviewStore()
        let repository = ReviewRepository(provider: provider, store: store, insights: InsightStore(), timeZone: { nyZone }, clock: { clock.now })
        self.provider = provider
        self.store = store
        self.repository = repository
        self.clock = clock
        cardProvider = ReviewCardProvider(repository: repository, retryAfter: retryAfter, clock: { clock.now })
    }

    func cards(weekday: Int = 1) async -> [HomeReviewCard] {
        await cardProvider.cards(profile: UserProfileSnapshot(), weekday: weekday, locale: Locale(identifier: "en_US"))
    }
}

// MARK: - The features

struct ReviewFeatureTests {
    @Test func theWeeklyCoverIsFreeAndTheRestOfTheReviewsArePremium() {
        #expect(FeatureTable.tier(of: .weeklyReviewCover) == .free)
        #expect(FeatureTable.tier(of: .weeklyReviewFull) == .premium && FeatureTable.tier(of: .monthlyReview) == .premium)
        #expect(FeatureTable.isIncluded(.weeklyReviewCover, in: .free) && !FeatureTable.isIncluded(.monthlyReview, in: .free) && FeatureTable.isIncluded(.monthlyReview, in: .premium))
        for feature in [Feature.weeklyReviewCover, .weeklyReviewFull, .monthlyReview] { #expect(FeatureTable.area(of: feature) == .reviews) }
        #expect(FeatureArea.reviews.title == "Reviews")
    }

    @Test func theCompareSheetListsThemPlainlyOnceEach() {
        let rows = FeatureTable.comparison().first { $0.area == .reviews }?.rows ?? []
        #expect(rows.map { $0.feature } == [.weeklyReviewCover, .weeklyReviewFull, .monthlyReview])
        #expect(rows.map { $0.title } == ["The summary of your weekly review", "Every page of your weekly review", "Your monthly review"])
        #expect(rows.map { $0.free } == [true, false, false])
        for row in rows { #expect(LockedCopy.pressure(in: row.title).isEmpty) }
        let all = FeatureTable.comparison().flatMap { $0.rows }.map { $0.feature }
        #expect(all.filter { [Feature.weeklyReviewCover, .weeklyReviewFull, .monthlyReview].contains($0) }.count == 3)
    }

    @Test func theLockedReviewsOpenThePaywallWithTheirOwnLine() {
        #expect(PaywallContext(feature: .weeklyReviewFull) == .weeklyReview && PaywallContext(feature: .monthlyReview) == .monthlyReview)
        #expect(PaywallContext.weeklyReview.line == "Unlock every page of your weekly review" && PaywallContext.monthlyReview.line == "Unlock your monthly review")
        #expect(PaywallContext(feature: .weeklyReviewCover) == .general, "a free feature has no lock to open")
        for context in [PaywallContext.weeklyReview, .monthlyReview] { #expect(LockedCopy.pressure(in: context.line).isEmpty) }
    }

    @Test func aCardOpensTheFeatureItIs() {
        let weekly = ReviewCardPolicy.card(for: ReviewPeriod.weekly(reviewDate: key(2026, 9, 27)), format: ReviewFormat(locale: Locale(identifier: "en_US")))
        let monthly = ReviewCardPolicy.card(for: ReviewPeriod.monthly(year: 2026, month: 9), format: ReviewFormat(locale: Locale(identifier: "en_US")))
        #expect(weekly.feature == .weeklyReviewCover && monthly.feature == .monthlyReview)
        #expect(weekly.title == "Your weekly review" && weekly.detail == "Sep 20 \u{2013} 26" && weekly.accessibilityLabel == "Your weekly review, Sep 20 \u{2013} 26")
        #expect(monthly.title == "Your monthly review" && monthly.detail == "September 2026")
    }
}

// MARK: - When a card is there

struct ReviewCardPolicyTests {
    private let week = ReviewPeriod.weekly(reviewDate: key(2026, 9, 27))

    @Test func aWeeksCardRunsFromTheReviewDaysFirstMomentForThreeDays() {
        let ny = calendar()
        #expect(!ReviewCardPolicy.isInWindow(week, now: at(2026, 9, 26, 23, 59), calendar: ny), "the week is not over")
        #expect(ReviewCardPolicy.isInWindow(week, now: at(2026, 9, 27, 0, 0), calendar: ny))
        #expect(ReviewCardPolicy.isInWindow(week, now: at(2026, 9, 29, 23, 59), calendar: ny), "Sunday, Monday and Tuesday")
        #expect(!ReviewCardPolicy.isInWindow(week, now: at(2026, 9, 30, 0, 0), calendar: ny), "three days have passed")
        #expect(ReviewCardPolicy.visibleDays == 3)
    }

    @Test func aMonthsCardRunsForTheFirstThreeDaysOfTheNextMonth() {
        let ny = calendar()
        let september = ReviewPeriod.monthly(year: 2026, month: 9)
        #expect(!ReviewCardPolicy.isInWindow(september, now: at(2026, 9, 30, 23, 59), calendar: ny))
        #expect(ReviewCardPolicy.isInWindow(september, now: at(2026, 10, 1, 0, 0), calendar: ny) && ReviewCardPolicy.isInWindow(september, now: at(2026, 10, 3, 23, 59), calendar: ny))
        #expect(!ReviewCardPolicy.isInWindow(september, now: at(2026, 10, 4, 0, 0), calendar: ny))
    }

    @Test func daylightSavingDoesNotChangeThreeDays() {
        let ny = calendar()
        // The week ending Oct 31, with clocks going back on Sunday Nov 1 (a 25-hour day): the card still runs Sun, Mon and Tue, to midnight.
        let autumn = ReviewPeriod.weekly(reviewDate: key(2026, 11, 1))
        #expect(ReviewCardPolicy.isInWindow(autumn, now: at(2026, 11, 3, 23, 59), calendar: ny) && !ReviewCardPolicy.isInWindow(autumn, now: at(2026, 11, 4, 0, 0), calendar: ny))
    }

    @Test func onlyAnUnopenedReviewShowsACard() {
        let ny = calendar()
        let fresh = StoredReview(record: ReviewTestRecords.record(week), state: .new, firstGeneratedAt: at(2026, 9, 27))
        var seen = fresh
        seen.state = .seen
        #expect(ReviewCardPolicy.isShown(fresh, now: at(2026, 9, 28), calendar: ny) && !ReviewCardPolicy.isShown(seen, now: at(2026, 9, 28), calendar: ny))
        #expect(!ReviewCardPolicy.isShown(fresh, now: at(2026, 10, 2), calendar: ny))
    }
}

// MARK: - The provider

struct ReviewCardProviderTests {
    @Test func onTheReviewDayTheWeekHasACardAndItIsMadeOnce() async {
        let rig = Rig(reference: at(2026, 9, 27))
        let cards = await rig.cards()
        #expect(cards.map { $0.id.description } == ["weekly-2026-09-26"] && cards.first?.title == "Your weekly review")
        let stored = await rig.store.stored(cards[0].id)
        #expect(stored?.state == .new && stored?.record.nightsRecorded == 7)
        let reads = rig.provider.sleepReads
        // Home refreshes again: the kept review is found, and Health is not read again.
        let again = await rig.cards()
        #expect(again == cards && rig.provider.sleepReads == reads)
    }

    @Test func aCardGoesWhenTheReviewIsOpenedAndDoesNotComeBack() async {
        let rig = Rig(reference: at(2026, 9, 28))
        let cards = await rig.cards()
        #expect(cards.count == 1)
        await rig.repository.markSeen(cards[0].id)
        let after = await rig.cards()
        #expect(after.isEmpty)
        rig.clock.set(at(2026, 9, 29))
        let later = await rig.cards()
        #expect(later.isEmpty)
    }

    @Test func aCardGoesByItselfAfterThreeDays() async {
        let rig = Rig(reference: at(2026, 9, 28), now: at(2026, 9, 29, 23, 0))
        #expect(await rig.cards().count == 1)
        rig.clock.set(at(2026, 9, 30, 0, 1))
        #expect(await rig.cards().isEmpty)
    }

    @Test func aWeekWithTooFewNightsHasNoCardAndHealthIsNotReadOverAndOver() async {
        let rig = Rig(.sparseWeek, reference: at(2026, 9, 28), retryAfter: 600)
        #expect(await rig.cards().isEmpty)
        let reads = rig.provider.sleepReads
        #expect(reads > 0)
        // Health changes and Home refreshes: not asked about again for ten minutes.
        #expect(await rig.cards().isEmpty && rig.provider.sleepReads == reads)
        rig.clock.set(at(2026, 9, 28, 10, 11))
        #expect(await rig.cards().isEmpty && rig.provider.sleepReads > reads, "after ten minutes it is asked about again, in case a night arrived")
        let kept = await rig.store.snapshot()
        #expect(kept.all.isEmpty, "too few nights is never kept")
    }

    @Test func noHealthAccessIsNoCard() async {
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: at(2026, 9, 28), calendar: calendar(), startAuthorized: false)
        let repository = ReviewRepository(provider: provider, store: ReviewStore(), insights: InsightStore(), timeZone: { nyZone }, clock: { at(2026, 9, 28) })
        let cards = await ReviewCardProvider(repository: repository, clock: { at(2026, 9, 28) }).cards(profile: UserProfileSnapshot(), weekday: 1)
        #expect(cards.isEmpty)
    }

    @Test func theMonthlyCardIsThereForTheFirstThreeDaysOfAMonthAndTheWeeklyOneHasGone() async {
        let rig = Rig(reference: at(2026, 10, 2))
        let cards = await rig.cards()
        #expect(cards.map { $0.id.description } == ["monthly-2026-09-30"] && cards.first?.detail == "September 2026")
        // Past the month's three days, and the next week's too (Sunday Oct 4's runs to Tuesday): nothing.
        rig.clock.set(at(2026, 10, 8))
        #expect(await rig.cards().isEmpty)
    }

    @Test func aMonthAndAWeekCanBothHaveACardOnTheSameDay() async {
        // Oct 4, 2026 is a Sunday: its week (Sep 27 - Oct 3) ended this morning and the month ended three days ago.
        let rig = Rig(reference: at(2026, 10, 4))
        let cards = await rig.cards()
        #expect(cards.map { $0.kind } == [.weekly], "the month's three days ended at midnight")
        let first = Rig(reference: at(2026, 11, 1))
        let both = await first.cards(weekday: 1)
        #expect(both.map { $0.kind } == [.weekly, .monthly], "Sunday Nov 1: the week ended and the month ended")
    }

    @Test func theReviewDayThePersonChoseDecidesTheWeek() async {
        // Wednesday Sep 30: a Wednesday review day makes Sep 23 - 29 the week, complete today.
        let rig = Rig(reference: at(2026, 9, 30))
        let wednesday = await rig.cards(weekday: 4)
        #expect(wednesday.map { $0.id.description } == ["weekly-2026-09-29"])
        let sunday = await Rig(reference: at(2026, 9, 30)).cards(weekday: 1)
        #expect(sunday.isEmpty, "Sunday's week ended three days ago")
    }

    @Test func deletedReviewsDoNotComeBackByThemselves() async {
        let rig = Rig(reference: at(2026, 9, 28))
        let cards = await rig.cards()
        #expect(cards.count == 1)
        await rig.cardProvider.reviewsDeleted(weekday: 1)
        #expect(await rig.cards().isEmpty)
    }
}

// MARK: - What opening a review lands on

struct ReviewRouteTests {
    private let format = ReviewFormat(locale: Locale(identifier: "en_US"))

    @Test func theLatestPeriodFollowsTheReviewDayAndAnIdNamesItsOwn() throws {
        let ny = calendar()
        let now = at(2026, 9, 30)
        #expect(ReviewRoute.period(kind: .weekly, id: nil, weekday: 1, now: now, calendar: ny).lastMorning == key(2026, 9, 26))
        #expect(ReviewRoute.period(kind: .weekly, id: nil, weekday: 4, now: now, calendar: ny).lastMorning == key(2026, 9, 29))
        #expect(ReviewRoute.period(kind: .monthly, id: nil, weekday: 1, now: now, calendar: ny) == ReviewPeriod.monthly(year: 2026, month: 8))
        let id = try #require(ReviewID("weekly-2026-09-12"))
        #expect(ReviewRoute.period(kind: .weekly, id: id, weekday: 4, now: now, calendar: ny).lastMorning == key(2026, 9, 12))
        // An id that names no period falls back to the latest.
        let bad = ReviewID(kind: .monthly, lastMorning: key(2026, 8, 15))
        #expect(ReviewRoute.period(kind: .monthly, id: bad, weekday: 1, now: now, calendar: ny) == ReviewPeriod.monthly(year: 2026, month: 8))
    }

    @Test func tooFewNightsIsTheRealCountAndAReviewHasNoMessage() async {
        let few = await Rig(.sparseWeek, reference: at(2026, 9, 28)).repository.review(ReviewPeriod.weekly(reviewDate: key(2026, 9, 27)), profile: UserProfileSnapshot())
        let period = ReviewPeriod.weekly(reviewDate: key(2026, 9, 27))
        guard case .notEnough(let content) = ReviewRoute.page(for: few, period: period, format: format) else { Issue.record("not enough nights: \(few)"); return }
        #expect(content.title == "Not enough nights yet" && content.count == "4 of 5 nights so far" && content.dateRange == "Sep 20 \u{2013} 26")
        #expect(content.detail == "Your weekly review appears once there are at least 5.")
        let enough = await Rig(reference: at(2026, 9, 28)).repository.review(period, profile: UserProfileSnapshot())
        #expect(ReviewRoute.page(for: enough, period: period, format: format) == nil, "a review is a story, not a message")
    }

    @Test func aPeriodNotOverIsSaidPlainlyWithNoCountClaimed() {
        let period = ReviewPeriod.weekly(reviewDate: key(2026, 10, 4))
        guard case .notOver(let content) = ReviewRoute.page(for: .notComplete, period: period, format: format) else { Issue.record("not over"); return }
        #expect(content.title == "This review isn't ready yet" && content.count == "Ready on Sun, Oct 4" && content.detail == "A week's review is made once the week is over.")
        #expect(!content.count.contains(" of "))
    }

    @Test func noHealthAndAFailedReadAreDifferentMessagesAndNeitherIsACountOfZero() {
        let period = ReviewPeriod.weekly(reviewDate: key(2026, 9, 27))
        guard case .noAccess(let title, let line) = ReviewRoute.page(for: .noAccess, period: period, format: format) else { Issue.record("no access"); return }
        #expect(title == "No Health data" && !line.contains("0 of"))
        guard case .failed(let failedTitle, let failedLine) = ReviewRoute.page(for: .unavailable, period: period, format: format) else { Issue.record("failed"); return }
        #expect(failedTitle == "Your review didn't load" && failedLine.contains("Try again"))
    }

    @Test func everyMessageIsFreeOfTheBannedLanguage() {
        let period = ReviewPeriod.weekly(reviewDate: key(2026, 9, 27))
        let month = ReviewPeriod.monthly(year: 2026, month: 9)
        var strings: [String] = []
        for (outcome, subject) in [(ReviewOutcome.notComplete, period), (.unavailable, period), (.noAccess, period), (.notEnoughNights(have: 19, need: 20), month), (.notEnoughNights(have: 4, need: 5), period)] {
            switch ReviewRoute.page(for: outcome, period: subject, format: format) {
            case .notEnough(let content), .notOver(let content): strings += [content.title, content.count, content.detail, content.dateRange]
            case .noAccess(let title, let line), .failed(let title, let line): strings += [title, line]
            case nil: break
            }
        }
        #expect(strings.count >= 16)
        for text in strings { #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: text)) }
    }
}

// MARK: - The page model and the app's routing

@MainActor
struct ReviewPageModelTests {
    private func story(_ rig: Rig, kind: ReviewKind = .weekly, unlocked: Bool = true, opened: Counter = Counter()) -> ReviewStoryViewModel {
        ReviewStoryViewModel(
            kind: kind, id: nil, repository: rig.repository, profile: { UserProfileSnapshot() }, weekday: { 1 }, isUnlocked: { _ in unlocked }, clock: { rig.clock.now },
            locale: Locale(identifier: "en_US"), opened: { opened.add() }
        )
    }

    @Test func openingAReviewMakesItMarksItSeenAndTellsHomeItsCardIsGone() async {
        let rig = Rig(reference: at(2026, 9, 28))
        let opened = Counter()
        let model = story(rig, opened: opened)
        #expect(model.phase == .loading)
        await model.load()
        guard case .story(let story) = model.phase else { Issue.record("a story: \(model.phase)"); return }
        #expect(story.title == "Your week" && story.dateRange == "Sep 20 \u{2013} 26" && model.pages.first?.kind == .cover)
        let stored = await rig.store.stored(ReviewPeriod.weekly(reviewDate: key(2026, 9, 27)).id)
        #expect(stored?.state == .seen && opened.value == 1)
    }

    @Test func aWeekWithFourNightsIsTheNotEnoughNightsMessageAndOpensNothingElse() async {
        let rig = Rig(.sparseWeek, reference: at(2026, 9, 28))
        let opened = Counter()
        let model = story(rig, opened: opened)
        await model.load()
        guard case .message(.notEnough(let content)) = model.phase else { Issue.record("not enough: \(model.phase)"); return }
        #expect(content.count == "4 of 5 nights so far" && opened.value == 0 && model.pages.isEmpty && !model.canShare)
    }

    @Test func noHealthAndAFailedReadAreTheirOwnMessages() async {
        let denied = Rig(.full, reference: at(2026, 9, 28))
        let deniedModel = ReviewStoryViewModel(
            kind: .weekly, id: nil,
            repository: ReviewRepository(
                provider: MockHealthKitProvider(scenario: .full, referenceDate: at(2026, 9, 28), calendar: calendar(), startAuthorized: false), store: ReviewStore(), insights: InsightStore(),
                timeZone: { nyZone }, clock: { denied.clock.now }
            ),
            profile: { UserProfileSnapshot() }, clock: { denied.clock.now }
        )
        await deniedModel.load()
        guard case .message(.noAccess) = deniedModel.phase else { Issue.record("no access: \(deniedModel.phase)"); return }
        let nothing = ReviewStoryViewModel(kind: .weekly, id: nil, repository: nil, profile: { UserProfileSnapshot() })
        await nothing.load()
        guard case .message(.failed) = nothing.phase else { Issue.record("failed: \(nothing.phase)"); return }
        // Try again runs the same load.
        await nothing.load()
        guard case .message(.failed) = nothing.phase else { Issue.record("still failed"); return }
    }

    private static func appModel(_ tier: Tier) throws -> AppModel {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        model.featureGate = FeatureGate(tier: tier)
        return model
    }

    @Test func theNotificationAndTheCardOpenTheWeeklyReviewOverTheInsightsTabOnEitherPlan() throws {
        for tier in [Tier.free, .premium] {
            let model = try Self.appModel(tier)
            model.selectedTab = .coach
            let route = try #require(NoctisNotification.route(for: NoctisNotification.weeklyReview, tier: tier))
            model.open(route)
            #expect(model.selectedTab == .insights && model.insightsPath == [.review(kind: .weekly, id: nil)], Comment(rawValue: tier.rawValue))
            let id = try #require(ReviewID("weekly-2026-09-26"))
            model.open(.review(kind: .weekly, id: id))
            #expect(model.insightsPath == [.review(kind: .weekly, id: id)])
        }
    }

    @Test func aLinkToTheMonthlyReviewOpensItsStoryOnEitherPlanAndNeverTheStoreByItself() throws {
        for tier in [Tier.premium, .free] {
            let model = try Self.appModel(tier)
            model.open(.review(kind: .monthly))
            #expect(model.selectedTab == .insights && model.insightsPath == [.review(kind: .monthly, id: nil)], Comment(rawValue: tier.rawValue))
            #expect(model.paywall == nil, "nothing was tapped, so nothing opens the paywall")
            #expect(model.isReviewStoryShowing, "the story is full-screen: the tab bar and the bedtime pill stay away")
        }
        let model = try Self.appModel(.free)
        model.open(.reviews)
        #expect(model.insightsPath == [.reviews] && !model.isReviewStoryShowing)
        model.selectedTab = .home
        model.insightsPath = [.review(kind: .weekly, id: nil)]
        #expect(!model.isReviewStoryShowing, "only while Insights is the tab showing")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}

// MARK: - Home

@MainActor
struct HomeReviewCardTests {
    private func homeModel(cards: @escaping () async -> [HomeReviewCard]) -> HomeViewModel {
        let now = at(2026, 9, 28)
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: calendar(), startAuthorized: true)
        return HomeViewModel(
            repository: HomeRepository(provider: provider, timeZone: nyZone, clock: { now }), profile: { UserProfileSnapshot() }, clock: { now }, calendar: calendar(),
            reviewCards: cards
        )
    }

    @Test func homeShowsTheCardsTheAppGivesItAndNoneBeforeThat() async {
        let card = ReviewCardPolicy.card(for: ReviewPeriod.weekly(reviewDate: key(2026, 9, 27)), format: ReviewFormat(locale: Locale(identifier: "en_US")))
        let model = homeModel { [card] }
        #expect(model.reviewCards.isEmpty)
        await model.refresh()
        #expect(model.reviewCards == [card])
        let none = homeModel { [] }
        await none.refresh()
        #expect(none.reviewCards.isEmpty, "absent when there is nothing honest to show")
    }

    @Test func aCardGoesWhenTheSourceStopsGivingIt() async {
        let box = CardBox([ReviewCardPolicy.card(for: ReviewPeriod.weekly(reviewDate: key(2026, 9, 27)), format: ReviewFormat(locale: Locale(identifier: "en_US")))])
        let model = homeModel { await box.cards }
        await model.refresh()
        #expect(model.reviewCards.count == 1)
        await box.set([])
        await model.refreshReviewCards()
        #expect(model.reviewCards.isEmpty)
    }

    @Test func theCardHasNoBadgeNoCountAndNoUrgencyInItsWords() {
        let format = ReviewFormat(locale: Locale(identifier: "en_US"))
        for period in [ReviewPeriod.weekly(reviewDate: key(2026, 9, 27)), ReviewPeriod.monthly(year: 2026, month: 9)] {
            let card = ReviewCardPolicy.card(for: period, format: format)
            for text in [card.title, card.detail, card.accessibilityLabel] {
                #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty && LockedCopy.pressure(in: text).isEmpty, Comment(rawValue: text))
                for word in ["new", "!", "ready", "don't", "miss", "unread"] { #expect(!text.lowercased().contains(word), Comment(rawValue: "\(text) has \(word)")) }
            }
        }
    }
}

private actor CardBox {
    private(set) var cards: [HomeReviewCard]
    init(_ cards: [HomeReviewCard]) { self.cards = cards }
    func set(_ next: [HomeReviewCard]) { cards = next }
}
