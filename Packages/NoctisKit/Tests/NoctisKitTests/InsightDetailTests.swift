import Foundation
import HealthProviding
import Testing

@testable import HomeFeature
@testable import InsightsFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import SleepKit

/// An insight's page and History: what each says, from the stored record.
struct InsightDetailTests {
    typealias R = InsightRecordFixture
    private let now = Fixture.date(2026, 9, 24, 10)

    private func detail(_ record: InsightRecord, state: InsightState = .new) -> InsightDetailContent {
        InsightsScreenBuilder.detail(StoredInsight(record: record, state: state), calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
    }

    private func history(_ entries: [StoredInsight], filter: InsightCategory? = nil, hidden: [InsightType] = []) -> InsightHistoryContent {
        var library = InsightLibrary()
        library.merge(entries.map(\.record))
        for entry in entries where entry.state == .dismissed { library.dismiss(id: entry.id) }
        for type in hidden { library.hide(type) }
        let snapshot = InsightsSnapshot(
            dataState: .ready, night: InsightFixture.last, nightsRecorded: 40, featured: nil, recent: [], all: library.visible,
            newThisWeek: 0, records: [], lastUpdated: now
        )
        return InsightsScreenBuilder.history(snapshot, filter: filter, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
    }

    // MARK: - The page

    @Test func everyKindOfInsightHasAWholePage() {
        for record in R.everyVariant {
            let page = detail(record)
            #expect(page.id == record.id)
            #expect(!page.title.isEmpty && !page.context.isEmpty && !page.interpretation.isEmpty && !page.whatToNotice.isEmpty, "\(record.type.rawValue)")
            #expect(page.evidenceLines.allSatisfy { $0.contains(" · ") }, "label · value: \(record.type.rawValue)")
            #expect(!page.method.rule.isEmpty && !page.method.thresholds.isEmpty && !page.method.nights.isEmpty)
            #expect(page.confidenceLine.contains("confidence · based on"))
            #expect((page.whatYouCanTry != nil) == record.type.offersSomethingToTry, "\(record.type.rawValue)")
            #expect((page.notProofLine != nil) == record.type.isPattern)
            #expect((page.chart == nil) == (record.type == .milestone), "\(record.type.rawValue)")
            #expect(page.dateLine == "Wed, Sep 23")
        }
    }

    @Test func aPatternSaysWhatItRestsOn() throws {
        let page = detail(R.pattern(earlier: true, early: 16, late: 17))
        #expect(page.notProofLine == "This is a pattern in your data, not proof of a cause.")
        #expect(page.method.thresholds.count == 3)
        #expect(page.method.nights == "16 earlier and 17 later nights (effect size 2.4).")
        #expect(page.method.rule.contains("60 nights"))
        // The chart carries both groups' sample sizes.
        guard case .groups(let groups)? = page.chart else {
            Issue.record("expected groups")
            return
        }
        #expect(groups.groups.map(\.countText) == ["16 nights", "17 nights"])
    }

    @Test func aDurationInsightHasBarsAndItsThreshold() {
        let page = detail(R.duration(delta: -70))
        #expect(page.title == "Shorter night than usual")
        #expect(page.method.thresholds == ["Shown when last night is 30 minutes or more away from your usual."])
        #expect(page.confidenceLine == "High confidence · based on 14 nights")
        #expect(page.whatYouCanTry == "Leave a little extra room for sleep tonight, if your evening allows.")
        #expect(page.numbers.map(\.value.plain) == ["7h", "5h 50m"])
    }

    @Test func aDismissedInsightSaysSo() {
        #expect(!detail(R.duration(delta: -70), state: .new).dismissed)
        #expect(!detail(R.duration(delta: -70), state: .seen).dismissed)
        #expect(detail(R.duration(delta: -70), state: .dismissed).dismissed)
    }

    // MARK: - History

    private func stored(_ record: InsightRecord, _ state: InsightState = .seen) -> StoredInsight {
        StoredInsight(record: record, state: state)
    }

    @Test func historyIsGroupedByMonthNewestFirst() {
        let content = history([
            stored(R.bedtime(delta: 55, on: SleepNightKey(year: 2026, month: 9, day: 23))),
            stored(R.duration(delta: -70, on: SleepNightKey(year: 2026, month: 9, day: 2))),
            stored(R.balance(on: SleepNightKey(year: 2026, month: 8, day: 30))),
            stored(R.pattern(on: SleepNightKey(year: 2026, month: 7, day: 14))),
        ])
        #expect(content.months.map(\.title) == ["September 2026", "August 2026", "July 2026"])
        #expect(content.months[0].rows.map(\.type) == [.bedtimeShift, .sleepDurationShift])
        #expect(content.months[0].rows.map(\.date) == ["Sep 23", "Sep 2"])
        #expect(content.summary == "4 insights so far.")
        #expect(content.note == nil)
    }

    @Test func historyKeepsDismissedInsightsMuted() throws {
        let content = history([stored(R.bedtime(delta: 55)), stored(R.duration(delta: -70), .dismissed)])
        let rows = content.months.flatMap(\.rows)
        #expect(rows.count == 2)
        let muted = try #require(rows.first { $0.type == .sleepDurationShift })
        #expect(muted.dismissed)
        #expect(muted.accessibilityLabel.hasSuffix("Marked not useful."))
        #expect(rows.first { $0.type == .bedtimeShift }?.dismissed == false)
    }

    @Test func historyLeavesOutHiddenTypes() {
        let content = history([stored(R.bedtime(delta: 55)), stored(R.duration(delta: -70))], hidden: [.bedtimeShift])
        #expect(content.months.flatMap(\.rows).map(\.type) == [.sleepDurationShift])
        #expect(content.summary == "1 insight so far.")
    }

    @Test func historyFiltersByTheSameChips() {
        let entries = [stored(R.bedtime(delta: 55)), stored(R.duration(delta: -70)), stored(R.balance()), stored(R.heart(.hrv))]
        let sleep = history(entries, filter: .sleep)
        #expect(sleep.months.flatMap(\.rows).map(\.category).allSatisfy { $0 == .sleep })
        #expect(sleep.months.flatMap(\.rows).count == 2)
        #expect(sleep.chips.map(\.title) == ["All", "Sleep", "Recovery", "Timing", "Consistency", "Heart", "Long-term"])
        let none = history(entries, filter: .recovery)
        #expect(none.months.isEmpty)
        #expect(none.note?.title == "No recovery insights yet")
        #expect(none.summary == "Nothing yet.")
        #expect(history([]).note?.title == "No insights yet")
    }

    @Test func aRowsAccessibilityLabelHasItsDayAndEvidence() throws {
        let row = try #require(history([stored(R.bedtime(delta: 55))]).months.first?.rows.first)
        #expect(row.accessibilityLabel.hasPrefix("Later bedtime than usual, Wed, Sep 23."))
        #expect(row.accessibilityLabel.contains("55 min later"))
    }
}

struct InsightHistoryViewModelTests {
    private let now = Fixture.date(2026, 9, 24, 10)

    private func viewModel() -> InsightsViewModel {
        let clock = now
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let repository = InsightsRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock })
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)")!
        return InsightsViewModel(
            repository: repository, profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: defaults, key: InsightsViewModel.introKey),
            washGate: HomeIntroGate(defaults: defaults, key: InsightsViewModel.washKey),
            reduceMotion: { true }, lowPower: { false }, clock: { clock }, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US")
        )
    }

    @Test func historyStartsOnTheTabsChipAndHasItsOwn() async {
        let model = viewModel()
        await model.onAppear()
        #expect(model.history?.months.flatMap(\.rows).count == model.snapshot?.all.count)
        model.select(filter: .sleep)
        model.openHistory()
        #expect(model.historyFilter == .sleep)
        #expect(model.history?.months.flatMap(\.rows).allSatisfy { $0.category == .sleep } == true)
        model.select(historyFilter: nil)
        #expect(model.historyFilter == nil)
        #expect(model.filter == .sleep, "History's chip doesn't move the tab's")
        #expect(model.history?.months.flatMap(\.rows).count == model.snapshot?.all.count)
    }

    @Test func aDismissedInsightStaysInHistory() async throws {
        let model = viewModel()
        await model.onAppear()
        let id = try #require(model.screen?.featured?.id)
        let before = model.history?.months.flatMap(\.rows).count
        await model.dismiss(id: id)
        #expect(model.history?.months.flatMap(\.rows).count == before)
        #expect(model.history?.months.flatMap(\.rows).first { $0.id == id }?.dismissed == true)
        #expect(model.detail(id: id)?.dismissed == true)
    }

    @Test func hidingRemovesItFromHistoryAndItsPage() async throws {
        let model = viewModel()
        await model.onAppear()
        let entry = try #require(model.snapshot?.recent.first)
        await model.hide(entry.record.type)
        #expect(model.history?.months.flatMap(\.rows).contains { $0.id == entry.id } != true)
        #expect(model.detail(id: entry.id) == nil)
    }

    @Test func aPageForAnUnknownIdIsNil() async {
        let model = viewModel()
        #expect(model.detail(id: "nope") == nil)
        await model.onAppear()
        #expect(model.detail(id: "nope") == nil)
    }
}
