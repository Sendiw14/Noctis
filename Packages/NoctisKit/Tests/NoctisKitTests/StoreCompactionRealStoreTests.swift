import Foundation
import SQLite3
import SwiftData
import Testing

@testable import CoachKit
@testable import JournalKit
@testable import NoctisCore

// Compaction against the stores NOCTIS really writes (S1B-R-05, R-04): insert, delete, compact, reopen through the real container, read every kept row, and check
// that nothing about the file's protection or backup exclusion changed. The temporary-file evidence for `temp_store = MEMORY` is measured here too.

private nonisolated func folder() throws -> URL {
    let url = URL.temporaryDirectory.appending(path: "noctis-realcompact-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private nonisolated func size(_ url: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 }

/// What the file and its folder say about protection and backup.
private nonisolated struct FileFacts: Equatable {
    var protection: String
    var folderProtection: String
    var excluded: Bool
    var folderExcluded: Bool

    init(_ file: URL) {
        func protection(_ url: URL) -> String {
            ((try? FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey]) as? FileProtectionType)?.rawValue ?? "none"
        }
        func excluded(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false }
        self.protection = protection(file)
        self.folderProtection = protection(file.deletingLastPathComponent())
        self.excluded = excluded(file)
        self.folderExcluded = excluded(file.deletingLastPathComponent())
    }
}

private nonisolated final class Outcomes: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [StoreOpenOutcome] = []
    func add(_ value: StoreOpenOutcome) { lock.withLock { values.append(value) } }
    var all: [StoreOpenOutcome] { lock.withLock { values } }
}

private nonisolated func recovery(_ folder: URL, _ outcomes: Outcomes) -> StoreRecovery {
    StoreRecovery(quarantineRoot: folder.appending(path: "Quarantine"), report: { _, outcome in outcomes.add(outcome) })
}

private nonisolated func millis(_ work: () -> Void) -> Double {
    let start = ContinuousClock.now
    work()
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
}

struct StoreCompactionRealStoreTests {
    @Test func theJournalIsCompactedAndEveryKeptEntryIsStillThere() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "journal.store")
        let outcomes = Outcomes()
        var kept: [String] = []
        do {
            let container = try JournalContainer.make(directory: dir, recovery: recovery(dir, outcomes))
            let context = ModelContext(container)
            for index in 0..<3000 {
                let entry = JournalEntry()
                entry.text = "\(index) " + String(repeating: "note ", count: 400)
                entry.mood = index % 5 + 1
                context.insert(entry)
            }
            try context.save()
            for entry in try context.fetch(FetchDescriptor<JournalEntry>()) {
                if (Int(entry.text.prefix(while: { $0 != " " })) ?? 1) % 10 == 0 {
                    kept.append(entry.text)
                } else {
                    context.delete(entry)
                }
            }
            try context.save()
        }
        let before = FileFacts(url)
        let bytesBefore = size(url) + size(dir.appending(path: "journal.store-wal"))
        var outcome = StoreCompaction.Outcome.failed
        let took = millis { outcome = StoreCompaction(defaults: UserDefaults(suiteName: "noctis.rc.\(UUID().uuidString)") ?? .standard).compact(url) }
        #expect(outcome == .compacted)
        print("COMPACTION-TIMING journal \(bytesBefore / 1024) KB -> \(size(url) / 1024) KB in \(Int(took)) ms")
        #expect(size(url) < bytesBefore / 2, "\(bytesBefore) -> \(size(url))")

        let reopened = try JournalContainer.make(directory: dir, recovery: recovery(dir, outcomes))
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<JournalEntry>())
        #expect(rows.count == kept.count && Set(rows.map(\.text)) == Set(kept), "every kept entry, and only those")
        #expect(outcomes.all.allSatisfy { $0 == .opened }, "no damaged store was set aside: \(outcomes.all)")
        #expect(FileFacts(url) == before, "protection and backup exclusion are as they were: \(before) -> \(FileFacts(url))")
    }

    @Test func coachConversationsAreCompactedAndReadBack() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "coach-history.store")
        let outcomes = Outcomes()
        var keptIDs: Set<UUID> = []
        do {
            let container = try CoachHistoryContainer.make(directory: dir, recovery: recovery(dir, outcomes))
            let context = ModelContext(container)
            for _ in 0..<30000 { context.insert(AIConversation()) }
            try context.save()
            for (index, conversation) in try context.fetch(FetchDescriptor<AIConversation>()).enumerated() {
                if index % 10 == 0 { keptIDs.insert(conversation.id) } else { context.delete(conversation) }
            }
            try context.save()
        }
        let before = FileFacts(url)
        let bytesBefore = size(url) + size(dir.appending(path: "coach-history.store-wal"))
        var outcome = StoreCompaction.Outcome.failed
        let took = millis { outcome = StoreCompaction(defaults: UserDefaults(suiteName: "noctis.rc.\(UUID().uuidString)") ?? .standard).compact(url) }
        #expect(outcome == .compacted)
        print("COMPACTION-TIMING coach \(bytesBefore / 1024) KB -> \(size(url) / 1024) KB in \(Int(took)) ms")
        #expect(size(url) < bytesBefore)

        let reopened = try CoachHistoryContainer.make(directory: dir, recovery: recovery(dir, outcomes))
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<AIConversation>())
        #expect(Set(rows.map(\.id)) == keptIDs)
        #expect(outcomes.all.allSatisfy { $0 == .opened }, "\(outcomes.all)")
        #expect(FileFacts(url) == before, "\(before) -> \(FileFacts(url))")
    }

    @Test func theAppDatabaseIsCompactedAndReadBack() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "default.store")
        var keptCount = 0
        do {
            let container = try NoctisStore.container(at: url)
            let context = ModelContext(container)
            let profile = UserProfileRecord()
            profile.name = "Kept"
            context.insert(profile)
            for index in 0..<40000 {
                let session = WindDownSession()
                session.plannedMinutes = index
                context.insert(session)
            }
            try context.save()
            for session in try context.fetch(FetchDescriptor<WindDownSession>()) {
                if session.plannedMinutes % 10 == 0 { keptCount += 1 } else { context.delete(session) }
            }
            try context.save()
        }
        let before = FileFacts(url)
        let bytesBefore = size(url) + size(dir.appending(path: "default.store-wal"))
        var outcome = StoreCompaction.Outcome.failed
        let took = millis { outcome = StoreCompaction(defaults: UserDefaults(suiteName: "noctis.rc.\(UUID().uuidString)") ?? .standard).compact(url) }
        #expect(outcome == .compacted)
        print("COMPACTION-TIMING app \(bytesBefore / 1024) KB -> \(size(url) / 1024) KB in \(Int(took)) ms")

        let reopened = try NoctisStore.container(at: url)
        let context = ModelContext(reopened)
        #expect(try context.fetchCount(FetchDescriptor<WindDownSession>()) == keptCount)
        #expect(try context.fetch(FetchDescriptor<UserProfileRecord>()).first?.name == "Kept", "the profile is untouched")
        #expect(FileFacts(url) == before)
        // And it still saves.
        context.insert(WindDownSession())
        try context.save()
    }

    @MainActor
    @Test func notBeingAskedCostsNothingAtLaunch() {
        let defaults = UserDefaults(suiteName: "noctis.rc.\(UUID().uuidString)") ?? .standard
        var found: [URL] = []
        let took = millis { found = DataManager.databaseFiles() }
        let idle = millis { StoreCompaction(defaults: defaults).runIfRequested(found) }
        print("COMPACTION-TIMING launch-with-no-request: list \(Int(took * 1000)) us, check \(Int(idle * 1000)) us")
        #expect(idle < 50, "a launch with no request does one flag read: \(idle) ms")
    }

    /// The measured evidence for R-04: by default SQLite writes the copy `VACUUM` makes into a temporary file in the app's temporary folder; with
    /// `temp_store = MEMORY`, which is what `compact` sets, it writes nothing there.
    @Test func compactionWritesNoTemporaryFileWhereTheDefaultDoes() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        func big(_ name: String) throws -> URL {
            let url = dir.appending(path: name)
            let container = try ModelContainer(
                for: JournalEntry.self, configurations: ModelConfiguration(name, url: url, allowsSave: true, cloudKitDatabase: .none))
            let context = ModelContext(container)
            for index in 0..<30000 {
                let entry = JournalEntry()
                entry.text = "\(index) " + String(repeating: "word ", count: 160)
                context.insert(entry)
            }
            try context.save()
            return url
        }
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        func sawTemporaryFile(during work: () -> Void) -> Bool {
            let seen = Seen()
            let stop = Seen()
            let poller = Thread {
                while !stop.flag {
                    if let names = try? FileManager.default.contentsOfDirectory(atPath: temporary.path), names.contains(where: { $0.hasPrefix("etilqs_") }) { seen.flag = true }
                }
            }
            poller.start()
            work()
            stop.flag = true
            return seen.flag
        }
        // Positive control: SQLite's default really does put a file there. The polling can miss it on a busy machine, so the control is tried a few times; if it
        // is never seen the result for `compact` is inconclusive and is not asserted (the source check below holds the pragma in place either way).
        var defaultSaw = false
        for attempt in 0..<5 where !defaultSaw {
            let control = try big("control\(attempt).store")
            defaultSaw = sawTemporaryFile(during: { Self.vacuum(control, memory: false) })
        }
        let ours = try big("ours.store")
        let oursSaw = sawTemporaryFile(during: {
            _ = StoreCompaction(defaults: UserDefaults(suiteName: "noctis.rc.\(UUID().uuidString)") ?? .standard, maximumBytes: 512 * 1_048_576).compact(ours)
        })
        print("COMPACTION-TIMING temp-file evidence: default saw=\(defaultSaw) ours saw=\(oursSaw)")
        if defaultSaw { #expect(!oursSaw, "compact must not write the copy outside the store") }
        let source = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisCore/StoreCompaction.swift"), encoding: .utf8)
        let pragma = try #require(source.range(of: "PRAGMA temp_store = MEMORY;"))
        let vacuum = try #require(source.range(of: "VACUUM;"))
        #expect(pragma.lowerBound < vacuum.lowerBound, "the copy is kept in memory before the VACUUM runs")
    }

    private nonisolated final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var flag: Bool {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    private static func vacuum(_ url: URL, memory: Bool) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(database) }
        if memory { sqlite3_exec(database, "PRAGMA temp_store = MEMORY;", nil, nil, nil) }
        sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        sqlite3_exec(database, "VACUUM;", nil, nil, nil)
    }
}
