import Foundation
import Testing

@testable import NightKit
@testable import NoctisCore
@testable import NoctisWatchKit
@testable import NoctisWidgetKit
@testable import PremiumKit

// QA part 2 (QA_LEDGER.md, APP_RULES.md R65): every store that is not SwiftData, handed a file or a value in the wrong shape or of another version,
// reads as empty and keeps working. What was written by another version of a store that holds what the person marked is set aside, not deleted.

private func folder() throws -> URL {
    let url = URL.temporaryDirectory.appending(path: "noctis-format-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// What a file can be found as, other than what the store wrote.
private enum Found: CaseIterable, CustomStringConvertible {
    case empty, garbage, truncated, wrongShape, anotherVersion

    var description: String {
        switch self {
        case .empty: "empty"
        case .garbage: "garbage"
        case .truncated: "truncated"
        case .wrongShape: "wrong shape"
        case .anotherVersion: "another version"
        }
    }

    /// `good` is what the store itself wrote; `versionKey` is the key its version number is under.
    func bytes(from good: Data, versionKey: String) -> Data {
        switch self {
        case .empty: return Data()
        case .garbage: return Data((0..<2048).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ 17) })
        case .truncated: return good.prefix(max(1, good.count / 2))
        case .wrongShape: return Data(#"["not", "an", "object", 3, null, {"a": []}]"#.utf8)
        case .anotherVersion:
            guard var object = (try? JSONSerialization.jsonObject(with: good)) as? [String: Any] else { return good }
            object[versionKey] = ((object[versionKey] as? Int) ?? 1) + 99
            return (try? JSONSerialization.data(withJSONObject: object)) ?? good
        }
    }
}

struct PersistedFormatTests {
    // MARK: Caches that are rebuilt: read as empty, replaced by the next save

    @Test(arguments: Found.allCases) private func theWidgetsSummaryReadsAsEmptyAndIsWrittenAgain(_ found: Found) throws {
        let directory = try folder()
        let store = WidgetSnapshotStore(directory: directory)
        let snapshot = WidgetSamples.snapshot(.full, now: Date(timeIntervalSince1970: 1_800_000_000), calendar: Calendar(identifier: .gregorian))
        #expect(store.save(snapshot))
        let good = try Data(contentsOf: store.fileURL)
        try found.bytes(from: good, versionKey: "v").write(to: store.fileURL)
        let loaded = store.load()
        if found == .empty || found == .garbage || found == .wrongShape || found == .anotherVersion { #expect(loaded == nil, Comment(rawValue: "\(found)")) }
        #expect(store.save(snapshot) && store.load() != nil, "a new file takes its place")
    }

    @Test(arguments: Found.allCases) private func theSoundsStatusReadsAsEmptyAndIsWrittenAgain(_ found: Found) throws {
        let directory = try folder()
        let store = SleepSoundsStore(directory: directory)
        let state = SleepSoundsState(endsAt: Date(timeIntervalSince1970: 4_000_000_000))
        #expect(store.save(state))
        let good = try Data(contentsOf: store.fileURL)
        try found.bytes(from: good, versionKey: "version").write(to: store.fileURL)
        let loaded = store.load()
        if found == .empty || found == .garbage || found == .wrongShape || found == .anotherVersion { #expect(loaded == nil, Comment(rawValue: "\(found)")) }
        #expect(found == .empty || found == .garbage || found == .wrongShape || found == .anotherVersion ? !store.isPlaying() : true, "an unreadable status is never 'on'")
        #expect(store.save(state) && store.load() != nil)
    }

    @Test func theWatchsReceiptAndCopyReadAsNeverSent() throws {
        let directory = try folder()
        let inbox = WatchInbox(directory: directory)
        try Data("{ not a receipt".utf8).write(to: directory.appending(path: WatchInbox.receiptFileName))
        try Data(repeating: 0xFF, count: 512).write(to: directory.appending(path: WidgetSnapshotStore.fileName))
        #expect(inbox.epoch == 0 && inbox.load() == nil)
    }

    @Test(arguments: Found.allCases) private func theHomeSnapshotReadsAsEmptyAndTheFileIsReplaced(_ found: Found) throws {
        let directory = try folder()
        let store = HomeSnapshotStore(directory: directory)
        let shape = Data(#"{"schema": 2, "recoveryModel": "x", "savedAt": 0, "home": {}}"#.utf8)
        try found.bytes(from: shape, versionKey: "schema").write(to: store.fileURL)
        #expect(store.load() == nil, Comment(rawValue: "\(found)"))
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path), "a cache that cannot be read is replaced, not kept")
    }

    // MARK: Values in the defaults

    @Test func preferencesReadBackInsideWhatIsOffered() async throws {
        let name = "noctis.format.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        // Every key holds something of the wrong type, the wrong word or out of range.
        let hostile: [Any] = [Data([1, 2, 3]), "💥", -9_999, 9_999_999, 3.5e300, [1, 2], ["a": 1], true]
        for (index, key) in AppPreferences.allKeys.enumerated() { defaults.set(hostile[index % hostile.count], forKey: key) }
        let values = await MainActor.run { AppPreferences.load(from: defaults) }
        #expect(values == values.normalized(), "inside what the screens offer")
        #expect((0...100).contains(values.soundsGainPercent))
        #expect(WindDownClock.options.contains(values.windDownMinutes))
        #expect((1...7).contains(values.notifications.weeklyWeekday))
        #expect((0..<1440).contains(values.notifications.weeklyMinutesSinceMidnight))
    }

    @Test func theCachedTierReadsAsFreeFromAnythingElse() throws {
        let name = "noctis.format.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = EntitlementCache(defaults: defaults)
        for value: Any in [Data([0, 1]), 42, "platinum", ["premium"], 1.5, ""] {
            defaults.set(value, forKey: PremiumKeys.cachedTier)
            #expect(cache.read() == .free, Comment(rawValue: "\(value)"))
        }
        cache.write(.premium)
        #expect(cache.read() == .premium)
    }

    @Test func theCoachQuotaReadsAsAFreshDayFromAnythingElse() throws {
        let name = "noctis.format.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = CoachQuotaStore(defaults: defaults)
        for value: Any in [Data([0, 1]), 42, "x|y|z", "2026-13-45|abc", ["a"], "|", "2026-09-24|-5"] {
            defaults.set(value, forKey: PremiumKeys.coachQuota)
            let state = store.read()
            #expect(state.used >= 0, Comment(rawValue: "\(value)"))
        }
    }
}
