import Foundation
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import NightKit
@testable import NoctisCore
@testable import NoctisWidgetKit
@testable import RecoveryKit
@testable import SleepKit

// The widgets' snapshot (APP_RULES.md R44): its shape and size, how it is stored, how it is made from Home's data, when it is
// written, and the few links that open the app from outside.

enum WidgetFixture {
    static let now = Fixture.date(2026, 9, 24, 10)
    static var calendar: Calendar { Fixture.calendar() }

    static var full: WidgetSnapshot {
        WidgetSnapshot(
            forDay: WidgetDay(year: 2026, month: 9, day: 24), generatedAt: now,
            plan: WidgetPlan(wakeMinutes: 7 * 60, needMinutes: 8 * 60, bedtimeMinutes: 23 * 60, windowStartMinutes: 22 * 60 + 45, windowEndMinutes: 23 * 60 + 15),
            state: .full,
            recovery: WidgetRecovery(
                score: 70, delta: 6, confidence: .high,
                ring: [
                    WidgetRingSegment(kind: .sleepDuration, weight: 0.4, fraction: 0.82), WidgetRingSegment(kind: .hrv, weight: 0.25, fraction: 0.64),
                    WidgetRingSegment(kind: .restingHeartRate, weight: 0.2, fraction: 0.71), WidgetRingSegment(kind: .sleepConsistency, weight: 0.15, fraction: 0.9),
                ]
            ),
            lastNight: WidgetNight(asleepMinutes: 402, stages: WidgetStages(deep: 74, core: 236, rem: 92), bedtimeMinutes: 23 * 60 + 4, wakeMinutes: 6 * 60 + 52, quality: 81),
            factors: WidgetFactors(hrv: 54, restingHeartRate: 52), alarm: WidgetAlarm(minutes: 7 * 60, isOn: true)
        )
    }

    static func directory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "noctis-widget-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct WidgetSnapshotShapeTests {
    @Test func aSnapshotRoundTripsExactly() throws {
        let snapshot = WidgetFixture.full
        let data = try snapshot.encoded()
        #expect(WidgetSnapshot.decode(data) == snapshot)
    }

    @Test func everyDataStateRoundTripsAsOneShortWord() throws {
        let states: [WidgetDataState] = [.full, .sleepOnly, .learning(nightsSoFar: 3), .empty, .noPermission, .stale(hours: 14), .gap]
        for state in states {
            var snapshot = WidgetFixture.full
            snapshot.state = state
            let decoded = try #require(WidgetSnapshot.decode(try snapshot.encoded()))
            #expect(decoded.state == state)
            #expect(WidgetDataState(token: state.token) == state)
        }
        #expect(WidgetDataState(token: "nonsense") == nil && WidgetDataState(token: "learning") == nil && WidgetDataState(token: "full:3") == nil)
    }

    @Test func theFullestSnapshotIsUnderTwoKilobytes() throws {
        let data = try WidgetFixture.full.encoded()
        #expect(data.count < WidgetSnapshot.maximumBytes, "\(data.count) bytes")
        #expect(data.count < 1024, "and well under it: \(data.count) bytes")
        // With every optional there is and the longest numbers.
        var worst = WidgetFixture.full
        worst.recovery = WidgetRecovery(score: 100, delta: -100, confidence: .moderate, ring: worst.recovery?.ring ?? [])
        worst.lastNight = WidgetNight(asleepMinutes: 1439, stages: WidgetStages(deep: 999, core: 999, rem: 999), bedtimeMinutes: 1439, wakeMinutes: 1439, quality: 100)
        worst.factors = WidgetFactors(hrv: 999, restingHeartRate: 199)
        worst.state = .stale(hours: 9999)
        #expect(try worst.encoded().count < WidgetSnapshot.maximumBytes)
    }

    @Test func aSnapshotOfAnotherVersionOrOfNoSenseIsNotRead() throws {
        var other = WidgetFixture.full
        other.version = WidgetSnapshot.currentVersion + 1
        #expect(WidgetSnapshot.decode(try other.encoded()) == nil, "a version this reader does not know")
        #expect(WidgetSnapshot.decode(Data("not json".utf8)) == nil)
        #expect(WidgetSnapshot.decode(Data("{}".utf8)) == nil)
        #expect(WidgetSnapshot.decode(Data()) == nil)
    }

    @Test func theSnapshotHasNoPlaceForASampleASourceTheJournalOrCoach() throws {
        // The keys on disk are the whole list of what the widgets can ever be told.
        let object = try #require(try JSONSerialization.jsonObject(with: WidgetFixture.full.encoded()) as? [String: Any])
        var keys = Set<String>()
        func collect(_ value: Any) {
            if let dictionary = value as? [String: Any] { for (key, inner) in dictionary { keys.insert(key); collect(inner) } }
            if let array = value as? [Any] { array.forEach(collect) }
        }
        collect(object)
        let allowed: Set<String> = ["v", "day", "at", "p", "st", "rec", "n", "f", "al", "w", "ws", "we", "b", "s", "d", "c", "r", "k", "a", "q", "hrv", "rhr", "m", "on", "deep", "core", "rem", "rf", "nh", "de", "t"]
        #expect(keys.isSubset(of: allowed), "unexpected keys: \(keys.subtracting(allowed).sorted())")
        // And the type's own source names none of them either.
        let source = (try? String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetSnapshot.swift"), encoding: .utf8)) ?? ""
        for word in ["sourceName", "sourceBundle", "sampleDate", "sampleTime", "journal", "Journal", "coach", "Coach", "insight", "Insight", "heartRateSamples"] {
            #expect(!RawDefaultsTests.code(source).contains(word), Comment(rawValue: "the snapshot mentions \(word)"))
        }
    }

    @Test func theLearningNightsMatchTheModel() {
        #expect(WidgetSnapshot.learningNights == RecoveryModelV2.learningNights)
    }

    // MARK: forDay

    @Test func aWidgetDayStartsAtFourInTheMorning() {
        let calendar = WidgetFixture.calendar
        #expect(WidgetDay.today(at: Fixture.date(2026, 9, 24, 3, 59), calendar: calendar) == WidgetDay(year: 2026, month: 9, day: 23), "the small hours are still last evening's")
        #expect(WidgetDay.today(at: Fixture.date(2026, 9, 24, 4, 0), calendar: calendar) == WidgetDay(year: 2026, month: 9, day: 24))
        #expect(WidgetDay.today(at: Fixture.date(2026, 9, 24, 23, 59), calendar: calendar) == WidgetDay(year: 2026, month: 9, day: 24))
        #expect(WidgetDay.today(at: Fixture.date(2026, 10, 1, 2), calendar: calendar) == WidgetDay(year: 2026, month: 9, day: 30), "across a month")
        #expect(WidgetDay(year: 2026, month: 9, day: 23) < WidgetDay(year: 2026, month: 10, day: 1))
        #expect(WidgetDay(year: 2026, month: 9, day: 4).description == "2026-09-04")
    }
}

struct WidgetSnapshotStoreTests {
    @Test func aSavedSnapshotIsLoadedBack() throws {
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.load() == nil && !store.exists)
        #expect(store.save(WidgetFixture.full))
        #expect(store.load() == WidgetFixture.full && store.exists)
        #expect(store.fileURL.lastPathComponent == "WidgetSnapshot.json")
    }

    @Test func theWriteIsAtomicAndLeavesNoOtherFile() throws {
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        for day in 1...5 {
            var snapshot = WidgetFixture.full
            snapshot.forDay = WidgetDay(year: 2026, month: 9, day: day)
            #expect(store.save(snapshot))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["WidgetSnapshot.json"], "no temporary file is left")
        #expect(store.load()?.forDay == WidgetDay(year: 2026, month: 9, day: 5), "the newest write won, whole")
    }

    @Test func aSnapshotOverTheCapIsRefusedAndTheOldFileStays() throws {
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.save(WidgetFixture.full))
        var bloated = WidgetFixture.full
        bloated.recovery?.ring = Array(repeating: WidgetRingSegment(kind: .hrv, weight: 0.123, fraction: 0.456), count: 200)
        #expect(!store.save(bloated), "over \(WidgetSnapshot.maximumBytes) bytes")
        #expect(store.load() == WidgetFixture.full, "the file that was there is untouched")
    }

    @Test func theFileIsExcludedFromBackupsAndWrittenWithTheProtectionTheWidgetNeeds() throws {
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.save(WidgetFixture.full))
        #expect(try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        // Complete-until-first-user-authentication: readable while locked after the first unlock. (The simulator does not report
        // a protection class, so the option is held in the source, and the real iPhone is on the list to check.)
        let source = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetSnapshotStore.swift"), encoding: .utf8)
        #expect(source.contains(".completeFileProtectionUntilFirstUserAuthentication") && source.contains(".atomic"))
        #expect(!source.contains(".completeFileProtection,") && !source.contains("completeFileProtection]"), "not the stronger class: a locked widget could not read it")
    }

    @Test func deletingIsIdempotent() throws {
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        store.delete()
        #expect(store.save(WidgetFixture.full))
        store.delete()
        #expect(store.load() == nil && !store.exists)
        store.delete()
    }

    @Test func aNewerWritersFileReadsAsNothingAndTheOldOneIsReplaced() throws {
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        var newer = WidgetFixture.full
        newer.version = 99
        try newer.encoded().write(to: store.fileURL)
        #expect(store.load() == nil, "an old reader shows 'Open NOCTIS' rather than guess")
        #expect(store.save(WidgetFixture.full) && store.load() != nil)
    }

    @Test func onlyThisStoreNamesTheAppGroup() throws {
        let files = RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App", "NoctisWidgets", "NoctisAlarmWidget"])
        #expect(files.count > 150)
        for file in files where !file.path.hasSuffix("NoctisWidgetKit/WidgetSnapshotStore.swift") {
            let code = RawDefaultsTests.code(file.text)
            #expect(!code.contains("containerURL(forSecurityApplicationGroupIdentifier"), Comment(rawValue: "\(file.path) opens the App Group"))
            #expect(!code.contains("group.com.noctis"), Comment(rawValue: "\(file.path) names the App Group"))
            #expect(code.range(of: #"UserDefaults\(suiteName"#, options: .regularExpression) == nil || file.path.hasSuffix("HomePreviews.swift"), Comment(rawValue: "\(file.path) opens a defaults suite"))
        }
        let entitlements = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/Noctis.entitlements"), encoding: .utf8)
        #expect(entitlements.components(separatedBy: "<string>group.").count == 2, "exactly one group")
        #expect(entitlements.contains("<string>\(WidgetSnapshotStore.appGroupIdentifier)</string>"))
    }

    @Test func theKitReachesNeitherHealthNorStoresNorCoach() throws {
        let kit = RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources/NoctisWidgetKit", "NoctisWidgets"])
        #expect(!kit.isEmpty)
        for file in kit {
            let code = RawDefaultsTests.code(file.text)
            for token in ["import HealthKit", "import HealthProviding", "import SwiftData", "import CoachKit", "import JournalKit", "import NoctisCore", "import SleepKit", "import RecoveryKit",
                          "import InsightsKit", "import NightKit", "HKHealthStore", "ModelContainer", "ModelContext", "import AppRoot"] {
                #expect(!code.contains(token), Comment(rawValue: "\(file.path) has \(token)"))
            }
        }
        let package = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Package.swift"), encoding: .utf8)
        #expect(package.contains(#".target(name: "NoctisWidgetKit", dependencies: ["DesignSystem", "PremiumKit"]"#), "the kit depends on the design tokens and the plan's names (a leaf with no dependencies) and nothing more")
    }
}

// MARK: - Made from Home's data

struct WidgetSnapshotMakerTests {
    private let now = WidgetFixture.now

    private func home(_ scenario: MockScenario, profile: UserProfileSnapshot = UserProfileSnapshot()) async -> HomeSnapshot {
        let clock = now
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: clock, calendar: Fixture.calendar(), startAuthorized: true, isHealthDataAvailable: true, failsQueries: false)
        return await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }).refresh(profile: profile)
    }

    private func make(_ home: HomeSnapshot, bedtime: BedtimeRecommendation? = nil, alarm: WidgetAlarm? = nil) -> WidgetSnapshot? {
        WidgetSnapshotMaker.make(home: home, profile: UserProfileSnapshot(), bedtime: bedtime, alarm: alarm, now: now, calendar: WidgetFixture.calendar)
    }

    @Test func aFullNightBecomesRecoveryLastNightAndTheHeartNumbers() async throws {
        let home = await home(.full)
        let snapshot = try #require(make(home, alarm: WidgetAlarm(minutes: 420, isOn: true)))
        #expect(snapshot.state == .full)
        guard case .scored(let result)? = home.recovery else { Issue.record("scored"); return }
        let recovery = try #require(snapshot.recovery)
        #expect(recovery.score == result.score && recovery.delta == result.comparison.delta)
        #expect(recovery.ring.map(\.kind) == [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency], "the ring's order")
        #expect(abs(recovery.ring.map(\.weight).reduce(0, +) - 1) < 0.01)
        let night = try #require(snapshot.lastNight)
        let session = try #require(home.lastNight)
        #expect(night.asleepMinutes == Int((session.totals.asleep / 60).rounded()))
        #expect(night.quality == home.lastNightSleepQuality)
        #expect(night.stages?.total ?? 0 > 0)
        #expect(snapshot.factors?.hrv == result.factor(.hrv).map { Int($0.value.rounded()) })
        #expect(snapshot.factors?.restingHeartRate == result.factor(.restingHeartRate).map { Int($0.value.rounded()) })
        #expect(snapshot.alarm == WidgetAlarm(minutes: 420, isOn: true))
        #expect(snapshot.plan.bedtimeMinutes == home.tonight.bedtimeMinutes && !snapshot.plan.hasWindow, "no recommendation: Home's own plan")
        #expect(try snapshot.encoded().count < WidgetSnapshot.maximumBytes)
    }

    @Test func forDayIsTheMorningTheNightEnded() async throws {
        let snapshot = try #require(make(await home(.full)))
        let session = try #require(await home(.full).lastNight)
        var zoned = WidgetFixture.calendar
        zoned.timeZone = session.timeZone
        #expect(snapshot.forDay == WidgetDay(session.wakeTime, calendar: zoned))
        #expect(snapshot.forDay == WidgetDay(year: 2026, month: 9, day: 24), "last night ended on the morning of the 24th")
    }

    @Test func aRecommendationGivesTheWidgetItsWindowAndItsBedtime() async throws {
        let recommendation = BedtimeRecommendationEngine.recommend(BedtimeInputs(wakeMinutes: 7 * 60, needMinutes: 8 * 60, balanceMinutes: -90, usualBedtimeMinutes: 23 * 60, nights: 10))
        let snapshot = try #require(make(await home(.full), bedtime: recommendation))
        #expect(snapshot.plan.bedtimeMinutes == recommendation.centerMinutes)
        #expect(snapshot.plan.windowStartMinutes == recommendation.window?.startMinutes && snapshot.plan.windowEndMinutes == recommendation.window?.endMinutes)
    }

    @Test func sleepAloneGivesTwoArcsAndNoHeartNumbers() async throws {
        let snapshot = try #require(make(await home(.sleepOnly)))
        #expect(snapshot.state == .sleepOnly)
        #expect(snapshot.recovery?.ring.map(\.kind).allSatisfy { $0 == .sleepDuration || $0 == .sleepConsistency } == true)
        #expect(snapshot.factors == nil)
    }

    @Test func learningHasNoScoreAndSaysHowFarItIs() async throws {
        let home = await home(.learning)
        let snapshot = try #require(make(home))
        guard case .learning(let nights) = snapshot.state else { Issue.record("learning, not \(snapshot.state)"); return }
        guard case .learning(let expected) = home.dataState else { Issue.record("home is learning"); return }
        #expect(nights == expected)
        #expect(snapshot.recovery == nil && snapshot.factors == nil)
    }

    @Test func emptyAndNoPermissionAndGapAndStaleEachGetTheirOwnState() async throws {
        #expect(try #require(make(await home(.empty))).state == .empty)
        let clock = now
        let denied = MockHealthKitProvider(scenario: .full, referenceDate: clock, calendar: Fixture.calendar(), startAuthorized: false, isHealthDataAvailable: true, failsQueries: false)
        let permission = await HomeRepository(provider: denied, timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        #expect(try #require(make(permission)).state == .noPermission)
        #expect(try #require(make(await home(.gap))).state == .gap)
        let stale = try #require(make(await home(.stale)))
        guard case .stale(let hours) = stale.state else { Issue.record("stale, not \(stale.state)"); return }
        #expect(hours >= 24, "the age at the time it was made")
        #expect(stale.forDay == WidgetDay.today(at: now, calendar: WidgetFixture.calendar), "a stale snapshot is for the day it was made, not the day of its numbers")
    }

    @Test func aFailedReadWritesNothing() async throws {
        let clock = now
        let failing = MockHealthKitProvider(scenario: .full, referenceDate: clock, calendar: Fixture.calendar(), startAuthorized: true, isHealthDataAvailable: true, failsQueries: true)
        let home = await HomeRepository(provider: failing, timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        #expect(home.dataState == .failed)
        #expect(make(home) == nil, "the last good snapshot is left as it was")
    }

    @Test func theMakerNeverCopiesASampleASourceOrAnInsight() throws {
        let source = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisCore/WidgetSnapshotMaker.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(source)
        for word in ["sourceName", "sourceBundleID", "newestSample", "topInsight", "heartRate:", "lastNightHeart", "Journal", "Coach"] {
            #expect(!code.contains(word), Comment(rawValue: "the maker reads \(word)"))
        }
    }

    @Test func theAlarmLineIsItsTimeAndWhetherItIsOn() {
        #expect(WidgetSnapshotMaker.alarm(nil) == nil)
        #expect(WidgetSnapshotMaker.alarm(AlarmSettings(minutesSinceMidnight: 6 * 60 + 30)) == WidgetAlarm(minutes: 390, isOn: false))
        var armed = AlarmSettings(minutesSinceMidnight: 420)
        armed.lastState = .armed
        #expect(WidgetSnapshotMaker.alarm(armed) == WidgetAlarm(minutes: 420, isOn: true))
    }
}

// MARK: - Written after a refresh

private nonisolated final class ReloadCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

struct WidgetPublisherTests {
    private let now = WidgetFixture.now

    private func provider(_ scenario: MockScenario = .full, fails: Bool = false) -> MockHealthKitProvider {
        MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true, isHealthDataAvailable: true, failsQueries: fails)
    }

    private func bench(alarm: @escaping @Sendable () async -> WidgetAlarm? = { nil }) throws -> (WidgetPublisher, WidgetSnapshotStore, ReloadCount, URL) {
        let directory = try WidgetFixture.directory()
        let store = WidgetSnapshotStore(directory: directory)
        let inputs = WidgetInputSource(profile: { UserProfileSnapshot() })
        inputs.setAlarm(alarm)
        let reloads = ReloadCount()
        let clock = now
        let publisher = WidgetPublisher(store: store, inputs: inputs, reload: { reloads.bump() }, clock: { clock }, calendar: WidgetFixture.calendar)
        return (publisher, store, reloads, directory)
    }

    @Test func aRefreshWritesTheSnapshotAndReloadsTheWidgets() async throws {
        let (publisher, store, reloads, directory) = try bench()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = now
        let repository = HomeRepository(provider: provider(), timeZone: Fixture.newYork, clock: { clock }, widgets: publisher)
        #expect(store.load() == nil)
        let home = await repository.refresh(profile: UserProfileSnapshot())
        let written = try #require(store.load())
        #expect(written.state == .full && written.recovery?.score != nil && home.dataState == .ready)
        #expect(reloads.count == 1)
    }

    @Test func nothingChangedMeansNoWriteAndNoReload() async throws {
        let (publisher, store, reloads, directory) = try bench()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = now
        let repository = HomeRepository(provider: provider(), timeZone: Fixture.newYork, clock: { clock }, widgets: publisher)
        _ = await repository.refresh(profile: UserProfileSnapshot())
        let before = try Data(contentsOf: store.fileURL)
        _ = await repository.refresh(profile: UserProfileSnapshot())
        await publisher.republish()
        #expect(reloads.count == 1, "the system's reload budget is for real changes")
        #expect(try Data(contentsOf: store.fileURL) == before)
    }

    @Test func aNewAlarmIsADifferenceAndRedrawsTheWidgets() async throws {
        let alarm = AlarmBox()
        let (publisher, store, reloads, directory) = try bench(alarm: { await alarm.value })
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = now
        let repository = HomeRepository(provider: provider(), timeZone: Fixture.newYork, clock: { clock }, widgets: publisher)
        _ = await repository.refresh(profile: UserProfileSnapshot())
        #expect(store.load()?.alarm == nil)
        await alarm.set(WidgetAlarm(minutes: 6 * 60 + 30, isOn: true))
        await publisher.republish()
        #expect(store.load()?.alarm == WidgetAlarm(minutes: 390, isOn: true) && reloads.count == 2)
    }

    @Test func aFailedReadLeavesTheLastSnapshot() async throws {
        let (publisher, store, reloads, directory) = try bench()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = now
        _ = await HomeRepository(provider: provider(), timeZone: Fixture.newYork, clock: { clock }, widgets: publisher).refresh(profile: UserProfileSnapshot())
        let good = try #require(store.load())
        _ = await HomeRepository(provider: provider(fails: true), timeZone: Fixture.newYork, clock: { clock }, widgets: publisher).refresh(profile: UserProfileSnapshot())
        #expect(store.load() == good && reloads.count == 1)
    }

    @Test func forgettingDeletesTheFileAndSuspendingStopsEveryLaterWrite() async throws {
        let (publisher, store, reloads, directory) = try bench()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = now
        let repository = HomeRepository(provider: provider(), timeZone: Fixture.newYork, clock: { clock }, widgets: publisher)
        _ = await repository.refresh(profile: UserProfileSnapshot())
        await publisher.forget()
        #expect(store.load() == nil && reloads.count == 2, "deleted, and the widgets told")
        await publisher.suspend()
        await repository.clearCache()
        _ = await repository.refresh(profile: UserProfileSnapshot())
        #expect(store.load() == nil, "delete-all is not undone by a refresh that was already on its way")
    }

    @Test func withoutAnAppGroupThePublisherDoesNothing() async {
        let publisher = WidgetPublisher(store: nil, inputs: WidgetInputSource(profile: { UserProfileSnapshot() }))
        let clock = now
        let home = await HomeRepository(provider: provider(), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        await publisher.publish(home)
        await publisher.republish()
        let written = await publisher.lastWritten
        #expect(written == nil)
    }
}

private actor AlarmBox {
    var value: WidgetAlarm?
    func set(_ alarm: WidgetAlarm?) { value = alarm }
}

// MARK: - The links

struct WidgetLinkTests {
    @Test func everyLinkIsOneShortURLThatTheRouterOpens() {
        #expect(WidgetLink.allCases.count == 5)
        for link in WidgetLink.allCases {
            #expect(link.url.absoluteString == "noctis://\(link.rawValue)")
            #expect(WidgetLink(url: link.url) == link)
            #expect(WidgetURLRouter.route(for: link.url) == WidgetURLRouter.route(for: link))
        }
        #expect(WidgetURLRouter.route(for: .recovery) == .recovery())
        #expect(WidgetURLRouter.route(for: .sleep) == .sleep())
        #expect(WidgetURLRouter.route(for: .tonight) == .tonight && WidgetURLRouter.route(for: .bedtime) == .tonight)
        #expect(WidgetURLRouter.route(for: .windDown) == .windDown(autostart: false), "opened, never started from a URL")
    }

    @Test func nothingButTheFiveLinksIsAccepted() {
        let rejected = [
            "noctis://coach", "noctis://insights", "noctis://insights?category=sleep", "noctis://settings", "noctis://settings?section=notifications", "noctis://profile",
            "noctis://alarm", "noctis://sounds", "noctis://home", "noctis://insight?id=bedtimeShift-3fa9c2d1",
            "noctis://wind-down?autostart=1", "noctis://recovery?range=30d", "noctis://sleep?night=2026-09-28T23:04:00Z", "noctis://tonight?x=1",
            "noctis://recovery/coach", "noctis://recovery/../coach", "noctis://recovery#section", "noctis://user@recovery", "noctis://user:pw@recovery", "noctis://recovery:8080",
            "noctis:recovery", "noctis:///recovery", "noctis://", "noctis", "https://recovery", "http://noctis/recovery", "noctisx://recovery", "xnoctis://recovery",
            "noctis://%72ecovery", "noctis://recovery%00", "noctis://recovery%20", "noctis://r\u{0435}covery", "noctis://RECOVERY.evil.example", "noctis://recovery.evil.example",
            "noctis://recovery//", "noctis://recovery/x", "noctis://wind_down", "noctis://winddown", "noctis://Wind Down",
            "noctis://" + String(repeating: "a", count: 5000), "noctis://recovery?" + String(repeating: "a", count: 5000),
        ]
        for text in rejected {
            guard let url = URL(string: text) else { continue }
            #expect(WidgetLink(url: url) == nil, Comment(rawValue: "\(text.prefix(60)) is accepted as a link"))
            #expect(WidgetURLRouter.route(for: url) == nil, Comment(rawValue: "\(text.prefix(60)) opens something"))
        }
    }

    @Test func caseAndATrailingSlashDoNotMatter() {
        for text in ["NOCTIS://RECOVERY", "Noctis://Recovery", "noctis://recovery/", "noctis://Wind-Down"] {
            #expect(URL(string: text).flatMap(WidgetLink.init(url:)) != nil, Comment(rawValue: text))
        }
    }

    @Test func theAppRegistersThatOneSchemeAndNothingOpensAURLWithoutTheRouter() throws {
        let plist = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/Info.plist"), encoding: .utf8)
        #expect(plist.components(separatedBy: "<key>CFBundleURLSchemes</key>").count == 2, "one URL type")
        #expect(plist.contains("<string>\(WidgetLink.scheme)</string>"))
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App"]) {
            let code = RawDefaultsTests.code(file.text)
            guard code.contains(".onOpenURL") else { continue }
            #expect(code.contains("WidgetURLRouter"), Comment(rawValue: "\(file.path) opens URLs from outside without the strict router"))
            #expect(!code.contains("AppRoute(url:"), Comment(rawValue: "\(file.path) parses an outside URL leniently"))
        }
    }
}
