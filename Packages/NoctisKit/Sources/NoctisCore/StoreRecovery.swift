import Foundation
import OSLog
import SQLite3
import SwiftData

// What a database that will not open does to the app (APP_RULES.md R65): nothing visible, and nothing lost. The file is set aside whole in a
// folder of its own, a new empty one is made, and the app starts with its empty state. It is never deleted by this code (the person deletes it
// from Data management, or with "Delete all NOCTIS data"), never read by anything else, never backed up, and the only thing logged is which
// store it was and what happened to it, as two enum names.
//
// A store that cannot be read because the iPhone is locked is not a damaged store: the files are protected until it is unlocked. Those are
// left exactly where they are, and the app runs on a store held in memory until it is opened again.

/// Which database.
public nonisolated enum StoreKind: String, Sendable, CaseIterable {
    case app
    case coachHistory
    case journal
    case insights
    case reviews
}

/// What happened when a database was opened.
public nonisolated enum StoreOpenOutcome: String, Sendable, Equatable {
    /// Opened as it was.
    case opened
    /// Could not be read. Set aside, whole, under `Noctis/Quarantine`, and a new empty database was made.
    case setAsideAndStartedFresh
    /// Could not be read and could not be replaced either: this run uses a store that lives in memory only.
    case runningInMemory
    /// Could not be read because the iPhone is locked. Nothing was moved.
    case lockedLeftInPlace
}

public nonisolated struct StoreRecovery: Sendable {
    /// Under Application Support: `Noctis/Quarantine`.
    public static let folderPath = "Noctis/Quarantine"

    public let quarantineRoot: URL
    /// Extra word on whether protected data can be read (a test says no); the file itself is always asked too.
    public let isProtectedDataAvailable: @Sendable () -> Bool
    public let now: @Sendable () -> Date
    /// Told the outcome of every open (the default logs two enum names and nothing else).
    public let report: @Sendable (StoreKind, StoreOpenOutcome) -> Void

    private static let log = Logger(subsystem: "com.noctis.app", category: "store")

    /// The default report: the store and the outcome, as two enum names, and nothing else. Nothing is logged for a store that simply opened.
    public static func logOutcome(_ kind: StoreKind, _ outcome: StoreOpenOutcome) {
        if outcome != .opened { log.error("store \(kind.rawValue, privacy: .public): \(outcome.rawValue, privacy: .public)") }
    }

    public init(
        quarantineRoot: URL = URL.applicationSupportDirectory.appending(path: StoreRecovery.folderPath, directoryHint: .isDirectory),
        isProtectedDataAvailable: @escaping @Sendable () -> Bool = { true },
        now: @escaping @Sendable () -> Date = { Date() },
        report: @escaping @Sendable (StoreKind, StoreOpenOutcome) -> Void = StoreRecovery.logOutcome
    ) {
        self.quarantineRoot = quarantineRoot
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.now = now
        self.report = report
    }

    /// Opens the database at `storeURL` with `make`. If it will not open: left alone when the iPhone is locked; otherwise set aside and made again.
    /// `inMemory` is the last resort and must not fail (an in-memory container of a valid schema cannot).
    public func open(
        _ kind: StoreKind, at storeURL: URL,
        make: (URL) throws -> ModelContainer,
        inMemory: () throws -> ModelContainer
    ) throws -> (container: ModelContainer, outcome: StoreOpenOutcome) {
        // Locked is not damaged: the file is protected until the iPhone is unlocked, and reading it is refused (this is what a launch in the
        // background before the first unlock meets). Whatever says so, the file stays where it is.
        guard isProtectedDataAvailable(), Self.canRead(storeURL) else {
            report(kind, .lockedLeftInPlace)
            return (try inMemory(), .lockedLeftInPlace)
        }
        // A file SQLite itself calls damaged is set aside before anything opens it: opening a damaged file can rewrite it, and a file that is
        // cut short can open and then fail on the page that is missing. (A file that is not there yet is simply made.)
        let intact = !FileManager.default.fileExists(atPath: storeURL.path) || SQLiteCheck.isIntact(storeURL)
        if intact, let opened = try? make(storeURL) {
            report(kind, .opened)
            return (opened, .opened)
        }
        guard setAside(kind, storeURL) else {
            report(kind, .runningInMemory)
            return (try inMemory(), .runningInMemory)
        }
        if let fresh = try? make(storeURL) {
            report(kind, .setAsideAndStartedFresh)
            return (fresh, .setAsideAndStartedFresh)
        }
        report(kind, .runningInMemory)
        return (try inMemory(), .runningInMemory)
    }

    /// Whether the file can be read at all: true when there is none yet. A protected file on a locked iPhone refuses to be opened.
    static func canRead(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 16)) != nil
    }

    /// A file store (the insights, the reviews) found its file unreadable: the file is set aside, whole, and the store starts empty. False when it
    /// could not be moved (it stays where it is, and the next save replaces it).
    @discardableResult
    public func setAsideFile(_ kind: StoreKind, _ url: URL) -> Bool {
        let moved = setAside(kind, url)
        report(kind, moved ? .setAsideAndStartedFresh : .runningInMemory)
        return moved
    }

    /// The set-aside folder that belongs to a store: `Quarantine`, beside the folder the store's own folder sits in (`Noctis/Quarantine`).
    public static func beside(folder storeFolder: URL, up levels: Int = 0) -> StoreRecovery {
        var base = storeFolder
        for _ in 0..<levels { base = base.deletingLastPathComponent() }
        return StoreRecovery(quarantineRoot: base.appending(path: "Quarantine", directoryHint: .isDirectory))
    }

    /// Moves the store's files, and only its files, into a folder of its own. False when nothing could be moved.
    func setAside(_ kind: StoreKind, _ storeURL: URL) -> Bool {
        let manager = FileManager.default
        let folder = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let base = (name as NSString).deletingPathExtension
        // The database, its write-ahead log and shared memory file, and the support folders Core Data keeps beside it.
        let owned: Set<String> = [name, name + "-wal", name + "-shm", "." + base + "_SUPPORT", base + "_ckAssets"]
        let present = ((try? manager.contentsOfDirectory(atPath: folder.path)) ?? []).filter { owned.contains($0) }
        guard !present.isEmpty else { return false }

        let stamp = Self.stamp(now())
        let destination = quarantineRoot.appending(path: "\(kind.rawValue)-\(stamp)-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        do {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        } catch {
            return false
        }
        var moved = 0
        for entry in present {
            do {
                try manager.moveItem(at: folder.appending(path: entry), to: destination.appending(path: entry))
                moved += 1
            } catch {
                // A file that cannot move is left in place and the open will fail again: that is the in-memory outcome, not a loop.
                continue
            }
        }
        Self.exclude(quarantineRoot)
        Self.exclude(destination)
        return moved == present.count
    }

    /// Out of backups, and complete file protection, for the folder (new files inside inherit it).
    private static func exclude(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    private static func stamp(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date)
        return String(format: "%04d%02d%02d-%02d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}

/// SQLite's own opinion of a database file, read without changing it: `PRAGMA quick_check`. The stores are SQLite files (SwiftData's), and this reads
/// only. It says "damaged" only when SQLite itself says the file is not a database, is malformed, or fails its check; a file that is busy, locked or
/// cannot be inspected is "unknown" and is opened as usual (locked is not damaged).
nonisolated enum SQLiteCheck {
    enum Verdict: Equatable { case intact, damaged, unknown }

    static func isIntact(_ url: URL) -> Bool { verdict(url) != .damaged }

    /// A check reads every page, and it runs before the first frame: a file larger than this is not checked (its open and its probes still are). The
    /// stores here are kilobytes to a few megabytes; QA found one at 6 GB, which a check held at launch for minutes.
    static let maximumCheckedBytes = 64 * 1_048_576

    static func verdict(_ url: URL) -> Verdict {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size <= maximumCheckedBytes else { return .unknown }
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close(database) }
        guard opened == SQLITE_OK, let database else { return opened == SQLITE_NOTADB || opened == SQLITE_CORRUPT ? .damaged : .unknown }
        sqlite3_busy_timeout(database, 250)
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, "PRAGMA quick_check(1);", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard prepared == SQLITE_OK, let statement else { return prepared == SQLITE_NOTADB || prepared == SQLITE_CORRUPT ? .damaged : .unknown }
        let stepped = sqlite3_step(statement)
        switch stepped {
        case SQLITE_ROW:
            guard let text = sqlite3_column_text(statement, 0) else { return .unknown }
            return String(cString: text) == "ok" ? .intact : .damaged
        case SQLITE_NOTADB, SQLITE_CORRUPT: return .damaged
        default: return .unknown
        }
    }
}
