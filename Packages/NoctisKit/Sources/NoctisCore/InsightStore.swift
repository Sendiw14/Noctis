import Foundation
import InsightsKit
import SleepKit

/// The insights kept on this device: `InsightLibrary` as a file.
///
/// What it holds is derived values only: each insight's typed numbers (never
/// a sentence, never a raw HealthKit record, source or device name), where it
/// stands (new, seen, dismissed) and the person's fatigue history. The file
/// has complete file protection (unreadable while the device is locked, so a
/// launch before first unlock simply finds nothing), is excluded from
/// backups, and is registered with `NoctisDataRegistry` so Data Management
/// erases it.
public nonisolated final class InsightFileStore: NoctisErasable, @unchecked Sendable {
    /// Bumped whenever the persisted shape changes: an older file is
    /// dropped, never half-read.
    public static let schemaVersion = InsightLibrary.schemaVersion

    public let fileURL: URL
    private let lock = NSLock()
    private var erasures = 0

    public var erasableName: String { "Insights" }

    /// `directory` defaults to a "Noctis" folder in Application Support.
    public init(directory: URL? = nil) {
        let folder = directory ?? URL.applicationSupportDirectory.appending(path: "Noctis", directoryHint: .isDirectory)
        fileURL = folder.appending(path: "insights.json", directoryHint: .notDirectory)
    }

    /// How many times the file was erased: a store holding a copy in memory
    /// compares it to know its copy is gone.
    public var erasureCount: Int { lock.withLock { erasures } }

    public func load() -> InsightLibrary? {
        lock.withLock {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            guard let library = try? JSONDecoder().decode(InsightLibrary.self, from: data), library.schema == Self.schemaVersion else {
                remove()
                return nil
            }
            return library
        }
    }

    public func save(_ library: InsightLibrary) {
        lock.withLock {
            do {
                let data = try JSONEncoder().encode(library)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var url = fileURL
                try? url.setResourceValues(values)
            } catch {
                // A cache that can't be written is a cache that isn't there.
            }
        }
    }

    public func erase() {
        lock.withLock {
            erasures += 1
            remove()
        }
    }

    private func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// The one place insights live. Generated records are merged in once and
/// never rewritten; the tab, History, the detail page and Home all read the
/// library from here, so they can't disagree about what's featured today.
public actor InsightStore {
    private let file: InsightFileStore?
    private var library: InsightLibrary
    private var erasuresSeen: Int

    /// With no `file` the store lives in memory only (tests, previews).
    public init(file: InsightFileStore? = nil) {
        self.file = file
        library = file?.load() ?? InsightLibrary()
        erasuresSeen = file?.erasureCount ?? 0
    }

    /// The library as it stands (an erased store is empty again).
    public func snapshot() -> InsightLibrary {
        syncWithFile()
        return library
    }

    /// Stores the generated insights not stored yet, and chooses `night`'s
    /// featured insight once. Returns the library after.
    @discardableResult
    public func ingest(_ records: [InsightRecord], featuredOn night: SleepNightKey?) -> InsightLibrary {
        syncWithFile()
        var next = library
        next.merge(records)
        if let night { next.chooseFeatured(on: night) }
        commit(next)
        return library
    }

    /// The featured insight for `night`, chosen and remembered if it wasn't.
    public func featured(on night: SleepNightKey) -> InsightRecord? {
        syncWithFile()
        var next = library
        let record = next.chooseFeatured(on: night)
        commit(next)
        return record
    }

    public func markSeen(id: String) {
        mutate { $0.markSeen(id: id) }
    }

    /// "Not useful".
    public func dismiss(id: String) {
        mutate { $0.dismiss(id: id) }
    }

    /// "Hide insights like this".
    public func hide(_ type: InsightType) {
        mutate { $0.hide(type) }
    }

    private func mutate(_ change: (inout InsightLibrary) -> Void) {
        syncWithFile()
        var next = library
        change(&next)
        commit(next)
    }

    private func commit(_ next: InsightLibrary) {
        guard next != library else { return }
        library = next
        file?.save(next)
    }

    /// Data Management erased the file: forget the copy in memory.
    private func syncWithFile() {
        guard let file, file.erasureCount != erasuresSeen else { return }
        erasuresSeen = file.erasureCount
        library = InsightLibrary()
    }
}
