import Foundation
import Testing

@testable import HealthProviding
@testable import InsightsKit
@testable import NoctisCore
@testable import NoctisWidgetKit
@testable import ReviewKit
@testable import SleepKit

// QA part 3, step 5 (lifecycle): a disk that refuses a write. Every file NOCTIS keeps is written atomically; a write that fails (the volume is full, the
// folder is read-only, the phone is locked with complete protection) must lose nothing already saved, say so where the caller can (false), and never crash.
// A full disk and a read-only folder fail the same way in `Data.write(to:options:)` (it throws), which is what is driven here by taking write permission
// from the folder. A true ENOSPC (a volume with no free blocks) is UNVERIFIED: it needs a device or a disk image filled to the brim.

struct WriteFailureTests {
    private func folder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "noctis.writefail.\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func lock(_ url: URL) throws { try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: url.path) }
    private func unlock(_ url: URL) { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }

    @Test func theWidgetsSummaryKeepsTheOldFileWhenTheWriteFails() throws {
        let directory = try folder()
        defer {
            unlock(directory)
            try? FileManager.default.removeItem(at: directory)
        }
        let calendar = Fixture.calendar()
        let store = WidgetSnapshotStore(directory: directory)
        let first = WidgetSamples.snapshot(.full, now: Fixture.date(2026, 9, 24, 10), calendar: calendar)
        #expect(store.save(first))
        let before = try Data(contentsOf: store.fileURL)
        try lock(directory)
        let second = WidgetSamples.snapshot(.full, now: Fixture.date(2026, 9, 25, 10), calendar: calendar)
        #expect(!store.save(second), "a refused write says so")
        unlock(directory)
        #expect(try Data(contentsOf: store.fileURL) == before, "the saved file is untouched and whole")
        #expect(store.load() != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1, "no half-written temporary file is left")
    }

    @Test func theSoundsControlKeepsTheOldFileWhenTheWriteFails() throws {
        let directory = try folder()
        defer {
            unlock(directory)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = SleepSoundsStore(directory: directory)
        #expect(store.save(SleepSoundsState(endsAt: Date(timeIntervalSince1970: 1_790_000_000))))
        let before = try Data(contentsOf: store.fileURL)
        try lock(directory)
        #expect(!store.save(SleepSoundsState(endsAt: Date(timeIntervalSince1970: 1_790_009_000))))
        unlock(directory)
        #expect(try Data(contentsOf: store.fileURL) == before)
    }

    @Test func reviewsKeepTheirLibraryWhenTheWriteFails() throws {
        let directory = try folder()
        defer {
            unlock(directory)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ReviewFileStore(directory: directory)
        var library = ReviewLibrary()
        library.put(ReviewTestRecords.stored())
        store.save(library)
        let before = try Data(contentsOf: store.fileURL)
        try lock(directory)
        var changed = library
        changed.put(ReviewTestRecords.stored())
        store.save(changed)  // must not crash or throw
        unlock(directory)
        #expect(try Data(contentsOf: store.fileURL) == before)
        #expect(store.load() != nil)
    }

    @Test func insightsKeepTheirLibraryWhenTheWriteFails() throws {
        let directory = try folder()
        defer {
            unlock(directory)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = InsightFileStore(directory: directory)
        store.save(InsightLibrary())
        let before = try Data(contentsOf: store.fileURL)
        try lock(directory)
        store.save(InsightLibrary())
        unlock(directory)
        #expect(try Data(contentsOf: store.fileURL) == before)
    }

    @Test func aFirstWriteThatFailsLeavesNoFileAndTheNextLoadIsEmptyNotACrash() throws {
        let directory = try folder()
        defer {
            unlock(directory)
            try? FileManager.default.removeItem(at: directory)
        }
        try lock(directory)
        let store = WidgetSnapshotStore(directory: directory.appending(path: "inner", directoryHint: .isDirectory))
        #expect(!store.save(WidgetSamples.snapshot(.full, now: Fixture.date(2026, 9, 24, 10), calendar: Fixture.calendar())))
        #expect(store.load() == nil && !store.exists)
    }
}
