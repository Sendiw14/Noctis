import Foundation
import Testing

@testable import HealthProviding
@testable import InsightsKit
@testable import NoctisCore
@testable import ReviewKit
@testable import SleepKit

// The reviews' storage (APP_RULES.md R39): the library, the freeze and regenerate rules, the file (derived values only, protected, off the backups, erased by Data
// management), and the mock scenarios the reviews' screens are checked against, built end to end: mock provider -> inputs -> engine -> store.
// The clock and zone are fixed: 10:00 AM on Monday, Sep 28, 2026, New York.

private nonisolated let nyZone = TimeZone(identifier: "America/New_York") ?? .gmt
private nonisolated let tokyoZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

private nonisolated func calendar(_ zone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

private nonisolated let ny = calendar(nyZone)

private nonisolated func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0, _ second: Int = 0) -> Date {
    ny.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) ?? Date()
}

private nonisolated let now = at(2026, 9, 28, 10)
private nonisolated let weekPeriod = ReviewPeriod.latestWeekly(now: now, weekday: 1, calendar: ny)
private nonisolated let monthPeriod = ReviewPeriod.latestMonthly(now: now, calendar: ny)

private nonisolated func key(_ year: Int, _ month: Int, _ day: Int) -> SleepNightKey { SleepNightKey(year: year, month: month, day: day) }

/// A record every test of storage can use: the store neither reads nor changes the values in it.
nonisolated enum ReviewTestRecords {
    static func stored() -> StoredReview {
        let period = ReviewPeriod.weekly(reviewDate: SleepNightKey(year: 2026, month: 9, day: 27))
        return StoredReview(record: record(period), firstGeneratedAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    static func record(_ period: ReviewPeriod, nights: Int = 7, generatedAt: Date = Date(timeIntervalSince1970: 1_790_000_000), version: Int = ReviewRecord.currentVersion, firstMorning: SleepNightKey? = nil) -> ReviewRecord {
        ReviewRecord(
            id: period.id, firstMorning: firstMorning ?? period.firstMorning, lastMorning: period.lastMorning, generatedAt: generatedAt, nightsRecorded: nights,
            nightsInPeriod: period.morningCount, hasComparison: false, sleep: ReviewSleep(averageMinutes: 450, nightsReachedNeed: 3, needMinutes: 480, deltaMinutes: nil),
            consistency: ReviewConsistency(bedtimeSD: 20, wakeSD: 15, bedtimeSDDelta: nil, wakeSDDelta: nil), recovery: nil,
            heart: ReviewHeart(hrvAverage: nil, hrvDelta: nil, restingHeartRateAverage: nil, restingHeartRateDelta: nil),
            timing: ReviewTiming(medianBedtimeMinutes: 660, medianWakeMinutes: 1140, bedtimeShift: nil, wakeShift: nil), nights: [],
            biggestImprovement: .noComparison, biggestChange: .noComparison, topInsightIDs: [], nextFocus: .keepGoing, monthly: nil, version: version
        )
    }
}

/// A record of `period` with `nights` recorded: every other value is plain, since the store neither reads nor changes them.
private nonisolated func record(
    _ period: ReviewPeriod, nights: Int = 7, generatedAt: Date = now, version: Int = ReviewRecord.currentVersion, firstMorning: SleepNightKey? = nil
) -> ReviewRecord {
    ReviewTestRecords.record(period, nights: nights, generatedAt: generatedAt, version: version, firstMorning: firstMorning)
}

private nonisolated func stored(_ period: ReviewPeriod, nights: Int = 7, first: Date = now, state: ReviewState = .new) -> StoredReview {
    StoredReview(record: record(period, nights: nights, generatedAt: first), state: state, firstGeneratedAt: first)
}

/// How many times the store asked for a review to be built.
private nonisolated final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}

private nonisolated func tempFile() -> ReviewFileStore {
    ReviewFileStore(directory: FileManager.default.temporaryDirectory.appending(path: "reviews-\(UUID().uuidString)", directoryHint: .isDirectory))
}

// MARK: - The lifecycle

struct ReviewLifecycleTests {
    @Test func aPeriodNobodyHasAskedForIsMade() {
        #expect(ReviewLifecycle.action(stored: nil, now: now) == .generate)
    }

    @Test func aReviewIsMadeAgainFor24HoursAndFrozenAfter() {
        let first = now
        let review = stored(weekPeriod, first: first)
        #expect(ReviewLifecycle.action(stored: review, now: first) == .refresh)
        #expect(ReviewLifecycle.action(stored: review, now: first.addingTimeInterval(24 * 3600 - 1)) == .refresh)
        #expect(ReviewLifecycle.action(stored: review, now: first.addingTimeInterval(24 * 3600)) == .reuse)
        #expect(ReviewLifecycle.action(stored: review, now: first.addingTimeInterval(30 * 86_400)) == .reuse)
        #expect(ReviewLifecycle.refreshWindow == 86_400)
    }

    @Test func aRefreshKeepsTheNewRecordOnlyWhenTheNightsChanged() {
        let old = stored(weekPeriod, nights: 5, state: .seen)
        // A late night arrived: the new record, with the old state and the old first-made time.
        let more = ReviewLifecycle.refreshed(old, with: .record(record(weekPeriod, nights: 6, generatedAt: now.addingTimeInterval(3600))))
        #expect(more.record.nightsRecorded == 6 && more.state == .seen && more.firstGeneratedAt == old.firstGeneratedAt)
        // A night left (Health data was deleted) is a change as well.
        #expect(ReviewLifecycle.refreshed(old, with: .record(record(weekPeriod, nights: 4))).record.nightsRecorded == 4)
        // The same number of nights: left exactly as it was.
        #expect(ReviewLifecycle.refreshed(old, with: .record(record(weekPeriod, nights: 5, generatedAt: now.addingTimeInterval(3600)))) == old)
        // Too few nights now, or no result at all: the kept one stands.
        #expect(ReviewLifecycle.refreshed(old, with: .notEnoughNights(have: 3, need: 5)) == old)
    }
}

// MARK: - The library

struct ReviewLibraryTests {
    @Test func aLibraryKeepsReviewsNewestFirstAndFindsThemById() {
        var library = ReviewLibrary()
        let older = ReviewPeriod.weekly(reviewDate: key(2026, 9, 20))
        library.put(stored(older))
        library.put(stored(weekPeriod))
        library.put(stored(monthPeriod))
        let order = library.all.map { $0.id }
        // Newest last morning first: the week ending Sep 26, the week ending Sep 19, the month ending Aug 31.
        #expect(order == [weekPeriod.id, older.id, monthPeriod.id])
        #expect(library.all(of: .weekly).map { $0.id } == [weekPeriod.id, older.id])
        #expect(library.all(of: .monthly).map { $0.id } == [monthPeriod.id])
        #expect(library.latest(of: .weekly)?.id == weekPeriod.id && library.latest(of: .monthly)?.id == monthPeriod.id)
        #expect(library[older.id]?.id == older.id)
        #expect(library[ReviewID(kind: .weekly, lastMorning: key(2020, 1, 1))] == nil)
    }

    @Test func markSeenChangesOnlyTheState() {
        var library = ReviewLibrary()
        library.put(stored(weekPeriod))
        library.markSeen(weekPeriod.id)
        #expect(library[weekPeriod.id]?.state == .seen)
        library.markSeen(ReviewID(kind: .weekly, lastMorning: key(2020, 1, 1)))
        #expect(library.all.count == 1)
    }

    @Test func theOldestAreLetGoPastTheLimit() {
        var library = ReviewLibrary()
        for index in 0..<(ReviewLibrary.keptWeekly + 5) {
            library.put(stored(ReviewPeriod.weekly(reviewDate: key(2024, 1, 1).adding(days: index * 7))))
        }
        library.put(stored(monthPeriod))
        #expect(library.all(of: .weekly).count == ReviewLibrary.keptWeekly && library.all(of: .monthly).count == 1)
        let oldest = ReviewPeriod.weekly(reviewDate: key(2024, 1, 1))
        #expect(library[oldest.id] == nil, "the five oldest weeks went")
        let kept = ReviewPeriod.weekly(reviewDate: key(2024, 1, 1).adding(days: 5 * 7))
        #expect(library.all(of: .weekly).last?.id == kept.id)
        for index in 0..<(ReviewLibrary.keptMonthly + 2) {
            library.put(stored(ReviewPeriod.monthly(year: 2020 + index / 12, month: index % 12 + 1)))
        }
        #expect(library.all(of: .monthly).count == ReviewLibrary.keptMonthly)
    }

    @Test func aLibraryRoundTripsAsAListAndAnotherVersionIsNotRead() throws {
        var library = ReviewLibrary()
        library.put(stored(weekPeriod, state: .seen))
        library.put(stored(monthPeriod))
        let data = try JSONEncoder().encode(library)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let list = object["reviews"] as? [Any]
        #expect(list?.count == 2 && object["schema"] as? Int == 1, "a list, not an object keyed by a type JSON cannot key by")
        let decoded = try JSONDecoder().decode(ReviewLibrary.self, from: data)
        #expect(decoded == library)
        // A record of another version, or whose dates are not its id's, is not read.
        var other = library
        let future = ReviewPeriod.weekly(reviewDate: key(2026, 9, 13))
        other.put(StoredReview(record: record(future, version: 99), firstGeneratedAt: now))
        other.put(StoredReview(record: record(ReviewPeriod.monthly(year: 2026, month: 7), firstMorning: key(2026, 7, 10)), firstGeneratedAt: now))
        #expect(other.all.count == 4)
        other.dropUnreadable()
        #expect(other == library)
    }
}

// MARK: - The store

struct ReviewStoreTests {
    private func ask(
        _ store: ReviewStore, _ period: ReviewPeriod = weekPeriod, at moment: Date = now, calls: Calls, result: @escaping @Sendable () -> ReviewResult?
    ) async -> ReviewOutcome {
        await store.review(for: period, now: moment, calendar: ny) {
            calls.add()
            return result()
        }
    }

    @Test func aPeriodThatHasNotEndedIsNotReviewedAndReadsNothing() async {
        let store = ReviewStore()
        let calls = Calls()
        let early = at(2026, 9, 26, 23, 59, 59)
        let outcome = await ask(store, at: early, calls: calls) { .record(record(weekPeriod)) }
        let library = await store.snapshot()
        #expect(outcome == .notComplete && calls.value == 0 && library.all.isEmpty)
    }

    @Test func theFirstRequestAfterThePeriodEndsMakesItAndKeepsItNew() async {
        let store = ReviewStore()
        let calls = Calls()
        let outcome = await ask(store, calls: calls) { .record(record(weekPeriod, nights: 6)) }
        guard case .review(let review) = outcome else { Issue.record("a review"); return }
        #expect(review.state == .new && review.firstGeneratedAt == now && review.record.nightsRecorded == 6 && calls.value == 1)
        let kept = await store.stored(weekPeriod.id)
        #expect(kept == review)
    }

    @Test func tooFewNightsIsNotKeptSoItCanFillInLater() async {
        let store = ReviewStore()
        let calls = Calls()
        let outcome = await ask(store, calls: calls) { .notEnoughNights(have: 4, need: 5) }
        let library = await store.snapshot()
        #expect(outcome == .notEnoughNights(have: 4, need: 5) && library.all.isEmpty)
        // A night arrives: the next request makes it.
        let later = await ask(store, at: now.addingTimeInterval(3600), calls: calls) { .record(record(weekPeriod, nights: 5)) }
        guard case .review(let review) = later else { Issue.record("it fills in"); return }
        #expect(review.record.nightsRecorded == 5 && calls.value == 2)
    }

    @Test func aHealthThatCannotBeReadIsUnavailableAndNothingIsKept() async {
        let store = ReviewStore()
        let calls = Calls()
        let outcome = await ask(store, calls: calls) { nil }
        let library = await store.snapshot()
        #expect(outcome == .unavailable && library.all.isEmpty)
    }

    @Test func insideTheFirst24HoursItIsMadeAgainAndReplacedOnlyWhenTheNightsChanged() async {
        let store = ReviewStore()
        let calls = Calls()
        _ = await ask(store, calls: calls) { .record(record(weekPeriod, nights: 5)) }
        await store.markSeen(weekPeriod.id)
        // An hour later, a late night has arrived.
        let hour = now.addingTimeInterval(3600)
        let more = await ask(store, at: hour, calls: calls) { .record(record(weekPeriod, nights: 6, generatedAt: hour)) }
        guard case .review(let replaced) = more else { Issue.record("a review"); return }
        #expect(replaced.record.nightsRecorded == 6 && replaced.state == .seen && replaced.firstGeneratedAt == now && calls.value == 2)
        // Two hours later, the same six nights: the kept record is untouched.
        let two = now.addingTimeInterval(7200)
        let same = await ask(store, at: two, calls: calls) { .record(record(weekPeriod, nights: 6, generatedAt: two)) }
        #expect(same == .review(replaced) && calls.value == 3)
    }

    @Test func after24HoursItIsFrozenAndHealthIsNotReadAgain() async {
        let store = ReviewStore()
        let calls = Calls()
        _ = await ask(store, calls: calls) { .record(record(weekPeriod, nights: 5)) }
        let day = now.addingTimeInterval(24 * 3600)
        let outcome = await ask(store, at: day, calls: calls) { .record(record(weekPeriod, nights: 7)) }
        guard case .review(let review) = outcome else { Issue.record("a review"); return }
        #expect(review.record.nightsRecorded == 5 && calls.value == 1, "what was read once stays what was read")
        _ = await ask(store, at: day.addingTimeInterval(40 * 86_400), calls: calls) { nil }
        #expect(calls.value == 1)
    }

    @Test func aRequestInsideTheWindowThatCannotReadHealthKeepsWhatIsKept() async {
        let store = ReviewStore()
        let calls = Calls()
        _ = await ask(store, calls: calls) { .record(record(weekPeriod, nights: 5)) }
        let outcome = await ask(store, at: now.addingTimeInterval(60), calls: calls) { nil }
        guard case .review(let review) = outcome else { Issue.record("the kept one"); return }
        #expect(review.record.nightsRecorded == 5)
        let fewer = await ask(store, at: now.addingTimeInterval(120), calls: calls) { .notEnoughNights(have: 2, need: 5) }
        #expect(fewer == .review(review))
    }

    @Test func markSeenIsKeptAndHarmlessForAnUnknownId() async {
        let store = ReviewStore()
        let calls = Calls()
        _ = await ask(store, calls: calls) { .record(record(weekPeriod)) }
        await store.markSeen(weekPeriod.id)
        await store.markSeen(ReviewID(kind: .weekly, lastMorning: key(2020, 1, 1)))
        let kept = await store.stored(weekPeriod.id)
        let library = await store.snapshot()
        #expect(kept?.state == .seen && library.all.count == 1)
    }

    @Test func theFileKeepsReviewsAcrossLaunchesAndHoldsDerivedValuesOnly() async throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.fileURL.deletingLastPathComponent()) }
        let store = ReviewStore(file: file)
        let calls = Calls()
        _ = await ask(store, calls: calls) { .record(record(weekPeriod, nights: 6)) }
        await store.markSeen(weekPeriod.id)
        // A new launch finds it, with its state.
        let again = ReviewStore(file: file)
        let found = await again.stored(weekPeriod.id)
        #expect(found?.record.nightsRecorded == 6 && found?.state == .seen)
        // What is on disk: no raw sample, no source, no device, no words.
        let text = String(decoding: try Data(contentsOf: file.fileURL), as: UTF8.self).lowercased()
        for word in ["sourcename", "bundle", "device", "journal", "coach", "uuid", "sample"] { #expect(!text.contains(word), Comment(rawValue: word)) }
        // Off the backups.
        let values = try file.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(file.fileURL.lastPathComponent == "reviews.json" && file.erasableName == "Reviews")
    }

    @Test func eraseGoesThroughTheRegistryAndAStoreHoldingACopyForgetsIt() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.fileURL.deletingLastPathComponent()) }
        let registry = NoctisDataRegistry()
        registry.register(file)
        let store = ReviewStore(file: file)
        let calls = Calls()
        _ = await ask(store, calls: calls) { .record(record(weekPeriod)) }
        #expect(FileManager.default.fileExists(atPath: file.fileURL.path))
        registry.eraseAll()
        #expect(!FileManager.default.fileExists(atPath: file.fileURL.path) && file.load() == nil)
        let library = await store.snapshot()
        let gone = await store.stored(weekPeriod.id)
        #expect(library.all.isEmpty && gone == nil, "the copy in memory is gone too")
        // And it is made again when asked for.
        let later = now.addingTimeInterval(86_400 * 3)
        let outcome = await ask(store, at: later, calls: calls) { .record(record(weekPeriod, nights: 7)) }
        guard case .review(let review) = outcome else { Issue.record("made again"); return }
        #expect(review.state == .new && review.firstGeneratedAt == later)
    }

    @Test func aFileOfAnotherSchemaOrNoJSONAtAllIsDroppedNotHalfRead() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"schema\":7,\"reviews\":[]}".utf8).write(to: file.fileURL)
        #expect(file.load() == nil && !FileManager.default.fileExists(atPath: file.fileURL.path))
        try Data("not json".utf8).write(to: file.fileURL)
        #expect(file.load() == nil && !FileManager.default.fileExists(atPath: file.fileURL.path))
    }
}

// MARK: - The data inventory

struct ReviewInventoryTests {
    @Test func reviewsAreInTheInventoryAsDerivedValuesThatNeverLeaveTheDeviceAndCoachCannotRead() {
        let inventory = DataInventory.shared
        let category = inventory[.reviews]
        #expect(category.locations == [.file(.applicationSupport, "Noctis/reviews.json")])
        #expect(category.holdsUserContent == false && category.inBackup == false && category.protection == .completeWhileLocked)
        #expect(category.coach == .none, "Coach cannot read reviews")
        #expect(category.export == .included("reviews") && category.deletion == .button("Reviews"))
        #expect(inventory.category(forFile: "Noctis/reviews.json", in: .applicationSupport) == .reviews)
        #expect(inventory.groups.contains { $0.id == "reviews" && $0.categories == [.reviews] })
    }
}

// MARK: - The scenarios

/// The nights of `scenario` as the reviews read them.
private func nights(_ scenario: MockScenario) async throws -> [ReviewNightInput] {
    let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: ny, startAuthorized: true)
    let start = now.addingTimeInterval(-Double(ReviewInputsBuilder.historyDays) * 86_400 - 18 * 3600)
    async let sleep = provider.fetchSleepSamples(from: start, to: now)
    async let hrv = provider.fetchHRVSamples(from: start, to: now)
    async let resting = provider.fetchRestingHeartRate(from: start, to: now)
    return ReviewInputsBuilder.nights(sleep: try await sleep, hrv: try await hrv, restingHeartRate: try await resting, needMinutes: 480, now: now, timeZone: ny.timeZone)
}

private func review(
    _ scenario: MockScenario, _ period: ReviewPeriod = weekPeriod, insights: [ReviewInsightInput] = []
) async throws -> ReviewResult {
    ReviewEngine.build(period: period, nights: try await nights(scenario), needMinutes: 480, insights: insights, now: now, calendar: ny)
}

private func record(of result: ReviewResult) -> ReviewRecord? {
    if case .record(let value) = result { value } else { nil }
}

struct ReviewScenarioTests {
    private let insight = [ReviewInsightInput(id: "bedtimeShift-3fa9c2d1", generatedAt: at(2026, 9, 23, 8), score: 0.9)]

    @Test func theLatestPeriodsAreTheOnesTheScenariosTellTheirStoriesAbout() {
        #expect(weekPeriod.firstMorning == key(2026, 9, 20) && weekPeriod.lastMorning == key(2026, 9, 26))
        #expect(monthPeriod.firstMorning == key(2026, 8, 1) && monthPeriod.lastMorning == key(2026, 8, 31))
    }

    @Test func fullTriggersEveryPageOfAWeekAndOfAMonth() async throws {
        let weekResult = try await review(.full, insights: insight)
        let week = try #require(record(of: weekResult))
        #expect(week.nightsRecorded == 7 && week.hasComparison && week.recovery != nil && week.heart.hrvAverage != nil && week.heart.restingHeartRateAverage != nil)
        #expect(week.topInsightIDs == ["bedtimeShift-3fa9c2d1"] && week.monthly == nil)
        let weekKinds = Set(ReviewScreenBuilder.build(week).pages.map { $0.kind })
        #expect(weekKinds == Set(ReviewPageContent.Kind.allCases).subtracting([.records]), "every page a week has")
        let monthInsight = [ReviewInsightInput(id: "a", generatedAt: at(2026, 8, 12, 8), score: 0.9)]
        let monthResult = try await review(.full, monthPeriod, insights: monthInsight)
        let month = try #require(record(of: monthResult))
        #expect(month.nightsRecorded == 31 && month.hasComparison && month.monthly != nil && month.recovery != nil)
        #expect(Set(ReviewScreenBuilder.build(month).pages.map { $0.kind }) == Set(ReviewPageContent.Kind.allCases), "every page a month has")
    }

    @Test func steadyWeekMovesNothing() async throws {
        let result = try await review(.steadyWeek)
        let week = try #require(record(of: result))
        #expect(week.hasComparison && week.biggestChange == .steady && week.biggestImprovement == .steady && week.nextFocus == .keepGoing)
        let cover = try #require(ReviewScreenBuilder.build(week).page(.cover))
        #expect(cover.headline == "A steady week.")
    }

    @Test func improvedWeekTightensTheBedtime() async throws {
        let result = try await review(.improvedWeek)
        let week = try #require(record(of: result))
        let delta = try #require(week.consistency.bedtimeSDDelta)
        #expect(delta < -15 && week.consistency.bedtimeSD < 10, "the week's bedtimes are tight and the week before's were scattered")
        // Something improved, by more than half the person's own variation. Recovery's model counts consistency among its factors, so recovery rises with it, and
        // whichever moved more is what the cover says.
        guard case .change(let change) = week.biggestImprovement else { Issue.record("an improvement: \(week.biggestImprovement)"); return }
        #expect(change.goodness > 0.5 && (change.metric == .bedtimeVariation || change.metric == .recovery))
        let headline = try #require(ReviewScreenBuilder.build(week).page(.cover)?.headline)
        #expect(headline == "Compared with the week before, your bedtimes were steadier." || headline == "Compared with the week before, your recovery averaged higher.")
        // Sleep itself did not move: the story is about consistency.
        #expect(abs(try #require(week.sleep.deltaMinutes)) < 10)
    }

    @Test func laterWeekShiftsTheBedtimeAnHourLater() async throws {
        let result = try await review(.laterWeek)
        let week = try #require(record(of: result))
        let shift = try #require(week.timing.bedtimeShift)
        #expect(shift > 55 && shift < 75)
        guard case .gentleShiftBack = week.nextFocus else { Issue.record("a gentle shift back: \(week.nextFocus)"); return }
        #expect(week.biggestImprovement == .steady, "nothing improved by a week going to bed later")
    }

    @Test func sparseWeekHasFourNightsOfFive() async throws {
        let result = try await review(.sparseWeek)
        #expect(result == .notEnoughNights(have: 4, need: 5))
        let content = ReviewScreenBuilder.notReady(period: weekPeriod, have: 4, need: 5, format: ReviewFormat(locale: Locale(identifier: "en_US")))
        #expect(content.count == "4 of 5 nights")
    }

    @Test func variedMonthHasWeeksThatDiffer() async throws {
        let result = try await review(.variedMonth, monthPeriod)
        let month = try #require(record(of: result))
        #expect(month.nightsRecorded == 31 && month.monthly != nil)
        func inWeek(_ week: Int) -> [ReviewNightValues] { month.nights.filter { $0.morning.days(from: monthPeriod.firstMorning) / 7 == week } }
        let medians = (0..<4).map { week in inWeek(week).map { Double($0.bedtimeMinutes) }.sorted()[3] }
        #expect((medians.max() ?? 0) - (medians.min() ?? 0) > 40, "the weeks' own bedtimes: \(medians)")
        let asleep = (0..<4).map { week in inWeek(week).map { Double($0.asleepMinutes) }.reduce(0, +) / 7 }
        #expect((asleep.max() ?? 0) - (asleep.min() ?? 0) > 45, "the weeks' own sleep: \(asleep)")
        #expect(inWeek(0).count == 7 && inWeek(3).count == 7)
        #expect(month.consistency.bedtimeSD > 25)
    }

    @Test func everyScenarioReadsToTheSameRecordTwice() async throws {
        for scenario in [MockScenario.full, .steadyWeek, .improvedWeek, .laterWeek, .variedMonth] {
            let first = try await review(scenario)
            let second = try await review(scenario)
            #expect(first == second, Comment(rawValue: scenario.rawValue))
        }
    }

    @Test func theSentencesOfEveryScenarioAreFreeOfTheBannedLanguage() async throws {
        let format = ReviewFormat(locale: Locale(identifier: "en_US"))
        var strings: [String] = []
        for scenario in [MockScenario.full, .steadyWeek, .improvedWeek, .laterWeek, .variedMonth, .highs, .recoveryDip, .hrvDip, .lateBedtime] {
            for period in [weekPeriod, monthPeriod] {
                let result = try await review(scenario, period, insights: insight)
                if let record = record(of: result) { strings += ReviewScreenBuilder.allStrings(record, format: format) }
            }
        }
        #expect(strings.count > 200)
        for text in strings { #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: text)) }
    }
}

// MARK: - The repository

struct ReviewRepositoryTests {
    private func repository(_ scenario: MockScenario = .full, store: ReviewStore = ReviewStore(), moment: Date = now, authorized: Bool = true, fails: Bool = false) -> ReviewRepository {
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: ny, startAuthorized: authorized, failsQueries: fails)
        return ReviewRepository(provider: provider, store: store, insights: InsightStore(), timeZone: { nyZone }, clock: { moment })
    }

    @Test func itReadsHealthMakesTheReviewAndKeepsIt() async throws {
        let store = ReviewStore()
        let repository = repository(store: store)
        let period = await repository.latestWeekly(weekday: 1)
        #expect(period == weekPeriod)
        let outcome = await repository.review(period, profile: UserProfileSnapshot())
        guard case .review(let review) = outcome else { Issue.record("a review: \(outcome)"); return }
        #expect(review.state == .new && review.record.nightsRecorded == 7 && review.record.id == weekPeriod.id)
        let kept = await store.stored(weekPeriod.id)
        #expect(kept == review)
        await repository.markSeen(weekPeriod.id)
        let seen = await repository.stored(weekPeriod.id)
        let monthly = await repository.latestMonthly()
        #expect(seen?.state == .seen && monthly == monthPeriod)
    }

    @Test func theRepositoryAndTheEngineAgree() async throws {
        let outcome = await repository(.improvedWeek).review(weekPeriod, profile: UserProfileSnapshot())
        guard case .review(let kept) = outcome else { Issue.record("a review"); return }
        let direct = try await review(.improvedWeek)
        #expect(direct == .record(kept.record))
    }

    @Test func fewNightsIsTheCountAndNotAReview() async {
        let outcome = await repository(.sparseWeek).review(weekPeriod, profile: UserProfileSnapshot())
        #expect(outcome == .notEnoughNights(have: 4, need: 5))
    }

    @Test func aWeekThatHasNotEndedIsNotComplete() async {
        let outcome = await repository(moment: at(2026, 9, 26, 12)).review(weekPeriod, profile: UserProfileSnapshot())
        #expect(outcome == .notComplete)
    }

    @Test func noAccessOrAFailedReadIsUnavailableNotACountOfZero() async {
        let denied = await repository(authorized: false).review(weekPeriod, profile: UserProfileSnapshot())
        let failed = await repository(fails: true).review(weekPeriod, profile: UserProfileSnapshot())
        #expect(denied == .unavailable && failed == .unavailable)
    }

    @Test func aTimeZoneThatMovesTheDayMovesTheLatestWeekAndNothingElse() async {
        let moment = at(2026, 9, 26, 23, 30)
        let tokyo = ReviewRepository(
            provider: MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: ny, startAuthorized: true), store: ReviewStore(), insights: InsightStore(),
            timeZone: { tokyoZone }, clock: { moment }
        )
        // 23:30 on Saturday in New York is Sunday 12:30 in Tokyo: the review day has begun there.
        let there = await tokyo.latestWeekly(weekday: 1)
        let here = await repository(moment: moment).latestWeekly(weekday: 1)
        #expect(there.lastMorning == key(2026, 9, 26) && here.lastMorning == key(2026, 9, 19))
    }
}
