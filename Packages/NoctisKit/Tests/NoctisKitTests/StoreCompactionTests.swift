import Foundation
import SQLite3
import Testing

@testable import NoctisCore

// Rows deleted from a database leave free pages until the file is compacted (S1B-B03). The next launch compacts, once, carefully, before anything opens it.

private func makeDatabase(rows: Int = 400, deleting: Bool = true) throws -> URL {
    let url = URL.temporaryDirectory.appending(path: "noctis-compact-\(UUID().uuidString).store", directoryHint: .notDirectory)
    var db: OpaquePointer?
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    sqlite3_exec(db, "CREATE TABLE entry (id INTEGER PRIMARY KEY, body TEXT);", nil, nil, nil)
    sqlite3_exec(db, "BEGIN;", nil, nil, nil)
    for index in 0..<rows { sqlite3_exec(db, "INSERT INTO entry (body) VALUES ('\(String(repeating: "x", count: 900))-\(index)');", nil, nil, nil) }
    sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    if deleting { sqlite3_exec(db, "DELETE FROM entry WHERE id % 10 <> 0;", nil, nil, nil) }
    sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    return url
}

private func rowCount(_ url: URL) -> Int {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM entry;", -1, &statement, nil)
    defer { sqlite3_finalize(statement) }
    return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : -1
}

private func size(_ url: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 }

private func defaults() -> UserDefaults { UserDefaults(suiteName: "noctis.compact.\(UUID().uuidString)") ?? .standard }

struct StoreCompactionTests {
    @Test func compactingGivesTheFreedPagesBackAndKeepsEveryRemainingRow() throws {
        let url = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let before = size(url)
        #expect(rowCount(url) == 40)
        #expect(StoreCompaction(defaults: defaults()).compact(url) == .compacted)
        #expect(size(url) < before / 2, "\(before) -> \(size(url))")
        #expect(rowCount(url) == 40, "what was kept is kept")
    }

    @Test func aMissingFileIsNothingToDo() {
        let url = URL.temporaryDirectory.appending(path: "noctis-none-\(UUID().uuidString).store")
        #expect(StoreCompaction(defaults: defaults()).compact(url) == .missing)
    }

    @Test func aDamagedFileIsLeftExactlyAsItIsForTheRecoveryToSetAside() throws {
        let url = URL.temporaryDirectory.appending(path: "noctis-bad-\(UUID().uuidString).store")
        try Data(repeating: 0x41, count: 8192).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try Data(contentsOf: url)
        #expect(StoreCompaction(defaults: defaults()).compact(url) == .notIntact)
        #expect(try Data(contentsOf: url) == bytes, "not a byte changed")
    }

    @Test func aLargeFileIsLeftAlone() throws {
        let url = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let before = size(url)
        #expect(StoreCompaction(defaults: defaults(), maximumBytes: 1_000).compact(url) == .tooLarge)
        #expect(size(url) == before && rowCount(url) == 40)
        #expect(StoreCompaction.maximumBytes == 16 * 1_048_576)
    }

    @Test func aFileThatCannotBeOpenedForWritingWaitsForTheNextLaunch() throws {
        let url = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let busy = StoreCompaction(defaults: defaults())
        // A connection that holds the write lock, as a running app's would.
        var holder: OpaquePointer?
        #expect(sqlite3_open(url.path, &holder) == SQLITE_OK)
        defer { sqlite3_close(holder) }
        sqlite3_exec(holder, "BEGIN EXCLUSIVE;", nil, nil, nil)
        let outcome = busy.compact(url)
        sqlite3_exec(holder, "ROLLBACK;", nil, nil, nil)
        #expect(outcome == .unavailable || outcome == .failed, "\(outcome)")
        #expect(rowCount(url) == 40)
    }
}

struct StoreCompactionRequestTests {
    @Test func nothingRunsUnlessADeletionAsked() throws {
        let url = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let before = size(url)
        let compaction = StoreCompaction(defaults: defaults())
        #expect(!compaction.isPending && compaction.runIfRequested([url]).isEmpty)
        #expect(size(url) == before, "no request, no work")
    }

    @Test func aRequestRunsOnceAndIsClearedWhenEveryDatabaseWasDealtWith() throws {
        let url = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let compaction = StoreCompaction(defaults: defaults())
        compaction.request()
        let missing = URL.temporaryDirectory.appending(path: "noctis-none-\(UUID().uuidString).store")
        let outcomes = compaction.runIfRequested([url, missing])
        #expect(outcomes.map(\.1) == [.compacted, .missing])
        #expect(!compaction.isPending, "once per request")
        #expect(compaction.runIfRequested([url]).isEmpty)
    }

    @Test func aRequestThatCouldNotRunWaitsForTheNextLaunch() throws {
        let url = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        let defaults = defaults()
        StoreCompaction(defaults: defaults).request()
        // A connection that holds the write lock, as a running app's would.
        var holder: OpaquePointer?
        #expect(sqlite3_open(url.path, &holder) == SQLITE_OK)
        sqlite3_exec(holder, "BEGIN EXCLUSIVE;", nil, nil, nil)
        let blocked = StoreCompaction(defaults: defaults).runIfRequested([url]).map(\.1)
        sqlite3_exec(holder, "ROLLBACK;", nil, nil, nil)
        sqlite3_close(holder)
        #expect(blocked == [.unavailable] || blocked == [.failed], "\(blocked)")
        #expect(StoreCompaction(defaults: defaults).isPending, "still asked for")
        #expect(StoreCompaction(defaults: defaults).runIfRequested([url]).map(\.1) == [.compacted])
        #expect(!StoreCompaction(defaults: defaults).isPending)
    }

    @Test func theCompactionNeverAsksTheSystemHowMuchSpaceIsFree() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisCore/StoreCompaction.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(text)
        for word in ["volumeAvailableCapacity", "systemFreeSize", "NSFileSystemFreeSize", "statfs"] { #expect(!code.contains(word), Comment(rawValue: word)) }
    }

    @MainActor
    @Test func deletingOneKindOfDataAsksForTheNextLaunchToCompact() async throws {
        let defaults = defaults()
        let manager = DataManager(erasers: [.journal: {}], providers: [:], deleteAllSteps: [], defaults: defaults)
        let group = try #require(DataInventory.shared.groups.first { $0.id == "journal" })
        let report = await manager.delete(group)
        #expect(report.succeeded && StoreCompaction(defaults: defaults).isPending)
    }

    @MainActor
    @Test func aDeletionOfAFileStoreAsksForNothing() async throws {
        let defaults = defaults()
        let manager = DataManager(erasers: [.insightHistory: {}], providers: [:], deleteAllSteps: [], defaults: defaults)
        let group = try #require(DataInventory.shared.groups.first { $0.id == "insights" })
        _ = await manager.delete(group)
        #expect(!StoreCompaction(defaults: defaults).isPending, "the insights are a file, not a database")
    }

    @MainActor
    @Test func theDatabasesAreTheInventorysAndTheLaunchCompactsBeforeAnythingOpens() throws {
        let files = DataManager.databaseFiles()
        let names = files.map(\.lastPathComponent)
        #expect(names.contains("default.store") && names.contains("journal.store") && names.contains("coach-history.store"), "\(names)")
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"), encoding: .utf8)
        let compact = try #require(text.range(of: "if compaction.isPending { compaction.runIfRequested("))
        let open = try #require(text.range(of: "NoctisStore.open()"))
        #expect(compact.lowerBound < open.lowerBound)
    }
}
