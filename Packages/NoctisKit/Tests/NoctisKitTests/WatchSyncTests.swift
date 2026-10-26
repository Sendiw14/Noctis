import Foundation
import Testing

@testable import HealthProviding
@testable import InsightsKit
@testable import NightKit
@testable import NoctisCore
@testable import NoctisWatchKit
@testable import NoctisWidgetKit
@testable import RecoveryKit

// The Apple Watch's data and sync (APP_RULES.md R50, R51, R52): snapshot v2 and what it holds, what the Watch is able to say for each state, the
// message the iPhone sends, how the Watch stores it and applies the data epoch, what the iPhone sends when, and what the inventory says about it.

/// 10:00 AM in New York on 24 September 2026 (what `Fixture.date(2026, 9, 24, 10)` is), as a plain instant that any context may read.
private nonisolated let now = Date(timeIntervalSince1970: 1_790_258_400)
private nonisolated let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return value
}()

/// The context the iPhone queued, read back the way the Watch reads it.
private func decoded(_ dictionary: [String: Any]?) throws -> WatchContext {
    let dictionary = try #require(dictionary)
    return try #require(WatchContext(dictionary: dictionary))
}

private func snapshot(
    _ state: WidgetDataState = .full, day: Int = 24, month: Int = 9, generated: Date? = nil, epoch: Int64 = 0, withFactors: Bool = true
) -> WidgetSnapshot {
    var value = WidgetSamples.snapshot(state, now: generated ?? Fixture.date(2026, month, day, 10), calendar: calendar)
    value.forDay = WidgetDay(year: 2026, month: month, day: day)
    value.dataEpoch = epoch
    if withFactors && state.showsScore {
        value.recoveryFactors = [
            WidgetRecoveryFactor(kind: .sleepDuration, score: 82, value: 402, baseline: 450),
            WidgetRecoveryFactor(kind: .hrv, score: 64, value: 54, baseline: 61.4, range: .within),
            WidgetRecoveryFactor(kind: .restingHeartRate, score: 71, value: 52, baseline: 50.2, range: .above),
            WidgetRecoveryFactor(kind: .sleepConsistency, score: 90, value: 12, baseline: nil),
        ]
        value.nightsOfHistory = 14
    }
    return value
}

// MARK: - Snapshot v2

struct SnapshotV2Tests {
    @Test func theThreeNewFieldsRoundTripAndTheSnapshotIsSmall() throws {
        let value = snapshot(epoch: 1_790_000_000)
        let data = try value.encoded()
        let decoded = try #require(WidgetSnapshot.decode(data))
        #expect(decoded == value)
        #expect(decoded.recoveryFactors.map(\.kind) == [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency])
        #expect(decoded.recoveryFactors[1].baseline == 61.4 && decoded.recoveryFactors[2].range == .above && decoded.recoveryFactors[3].baseline == nil)
        #expect(decoded.nightsOfHistory == 14 && decoded.dataEpoch == 1_790_000_000)
        #expect(WidgetSnapshot.currentVersion == 2 && WidgetSnapshot.maximumBytes == 3072)
        #expect(data.count < WidgetSnapshot.maximumBytes / 2, "\(data.count) bytes: well under the cap")
    }

    @Test func theWorstSnapshotStillFitsUnderThreeKilobytes() throws {
        var worst = snapshot(.stale(hours: 99), epoch: Int64.max / 4)
        worst.lastNight = WidgetNight(
            asleepMinutes: 1439, stages: WidgetStages(deep: 999, core: 999, rem: 999), bedtimeMinutes: 1439, wakeMinutes: 1439, quality: 100)
        worst.factors = WidgetFactors(hrv: 999, restingHeartRate: 199)
        worst.recoveryFactors = WidgetFactorKind.allCases.map { WidgetRecoveryFactor(kind: $0, score: 100, value: 1439.9, baseline: 1439.9, range: .below) }
        #expect(try worst.encoded().count < WidgetSnapshot.maximumBytes)
    }

    @Test func aVersionOneFileIsNotReadAndEveryReaderSaysOpenNOCTIS() throws {
        // What the iPhone wrote before the Watch: no factors, no history, no epoch, version 1.
        let version1 = """
            {"al":{"m":420,"on":true},"at":1790000000,"day":"2026-09-24","f":{"hrv":54,"rhr":52},"n":{"a":402,"b":1384,"q":81,"st":{"deep":74,"core":236,"rem":92},"w":412},\
            "p":{"b":1380,"n":480,"w":420},"rec":{"c":2,"d":6,"r":[{"f":0.82,"k":0,"w":0.4}],"s":70},"st":"full","v":1}
            """
        let data = Data(version1.utf8)
        #expect(WidgetSnapshot.decode(data) == nil, "another version: nothing is shown from it")
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try data.write(to: directory.appending(path: WidgetSnapshotStore.fileName))
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.exists && store.load() == nil)
        // The Watch says what it says with no snapshot, and the widgets do the same.
        #expect(WatchState.map(store.load(), now: now, calendar: calendar) == .noSnapshotYet)
        #expect(WidgetTimelineBuilder.entry(for: store.load(), at: now, calendar: calendar).scene == .noSnapshot)
        // The next write by this build replaces it.
        #expect(store.save(snapshot()) && store.load() != nil)
    }

    @Test func aVersionTwoFileWithoutTheNewFieldsReadsWithTheirDefaults() throws {
        let value = snapshot(withFactors: false)
        var json = try #require(try JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any])
        for key in ["rf", "nh", "de"] { json[key] = nil }
        let decoded = try #require(WidgetSnapshot.decode(try JSONSerialization.data(withJSONObject: json)))
        #expect(decoded.recoveryFactors.isEmpty && decoded.nightsOfHistory == 0 && decoded.dataEpoch == 0)
    }

    @Test func factorValuesAreRoundedToATenthAndScoresAreKeptInRange() {
        let factor = WidgetRecoveryFactor(kind: .hrv, score: 140, value: 53.96, baseline: 61.449, range: .within)
        #expect(factor.score == 100 && factor.value == 54.0 && factor.baseline == 61.4)
        #expect(WidgetRecoveryFactor(kind: .hrv, score: -3, value: 1, baseline: nil).score == 0)
        #expect(
            WidgetSnapshot(forDay: WidgetDay(year: 2026, month: 9, day: 24), generatedAt: now, plan: snapshot().plan, state: .empty, nightsOfHistory: 99)
                .nightsOfHistory == 14)
    }

    @Test func theMakerCarriesTheFourFactorsTheHistoryAndTheEpochOnlyForWhatWasScored() async throws {
        let provider = MockHealthKitProvider(
            scenario: .full, referenceDate: now, calendar: calendar, startAuthorized: true, isHealthDataAvailable: true, failsQueries: false)
        let home = await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        let made = try #require(
            WidgetSnapshotMaker.make(
                home: home, profile: UserProfileSnapshot(), bedtime: nil, alarm: nil, now: now, calendar: calendar, dataEpoch: 1_790_000_123))
        guard case .scored(let result)? = home.recovery else {
            Issue.record("scored")
            return
        }
        #expect(
            made.recoveryFactors.map(\.kind)
                == WidgetFactorKind.allCases.filter { kind in result.factors.contains { WidgetSnapshotMaker.factorKind($0.kind) == kind } })
        for factor in made.recoveryFactors {
            let source = try #require(result.factors.first { WidgetSnapshotMaker.factorKind($0.kind) == factor.kind })
            #expect(factor.score == source.score && abs(factor.value - source.value) < 0.06)
            #expect(factor.range == WidgetSnapshotMaker.range(source.range))
        }
        #expect(made.nightsOfHistory == result.baselineNights && made.dataEpoch == 1_790_000_123)
        #expect(try made.encoded().count < WidgetSnapshot.maximumBytes)

        let learning = await HomeRepository(
            provider: MockHealthKitProvider(
                scenario: .learning, referenceDate: now, calendar: calendar, startAuthorized: true, isHealthDataAvailable: true, failsQueries: false),
            timeZone: Fixture.newYork, clock: { now }
        ).refresh(profile: UserProfileSnapshot())
        let nothing = try #require(
            WidgetSnapshotMaker.make(home: learning, profile: UserProfileSnapshot(), bedtime: nil, alarm: nil, now: now, calendar: calendar))
        #expect(nothing.recoveryFactors.isEmpty && nothing.nightsOfHistory == 0 && nothing.dataEpoch == 0, "no score: no factors")
    }
}

// MARK: - What the Watch is able to say

struct WatchStateTests {
    private func map(_ value: WidgetSnapshot?, at date: Date = now) -> WatchState { WatchState.map(value, now: date, calendar: calendar) }

    @Test func everyStateIsMappedFromTheSnapshotsOwn() {
        #expect(map(nil) == .noSnapshotYet)
        #expect(map(snapshot(.full)) == .ok)
        #expect(map(snapshot(.sleepOnly)) == .sleepOnly)
        #expect(map(snapshot(.learning(nightsSoFar: 3))) == .learning(nightsSoFar: 3))
        #expect(map(snapshot(.empty)) == .empty)
        #expect(map(snapshot(.noPermission)) == .noPermission)
        #expect(map(snapshot(.gap)) == .gap)
        let stale = snapshot(.stale(hours: 14))
        #expect(map(stale) == .stale(since: stale.generatedAt.addingTimeInterval(-14 * 3600)))
    }

    @Test func aSnapshotForAnEarlierDayIsWaitingForTodayWhateverItSays() {
        for state in [WidgetDataState.full, .sleepOnly, .learning(nightsSoFar: 2), .empty, .noPermission, .gap, .stale(hours: 3)] {
            #expect(map(snapshot(state, day: 23)) == .waitingForToday, "yesterday's numbers are never today's (\(state.token))")
        }
        // A snapshot for a later day (the person woke before 4 AM) is already today's.
        #expect(map(snapshot(.full, day: 25)) == .ok)
    }

    @Test func aDayStartsAtFourInTheMorningOnTheWatchesClockToo() {
        let yesterdays = snapshot(.full, day: 23)
        #expect(map(yesterdays, at: Fixture.date(2026, 9, 24, 3, 59)) == .ok, "still the evening of the 23rd")
        #expect(map(yesterdays, at: Fixture.date(2026, 9, 24, 4, 0)) == .waitingForToday)
        #expect(map(yesterdays, at: Fixture.date(2026, 9, 24, 23, 59)) == .waitingForToday)
        // Midnight itself is not a boundary.
        #expect(map(snapshot(.full, day: 24), at: Fixture.date(2026, 9, 25, 0, 0)) == .ok)
        #expect(map(snapshot(.full, day: 24), at: Fixture.date(2026, 9, 25, 4, 0)) == .waitingForToday)
    }

    @Test func daylightSavingMovesNothing() {
        // US spring forward: 2:00 AM on 8 March 2026 becomes 3:00.
        let before = snapshot(.full, day: 7, month: 3)
        #expect(map(before, at: Fixture.date(2026, 3, 8, 3, 59)) == .ok)
        #expect(map(before, at: Fixture.date(2026, 3, 8, 4, 0)) == .waitingForToday)
        // Fall back: 2:00 AM on 1 November 2026 becomes 1:00 again.
        let autumn = snapshot(.full, day: 31, month: 10)
        #expect(map(autumn, at: Fixture.date(2026, 11, 1, 1, 30)) == .ok)
        #expect(map(autumn, at: Fixture.date(2026, 11, 1, 3, 59)) == .ok)
        #expect(map(autumn, at: Fixture.date(2026, 11, 1, 4, 0)) == .waitingForToday)
        // The same instants on a clock that does not shift (Tokyo) give the same rule.
        let tokyo = Fixture.calendar(Fixture.tokyo)
        let tokyoSnapshot = WidgetSnapshot(forDay: WidgetDay(year: 2026, month: 9, day: 23), generatedAt: now, plan: snapshot().plan, state: .full)
        #expect(WatchState.map(tokyoSnapshot, now: Fixture.date(2026, 9, 24, 3, 59, in: Fixture.tokyo), calendar: tokyo) == .ok)
        #expect(WatchState.map(tokyoSnapshot, now: Fixture.date(2026, 9, 24, 4, 0, in: Fixture.tokyo), calendar: tokyo) == .waitingForToday)
    }

    @Test func onlyNumbersForTodayOrMarkedOldOnesMayBeShown() {
        let shown: [WatchState] = [.ok, .sleepOnly, .stale(since: now)]
        let hidden: [WatchState] = [.waitingForToday, .learning(nightsSoFar: 1), .empty, .noPermission, .gap, .noSnapshotYet]
        #expect(shown.allSatisfy(\.showsNumbers) && hidden.allSatisfy { !$0.showsNumbers })
        #expect(WatchState.stale(since: now).isStale && !WatchState.ok.isStale)
        #expect(WatchState.noSnapshotYet.needsIPhone && WatchState.empty.needsIPhone && !WatchState.learning(nightsSoFar: 2).needsIPhone)
    }
}

// MARK: - The message

struct WatchContextTests {
    @Test func aContextIsAPropertyListWithTheSnapshotAndTheEpoch() throws {
        let value = snapshot(epoch: 1_790_000_000)
        let context = try WatchContext(snapshot: value, sentAt: now)
        let dictionary = context.dictionary
        // Property-list types only: that is all WatchConnectivity accepts.
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
        #expect(!data.isEmpty)
        let back = try #require(WatchContext(dictionary: dictionary))
        #expect(back.snapshot == value && back.epoch == 1_790_000_000 && back.effectiveEpoch == 1_790_000_000)
        #expect(Int(back.sentAt.timeIntervalSince1970) == Int(now.timeIntervalSince1970))
        #expect(context.byteCount < WatchContext.maximumBytes)
    }

    @Test func aContextWithNoSnapshotStillCarriesTheEpochSoTheWatchCanWipe() throws {
        let empty = WatchContext(epoch: 1_790_000_500, snapshotData: nil, sentAt: now)
        let back = try #require(WatchContext(dictionary: empty.dictionary))
        #expect(back.snapshot == nil && back.snapshotData == nil && back.effectiveEpoch == 1_790_000_500)
        #expect(empty.dictionary["snapshot"] == nil)
    }

    @Test func theEpochTheWatchAppliesIsTheGreaterOfTheTwo() throws {
        let value = snapshot(epoch: 200)
        #expect(WatchContext(epoch: 100, snapshotData: try value.encoded(), sentAt: now).effectiveEpoch == 200)
        #expect(WatchContext(epoch: 300, snapshotData: try value.encoded(), sentAt: now).effectiveEpoch == 300)
    }

    @Test func aContextOfAnotherFormatOrNoneIsIgnored() {
        #expect(WatchContext(dictionary: [:]) == nil)
        #expect(WatchContext(dictionary: ["wire": 2, "epoch": 0]) == nil)
        #expect(WatchContext(dictionary: ["wire": 1]) == nil)
        #expect(WatchContext(dictionary: ["wire": 1, "epoch": 0])?.snapshot == nil)
    }
}

// MARK: - What the Watch keeps

struct WatchInboxTests {
    private func inbox() throws -> (WatchInbox, URL) {
        let directory = try WidgetFixture.directory()
        return (WatchInbox(directory: directory), directory)
    }

    private func context(_ value: WidgetSnapshot?, epoch: Int64? = nil) throws -> WatchContext {
        WatchContext(epoch: epoch ?? value?.dataEpoch ?? 0, snapshotData: try value?.encoded(), sentAt: now)
    }

    @Test func aSnapshotIsStoredWithWhenItArrived() throws {
        let (inbox, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(inbox.load() == nil && inbox.epoch == 0)
        let arrival = now.addingTimeInterval(120)
        #expect(inbox.receive(try context(snapshot()), now: arrival) == .stored)
        let held = try #require(inbox.load())
        let receivedAt = try #require(held.receivedAt)
        #expect(held.snapshot == snapshot() && Int(receivedAt.timeIntervalSince1970) == Int(arrival.timeIntervalSince1970))
    }

    @Test func aLowerEpochIsIgnoredAndTheCopyStays() throws {
        let (inbox, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        inbox.receive(try context(snapshot(epoch: 500)), now: now)
        let older = snapshot(.learning(nightsSoFar: 1), epoch: 400)
        #expect(inbox.receive(try context(older), now: now) == .ignoredOlderEpoch)
        #expect(inbox.receive(WatchContext(epoch: 100, snapshotData: nil, sentAt: now), now: now) == .ignoredOlderEpoch, "an old wipe does not wipe")
        #expect(inbox.load()?.snapshot == snapshot(epoch: 500) && inbox.epoch == 500)
    }

    @Test func aGreaterEpochWipesTheCopyFirstAndThenAppliesWhatCame() throws {
        let (inbox, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        inbox.receive(try context(snapshot(epoch: 100)), now: now)
        // The iPhone deleted everything: the new epoch with nothing else.
        #expect(inbox.receive(WatchContext(epoch: 200, snapshotData: nil, sentAt: now), now: now) == .wiped(thenStored: false))
        #expect(inbox.load() == nil && inbox.epoch == 200)
        // And a snapshot made after it is kept.
        #expect(inbox.receive(try context(snapshot(epoch: 200)), now: now) == .stored)
        // A snapshot that came with a greater epoch replaces the copy in one step.
        #expect(inbox.receive(try context(snapshot(.gap, epoch: 300)), now: now) == .wiped(thenStored: true))
        #expect(inbox.load()?.snapshot.state == .gap && inbox.epoch == 300)
    }

    @Test func aSnapshotAnEpochBehindTheContextIsNotKept() throws {
        let (inbox, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        inbox.receive(try context(snapshot(epoch: 100)), now: now)
        // The context says epoch 250 but carries a snapshot stamped 100: the greater epoch wipes, and the older snapshot is stored only as what the
        // iPhone chose to send with it: the context's epoch is what is held.
        let result = inbox.receive(try context(snapshot(epoch: 100), epoch: 250), now: now)
        #expect(result == .wiped(thenStored: true) && inbox.epoch == 250)
    }

    @Test func theEpochOutlivesARelaunchAndStillGuardsTheCopy() throws {
        let (first, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        first.receive(try context(snapshot(epoch: 700)), now: now)
        // A new process on the same folder: what was held, and the epoch, are read back.
        let second = WatchInbox(directory: directory)
        #expect(second.epoch == 700 && second.load()?.snapshot == snapshot(epoch: 700))
        #expect(second.receive(try context(snapshot(epoch: 650)), now: now) == .ignoredOlderEpoch)
        // Wiped, and a relaunch later it is still 700: an old message cannot bring the data back.
        second.receive(WatchContext(epoch: 800, snapshotData: nil, sentAt: now), now: now)
        let third = WatchInbox(directory: directory)
        #expect(third.epoch == 800 && third.load() == nil)
        #expect(third.receive(try context(snapshot(epoch: 700)), now: now) == .ignoredOlderEpoch && third.load() == nil)
    }

    @Test func aSnapshotOlderThanTheOneHeldInTheSameEpochIsIgnored() throws {
        let (inbox, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        let newer = snapshot(generated: Fixture.date(2026, 9, 24, 11))
        inbox.receive(try context(newer), now: now)
        #expect(inbox.receive(try context(snapshot(generated: Fixture.date(2026, 9, 24, 9))), now: now) == .ignoredOlderSnapshot)
        #expect(inbox.load()?.snapshot == newer)
    }

    @Test func noSummaryInTheSameEpochMeansTheIPhoneDeletedItsSummaryAndTheCopyGoesToo() throws {
        let (inbox, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        inbox.receive(try context(snapshot(epoch: 5)), now: now)
        #expect(inbox.receive(WatchContext(epoch: 5, snapshotData: nil, sentAt: now), now: now) == .cleared)
        #expect(inbox.load() == nil && inbox.epoch == 5)
    }

    @Test func bytesNoBuildCanReadLeaveWhatIsHeld() throws {
        let (inbox, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        inbox.receive(try context(snapshot()), now: now)
        let unreadable = WatchContext(epoch: 0, snapshotData: Data("{\"v\":9}".utf8), sentAt: now)
        #expect(inbox.receive(unreadable, now: now) == .ignoredUnreadable && inbox.load()?.snapshot == snapshot())
        let huge = WatchContext(epoch: 0, snapshotData: Data(count: WidgetSnapshot.maximumBytes + 1), sentAt: now)
        #expect(inbox.receive(huge, now: now) == .ignoredUnreadable)
    }

    @Test func wipingKeepsTheEpoch() throws {
        let (inbox, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        inbox.receive(try context(snapshot(epoch: 42)), now: now)
        inbox.wipeKeepingEpoch()
        #expect(inbox.load() == nil && inbox.epoch == 42)
    }

    @Test func theFilesAreProtectedAndKeptOutOfBackups() throws {
        let (inbox, directory) = try inbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        inbox.receive(try context(snapshot()), now: now)
        for name in [WidgetSnapshotStore.fileName, WatchInbox.receiptFileName] {
            let url = directory.appending(path: name)
            #expect(FileManager.default.fileExists(atPath: url.path), Comment(rawValue: name))
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, Comment(rawValue: "\(name) is in backups"))
        }
        let source = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWatchKit/WatchInbox.swift"), encoding: .utf8)
        #expect(source.contains("completeFileProtectionUntilFirstUserAuthentication"), "readable once the Watch has been unlocked: a complication reads it")
    }
}

struct WatchBackgroundDrainTests {
    private actor Clock {
        var slept: [TimeInterval] = []
        func sleep(_ seconds: TimeInterval) { slept.append(seconds) }
    }

    private nonisolated final class Pending: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        init(checks: Int) { remaining = checks }
        func check() -> Bool {
            lock.withLock {
                remaining -= 1
                return remaining >= 0
            }
        }
    }

    @Test func itReturnsAsSoonAsNothingIsPending() async {
        let clock = Clock()
        let pending = Pending(checks: 3)
        let drained = await WatchBackgroundDrain.wait(hasContentPending: { pending.check() }, timeout: 15, poll: 0.25, sleep: { await clock.sleep($0) })
        let slept = await clock.slept
        #expect(drained)
        #expect(slept == [0.25, 0.25, 0.25])
    }

    @Test func itDoesNotWaitWhenNothingWasPending() async {
        let clock = Clock()
        let drained = await WatchBackgroundDrain.wait(hasContentPending: { false }, sleep: { await clock.sleep($0) })
        let slept = await clock.slept
        #expect(drained && slept.isEmpty)
    }

    @Test func itAlwaysReturnsSoTheSystemsTaskIsCompleted() async {
        let clock = Clock()
        let drained = await WatchBackgroundDrain.wait(hasContentPending: { true }, timeout: 2, poll: 0.5, sleep: { await clock.sleep($0) })
        let slept = await clock.slept
        #expect(!drained, "time ran out, and it still returned")
        #expect(slept.count == 4)
    }
}

// MARK: - What the iPhone sends, and when

nonisolated final class FakeWatchSession: WatchSessionDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()

    private struct State {
        var supported = true, paired = true, installed = true, complication = true, reachable = true
        var activation = WatchActivation.activated
        var remaining = 50
        var contexts: [[String: Any]] = []
        var infos: [[String: Any]] = []
        var activations = 0
        var failUpdates = false
        var onChange: (@Sendable () -> Void)?
        var onRequest: (@Sendable () -> Void)?
    }

    private func read<T>(_ get: (State) -> T) -> T { lock.withLock { get(state) } }
    private func write(_ change: (inout State) -> Void) { lock.withLock { change(&state) } }

    var isSupported: Bool {
        get { read(\.supported) }
        set { write { $0.supported = newValue } }
    }
    var isPaired: Bool {
        get { read(\.paired) }
        set { write { $0.paired = newValue } }
    }
    var isWatchAppInstalled: Bool {
        get { read(\.installed) }
        set { write { $0.installed = newValue } }
    }
    var isComplicationEnabled: Bool {
        get { read(\.complication) }
        set { write { $0.complication = newValue } }
    }
    var isReachable: Bool {
        get { read(\.reachable) }
        set { write { $0.reachable = newValue } }
    }
    var activation: WatchActivation {
        get { read(\.activation) }
        set { write { $0.activation = newValue } }
    }
    var remainingComplicationTransfers: Int {
        get { read(\.remaining) }
        set { write { $0.remaining = newValue } }
    }
    var failUpdates: Bool {
        get { read(\.failUpdates) }
        set { write { $0.failUpdates = newValue } }
    }
    var contexts: [[String: Any]] { read(\.contexts) }
    var complicationInfos: [[String: Any]] { read(\.infos) }
    var activations: Int { read(\.activations) }

    func activate() { write { $0.activations += 1 } }

    func updateApplicationContext(_ context: [String: Any]) throws {
        if read(\.failUpdates) { throw FakeWatchError() }
        write { $0.contexts.append(context) }
    }

    func transferCurrentComplicationUserInfo(_ info: [String: Any]) -> Bool {
        write {
            $0.infos.append(info)
            $0.remaining -= 1
        }
        return true
    }

    func setHandlers(onChange: @escaping @Sendable () -> Void, onUpdateRequested: @escaping @Sendable () -> Void) {
        write {
            $0.onChange = onChange
            $0.onRequest = onUpdateRequested
        }
    }

    func linkChanged() { read(\.onChange)?() }
    func watchAsked() { read(\.onRequest)?() }

    struct FakeWatchError: Error {}
}

struct WatchSyncServiceTests {
    private nonisolated final class Budget: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [Int] = []
        func note(_ value: Int) { lock.withLock { seen.append(value) } }
        var values: [Int] { lock.withLock { seen } }
    }

    private func make(_ session: FakeWatchSession = FakeWatchSession(), clock: Date = now) -> (WatchSyncService, FakeWatchSession, WatchSyncDefaults, Budget) {
        let defaults = WatchSyncDefaults(defaults: UserDefaults(suiteName: "noctis.watch.\(UUID().uuidString)") ?? .standard)
        let budget = Budget()
        let service = WatchSyncService(session: session, defaults: defaults, clock: { clock }, signpost: { budget.note($0) })
        return (service, session, defaults, budget)
    }

    @Test func aWrittenSnapshotIsQueuedForTheWatchAndRemembered() async throws {
        let (service, session, defaults, _) = make()
        await service.publish(snapshot())
        let context = try decoded(session.contexts.first)
        #expect(session.contexts.count == 1 && context.snapshot == snapshot())
        #expect(defaults.lastSentAt == now)
        let status = await service.status()
        #expect(status.lastSentAt == now && status.connection == .connected)
    }

    @Test func nothingIsQueuedForAWatchThatCannotTakeIt() async {
        for (change, expected) in [
            ({ (s: FakeWatchSession) in s.isSupported = false }, WatchConnectionStatus.Connection.notSupported),
            ({ $0.isPaired = false }, .noWatchPaired),
            ({ $0.isWatchAppInstalled = false }, .appNotInstalled),
            ({ $0.activation = .notActivated }, .notActivated),
        ] as [((FakeWatchSession) -> Void, WatchConnectionStatus.Connection)] {
            let (service, session, defaults, _) = make()
            change(session)
            await service.publish(snapshot())
            #expect(session.contexts.isEmpty && defaults.lastSentAt == nil, Comment(rawValue: "\(expected)"))
            #expect(await service.status().connection == expected)
        }
    }

    @Test func anUnreachableWatchStillGetsTheUpdateQueuedForWhenItConnects() async {
        let session = FakeWatchSession()
        session.isReachable = false
        let (service, _, _, _) = make(session)
        await service.publish(snapshot())
        #expect(session.contexts.count == 1)
        #expect(await service.status().connection == .notReachable)
    }

    @Test func aSnapshotIsNeverSentOlderThanTheEpochTheIPhoneHolds() async throws {
        let (service, session, defaults, _) = make()
        defaults.dataEpoch = 900
        await service.publish(snapshot(epoch: 0))
        let context = try decoded(session.contexts.first)
        #expect(context.snapshot?.dataEpoch == 900 && context.effectiveEpoch == 900)
    }

    // MARK: Complication

    @Test func theComplicationIsWokenWhenTheDayChangesWithinTheBudget() async throws {
        let (service, session, _, budget) = make()
        await service.publish(snapshot(day: 24))
        #expect(session.complicationInfos.count == 1, "a new day")
        #expect(budget.values == [50], "the budget left is logged, nothing else")
        await service.publish(snapshot(.full, day: 24, generated: now.addingTimeInterval(600)))
        #expect(session.complicationInfos.count == 1, "the same day with its recovery: nothing new")
        await service.publish(snapshot(day: 25))
        #expect(session.complicationInfos.count == 2, "the next day")
        let sent = try decoded(session.complicationInfos.last)
        #expect(sent.snapshot?.forDay == WidgetDay(year: 2026, month: 9, day: 25))
    }

    @Test func theComplicationIsWokenWhenRecoveryFirstAppearsForTheDay() async {
        let (service, session, _, _) = make()
        await service.publish(snapshot(.learning(nightsSoFar: 4), day: 24))
        #expect(session.complicationInfos.count == 1, "a new day, no recovery yet")
        await service.publish(snapshot(.full, day: 24))
        #expect(session.complicationInfos.count == 2, "recovery appeared")
        await service.publish(snapshot(.sleepOnly, day: 24))
        #expect(session.complicationInfos.count == 2, "and only once")
    }

    @Test func theComplicationIsLeftAloneWithoutItOnTheFaceOrWithNoBudgetLeft() async {
        let off = FakeWatchSession()
        off.isComplicationEnabled = false
        let (first, offSession, _, offBudget) = make(off)
        await first.publish(snapshot())
        #expect(offSession.complicationInfos.isEmpty && offSession.contexts.count == 1, "the context still goes")
        #expect(offBudget.values.isEmpty)

        let spent = FakeWatchSession()
        spent.remainingComplicationTransfers = 0
        let (second, spentSession, defaults, spentBudget) = make(spent)
        await second.publish(snapshot())
        #expect(spentSession.complicationInfos.isEmpty && spentBudget.values == [0], "the budget is logged even when it stops the transfer")
        #expect(defaults.complicationMark == nil, "not marked: tomorrow's budget is tried again")
        spent.remainingComplicationTransfers = 3
        await second.publish(snapshot(generated: now.addingTimeInterval(60)))
        #expect(spentSession.complicationInfos.count == 1)
    }

    @Test func theComplicationMarkSurvivesARelaunchSoItIsNotWokenAgain() async {
        let defaults = WatchSyncDefaults(defaults: UserDefaults(suiteName: "noctis.watch.\(UUID().uuidString)") ?? .standard)
        let session = FakeWatchSession()
        let first = WatchSyncService(session: session, defaults: defaults, clock: { now })
        await first.publish(snapshot())
        let second = WatchSyncService(session: session, defaults: defaults, clock: { now })
        await second.publish(snapshot(generated: now.addingTimeInterval(60)))
        #expect(session.complicationInfos.count == 1)
    }

    // MARK: Delete

    @Test func deleteAllRaisesTheEpochAndSendsItWithNoSnapshot() async throws {
        let (service, session, defaults, _) = make()
        await service.publish(snapshot())
        let outcome = await service.wipe()
        #expect(outcome == .sent && outcome.line == "Apple Watch: wipe sent")
        let context = try decoded(session.contexts.last)
        #expect(context.snapshot == nil && context.epoch == defaults.dataEpoch && context.epoch >= Int64(now.timeIntervalSince1970.rounded()))
        #expect(defaults.lastSentAt == nil && defaults.complicationMark == nil, "nothing is remembered about what was sent")
    }

    @Test func theEpochNeverGoesBackwardsWhateverTheClockSays() async {
        let (service, _, defaults, _) = make()
        defaults.dataEpoch = Int64(now.timeIntervalSince1970) + 5000
        _ = await service.wipe()
        #expect(defaults.dataEpoch == Int64(now.timeIntervalSince1970) + 5001, "a Watch ignores a lower epoch: it is always raised")
    }

    @Test func aWatchThatCannotBeReachedIsToldWhenItConnects() async {
        let away = FakeWatchSession()
        away.isReachable = false
        let (service, session, _, _) = make(away)
        let outcome = await service.wipe()
        #expect(outcome == .willApplyWhenConnected && outcome.line == "Apple Watch: will apply when your Watch connects")
        #expect(session.contexts.count == 1, "it is queued, and delivered then")
    }

    @Test func withNoWatchThereIsNothingToWipeAndTheEpochIsStillRaised() async {
        let none = FakeWatchSession()
        none.isPaired = false
        let (service, session, defaults, _) = make(none)
        let outcome = await service.wipe()
        #expect(outcome == .noWatch && outcome.line == "Apple Watch: none set up with NOCTIS")
        #expect(session.contexts.isEmpty && defaults.dataEpoch > 0, "a Watch paired later still learns of it from the next snapshot")
        let refused = FakeWatchSession()
        refused.failUpdates = true
        let (failing, _, _, _) = make(refused)
        #expect(await failing.wipe() == .willApplyWhenConnected, "the next snapshot carries the epoch")
    }

    @Test func theEpochIsTheOneValueDeleteAllLeavesAndTheOthersGo() {
        let suite = UserDefaults(suiteName: "noctis.watch.\(UUID().uuidString)") ?? .standard
        let defaults = WatchSyncDefaults(defaults: suite)
        defaults.lastSentAt = now
        defaults.complicationMark = "2026-09-24:1"
        defaults.dataEpoch = 123
        #expect(
            suite.dictionaryRepresentation().keys.filter { $0.hasPrefix("noctis.watch.") }.sorted() == [
                WatchSyncDefaults.complicationMarkKey, WatchSyncDefaults.lastSentAtKey,
            ])
        #expect(!WatchSyncDefaults.dataEpochKey.hasPrefix("noctis."), "so the clear-everything step leaves it")
        // What delete-all does to the defaults: every key under the prefix.
        for key in suite.dictionaryRepresentation().keys where key.hasPrefix("noctis.") { suite.removeObject(forKey: key) }
        #expect(defaults.lastSentAt == nil && defaults.complicationMark == nil && defaults.dataEpoch == 123)
    }

    @Test func deletingTheSummaryAlonetellsTheWatchToDropItsCopyWithoutRaisingTheEpoch() async throws {
        let (service, session, defaults, _) = make()
        defaults.dataEpoch = 77
        await service.publish(snapshot(epoch: 77))
        await service.forget()
        let context = try decoded(session.contexts.last)
        #expect(context.snapshot == nil && context.epoch == 77 && defaults.dataEpoch == 77)
        // The Watch drops its copy and keeps its epoch.
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = WatchInbox(directory: directory)
        inbox.receive(try WatchContext(snapshot: snapshot(epoch: 77), sentAt: now), now: now)
        #expect(inbox.receive(context, now: now) == .cleared && inbox.load() == nil && inbox.epoch == 77)
    }

    // MARK: Asking

    @Test func theWatchAskingForAnUpdateRunsTheRefreshThenSendsTheLatestAgain() async throws {
        let (service, session, _, _) = make()
        nonisolated final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func bump() { lock.withLock { value += 1 } }
            var count: Int { lock.withLock { value } }
        }
        let refreshes = Counter()
        await service.activate(onUpdateRequested: { refreshes.bump() })
        #expect(session.activations == 1)
        await service.publish(snapshot())
        session.watchAsked()
        // The request runs on its own task: wait for the second send.
        _ = await waitFor { !(session.contexts.count < 2) }
        #expect(refreshes.count == 1 && session.contexts.count == 2)
    }

    @Test func sendNowSaysWhatHappened() async {
        let (service, session, _, _) = make()
        #expect(await service.sendNow() == .nothingToSend)
        #expect(await service.sendNow(snapshot()) == .sent(now))
        session.failUpdates = true
        #expect(await service.sendNow(snapshot()) == .failed("The system would not queue the update."))
        session.failUpdates = false
        session.isWatchAppInstalled = false
        #expect(await service.sendNow(snapshot()) == .appNotInstalled)
        session.isPaired = false
        #expect(await service.sendNow(snapshot()) == .noWatchPaired)
    }

    @Test func theStatusStreamSpeaksNowAndWhenTheLinkChanges() async throws {
        let (service, session, _, _) = make()
        await service.activate()
        var iterator = await service.updates().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.connection == .connected)
        session.isReachable = false
        session.linkChanged()
        let second = await iterator.next()
        #expect(second?.connection == .notReachable)
    }

    @Test func theSettingsRowAppearsOnlyWithAPairedWatch() {
        var status = WatchConnectionStatus(isSupported: true, isPaired: true, isWatchAppInstalled: false, activation: .activated, isReachable: false)
        #expect(status.showsSettingsRow && status.connection == .appNotInstalled && !status.canSend)
        status.isPaired = false
        #expect(!status.showsSettingsRow && status.connection == .noWatchPaired)
        #expect(!WatchConnectionStatus.unsupported.showsSettingsRow)
        #expect(WatchConnectionStatus(isSupported: true, isPaired: true, isWatchAppInstalled: true, activation: .activated, isReachable: false).canSend)
    }
}

// MARK: - What the inventory says, and what the code holds to it

struct WatchInventoryTests {
    private let inventory = DataInventory.shared

    @Test func theSummaryLeavesTheIPhoneOnlyToTheUsersOwnWatchAndSaysSo() {
        let summary = inventory[.widgetSnapshot]
        guard case .pairedWatch(let detail) = summary.destination else {
            Issue.record("the destination is the paired Watch")
            return
        }
        #expect(detail.contains("paired Apple Watch") && detail.contains("never sent to a server"))
        #expect(!summary.holdsUserContent && summary.summary.contains("Apple Watch"))
        let flow = inventory.flows.first { $0.id == "appleWatch" }
        #expect(flow?.trigger == .toYourWatch && flow?.categories == [.widgetSnapshot])
        #expect(flow?.detail.contains("never to a server") == true)
    }

    @Test func theStatementsStayTrueAndOneMoreIsSaid() throws {
        let sent = try #require(PrivacyStatements.sentToWatch(inventory))
        #expect(sent.text == "A summary of your recovery and sleep is sent to your Apple Watch." && sent.evidence == [.widgetSnapshot])
        #expect(PrivacyStatements.nothingSoldOrShared(inventory)?.text == "Nothing is sold or shared.")
        #expect(PrivacyStatements.storedOnDevice(inventory)?.text == "Your data is stored on this iPhone.")
        #expect(PrivacyStatements.noSync(inventory) != nil, "the Watch gets a copy over WatchConnectivity; nothing syncs through iCloud or a server")
        #expect(PrivacyStatements.headline(inventory).map(\.id).contains("sentToWatch"))
        // It is not said while no category goes to the Watch.
        let without = DataInventory(
            categories: inventory.categories.map { category in
                guard category.id == .widgetSnapshot else { return category }
                return DataCategory(
                    category.id, name: category.name, summary: category.summary, contents: category.contents, locations: category.locations,
                    entities: category.entities, notificationIdentifiers: category.notificationIdentifiers, destination: .never, syncs: category.syncs,
                    coach: category.coach, inBackup: category.inBackup, protection: category.protection, deletion: category.deletion, owner: category.owner,
                    holdsUserContent: category.holdsUserContent, export: category.export
                )
            },
            flows: inventory.flows, networkUses: inventory.networkUses, groups: inventory.groups, retiredKeys: inventory.retiredKeys, facts: inventory.facts
        )
        #expect(PrivacyStatements.sentToWatch(without) == nil)
    }

    @Test func thePrivacyCenterListsTheWatchAndWhatItSays() {
        let content = PrivacyCenterBuilder.content(inventory)
        #expect(content.leavesToWatch.map(\.id) == ["appleWatch"])
        #expect(content.leavesNote.contains("your own Apple Watch") && content.leavesNote.contains("nothing anywhere else"))
        #expect(content.headline.map(\.id).contains("sentToWatch"))
        #expect(content.stays.contains { $0.category == .widgetSnapshot }, "the summary is still kept on this iPhone")
        let page = PrivacyCategoryContent.make(inventory[.widgetSnapshot], in: inventory)
        #expect(page.leaves.hasPrefix("Yes, to your own paired Apple Watch"))
    }

    @Test func theReportCoversTheWatch() throws {
        let report = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Docs/PRIVACY_REPORT.md"), encoding: .utf8)
        #expect(report.contains("A summary of your recovery and sleep is sent to your Apple Watch"))
        #expect(report.contains("WatchConnectivity") && report.contains("Apple Watch status"))
    }

    @Test func watchConnectivityIsNamedOnlyInTheDriverAndTheReceiver() throws {
        var found: Set<String> = []
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App", "Widgets/Alarm", "Widgets/Home", "Watch/App", "Watch/Widgets"]) {
            // The inventory names the API as a string; that is not a use.
            if file.path.contains("NoctisCore/DataInventory") || file.path.contains("NoctisCore/Privacy") { continue }
            let code = RawDefaultsTests.code(file.text)
            if code.contains("import WatchConnectivity") {
                found.insert(file.path.replacingOccurrences(of: "Packages/NoctisKit/Sources/", with: ""))
            }
        }
        #expect(found == ["NoctisCore/WatchSync/WCSessionDriver.swift", "Watch/App/WatchSnapshotReceiver.swift"], "\(found)")
        let use = try #require(inventory.networkUses.first { $0.token == "import WatchConnectivity" })
        #expect(Set(use.files) == found && use.categories == [.widgetSnapshot])
    }

    @Test func theWatchStatusIsListedAndTheEpochIsTheOneValueThatSurvives() {
        let status = inventory[.watchSync]
        #expect(status.defaultsKeys == [WatchSyncDefaults.lastSentAtKey, WatchSyncDefaults.complicationMarkKey, WatchPreferenceKeys.breathHaptics])
        #expect(inventory.facts.survivesDeleteAll.map(\.key) == [WatchSyncDefaults.dataEpochKey])
        let keys = inventory.defaultsKeys
        #expect(!keys.contains(WatchSyncDefaults.dataEpochKey), "no category lists it: delete-all must leave it")
        #expect(inventory.facts.survivesDeleteAll.allSatisfy { !$0.key.hasPrefix("noctis.") && !$0.why.isEmpty && !$0.what.isEmpty })
        #expect(inventory.groups.first { $0.id == "cache" }?.categories.contains(.watchSync) == true)
        #expect(inventory.groups.first { $0.id == "cache" }?.removes.contains("Apple Watch") == true)
    }
}

// MARK: - The Watch targets read no Health

struct WatchTargetStructureTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RawDefaultsTests.root.appendingPathComponent(path), encoding: .utf8)
    }

    private func block(_ name: String, in project: String) throws -> String {
        let start = try #require(project.range(of: "\n  \(name):\n"))
        let tail = String(project[start.upperBound...])
        let end = tail.range(of: "\n  [A-Za-z]+:\n", options: .regularExpression)?.lowerBound ?? tail.endIndex
        return String(tail[..<end])
    }

    @Test func theTargetsAreDerivedFromTheAppsBundleIDAndTheWatchAppIsEmbedded() throws {
        let project = try read("project.yml")
        let watch = try block("NOCTISWatch", in: project)
        let widgets = try block("NOCTISWatchWidgets", in: project)
        #expect(watch.contains("platform: watchOS") && watch.contains("deploymentTarget: \"26.0\"") && watch.contains("type: application"))
        #expect(watch.contains("PRODUCT_BUNDLE_IDENTIFIER: com.noctis.app.watchkitapp") && watch.contains("WKCompanionAppBundleIdentifier: com.noctis.app"))
        #expect(
            widgets.contains("PRODUCT_BUNDLE_IDENTIFIER: com.noctis.app.watchkitapp.widgets") && widgets.contains("type: app-extension")
                && widgets.contains("platform: watchOS"))
        #expect(watch.contains("target: NOCTISWatchWidgets"), "the complications are embedded in the Watch app")
        let app = try block("Noctis", in: project)
        #expect(app.contains("- target: NOCTISWatch"), "the Watch app is embedded in the iPhone app")
        // The same App Group identifier on both sides (separate containers on separate devices).
        for entitlement in ["Config/NOCTISWatch.entitlements", "Config/NOCTISWatchWidgets.entitlements"] {
            let text = try read(entitlement)
            #expect(
                text.contains("<string>\(WidgetSnapshotStore.appGroupIdentifier)</string>") && text.components(separatedBy: "<string>").count - 1 == 1,
                Comment(rawValue: entitlement))
        }
    }

    @Test func noWatchTargetHasHealthKitAnEntitlementOrAUsageString() throws {
        let project = try read("project.yml")
        for name in ["NOCTISWatch", "NOCTISWatchWidgets"] {
            let text = try block(name, in: project)
            for token in [
                "HealthKit", "healthkit", "NSHealth", "HealthProviding", "SleepKit", "RecoveryKit", "SleepAnalysisKit", "InsightsKit", "NoctisCore",
                "HomeFeature",
            ] {
                #expect(!text.contains(token), Comment(rawValue: "\(name) mentions \(token)"))
            }
        }
        for path in ["Config/NOCTISWatch.entitlements", "Config/NOCTISWatchWidgets.entitlements"] {
            let text = try read(path)
            #expect(!text.lowercased().contains("healthkit") && !text.contains("NSHealth"), Comment(rawValue: path))
        }
        // The code: no import of HealthKit or anything that reads Health, and no engine.
        for file in RawDefaultsTests.swiftFiles(under: [
            "Watch/App", "Watch/Widgets", "Packages/NoctisKit/Sources/NoctisWatchKit", "Packages/NoctisKit/Sources/NoctisWidgetKit",
        ]) {
            let code = RawDefaultsTests.code(file.text)
            for token in [
                "import HealthKit", "HKHealthStore", "import HealthProviding", "import SleepKit", "import RecoveryKit", "import SleepAnalysisKit",
                "import InsightsKit",
                "import NoctisCore", "import SwiftData", "import CoachKit", "import JournalKit",
            ] { #expect(!code.contains(token), Comment(rawValue: "\(file.path) has \(token)")) }
        }
    }

    @Test func theKitsTheWatchLinksDependOnNothingThatReadsHealth() throws {
        let package = try read("Packages/NoctisKit/Package.swift")
        for line in ["name: \"NoctisWatchKit\"", "name: \"NoctisWidgetKit\"", "name: \"DesignSystem\"", "name: \"BreathingKit\""] {
            let row = try #require(package.components(separatedBy: "\n").first { $0.contains(".target(\(line)") })
            for token in ["HealthProviding", "SleepKit", "RecoveryKit", "SleepAnalysisKit", "NoctisCore", "InsightsKit", "NightKit", "SoundKit"] {
                #expect(!row.contains(token), Comment(rawValue: "\(line) depends on \(token)"))
            }
        }
        let project = try read("project.yml")
        let products = try block("NOCTISWatch", in: project).components(separatedBy: "product: ").dropFirst().map { String($0.prefix { $0.isLetter }) }
        #expect(Set(products) == ["NoctisWatchKit", "NoctisWidgetKit", "DesignSystem", "BreathingKit"], "\(products)")
    }

    @Test func eachWatchTargetHasItsOwnPrivacyManifestThatDeclaresOnlyWhatItUses() throws {
        for path in ["Watch/App/PrivacyInfo.xcprivacy", "Watch/Widgets/PrivacyInfo.xcprivacy"] {
            let data = try Data(contentsOf: RawDefaultsTests.root.appendingPathComponent(path))
            let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            #expect(plist["NSPrivacyTracking"] as? Bool == false, Comment(rawValue: path))
            #expect((plist["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true && (plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
            let types = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]], Comment(rawValue: path))
            if path.hasPrefix("Watch/Widgets") {
                #expect(types.isEmpty, "the complications use no required-reason API: no defaults, no timestamps")
            } else {
                // The Watch app keeps one preference of its own in UserDefaults (R55), for its own use only: reason CA92.1.
                #expect(types.count == 1 && types.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
                #expect(types.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
            }
        }
    }

    @Test func theWatchCodeUsesNoRequiredReasonAPIBeyondTheOneItsManifestDeclares() throws {
        let tokens = [
            "@AppStorage", "creationDate", "modificationDate", "contentModificationDate", "systemUptime", "mach_absolute_time", "volumeAvailableCapacity",
            "systemFreeSize", "activeInputModes", "fstat(", "lstat(",
        ]
        let files = RawDefaultsTests.swiftFiles(under: [
            "Watch/App", "Watch/Widgets", "Packages/NoctisKit/Sources/NoctisWatchKit", "Packages/NoctisKit/Sources/NoctisWidgetKit",
            "Packages/NoctisKit/Sources/DesignSystem",
        ])
        #expect(files.count > 20)
        var usesDefaults: Set<String> = []
        for file in files {
            let code = RawDefaultsTests.code(file.text)
            for token in tokens { #expect(!code.contains(token), Comment(rawValue: "\(file.path) uses \(token)")) }
            if code.contains("UserDefaults") { usesDefaults.insert(file.path) }
        }
        // UserDefaults is named only by the small wrapper in the Watch kit (`WatchPreferences`, the Watch app's one preference); the Watch app opens it
        // with the system's own defaults, and that is the use its manifest declares.
        #expect(usesDefaults == ["Packages/NoctisKit/Sources/NoctisWatchKit/WatchBreathing.swift"], "\(usesDefaults)")
        let model = try read("Watch/App/WatchModel.swift")
        #expect(model.contains("WatchPreferences(defaults: .standard)"))
    }

    @Test func theWatchBuildsOnlyWhatItNeedsFromTheKits() throws {
        // The iOS-only parts of the widget kit are not built for the Watch.
        for name in ["WidgetViews.swift", "WindDownActivity.swift", "WindDownActivityViews.swift"] {
            let text = try read("Packages/NoctisKit/Sources/NoctisWidgetKit/\(name)")
            #expect(text.hasPrefix("#if os(iOS)"), Comment(rawValue: name))
        }
        let package = try read("Packages/NoctisKit/Package.swift")
        #expect(package.contains("platforms: [.iOS(\"26.1\"), .watchOS(.v26)]"))
    }
}
