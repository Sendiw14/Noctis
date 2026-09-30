import Foundation
import Testing
@testable import InsightsKit
@testable import NoctisCore
@testable import SleepKit

/// Fatigue, dismissal, hiding, and the library that keeps every insight.
struct InsightV2FatigueTests {
    typealias R = InsightRecordFixture
    private let today = InsightFixture.last

    // MARK: - The same type is not featured again within three nights

    @Test func aTypeFeaturedTwoNightsAgoIsNotFeaturedAgain() {
        var history = InsightHistory()
        history.recordFeatured(R.bedtime(delta: 40, on: today.adding(days: -2)), on: today.adding(days: -2))
        #expect(!history.mayFeature(R.bedtime(delta: 41), on: today))
    }

    @Test func threeNightsLaterItMayReturn() {
        var history = InsightHistory()
        history.recordFeatured(R.bedtime(delta: 40, on: today.adding(days: -3)), on: today.adding(days: -3))
        #expect(history.mayFeature(R.bedtime(delta: 41), on: today))
        var recent = InsightHistory()
        recent.recordFeatured(R.bedtime(delta: 40, on: today.adding(days: -2)), on: today.adding(days: -2))
        #expect(!recent.mayFeature(R.bedtime(delta: 41), on: today), "two nights is still inside the three")
    }

    @Test func changedEvidenceOfTwentyPercentOrMoreMayReturnEarly() {
        var history = InsightHistory()
        history.recordFeatured(R.bedtime(delta: 100, on: today.adding(days: -1)), on: today.adding(days: -1))
        #expect(history.mayFeature(R.bedtime(delta: 120), on: today), "exactly 20% more")
        #expect(history.mayFeature(R.bedtime(delta: 80), on: today), "exactly 20% less")
        #expect(!history.mayFeature(R.bedtime(delta: 119.9), on: today))
        #expect(!history.mayFeature(R.bedtime(delta: 80.1), on: today))
    }

    @Test func aDifferentTypeIsNotHeldBack() {
        var history = InsightHistory()
        history.recordFeatured(R.bedtime(delta: 40, on: today.adding(days: -1)), on: today.adding(days: -1))
        #expect(history.mayFeature(R.duration(delta: -70), on: today))
    }

    @Test func fatigueMeasuresChangeFromZero() {
        #expect(InsightHistory.changed(from: 0, to: 1))
        #expect(!InsightHistory.changed(from: 0, to: 0))
        #expect(InsightHistory.changed(from: 100, to: 120))
        #expect(!InsightHistory.changed(from: 100, to: 119.94))
    }

    @Test func theFeaturedForAMorningIsWhatWasAlreadyFeaturedThen() {
        // The same evidence, on the same night, stays featured however often it is asked.
        let record = R.bedtime(delta: 55)
        var history = InsightHistory()
        #expect(history.featured(from: [record], on: today)?.id == record.id)
        history.recordFeatured(record, on: today)
        #expect(history.mayFeature(record, on: today), "the same evidence is not different evidence")
        #expect(history.featured(from: [R.duration(delta: -70), record], on: today)?.id == record.id, "chosen once, kept")
    }

    // MARK: - Hidden types

    @Test func aHiddenTypeIsNeverFeatured() {
        var history = InsightHistory()
        history.hide(type: .bedtimeShift)
        #expect(history.isHidden(.bedtimeShift))
        #expect(!history.mayFeature(R.bedtime(delta: 55), on: today))
        #expect(history.featured(from: [R.bedtime(delta: 55), R.duration(delta: -70)], on: today)?.type == .sleepDurationShift)
        #expect(history.featured(from: [R.bedtime(delta: 55)], on: today) == nil)
    }

    @Test func aHiddenTypeStopsBeingFeaturedEvenIfChosen() {
        let record = R.bedtime(delta: 55)
        var history = InsightHistory()
        history.recordFeatured(record, on: today)
        history.hide(type: .bedtimeShift)
        #expect(history.featured(from: [record], on: today) == nil, "nothing else to show")
        // With another insight about the night, hiding the featured kind moves on to it.
        let other = R.duration(delta: -70)
        #expect(history.featured(from: [record, other], on: today)?.id == other.id)
    }

    // MARK: - Dismissed insights

    @Test func aDismissedInsightNeverReturnsForTheSameEvidence() {
        let record = R.bedtime(delta: 55)
        var history = InsightHistory()
        history.dismiss(record)
        #expect(history.isDismissed(id: record.id))
        #expect(!history.mayFeature(record, on: today))
        #expect(!history.mayFeature(record, on: today.adding(days: 30)), "not a day count that lets it back")
        // Different evidence is a different insight.
        #expect(history.mayFeature(R.bedtime(delta: 56), on: today))
    }

    @Test func dismissingTheFeaturedInsightLeavesNoReplacementThatNight() {
        let record = R.bedtime(delta: 55)
        let other = R.duration(delta: -70)
        var history = InsightHistory()
        history.recordFeatured(record, on: today)
        history.dismiss(record)
        #expect(history.featured(from: [record, other], on: today) == nil, "the gap closes, nothing else steps in")
        // The next night starts fresh.
        #expect(history.featured(from: [other], on: today.adding(days: 1))?.id == other.id)
    }

    @Test func aFileWithExtraKeysStillDecodes() throws {
        // A file written while the v1 fatigue keys were still around: the extras are ignored.
        let file = #"{"lastShown":null,"dismissals":[],"hiddenKinds":[],"featuredTypes":{},"featuredByNight":{},"dismissedIDs":["bedtimeShift-3fa9c2d1"],"hiddenTypes":["weekendShift"]}"#
        let history = try JSONDecoder().decode(InsightHistory.self, from: Data(file.utf8))
        #expect(history.dismissedIDs == ["bedtimeShift-3fa9c2d1"])
        #expect(history.isHidden(.weekendShift))
    }

    @Test func historyRoundTrips() throws {
        var history = InsightHistory()
        history.recordFeatured(R.bedtime(delta: 55), on: today)
        history.dismiss(R.duration(delta: -70))
        history.hide(type: .weekendShift)
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(InsightHistory.self, from: data) == history)
    }
}

struct InsightLibraryTests {
    typealias R = InsightRecordFixture
    private let today = InsightFixture.last

    private func library(_ records: [InsightRecord]) -> InsightLibrary {
        var library = InsightLibrary()
        library.merge(records)
        return library
    }

    // MARK: - Merging

    @Test func mergeStoresNewInsightsAsNew() {
        let records = [R.bedtime(delta: 55), R.duration(delta: -70)]
        var library = InsightLibrary()
        let added = library.merge(records)
        #expect(Set(added) == Set(records.map(\.id)))
        #expect(library.entries.values.allSatisfy { $0.state == .new })
    }

    @Test func aRecordIsGeneratedOnceAndNeverRewritten() {
        // The same slot (type and night) with different numbers later in the day: the first stays.
        var library = library([R.bedtime(delta: 55)])
        let first = library.entries.values.first
        let added = library.merge([R.bedtime(delta: 58)])
        #expect(added.isEmpty)
        #expect(library.entries.count == 1)
        #expect(library.entries.values.first == first)
    }

    @Test func mergingTheSameRecordsTwiceChangesNothing() {
        var library = library([R.bedtime(delta: 55), R.pattern()])
        let before = library
        library.merge([R.bedtime(delta: 55), R.pattern()])
        #expect(library == before)
    }

    @Test func bothStagesShareANightBecauseTheyAreDifferentSlots() {
        let library = library([R.stage(.deep), R.stage(.rem)])
        #expect(library.entries.count == 2)
    }

    @Test func hiddenTypesAreNotStored() {
        var library = InsightLibrary()
        library.hide(.bedtimeShift)
        let added = library.merge([R.bedtime(delta: 55), R.duration(delta: -70)])
        #expect(added.count == 1)
        #expect(library.entries.count == 1)
    }

    @Test func aDismissedInsightIsNotAddedBack() {
        var library = library([R.bedtime(delta: 55)])
        let id = R.bedtime(delta: 55).id
        library.dismiss(id: id)
        #expect(library.entries[id]?.state == .dismissed)
        #expect(library.merge([R.bedtime(delta: 55)]).isEmpty)
        #expect(library.entries.count == 1)
    }

    @Test func oldInsightsAreDropped() {
        var library = library([R.bedtime(delta: 55, on: today.adding(days: -InsightLibrary.keptNights))])
        library.merge([R.duration(delta: -70)])
        #expect(library.entries.count == 1)
        #expect(library.entries.values.first?.record.type == .sleepDurationShift)
    }

    // MARK: - State

    @Test func openingAnInsightMarksItSeen() {
        var library = library([R.bedtime(delta: 55)])
        let id = R.bedtime(delta: 55).id
        library.markSeen(id: id)
        #expect(library.entries[id]?.state == .seen)
        library.dismiss(id: id)
        library.markSeen(id: id)
        #expect(library.entries[id]?.state == .dismissed, "seen never undoes a dismissal")
    }

    @Test func newThisWeekCountsNewInsightsFromTheLastSevenNights() {
        var library = library([
            R.bedtime(delta: 55), R.duration(delta: -70), R.balance(),
            R.weekend(on: today.adding(days: -6)), R.pattern(on: today.adding(days: -7)), R.milestone(7),
        ])
        #expect(library.newThisWeek(on: today).count == 4, "the milestone is information, the 8th-night-old pattern is out")
        library.markSeen(id: R.bedtime(delta: 55).id)
        #expect(library.newThisWeek(on: today).count == 3)
        library.dismiss(id: R.duration(delta: -70).id)
        #expect(library.newThisWeek(on: today).count == 2)
        library.hide(.sleepBalance)
        #expect(library.newThisWeek(on: today).count == 1)
    }

    // MARK: - What each screen reads

    @Test func hidingATypeRemovesItFromEverything() {
        var library = library([R.bedtime(delta: 55), R.duration(delta: -70)])
        library.hide(.bedtimeShift)
        #expect(library.visible.map(\.record.type) == [.sleepDurationShift])
        #expect(library.entry(id: R.bedtime(delta: 55).id) == nil)
        #expect(library.recent(on: today).map(\.record.type) == [.sleepDurationShift])
        #expect(library.featured(on: today)?.type == .sleepDurationShift)
    }

    @Test func historyIsNewestNightFirstAndKeepsDismissedOnes() {
        var library = library([R.bedtime(delta: 55, on: today.adding(days: -20)), R.duration(delta: -70), R.balance(on: today.adding(days: -3))])
        library.dismiss(id: R.duration(delta: -70).id)
        #expect(library.visible.map(\.record.night) == [today, today.adding(days: -3), today.adding(days: -20)])
        #expect(library.visible.first?.state == .dismissed, "muted in History, not gone")
    }

    @Test func recentKeepsTheLatestOfEachTypeFromTheLastFourteenNights() {
        let library = library([
            R.bedtime(delta: 55, on: today.adding(days: -2)), R.bedtime(delta: 60, on: today),
            R.duration(delta: -70, on: today.adding(days: -13)), R.balance(on: today.adding(days: -14)),
        ])
        let recent = library.recent(on: today)
        #expect(recent.map(\.record.type) == [.bedtimeShift, .sleepDurationShift], "one bedtime shift, the newest; the 15th night back is out")
        #expect(recent.first?.record.night == today)
    }

    @Test func recentLeavesOutDismissedInsights() {
        var library = library([R.bedtime(delta: 55), R.duration(delta: -70)])
        library.dismiss(id: R.duration(delta: -70).id)
        #expect(library.recent(on: today).map(\.record.type) == [.bedtimeShift])
    }

    @Test func recentKeepsDeepAndRemApart() {
        let library = library([R.stage(.deep), R.stage(.rem)])
        #expect(library.recent(on: today).count == 2)
    }

    // MARK: - The featured story

    @Test func theFeaturedIsTheTopRankedInsightAboutLastNight() {
        let library = library([R.bedtime(delta: 55), R.duration(delta: -70), R.pattern(), R.duration(delta: -50, on: today.adding(days: -1))])
        let featured = library.featured(on: today)
        // Duration and bedtime share confidence and actionability; the larger shift (70 minutes) leads.
        #expect(featured?.id == R.duration(delta: -70).id)
    }

    @Test func aMilestoneIsFeaturedOnlyWhenNothingElseIs() {
        #expect(library([R.milestone(7)]).featured(on: today)?.type == .milestone)
        #expect(library([R.milestone(7), R.pattern()]).featured(on: today)?.type == .earlierBedtimePattern)
    }

    @Test func theFeaturedInsightIsChosenOnceAndKept() {
        var library = library([R.duration(delta: -70)])
        let first = library.chooseFeatured(on: today)
        #expect(first?.type == .sleepDurationShift)
        // A better-ranked insight arrives later the same day: the featured doesn't change.
        library.merge([R.bedtime(delta: 55), R.streak()])
        #expect(library.chooseFeatured(on: today)?.id == first?.id)
        #expect(library.featured(on: today)?.id == first?.id)
    }

    @Test func homeAndTheTabAskTheSameLibraryAndGetTheSameAnswer() {
        var library = library([R.duration(delta: -70), R.bedtime(delta: 55), R.balance()])
        let forHome = library.chooseFeatured(on: today)
        let forTab = library.featured(on: today)
        #expect(forHome == forTab)
    }

    @Test func nothingStandsInForADismissedFeaturedInsight() {
        var library = library([R.duration(delta: -70), R.bedtime(delta: 55)])
        let featured = library.chooseFeatured(on: today)
        library.dismiss(id: featured?.id ?? "")
        #expect(library.featured(on: today) == nil)
        #expect(library.chooseFeatured(on: today) == nil)
    }

    @Test func aTypeRecentlyFeaturedGivesWayToTheNextOne() {
        var library = library([R.bedtime(delta: 55, on: today.adding(days: -1))])
        library.chooseFeatured(on: today.adding(days: -1))
        library.merge([R.bedtime(delta: 56), R.duration(delta: -70)])
        // Bedtime shift was featured last night and barely changed: duration takes its place.
        #expect(library.chooseFeatured(on: today)?.type == .sleepDurationShift)
    }

    @Test func libraryRoundTripsThroughJSON() throws {
        var library = library(R.everyVariant)
        library.chooseFeatured(on: today)
        library.dismiss(id: R.everyVariant[0].id)
        library.hide(.weekendShift)
        let data = try JSONEncoder().encode(library)
        #expect(try JSONDecoder().decode(InsightLibrary.self, from: data) == library)
    }
}

/// The file: derived values only, protected, excluded from backups, erased
/// with the rest of the person's data.
struct InsightStoreTests {
    typealias R = InsightRecordFixture
    private let today = InsightFixture.last

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "noctis-insight-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func aStoreKeepsItsInsightsAcrossLaunches() async {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = InsightStore(file: InsightFileStore(directory: folder))
        await first.ingest([R.duration(delta: -70), R.bedtime(delta: 55)], featuredOn: today)
        await first.dismiss(id: R.bedtime(delta: 55).id)
        await first.hide(.weekendShift)

        let reopened = InsightStore(file: InsightFileStore(directory: folder))
        let library = await reopened.snapshot()
        #expect(library.entries.count == 2)
        #expect(library.entries[R.bedtime(delta: 55).id]?.state == .dismissed)
        #expect(library.history.isHidden(.weekendShift))
        #expect(library.history.featuredByNight[today.description] != nil)
    }

    @Test func theSameEvidenceIsNotStoredTwice() async {
        let store = InsightStore()
        await store.ingest([R.duration(delta: -70)], featuredOn: today)
        let again = await store.ingest([R.duration(delta: -70)], featuredOn: today)
        #expect(again.entries.count == 1)
    }

    @Test func theFileHoldsDerivedValuesOnly() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = InsightFileStore(directory: folder)
        await InsightStore(file: file).ingest(R.everyVariant, featuredOn: today)
        let text = try String(contentsOf: file.fileURL, encoding: .utf8)
        for raw in ["sourceName", "sourceBundleID", "bundle", "device", "sample", "Apple Watch", "HKSample"] {
            #expect(!text.contains(raw), "no raw HealthKit record: \(raw)")
        }
        // Numbers and enums, never a sentence the builder writes.
        for phrase in ["Compared with", "Your recent data suggests", "This has coincided", "not proof"] {
            #expect(!text.contains(phrase), "words are written from numbers each time: \(phrase)")
        }
    }

    @Test func theFileIsExcludedFromBackups() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = InsightFileStore(directory: folder)
        await InsightStore(file: file).ingest([R.duration(delta: -70)], featuredOn: today)
        let values = try file.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func dataManagementErasesItThroughTheRegistry() async {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = InsightFileStore(directory: folder)
        let registry = NoctisDataRegistry()
        registry.register(file)
        #expect(registry.stores.map(\.erasableName) == ["Insights"])
        let store = InsightStore(file: file)
        await store.ingest([R.duration(delta: -70)], featuredOn: today)
        #expect(FileManager.default.fileExists(atPath: file.fileURL.path))
        registry.eraseAll()
        #expect(!FileManager.default.fileExists(atPath: file.fileURL.path))
        // The store holding a copy in memory forgets it too.
        #expect(await store.snapshot().entries.isEmpty)
        // A later write starts fresh.
        await store.ingest([R.bedtime(delta: 55)], featuredOn: today)
        #expect(await store.snapshot().entries.count == 1)
    }

    @Test func aFileFromAnotherSchemaIsDroppedNotHalfRead() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = InsightFileStore(directory: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"schema":999,"entries":{},"history":{}}"#.utf8).write(to: file.fileURL)
        #expect(file.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: file.fileURL.path))
        try Data("not json".utf8).write(to: file.fileURL)
        #expect(file.load() == nil)
    }

    @Test func markSeenAndHideGoThroughTheStore() async {
        let store = InsightStore()
        await store.ingest([R.duration(delta: -70), R.bedtime(delta: 55)], featuredOn: today)
        await store.markSeen(id: R.duration(delta: -70).id)
        await store.hide(.bedtimeShift)
        let library = await store.snapshot()
        #expect(library.entries[R.duration(delta: -70).id]?.state == .seen)
        #expect(library.visible.count == 1)
    }
}
