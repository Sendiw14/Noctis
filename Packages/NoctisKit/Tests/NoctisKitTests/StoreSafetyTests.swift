import AVFoundation
import Foundation
import SQLite3
import SwiftData
import Testing

@testable import CoachKit
@testable import InsightsKit
@testable import JournalKit
@testable import NoctisCore
@testable import ReviewKit
@testable import SoundKit

// QA part 2 (QA_LEDGER.md, APP_RULES.md R65): every database has a named version and a way forward, and a file that cannot be read is set aside,
// never deleted, and never stops the app. Real files, in a folder per test.

/// Moves everything the write-ahead log holds into the database file itself (a store that has been closed cleanly is like this), so damage done to the
/// file is damage to the rows and not only to an empty skeleton.
private func checkpoint(_ url: URL) {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
    sqlite3_busy_timeout(database, 2000)
    sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    sqlite3_close(database)
}

private func temporaryFolder() throws -> URL {
    let url = URL.temporaryDirectory.appending(path: "noctis-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Versions

struct SchemaVersionTests {
    private func names(_ models: [any PersistentModel.Type]) -> Set<String> { Set(models.map { String(describing: $0) }) }

    @Test func theAppDatabaseIsVersion1AndNamesEveryModelItHolds() {
        #expect(NoctisSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(names(NoctisSchemaV1.models) == ["UserProfileRecord", "AlarmConfiguration", "WindDownSession"])
        #expect(NoctisMigrationPlan.schemas.count == 1 && NoctisMigrationPlan.stages.isEmpty)
    }

    @Test func coachAndTheJournalAreVersion1WithTheirOwnPlans() {
        #expect(CoachHistorySchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(names(CoachHistorySchemaV1.models) == ["AIConversation", "AIMessage"])
        #expect(JournalSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(names(JournalSchemaV1.models) == ["JournalEntry"])
        #expect(CoachHistoryMigrationPlan.schemas.count == 1 && JournalMigrationPlan.schemas.count == 1)
    }

    @Test func everyPlanHasAStageBetweenEachPairOfVersionsAndNoVersionTwice() {
        let plans: [(schemas: [any VersionedSchema.Type], stages: Int)] = [
            (NoctisMigrationPlan.schemas, NoctisMigrationPlan.stages.count),
            (CoachHistoryMigrationPlan.schemas, CoachHistoryMigrationPlan.stages.count),
            (JournalMigrationPlan.schemas, JournalMigrationPlan.stages.count),
        ]
        for plan in plans {
            #expect(plan.stages == plan.schemas.count - 1, "a new version needs a stage from the one before it")
            let versions = plan.schemas.map { "\($0.versionIdentifier)" }
            #expect(Set(versions).count == versions.count)
        }
    }

    /// R65: a `@Model` that is in no version is a table no migration knows about.
    @Test func everyModelClassInTheSourcesIsInAVersionedSchema() {
        var declared: Set<String> = []
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources"]) {
            let code = SwiftCodeScanner.codeOnly(file.text)
            let range = NSRange(code.startIndex..., in: code)
            let regex = try? NSRegularExpression(pattern: #"@Model\s+(?:public\s+|internal\s+)?(?:final\s+)?class\s+([A-Za-z_]\w*)"#)
            for match in regex?.matches(in: code, range: range) ?? [] {
                if let name = Range(match.range(at: 1), in: code) { declared.insert(String(code[name])) }
            }
        }
        let versioned = names(NoctisSchemaV1.models).union(names(CoachHistorySchemaV1.models)).union(names(JournalSchemaV1.models))
        #expect(declared == versioned, Comment(rawValue: "declared \(declared.sorted()), versioned \(versioned.sorted())"))
    }
}

// MARK: - Migration

/// A pretend version 2 of the app's database: `WindDownSession` gains an optional note. The other two entities are the shipped classes.
private enum DummyV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [UserProfileRecord.self, AlarmConfiguration.self, WindDownSession.self] }

    @Model
    final class WindDownSession {
        var id: UUID = UUID()
        var start: Date = Date.now
        var plannedMinutes: Int = 20
        var completed: Bool = false
        var note: String?

        init() {}
    }
}

private enum LightweightPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NoctisSchemaV1.self, DummyV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: NoctisSchemaV1.self, toVersion: DummyV2.self)] }
}

private enum CustomPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NoctisSchemaV1.self, DummyV2.self] }
    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: NoctisSchemaV1.self, toVersion: DummyV2.self, willMigrate: nil,
                didMigrate: { context in
                    for session in try context.fetch(FetchDescriptor<DummyV2.WindDownSession>()) { session.note = "migrated" }
                    try context.save()
                })
        ]
    }
}

struct SchemaMigrationTests {
    /// The database as the app wrote it before there were versions: the live classes, no plan.
    private func writeUnversionedStore(at url: URL) throws {
        let container = try ModelContainer(
            for: UserProfileRecord.self, AlarmConfiguration.self, WindDownSession.self,
            configurations: ModelConfiguration("default", url: url, allowsSave: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let profile = UserProfileRecord()
        profile.name = "Saved before versions"
        profile.typicalWakeMinutes = 6 * 60 + 45
        profile.onboardingComplete = true
        context.insert(profile)
        for minutes in [10, 20, 30] {
            let session = WindDownSession()
            session.plannedMinutes = minutes
            session.completed = minutes != 30
            context.insert(session)
        }
        try context.save()
    }

    @Test func aStoreWrittenBeforeVersionsOpensThroughThePlanWithEveryRow() throws {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "default.store")
        try writeUnversionedStore(at: url)

        let opened = try NoctisStore.container(at: url)
        let context = ModelContext(opened)
        let profiles = try context.fetch(FetchDescriptor<UserProfileRecord>())
        #expect(profiles.count == 1 && profiles.first?.name == "Saved before versions" && profiles.first?.typicalWakeMinutes == 6 * 60 + 45)
        let sessions = try context.fetch(FetchDescriptor<WindDownSession>(sortBy: [SortDescriptor(\.plannedMinutes)]))
        #expect(sessions.map(\.plannedMinutes) == [10, 20, 30] && sessions.map(\.completed) == [true, true, false])
    }

    @Test func aVersion2ThatAddsAnOptionalPropertyMigratesTheStoreAndKeepsEveryRow() throws {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "default.store")
        try writeUnversionedStore(at: url)

        let schema = Schema(versionedSchema: DummyV2.self)
        let migrated = try ModelContainer(
            for: schema, migrationPlan: LightweightPlan.self,
            configurations: ModelConfiguration("default", schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(migrated)
        let sessions = try context.fetch(FetchDescriptor<DummyV2.WindDownSession>(sortBy: [SortDescriptor(\.plannedMinutes)]))
        #expect(sessions.map(\.plannedMinutes) == [10, 20, 30], "every row came through")
        #expect(sessions.allSatisfy { $0.note == nil }, "the new property is empty on old rows")
        #expect(try context.fetch(FetchDescriptor<UserProfileRecord>()).first?.name == "Saved before versions", "an entity that did not change is untouched")

        sessions.first?.note = "new in v2"
        try context.save()
        #expect(try context.fetch(FetchDescriptor<DummyV2.WindDownSession>(sortBy: [SortDescriptor(\.plannedMinutes)])).first?.note == "new in v2")
    }

    @Test func aCustomStageRunsOnTheOldRows() throws {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "default.store")
        try writeUnversionedStore(at: url)

        let schema = Schema(versionedSchema: DummyV2.self)
        let migrated = try ModelContainer(
            for: schema, migrationPlan: CustomPlan.self,
            configurations: ModelConfiguration("default", schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        )
        let sessions = try ModelContext(migrated).fetch(FetchDescriptor<DummyV2.WindDownSession>())
        #expect(sessions.count == 3 && sessions.allSatisfy { $0.note == "migrated" })
    }

    @Test func anEmptyFolderMakesTheDatabaseFromScratchAsVersion1() throws {
        let folder = try temporaryFolder()
        let opened = try NoctisStore.container(at: folder.appending(path: "Nested/default.store"))
        #expect(try ModelContext(opened).fetchCount(FetchDescriptor<UserProfileRecord>()) == 0)
    }
}

// MARK: - Damage

/// What was done to the file: the ways a database file is found unreadable.
enum FileDamage: CaseIterable, CustomStringConvertible {
    case garbage, truncatedToHalf, truncatedToTheFirstPage, headerOverwritten

    var description: String {
        switch self {
        case .garbage: "garbage"
        case .truncatedToHalf: "truncated to half"
        case .truncatedToTheFirstPage: "truncated to its first page"
        case .headerOverwritten: "header overwritten"
        }
    }

    func apply(to url: URL) throws {
        let original = try Data(contentsOf: url)
        switch self {
        case .garbage:
            try Data((0..<max(original.count, 4096)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: url)
        case .truncatedToHalf:
            try original.prefix(original.count / 2).write(to: url)
        case .truncatedToTheFirstPage:
            try original.prefix(4096).write(to: url)
        case .headerOverwritten:
            var damaged = original
            for index in 0..<min(100, damaged.count) { damaged[index] = 0x58 }
            try damaged.write(to: url)
        }
    }
}

struct StoreDamageTests {
    /// The check must leave the file as it found it: a store the app crashed in has rows only in its write-ahead log, and a read-write check would move them
    /// into the file (and delete the log) before a damaged store is set aside whole.
    @Test func theDamageCheckChangesNothingOnDisk() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let live = folder.appending(path: "live.store")
        var database: OpaquePointer?
        #expect(sqlite3_open_v2(live.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
        sqlite3_exec(
            database, "CREATE TABLE t(x INTEGER); PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; INSERT INTO t VALUES (1),(2),(3);", nil, nil, nil)
        // What a crash leaves: the file and its log, copied while the writer is still open.
        let crashed = folder.appending(path: "crashed.store")
        let crashedLog = folder.appending(path: "crashed.store-wal")
        try FileManager.default.copyItem(at: live, to: crashed)
        try FileManager.default.copyItem(at: folder.appending(path: "live.store-wal"), to: crashedLog)
        sqlite3_close(database)
        let fileBefore = try Data(contentsOf: crashed)
        let logBefore = try Data(contentsOf: crashedLog)
        #expect(!logBefore.isEmpty, "the rows are only in the log")

        #expect(SQLiteCheck.verdict(crashed) == .intact)

        #expect(try Data(contentsOf: crashed) == fileBefore, "the database file was not written to")
        #expect(try Data(contentsOf: crashedLog) == logBefore, "the log is still there, as it was")
    }

    private nonisolated final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ kind: StoreKind, _ outcome: StoreOpenOutcome) { lock.withLock { items.append("\(kind.rawValue):\(outcome.rawValue)") } }
        var all: [String] { lock.withLock { items } }
    }

    private func recovery(in folder: URL, reports: Reports, locked: Bool = false) -> StoreRecovery {
        StoreRecovery(
            quarantineRoot: folder.appending(path: "Quarantine", directoryHint: .isDirectory), isProtectedDataAvailable: { !locked },
            report: { reports.add($0, $1) }
        )
    }

    private func listing(_ url: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }

    /// A store with a few rows, written, closed, and on disk at `url`.
    private func writeApp(at url: URL) throws {
        let container = try NoctisStore.container(at: url)
        let context = ModelContext(container)
        let profile = UserProfileRecord()
        profile.name = "Kept"
        context.insert(profile)
        for minutes in 1...40 {
            let session = WindDownSession()
            session.plannedMinutes = minutes
            context.insert(session)
        }
        try context.save()
        checkpoint(url)
    }

    private func writeJournal(in folder: URL) throws -> URL {
        let container = try JournalContainer.make(directory: folder, recovery: StoreRecovery(quarantineRoot: folder.appending(path: "Q")))
        let context = ModelContext(container)
        for index in 0..<40 {
            let entry = JournalEntry()
            entry.text = "A line of the journal, number \(index), long enough to take real pages in the file. " + String(repeating: "x", count: 80)
            context.insert(entry)
        }
        try context.save()
        checkpoint(folder.appending(path: "journal.store"))
        return folder.appending(path: "journal.store")
    }

    private func writeCoach(in folder: URL) async throws -> URL {
        let container = try CoachHistoryContainer.make(directory: folder, recovery: StoreRecovery(quarantineRoot: folder.appending(path: "Q")))
        let context = ModelContext(container)
        for _ in 0..<40 {
            let conversation = AIConversation()
            context.insert(conversation)
        }
        try context.save()
        checkpoint(folder.appending(path: "coach-history.store"))
        return folder.appending(path: "coach-history.store")
    }

    // MARK: The app database

    @Test(arguments: FileDamage.allCases) func aDamagedAppDatabaseIsSetAsideWholeAndTheAppStartsEmpty(_ damage: FileDamage) throws {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "default.store")
        try writeApp(at: url)
        try damage.apply(to: url)
        let damaged = try Data(contentsOf: url)
        let reports = Reports()

        let (container, outcome) = NoctisStore.open(at: url, recovery: recovery(in: folder, reports: reports))
        #expect(outcome == .setAsideAndStartedFresh, Comment(rawValue: "\(damage): \(outcome)"))
        // The app runs on an empty database it can write to.
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<UserProfileRecord>()) == 0)
        context.insert(UserProfileRecord())
        try context.save()
        // The damaged file is in the folder of its own, byte for byte, and not at its old place.
        let sets = listing(folder.appending(path: "Quarantine"))
        #expect(sets.count == 1 && sets.first?.hasPrefix("app-") == true, Comment(rawValue: "\(damage): \(sets)"))
        let set = try #require(sets.first)
        let kept = folder.appending(path: "Quarantine/\(set)/default.store")
        #expect(try Data(contentsOf: kept) == damaged, "never altered, never deleted")
        #expect(reports.all == ["app:setAsideAndStartedFresh"], "one enum-only event")
    }

    @Test func afterwardsItOpensAsItselfAndDoesNotSetAnythingAsideAgain() throws {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "default.store")
        try writeApp(at: url)
        try FileDamage.garbage.apply(to: url)
        let reports = Reports()
        _ = NoctisStore.open(at: url, recovery: recovery(in: folder, reports: reports))
        let again = NoctisStore.open(at: url, recovery: recovery(in: folder, reports: reports))
        #expect(again.outcome == .opened)
        #expect(listing(folder.appending(path: "Quarantine")).count == 1, "no loop: one set, once")
    }

    @Test func aLockedPhoneLeavesTheDatabaseWhereItIsAndRunsInMemory() throws {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "default.store")
        try writeApp(at: url)
        try FileDamage.garbage.apply(to: url)
        let damaged = try Data(contentsOf: url)
        let reports = Reports()

        let (container, outcome) = NoctisStore.open(at: url, recovery: recovery(in: folder, reports: reports, locked: true))
        #expect(outcome == .lockedLeftInPlace)
        #expect(try Data(contentsOf: url) == damaged, "locked is not damaged: nothing moved")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "Quarantine").path))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<UserProfileRecord>()) == 0)
        #expect(reports.all == ["app:lockedLeftInPlace"])
    }

    @Test func aHealthyDatabaseIsOpenedAndTouchesNothing() throws {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "default.store")
        try writeApp(at: url)
        let reports = Reports()
        let (container, outcome) = NoctisStore.open(at: url, recovery: recovery(in: folder, reports: reports))
        #expect(outcome == .opened)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<WindDownSession>()) == 40)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "Quarantine").path))
    }

    // MARK: The journal and Coach's history

    @Test(arguments: FileDamage.allCases) func aDamagedJournalIsSetAsideNeverDeletedAndTheJournalStartsEmpty(_ damage: FileDamage) async throws {
        let root = try temporaryFolder()
        let folder = root.appending(path: "Journal", directoryHint: .isDirectory)
        let url = try writeJournal(in: folder)
        try damage.apply(to: url)
        let damaged = try Data(contentsOf: url)
        let reports = Reports()

        let container = try JournalContainer.make(directory: folder, recovery: recovery(in: root, reports: reports))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<JournalEntry>()) == 0, Comment(rawValue: "\(damage)"))
        let sets = listing(root.appending(path: "Quarantine"))
        #expect(sets.count == 1 && sets.first?.hasPrefix("journal-") == true, Comment(rawValue: "\(damage): \(sets)"))
        let set = try #require(sets.first)
        #expect(try Data(contentsOf: root.appending(path: "Quarantine/\(set)/journal.store")) == damaged)
        #expect(reports.all == ["journal:setAsideAndStartedFresh"])
    }

    @Test(arguments: FileDamage.allCases) func aDamagedCoachHistoryIsSetAsideNeverDeletedAndCoachStartsEmpty(_ damage: FileDamage) async throws {
        let root = try temporaryFolder()
        let folder = root.appending(path: "CoachHistory", directoryHint: .isDirectory)
        let url = try await writeCoach(in: folder)
        try damage.apply(to: url)
        let damaged = try Data(contentsOf: url)
        let reports = Reports()

        let container = try CoachHistoryContainer.make(directory: folder, recovery: recovery(in: root, reports: reports))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<AIConversation>()) == 0, Comment(rawValue: "\(damage)"))
        let sets = listing(root.appending(path: "Quarantine"))
        #expect(sets.count == 1 && sets.first?.hasPrefix("coachHistory-") == true, Comment(rawValue: "\(damage): \(sets)"))
        let set = try #require(sets.first)
        #expect(try Data(contentsOf: root.appending(path: "Quarantine/\(set)/coach-history.store")) == damaged)
        #expect(reports.all == ["coachHistory:setAsideAndStartedFresh"])
    }

    @Test func aLockedPhoneThrowsFromTheJournalSoItIsAskedAgainAndMovesNothing() throws {
        let root = try temporaryFolder()
        let folder = root.appending(path: "Journal", directoryHint: .isDirectory)
        let url = try writeJournal(in: folder)
        try FileDamage.garbage.apply(to: url)
        let damaged = try Data(contentsOf: url)
        #expect(throws: JournalStoreLocked.self) {
            _ = try JournalContainer.make(directory: folder, recovery: recovery(in: root, reports: Reports(), locked: true))
        }
        #expect(try Data(contentsOf: url) == damaged)
    }

    // MARK: Set-aside files

    @Test func theSetAsideFolderIsOutOfBackupsAndInTheInventoryAndDeletedWithEverything() throws {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "default.store")
        try writeApp(at: url)
        try FileDamage.garbage.apply(to: url)
        _ = NoctisStore.open(at: url, recovery: recovery(in: folder, reports: Reports()))
        let quarantine = folder.appending(path: "Quarantine", directoryHint: .isDirectory)
        let values = try quarantine.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)

        let category = DataInventory.shared[.setAsideFiles]
        #expect(category.locations == [.folder(.applicationSupport, "Noctis/Quarantine")])
        #expect(category.holdsUserContent && !category.inBackup)
        #expect(StoreRecovery.folderPath == "Noctis/Quarantine")
    }

    @Test(arguments: [StoreKind.insights, StoreKind.reviews]) func anUnreadableFileStoreIsSetAsideAndStartsEmpty(_ kind: StoreKind) throws {
        let folder = try temporaryFolder()
        let damagedBytes = Data("{ this is not json".utf8)
        switch kind {
        case .insights:
            let store = InsightFileStore(directory: folder)
            try damagedBytes.write(to: store.fileURL)
            #expect(store.load() == nil)
            store.save(InsightLibrary())
            #expect(store.load() != nil, "a new file is written in its place")
        case .reviews:
            let store = ReviewFileStore(directory: folder)
            try damagedBytes.write(to: store.fileURL)
            #expect(store.load() == nil)
            store.save(ReviewLibrary())
            #expect(store.load() != nil)
        default:
            Issue.record("not a file store")
        }
        let sets = listing(folder.appending(path: "Quarantine"))
        #expect(sets.count == 1 && sets.first?.hasPrefix(kind.rawValue + "-") == true, Comment(rawValue: "\(sets)"))
        let set = try #require(sets.first)
        let file = kind == .insights ? "insights.json" : "reviews.json"
        #expect(try Data(contentsOf: folder.appending(path: "Quarantine/\(set)/\(file)")) == damagedBytes)
    }
}

// MARK: - The audio engine goes away

@MainActor
struct AudioEngineTeardownTests {
    /// The real AVAudioEngine: after `stop()` the engine is released, its meter tap is removed, and it is made again on the next start.
    @Test func stoppingReleasesTheEngineAndRemovesItsTap() throws {
        let driver = AVSoundEngineDriver()
        driver.setMeter { _ in }
        do {
            try driver.start()
        } catch {
            // No audio device in this environment (a bare CI agent): nothing to tear down. The fake-engine tests cover the sequence.
            return
        }
        weak let engine = driver.engineForTesting
        #expect(engine != nil && engine?.isRunning == true && driver.meterIsInstalled)
        driver.stop()
        #expect(driver.engineForTesting == nil && !driver.meterIsInstalled)
        #expect(engine == nil, "nothing else holds the engine")

        // And it can start again, and stop again.
        try driver.start()
        #expect(driver.engineForTesting?.isRunning == true)
        driver.stop()
        #expect(driver.engineForTesting == nil)
    }

    @Test func pausingKeepsTheEngineButNotTheTap() throws {
        let driver = AVSoundEngineDriver()
        driver.setMeter { _ in }
        do { try driver.start() } catch { return }
        driver.pause()
        #expect(!driver.meterIsInstalled, "nothing is sampled while paused (R31)")
        #expect(driver.engineForTesting?.isRunning == false)
        driver.stop()
        #expect(driver.engineForTesting == nil)
    }
}
