import Foundation
import SQLite3

// Deleting rows from a SQLite database leaves their pages in the file's free list until the file is compacted (X-15, S1B-B03). After a deletion of one kind of data
// (the Journal, Coach conversations, the wind-down history) the next launch compacts the databases, before anything opens them: a checkpoint of the write-ahead log,
// then `VACUUM`. That frees the space. It is not a promise that anything is unrecoverable: iOS encrypts the file at rest, and this says nothing about the flash
// underneath. "Delete all NOCTIS data" removes the files themselves and never needs it.
//
// It is careful and it is rare: it runs only when a deletion asked for it, only on a database SQLite itself calls intact, only with room for the copy `VACUUM`
// makes, never while the iPhone is locked (the file cannot be opened then, and the request waits), and once per request.

public nonisolated struct StoreCompaction {
    /// Set by a deletion of one kind of data, cleared when every database has been dealt with.
    public static let pendingKey = "noctis.compact.pending"

    public enum Outcome: String, Sendable, Equatable {
        /// Compacted.
        case compacted
        /// There is no such file (nothing to do).
        case missing
        /// Not touched: larger than `maximumBytes`.
        case tooLarge
        /// SQLite calls it damaged: left for `StoreRecovery`, which sets it aside at the next open.
        case notIntact
        /// Could not be opened for writing (the iPhone is locked, or another connection holds it): tried at the next launch.
        case unavailable
        /// SQLite refused the work: left as it was, tried at the next launch.
        case failed
    }

    /// The largest database it compacts. The stores here are kilobytes to a few megabytes; a larger one is left alone. The compaction keeps the copy in memory
    /// (see `compact`), so this also bounds the memory it uses.
    public static let maximumBytes = 16 * 1_048_576

    private let defaults: UserDefaults
    private let maximumBytes: Int

    public init(defaults: UserDefaults = NoctisUserDefaults.standard, maximumBytes: Int = StoreCompaction.maximumBytes) {
        self.defaults = defaults
        self.maximumBytes = maximumBytes
    }

    public var isPending: Bool { defaults.bool(forKey: Self.pendingKey) }

    /// A deletion of one kind of data asks for the next launch to compact.
    public func request() { defaults.set(true, forKey: Self.pendingKey) }

    /// At launch, before any database opens: compacts `databases` if a deletion asked for it. The request is cleared once no database is waiting on room or on the
    /// iPhone being unlocked. Returns what happened to each.
    @discardableResult
    public func runIfRequested(_ databases: [URL]) -> [(URL, Outcome)] {
        guard isPending else { return [] }
        let outcomes = databases.map { ($0, compact($0)) }
        let waiting: Set<Outcome> = [.unavailable, .failed]
        if !outcomes.contains(where: { waiting.contains($0.1) }) { defaults.removeObject(forKey: Self.pendingKey) }
        return outcomes
    }

    /// One database.
    public func compact(_ url: URL) -> Outcome {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return .missing }
        let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size <= maximumBytes else { return .tooLarge }
        switch SQLiteCheck.verdict(url) {
        case .damaged: return .notIntact
        case .unknown: return .unavailable  // busy or locked: tried again at the next launch
        case .intact: break
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return .unavailable
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_000)
        // `VACUUM` builds the compacted copy in a temporary file by default, in the app's temporary folder, which is not the Journal's and Coach's protected folder
        // (measured: the file `etilqs_…` appears in the temporary folder and holds the whole copy). In memory, nothing is written outside the store (S1B-R-04).
        guard sqlite3_exec(database, "PRAGMA temp_store = MEMORY;", nil, nil, nil) == SQLITE_OK else { return .failed }
        guard sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil) == SQLITE_OK else { return .unavailable }
        return sqlite3_exec(database, "VACUUM;", nil, nil, nil) == SQLITE_OK ? .compacted : .failed
    }
}
