import Foundation
import ReviewKit

/// The reviews kept on this device: `ReviewLibrary` as a file.
///
/// What it holds is derived values only (APP_RULES.md R39): the numbers a review is made of, never a sentence, a raw HealthKit record, a source or device name, anything
/// from the Journal or anything Coach wrote. The file has complete file protection (unreadable while the device is locked, so a launch before first unlock simply
/// finds nothing), is excluded from backups, never leaves the device, and is registered with `NoctisDataRegistry` so Data management erases it. Coach cannot read it.
public nonisolated final class ReviewFileStore: NoctisErasable, @unchecked Sendable {
    public static let schemaVersion = ReviewLibrary.schemaVersion

    public let fileURL: URL
    private let lock = NSLock()
    private var erasures = 0

    public var erasableName: String { "Reviews" }

    /// `directory` defaults to a "Noctis" folder in Application Support.
    public init(directory: URL? = nil) {
        let folder = directory ?? URL.applicationSupportDirectory.appending(path: "Noctis", directoryHint: .isDirectory)
        fileURL = folder.appending(path: "reviews.json", directoryHint: .notDirectory)
    }

    /// How many times the file was erased: a store holding a copy in memory compares it to know its copy is gone.
    public var erasureCount: Int { lock.withLock { erasures } }

    public func load() -> ReviewLibrary? {
        lock.withLock {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            guard var library = try? JSONDecoder().decode(ReviewLibrary.self, from: data), library.schema == Self.schemaVersion else {
                remove()
                return nil
            }
            library.dropUnreadable()
            return library
        }
    }

    public func save(_ library: ReviewLibrary) {
        lock.withLock {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(library)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var url = fileURL
                try? url.setResourceValues(values)
            } catch {
                // A review that can't be written is made again from Health when it is asked for.
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

/// What asking for a review gives back.
public nonisolated enum ReviewOutcome: Sendable, Equatable {
    case review(StoredReview)
    /// The period has too few nights; the nights there are and the nights needed ("4 of 5 nights").
    case notEnoughNights(have: Int, need: Int)
    /// The period has not ended yet.
    case notComplete
    /// Health could not be read (no access, or an error), so nothing can be said about the nights.
    case unavailable
}

/// The one place reviews live. A review is made the first time its period is asked for after it ended, made again for 24 hours when asked for (a night Apple Health
/// delivered late is counted), and frozen after that (`ReviewLifecycle`).
public actor ReviewStore {
    private let file: ReviewFileStore?
    private var library: ReviewLibrary
    private var erasuresSeen: Int

    /// With no `file` the store lives in memory only (tests, previews).
    public init(file: ReviewFileStore? = nil) {
        self.file = file
        library = file?.load() ?? ReviewLibrary()
        erasuresSeen = file?.erasureCount ?? 0
    }

    /// The library as it stands (an erased store is empty again).
    public func snapshot() -> ReviewLibrary {
        syncWithFile()
        return library
    }

    public func stored(_ id: ReviewID) -> StoredReview? {
        syncWithFile()
        return library[id]
    }

    /// The review of `period` as it is asked for at `now`. `build` reads Health and runs the engine (nil when Health could not be read); it is called only when the
    /// rules say a review is to be made, so a frozen one never reads Health again.
    public func review(for period: ReviewPeriod, now: Date, calendar: Calendar, build: @Sendable () async -> ReviewResult?) async -> ReviewOutcome {
        guard period.isComplete(at: now, calendar: calendar) else { return .notComplete }
        syncWithFile()
        let id = period.id
        if let stored = library[id], ReviewLifecycle.action(stored: stored, now: now) == .reuse { return .review(stored) }

        let result = await build()

        // Another request may have stored it while this one was reading Health: decide again with what is stored now.
        syncWithFile()
        if let existing = library[id] {
            guard let result, ReviewLifecycle.action(stored: existing, now: now) == .refresh else { return .review(existing) }
            let next = ReviewLifecycle.refreshed(existing, with: result)
            commit { $0.put(next) }
            return .review(next)
        }
        guard let result else { return .unavailable }
        switch result {
        case .record(let record):
            let stored = StoredReview(record: record, state: .new, firstGeneratedAt: now)
            commit { $0.put(stored) }
            return .review(stored)
        case .notEnoughNights(let have, let need):
            // Not kept: nights are added as Health receives them, so it can fill in later.
            return .notEnoughNights(have: have, need: need)
        }
    }

    /// The person opened it: a card for it stops appearing.
    public func markSeen(_ id: ReviewID) {
        syncWithFile()
        guard library[id]?.state == .new else { return }
        commit { $0.markSeen(id) }
    }

    private func commit(_ change: (inout ReviewLibrary) -> Void) {
        var next = library
        change(&next)
        guard next != library else { return }
        library = next
        file?.save(next)
    }

    /// Data management erased the file: forget the copy in memory.
    private func syncWithFile() {
        guard let file, file.erasureCount != erasuresSeen else { return }
        erasuresSeen = file.erasureCount
        library = ReviewLibrary()
    }
}
