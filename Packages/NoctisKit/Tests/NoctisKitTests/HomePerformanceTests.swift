import DesignSystem
import Foundation
import Observation
import SwiftUI
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepKit

// Home v4, part 2: the render model, the saved snapshot, the minute clock,
// and the rules that keep the root from re-evaluating.

/// 10 AM on Sep 24, 2026 in New York (`Fixture.date(2026, 9, 24, 10)`),
/// built without the main actor so `@Sendable` clocks can use it.
private nonisolated let now: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 10)) ?? Date()
}()

/// Whether an observed property changed: `withObservationTracking`'s
/// `onChange` is called synchronously at the mutation, on any thread.
private nonisolated final class Change: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    var happened: Bool { lock.withLock { fired } }
    func mark() { lock.withLock { fired = true } }
}

/// Starts watching `read`'s properties; the returned flag is set by the
/// first change to any of them.
@MainActor
private func watch(_ read: () -> Void) -> Change {
    let change = Change()
    withObservationTracking(read) { change.mark() }
    return change
}

private func snapshot(_ scenario: MockScenario = .full, at date: Date = now) async -> HomeSnapshot {
    let provider = MockHealthKitProvider(scenario: scenario, referenceDate: date, calendar: Fixture.calendar(), startAuthorized: true)
    return await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { date }).refresh(profile: UserProfileSnapshot())
}

// MARK: - Render model

struct HomeRenderModelTests {
    @Test func theRingsArcsAreTheLayoutsAndTheTicksSitOnThem() async throws {
        let render = await snapshot().render
        #expect(render.ring.count == 4)
        let weights = render.ring.map(\.weight)
        let layout = NoctisRecoveryRingLayout.arcs(weights: weights)
        for (arc, expected) in zip(render.ring, layout) {
            #expect(arc.startDegrees == expected.start && arc.endDegrees == expected.end)
        }
        // 3° visible gaps between neighbors.
        for (a, b) in zip(render.ring, render.ring.dropFirst()) {
            #expect(abs((b.startDegrees - a.endDegrees) - NoctisRecoveryRingLayout.gapDegrees) < 1e-9)
        }
        for (index, arc) in render.ring.enumerated() {
            guard let usual = arc.usual, let tick = arc.tickDegrees else {
                #expect(arc.usual == nil && arc.tickDegrees == nil)
                continue
            }
            #expect(tick == NoctisRecoveryRingLayout.tickAngle(weights: weights, index: index, usual: usual))
            #expect(tick >= arc.startDegrees && tick <= arc.endDegrees)
        }
    }

    @Test func noScoreMeansNoArcsNoSparklinesAndNoNight() async {
        for scenario in [MockScenario.learning, .empty] {
            let render = await snapshot(scenario).render
            #expect(render.ring.isEmpty)
            #expect(render.sparklines.isEmpty)
        }
        #expect(await snapshot(.empty).render.night == nil)
    }

    @Test func theWeekBarsAreSharesOfTheTallestNightOrTheNeed() async throws {
        let snap = await snapshot()
        let week = snap.render.week
        #expect(week.bars.count == snap.recentNights.count)
        let need = Double(snap.tonight.needMinutes)
        let top = max(need, snap.recentNights.compactMap(\.asleepMinutes).max() ?? 0) * WeekRenderBuilder.headroom
        #expect(abs(week.needFraction - need / top) < 1e-12)
        for (bar, night) in zip(week.bars, snap.recentNights) {
            #expect(bar.fraction == night.asleepMinutes.map { $0 / top })
            if let stages = bar.stages {
                #expect(abs(stages.deep + stages.core + stages.rem - 1) < 1e-9)
            }
            #expect(bar.isLastNight == (night.night == snap.lastNight?.night))
        }
        #expect(week.bars.filter(\.isLastNight).count <= 1)
    }

    @Test func aNightWithNoDataIsAnEmptyTrackNotAZeroBar() {
        let nights = [
            NightDuration(night: SleepNightKey(year: 2026, month: 9, day: 22), asleepMinutes: nil),
            NightDuration(night: SleepNightKey(year: 2026, month: 9, day: 23), asleepMinutes: 420),
        ]
        let week = WeekRenderBuilder.build(nights, needMinutes: 480, lastNight: nil)
        #expect(week.bars[0].fraction == nil)
        #expect(week.bars[1].fraction == 420 / (480 * WeekRenderBuilder.headroom))
    }

    @Test func theNightsRenderIsTheBuildersAndTheHeartLineIsInTheStripsSpace() async throws {
        let snap = await snapshot()
        let night = try #require(snap.render.night)
        let session = try #require(snap.lastNight)
        #expect(night == NightRenderBuilder.build(session, heart: snap.lastNightHeart))
        let heart = try #require(night.heart)
        #expect(heart.points.allSatisfy { (0...1).contains($0.y) && (0...1).contains($0.x) })
        #expect(heart.points.map(\.y).min().map { abs($0 - heart.lowest.y) < 1e-12 } == true)
        #expect(heart.high > heart.low)
    }

    @Test func theRibbonLaneLookupMatchesALinearSearch() async throws {
        let night = try #require(await snapshot(.messyNight).render.night)
        #expect(night.ribbon.count > 10)
        func linear(_ position: Double) -> NightLane? {
            guard let first = night.ribbon.first else { return nil }
            if position <= first.start { return first.lane }
            return (night.ribbon.last { $0.start <= position } ?? first).lane
        }
        for step in 0...1000 {
            let position = Double(step) / 1000
            #expect(night.lane(at: position) == linear(position), "\(position)")
        }
    }

    @Test func sparklinesScaleEachFactorToOneChart() async throws {
        let render = await snapshot().render
        #expect(!render.sparklines.isEmpty)
        for line in render.sparklines {
            #expect(line.bandLow < line.bandHigh)
            #expect((0...1).contains(line.today))
            #expect(line.nights.compactMap { $0 }.allSatisfy { (0...1).contains($0) })
            #expect(render.sparkline(line.kind) == line)
        }
    }

    @Test func aSnapshotCarriesItsRenderModelAndViewsReadItRatherThanRecomputing() async throws {
        let snap = await snapshot()
        // Built once with the snapshot…
        #expect(snap.render != .empty)
        // …and used as given: a snapshot handed a model keeps exactly it.
        let handed = HomeSnapshot(
            dataState: snap.dataState, recovery: snap.recovery, lastNight: snap.lastNight, latestSleep: snap.latestSleep,
            recentNights: snap.recentNights, weekAverageMinutes: snap.weekAverageMinutes, tonight: snap.tonight,
            topInsight: snap.topInsight, lastNightHeart: snap.lastNightHeart, newestSample: snap.newestSample,
            lastUpdated: snap.lastUpdated, render: .empty
        )
        #expect(handed.render == .empty)
        #expect(snap.replacingInsight(nil).render == snap.render)
    }

    @Test func theScreenReadsItsGeometryFromTheSnapshotsModel() async throws {
        let snap = await snapshot()
        let screen = HomeScreenBuilder.build(snap, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        guard case .scored(let scored) = screen.recovery else {
            Issue.record("not scored")
            return
        }
        #expect(scored.segments.map(\.arc) == snap.render.ring)
        #expect(screen.lastNight?.chart.render == snap.render.night)
        #expect(screen.week?.bars.map(\.fraction) == snap.render.week.bars.map(\.fraction))
    }
}

// MARK: - The saved snapshot

struct HomeSnapshotStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "noctis-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func store(_ directory: URL, at date: Date = now) -> HomeSnapshotStore {
        HomeSnapshotStore(directory: directory, clock: { date })
    }

    @Test func whatIsWrittenComesBackWithoutTheStageTimelineOrTheSource() async throws {
        let dir = directory()
        let snap = await snapshot()
        store(dir).save(snap)
        let restored = try #require(store(dir).load())
        #expect(restored.dataState == snap.dataState)
        #expect(restored.recovery == snap.recovery)
        #expect(restored.recentNights == snap.recentNights)
        #expect(restored.tonight == snap.tonight)
        #expect(restored.topInsight == snap.topInsight)
        #expect(restored.lastNightHeart == snap.lastNightHeart)
        #expect(restored.render == snap.render)
        #expect(restored.lastNight?.totals == snap.lastNight?.totals)
        #expect(restored.lastNight?.bedtime == snap.lastNight?.bedtime)
        #expect(restored.lastNight?.timeline.isEmpty == true)
        #expect(restored.lastNight?.sourceName == "")
        // The screen built from it says what the screen built from the real one does.
        let locale = Locale(identifier: "en_US")
        let fresh = HomeScreenBuilder.build(snap, now: now, calendar: Fixture.calendar(), locale: locale)
        let fromFile = HomeScreenBuilder.build(restored, now: now, calendar: Fixture.calendar(), locale: locale)
        #expect(fromFile == fresh)
    }

    @Test func theFileHoldsNoRawRecordsNoTimelineAndNoSourceName() async throws {
        let dir = directory()
        let saved = store(dir)
        saved.save(await snapshot())
        let text = try String(contentsOf: saved.fileURL, encoding: .utf8)
        #expect(!text.contains("Simulated"), "no source or device name")
        #expect(!text.localizedCaseInsensitiveContains("sourceName"))
        #expect(!text.contains("\"timeline\""))
        #expect(!text.contains("sourceBundle"))
        #expect(!text.contains("RawSleepSample") && !text.contains("HRVSample"))
    }

    @Test func theFileIsProtectedAndKeptOutOfBackups() async throws {
        let dir = directory()
        let saved = store(dir)
        saved.save(await snapshot())
        let values = try saved.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        // The simulator may not report a protection class; a device does.
        let attributes = try FileManager.default.attributesOfItem(atPath: saved.fileURL.path)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
    }

    @Test func aMissingFileIsNothing() {
        #expect(store(directory()).load() == nil)
    }

    @Test func aCorruptFileIsNothingAndIsDeleted() throws {
        let dir = directory()
        let saved = store(dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: saved.fileURL)
        #expect(saved.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: saved.fileURL.path))
    }

    private func rewrite(_ store: HomeSnapshotStore, _ change: (inout [String: Any]) -> Void) throws {
        let data = try Data(contentsOf: store.fileURL)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        try JSONSerialization.data(withJSONObject: object).write(to: store.fileURL)
    }

    @Test func anotherSchemaIsDropped() async throws {
        let saved = store(directory())
        saved.save(await snapshot())
        try rewrite(saved) { $0["schema"] = HomeSnapshotStore.schemaVersion + 1 }
        #expect(saved.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: saved.fileURL.path))
    }

    @Test func anotherRecoveryModelIsDropped() async throws {
        let saved = store(directory())
        saved.save(await snapshot())
        try rewrite(saved) { $0["recoveryModel"] = "recovery-v0" }
        #expect(saved.load() == nil)
    }

    @Test func aFileOlderThanThirtyDaysIsDropped() async throws {
        let dir = directory()
        store(dir).save(await snapshot())
        let later = now.addingTimeInterval(HomeSnapshotStore.maximumAge + 60)
        #expect(store(dir, at: later).load() == nil)
        #expect(!FileManager.default.fileExists(atPath: store(dir).fileURL.path))
        // Just inside the limit it still reads.
        store(dir).save(await snapshot())
        #expect(store(dir, at: now.addingTimeInterval(HomeSnapshotStore.maximumAge - 60)).load() != nil)
    }

    @Test func aFileFromTheFutureIsDropped() async {
        let dir = directory()
        store(dir, at: now.addingTimeInterval(3 * 86_400)).save(await snapshot())
        #expect(store(dir, at: now).load() == nil)
    }

    @Test func dataWhoseNewestSampleIsOverADayOldComesBackStale() async throws {
        let dir = directory()
        let snap = await snapshot()
        let newest = try #require(snap.newestSample)
        store(dir).save(snap)
        let restored = try #require(store(dir, at: newest.addingTimeInterval(25 * 3600)).load())
        #expect(restored.dataState == .stale(newestSample: newest))
        let fresh = try #require(store(dir, at: newest.addingTimeInterval(3600)).load())
        #expect(fresh.dataState == snap.dataState)
    }

    @Test func onlyStatesWithDataAreKeptAndEmptyOnesEraseIt() async throws {
        let dir = directory()
        let saved = store(dir)
        saved.save(await snapshot())
        let exists = { FileManager.default.fileExists(atPath: saved.fileURL.path) }
        #expect(exists())
        let profile = UserProfileSnapshot()
        // A failed read is a hiccup: the last good file stays.
        saved.save(HomeSnapshotBuilder.placeholder(.failed, profile: profile, now: now, timeZone: Fixture.newYork))
        #expect(exists())
        for state in [HomeDataState.permissionRequired, .healthDataUnavailable, .empty] {
            saved.save(await snapshot())
            #expect(exists())
            saved.save(HomeSnapshotBuilder.placeholder(state, profile: profile, now: now, timeZone: Fixture.newYork))
            #expect(!exists(), "\(state)")
        }
        #expect(!HomeSnapshotStore.isPersistable(.learning(nightsSoFar: 0)))
        #expect(HomeSnapshotStore.isPersistable(.learning(nightsSoFar: 2)))
    }

    @Test func eraseDeletesTheFileAndDataManagementReachesItThroughTheRegistry() async throws {
        let dir = directory()
        let saved = store(dir)
        saved.save(await snapshot())
        let registry = NoctisDataRegistry()
        registry.register(saved)
        #expect(registry.stores.map(\.erasableName) == ["Home snapshot"])
        registry.eraseAll()
        #expect(!FileManager.default.fileExists(atPath: saved.fileURL.path))
        // Idempotent.
        registry.eraseAll()
    }

    @Test func theRepositorySavesEachSnapshotAndTheNextOneRestoresIt() async throws {
        let dir = directory()
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let first = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }, store: store(dir))
        #expect(first.restoredSnapshot == nil)
        let built = await first.refresh(profile: UserProfileSnapshot())
        let second = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }, store: store(dir))
        let restored = try #require(second.restoredSnapshot)
        #expect(restored.recovery == built.recovery)
        #expect(await second.cachedSnapshot == restored)
    }

    @Test func dismissingAnInsightSavesTheSnapshotWithoutIt() async throws {
        let dir = directory()
        let provider = MockHealthKitProvider(scenario: .steady, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }, store: store(dir))
        let built = await repository.refresh(profile: UserProfileSnapshot())
        let insight = try #require(built.topInsight)
        _ = await repository.dismiss(id: insight.id)
        #expect(store(dir).load()?.topInsight == nil)
    }
}

// MARK: - The view model, with a saved snapshot

@MainActor
struct HomeRestoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "noctis-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// A store already holding `scenario`'s snapshot, as the last launch left it.
    private func saved(_ scenario: MockScenario = .full) async -> HomeSnapshotStore {
        let store = HomeSnapshotStore(directory: directory(), clock: { now })
        store.save(await snapshot(scenario))
        return store
    }

    private func viewModel(
        store: HomeSnapshotStore, scenario: MockScenario = .full, defaults: UserDefaults, latency: Duration = .zero
    ) -> HomeViewModel {
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true, latency: latency)
        return HomeViewModel(
            repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }, store: store),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: defaults),
            reduceMotion: { false },
            clock: { now },
            calendar: Fixture.calendar(),
            locale: Locale(identifier: "en_US")
        )
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard
    }

    @Test func aSavedSnapshotIsOnScreenBeforeHealthHasAnswered() async {
        let model = viewModel(store: await saved(), defaults: defaults(), latency: .seconds(30))
        // No refresh has run: the first frame has content.
        #expect(model.screen != nil)
        if case .scored = model.screen?.recovery {} else { Issue.record("expected a score") }
        #expect(model.snapshot?.render.ring.count == 4)
    }

    @Test func withNothingSavedTheFirstFrameIsTheSkeleton() {
        let store = HomeSnapshotStore(directory: directory(), clock: { now })
        #expect(viewModel(store: store, defaults: defaults()).screen == nil)
    }

    @Test func onTheFirstOpenOfTheDayTheRevealWaitsForFreshDataThenPlays() async {
        let model = viewModel(store: await saved(), defaults: defaults())
        #expect(model.reveal == .pending)
        #expect(model.awaitsFreshData)
        // Yesterday's numbers never play: the reveal holds.
        model.beginReveal()
        #expect(model.reveal == .pending)
        await model.refresh()
        #expect(!model.awaitsFreshData)
        model.beginReveal()
        #expect(model.reveal == .playing)
    }

    @Test func onALaterOpenTheSavedScreenShowsAtItsEndStateWithNoReveal() async {
        let store = await saved()
        let used = defaults()
        _ = HomeIntroGate(defaults: used).claim(now: now, calendar: Fixture.calendar())
        let model = viewModel(store: store, defaults: used)
        #expect(model.screen != nil)
        #expect(model.reveal == .none)
        #expect(!model.awaitsFreshData)
    }

    @Test func aSavedLearningScreenDoesNotSpendTheDaysReveal() async {
        let store = await saved(.learning)
        let gate = defaults()
        let model = viewModel(store: store, scenario: .full, defaults: gate)
        #expect(model.screen != nil)
        #expect(!HomeIntroGate(defaults: gate).isClaimed(now: now, calendar: Fixture.calendar()))
        // The real data has a score, and the reveal is still there for it.
        await model.refresh()
        #expect(model.reveal == .pending)
    }

    @Test func revalidatingReplacesWhatChanged() async {
        // Saved when there were five nights; Health now has the full month.
        let model = viewModel(store: await saved(.learning), scenario: .full, defaults: defaults())
        let before = model.screen
        await model.refresh()
        #expect(model.screen != before)
        if case .scored = model.screen?.recovery {} else { Issue.record("expected a score after revalidating") }
    }

    @Test func aRebuildThatChangesNothingRepublishesNothing() async {
        let model = viewModel(store: await saved(), defaults: defaults())
        await model.refresh()
        let change = watch {
            _ = model.screen
            _ = model.header
            _ = model.snapshot
        }
        // Coming back to the foreground: the clock is read again.
        model.updateClock()
        model.updateClock()
        #expect(!change.happened)
    }
}

// MARK: - The minute clock

/// A clock a test moves by hand.
private nonisolated final class Time: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var value: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

@MainActor
struct HomeClockTests {
    @Test func minutesStartOnTheBoundary() {
        let date = Fixture.date(2026, 9, 24, 21, 14, 37)
        #expect(HomeClock.startOfMinute(date) == Fixture.date(2026, 9, 24, 21, 14, 0))
        #expect(HomeClock.nextMinute(after: date) == Fixture.date(2026, 9, 24, 21, 15, 0))
        // On the boundary the next one is a full minute away.
        #expect(HomeClock.nextMinute(after: Fixture.date(2026, 9, 24, 21, 14, 0)) == Fixture.date(2026, 9, 24, 21, 15, 0))
    }

    @Test func itPublishesOnlyWhenTheMinuteChanges() {
        let time = Time(Fixture.date(2026, 9, 24, 21, 14, 5))
        let clock = HomeClock { time.value }
        let change = watch { _ = clock.minute }
        time.value = Fixture.date(2026, 9, 24, 21, 14, 50)
        clock.refresh()
        #expect(!change.happened, "the same minute publishes nothing")
        time.value = Fixture.date(2026, 9, 24, 21, 15, 1)
        clock.refresh()
        #expect(change.happened)
        #expect(clock.minute == Fixture.date(2026, 9, 24, 21, 15, 0))
    }

    @Test func startAndStopAreSafeToRepeat() {
        let clock = HomeClock()
        clock.start()
        clock.start()
        clock.stop()
        clock.stop()
        clock.start()
        clock.stop()
    }
}

// MARK: - Scroll and collapse

@MainActor
struct HomeCollapseWriteTests {
    private func model() async -> HomeViewModel {
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let model = HomeViewModel(
            repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard),
            reduceMotion: { true }, clock: { now }, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US")
        )
        await model.refresh()
        return model
    }

    @Test func aScrollWritesStateOnlyWhenAStepOrThresholdIsCrossed() async {
        let model = await model()
        var writes = 0
        var change = watch {
            _ = model.collapseProgress
            _ = model.showsCollapsedBar
        }
        /// Counts a write and watches again.
        func scroll(to top: Double) {
            model.scrolled(visibleTop: top, heroTop: 0, heroHeight: 500)
            if change.happened {
                writes += 1
                change = watch {
                    _ = model.collapseProgress
                    _ = model.showsCollapsedBar
                }
            }
        }
        // 500pt hero at the top of the content: progress moves in steps of
        // 1%, rounded, so movements under 2.5pt change nothing.
        for top in stride(from: 0.0, through: 2.0, by: 0.5) { scroll(to: top) }
        #expect(writes == 0)
        // Crossing steps writes the progress…
        scroll(to: 100)
        #expect(writes == 1)
        #expect(model.collapseProgress == 0.2)
        // …but the bar's flag isn't touched until its threshold.
        #expect(!model.showsCollapsedBar)
        scroll(to: 360)
        #expect(model.showsCollapsedBar)
        // Wobbling around the line doesn't flicker it (hysteresis).
        scroll(to: 330)
        #expect(model.showsCollapsedBar)
        scroll(to: 300)
        #expect(!model.showsCollapsedBar)
    }

    @Test func theCollapseStateStillReadsAsOneValue() async {
        let model = await model()
        model.scrolled(visibleTop: 250, heroTop: 0, heroHeight: 500)
        #expect(model.collapse == HomeCollapse(progress: 0.5, showsBar: false))
        #expect(HomeCollapse.scale(at: 0.5) == model.collapse.heroScale)
        #expect(HomeCollapse.opacity(at: 0.5) == model.collapse.heroOpacity)
    }
}

// MARK: - Rules kept in the source

/// The performance rules that a compiler can't check: read from the source
/// files themselves, so a regression fails a test rather than a device.
struct HomePerformanceRulesTests {
    private static func sources(_ module: String) throws -> [(name: String, text: String)] {
        // …/Tests/NoctisKitTests/<this file> → the package root.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appending(path: "Sources/\(module)", directoryHint: .isDirectory)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// No text under 12pt in the main app (R4): every `noctisFont`,
    /// `noctisNumeral` and `Font.system(size:)` in the feature and design
    /// system sources names 12 or more. (Onboarding, which has its own rules,
    /// and its badge are left out.)
    @Test func noTextInTheMainAppIsUnder12pt() throws {
        let pattern = try Regex(
            #"(?:noctisFont|noctisNumeral)\(\s*(\d+(?:\.\d+)?)|Font\.system\(size:\s*(\d+(?:\.\d+)?)|\.font\(\.system\(size:\s*(\d+(?:\.\d+)?)"#)
        var checked = 0
        for module in ["HomeFeature", "SleepFeature", "RecoveryFeature", "DesignSystem", "AppRoot"] {
            for file in try Self.sources(module)
            where ![
                "NoctisBadge.swift", "NoctisScaledType.swift", "NoctisMetric.swift", "OnboardingScaffold.swift", "SampleNight.swift", "NoctisPaper.swift",
                "NoctisColor.swift",
            ].contains(file.name) {
                for match in file.text.matches(of: pattern) {
                    let number = (1...3).compactMap { match.output[$0].substring }.first.flatMap { Double($0) }
                    if let number {
                        checked += 1
                        #expect(number >= 12, "\(file.name): a \(number)pt font")
                    }
                }
            }
        }
        #expect(checked > 100, "the scan reads the fonts (\(checked))")
    }

    @Test func homeAnimatesWithSpringTokensAndNoTimedCurves() throws {
        // Springs can be interrupted and retargeted; a timed curve restarts.
        let banned = [".easeIn(", ".easeOut(", ".easeInOut(", ".linear(", ".timingCurve(", ".easeIn)", ".easeOut)", ".easeInOut)", ".linear)"]
        for file in try Self.sources("HomeFeature") where file.name != "HomePreviews.swift" {
            for pattern in banned {
                #expect(!file.text.contains(pattern), "\(file.name) uses \(pattern); use a NoctisMotion token")
            }
        }
    }

    @Test func onlyLeafViewsReadTheMinuteClock() throws {
        // Home's root and its cards never read the clock, so a minute
        // passing re-evaluates only the countdown text, the "now" marker
        // and the tab accessory.
        let allowed: Set<String> = ["HomeClock.swift", "HomeHeroViews.swift", "HomeOverlays.swift"]
        for file in try Self.sources("HomeFeature") where !allowed.contains(file.name) {
            #expect(!file.text.contains("homeClock"), "\(file.name) reads the minute clock")
            #expect(!file.text.contains("homeMinute"), "\(file.name) reads the minute")
        }
        for file in try Self.sources("AppRoot") {
            #expect(!file.text.contains("TimelineView"), "\(file.name) wraps the app in a TimelineView")
        }
    }

    @Test func thereIsOneTimelineViewAndItIsTheNowMarker() throws {
        var count = 0
        // (The DEBUG probe has one of its own; it isn't in Release.)
        for file in try Self.sources("HomeFeature") where file.name != "HomeDebug.swift" {
            count += file.text.components(separatedBy: "TimelineView(").count - 1
        }
        #expect(count == 1)
    }

    @Test func noCanvasClosureBuildsPathsFromGeometry() throws {
        // Paths are resolved when a size or a value changes, not inside a
        // Canvas: no arc, curve or shape is built in a draw closure.
        for name in ["HomeNightChartViews.swift", "FactorSparkline.swift"] {
            let text = try #require(try Self.sources("HomeFeature").first { $0.name == name }?.text)
            let lines = text.components(separatedBy: "\n")
            var canvases = 0
            for (index, line) in lines.enumerated() where line.contains("Canvas {") {
                canvases += 1
                let indent = String(line.prefix { $0 == " " })
                var block: [String] = []
                var next = index + 1
                while next < lines.count, !(lines[next].hasPrefix(indent + "}") && !lines[next].hasPrefix(indent + " ")) {
                    block.append(lines[next])
                    next += 1
                }
                let code = block.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
                #expect(!code.contains("Path("), "\(name): a Canvas closure builds a Path")
                #expect(!code.contains("addCurve") && !code.contains("addArc") && !code.contains("addLine"), "\(name)")
            }
            #expect(canvases > 0, "\(name) has canvases to check")
        }
    }
}

// MARK: - Low Power Mode

@MainActor
struct HomeLowPowerTests {
    @Test func theStaggersAndTheCountUpGoAndTheEndStatesStay() {
        for index in 0..<4 {
            #expect(HomeReveal.capsuleDelay(index, lowPower: false) == HomeReveal.capsuleStagger * Double(index))
            #expect(HomeReveal.capsuleDelay(index, lowPower: true) == 0)
        }
        for index in 0..<7 {
            #expect(HomeReveal.weekDelay(index, lowPower: false) == HomeReveal.weekStagger * Double(index))
            #expect(HomeReveal.weekDelay(index, lowPower: true) == 0)
        }
        #expect(HomeReveal.countsUp(lowPower: false))
        #expect(!HomeReveal.countsUp(lowPower: true))
        // The ring, the night and the dusk (the primary motion) are unchanged.
        #expect(HomeReveal.totalDuration == HomeReveal.backgroundDuration + HomeReveal.ringDuration + 0.4)
    }

    private func model(lowPower: @escaping () -> Bool) -> HomeViewModel {
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        return HomeViewModel(
            repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard),
            reduceMotion: { false }, lowPower: lowPower, clock: { now }, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US")
        )
    }

    @Test func theViewModelReadsLowPowerModeAtStartAndFollowsItsChanges() async throws {
        #expect(model { true }.isLowPower)
        #expect(!model { false }.isLowPower)

        let flag = Change()
        let live = model { flag.happened }
        #expect(!live.isLowPower)
        await live.onAppear()
        flag.mark()
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        _ = await waitFor { !(!live.isLowPower) }
        #expect(live.isLowPower)
        live.stopObserving()
    }

    @Test func reduceMotionIsSeparateFromLowPower() {
        // Low Power Mode changes nothing about how Reduce Motion behaves:
        // the view model carries both, independently.
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let calm = HomeViewModel(
            repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard),
            reduceMotion: { true }, lowPower: { false }, clock: { now }, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US")
        )
        #expect(!calm.isLowPower)
        #expect(calm.reveal == .none)
    }
}

// MARK: - Signposts, motion tokens, erasable stores

struct NoctisSignpostTests {
    @Test func everyIntervalHasItsOwnNameForInstrumentsAndTheMetrics() {
        let names = NoctisSignpost.Interval.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
        #expect(
            Set(names) == [
                "LaunchToFirstFrame", "LaunchToPopulated", "Reveal", "Morph", "Collapse", "Scrub", "TabSwitch", "SleepLoad", "SleepModel", "RecoveryLoad",
                "RecoveryModel", "BackgroundRefresh",
            ])
        #expect(NoctisSignpost.subsystem == "com.noctis.app" && NoctisSignpost.category == "Performance")
    }

    @Test func anIntervalRunsFromBeginToEndOnceAndRepeatsAreHarmless() {
        NoctisSignpost.end(.scrub)
        #expect(!NoctisSignpost.active.contains(.scrub))
        NoctisSignpost.begin(.scrub)
        NoctisSignpost.begin(.scrub)
        #expect(NoctisSignpost.active.contains(.scrub))
        NoctisSignpost.end(.scrub)
        NoctisSignpost.end(.scrub)
        #expect(!NoctisSignpost.active.contains(.scrub))
    }

    @Test func intervalsRunIndependently() {
        NoctisSignpost.begin(.morph)
        NoctisSignpost.begin(.collapse)
        NoctisSignpost.end(.morph)
        #expect(NoctisSignpost.active.contains(.collapse) && !NoctisSignpost.active.contains(.morph))
        NoctisSignpost.end(.collapse)
    }
}

struct ErasableStoresTests {
    @Test func storedInsightsAreErasedThroughTheRegistry() async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "noctis-erase-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = InsightFileStore(directory: folder)
        let store = InsightStore(file: file)
        await store.ingest([InsightRecordFixture.duration(delta: -70)], featuredOn: InsightFixture.last)
        #expect(FileManager.default.fileExists(atPath: file.fileURL.path))
        let registry = NoctisDataRegistry()
        registry.register(file)
        registry.eraseAll()
        #expect(!FileManager.default.fileExists(atPath: file.fileURL.path))
        #expect(await store.snapshot().entries.isEmpty)
    }
}
