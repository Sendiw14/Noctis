import Foundation
import Testing

@testable import NoctisCore
@testable import NoctisWatchKit
@testable import NoctisWidgetKit

// Everything NOCTIS reads from outside its own memory: the widget snapshot and the sleep sounds record (files in the App Group that another process writes), and every
// link that reaches the app (widgets, the Watch, Siri, a tapped URL). Seeded, so a failure repeats. A crash here is the process dying, so the tests assert that every input
// is answered, and what an answer may be.

/// SplitMix64: the same inputs for the same seed on every run.
private nonisolated struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct ParserFuzzTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// A valid file, then the ways a file goes wrong: bytes flipped, cut short, a piece repeated, a piece dropped, junk added.
    private func mutated(_ seed: Data, _ random: inout SeededGenerator) -> Data {
        var bytes = [UInt8](seed)
        switch Int.random(in: 0..<6, using: &random) {
        case 0:
            for _ in 0..<Int.random(in: 1...8, using: &random) where !bytes.isEmpty { bytes[Int.random(in: 0..<bytes.count, using: &random)] = UInt8.random(in: 0...255, using: &random) }
        case 1: bytes = Array(bytes.prefix(Int.random(in: 0...max(bytes.count, 1), using: &random)))
        case 2:
            if !bytes.isEmpty {
                let start = Int.random(in: 0..<bytes.count, using: &random)
                bytes.insert(contentsOf: bytes[start..<min(start + Int.random(in: 1...40, using: &random), bytes.count)], at: Int.random(in: 0...bytes.count, using: &random))
            }
        case 3:
            if !bytes.isEmpty {
                let start = Int.random(in: 0..<bytes.count, using: &random)
                bytes.removeSubrange(start..<min(start + Int.random(in: 1...40, using: &random), bytes.count))
            }
        case 4: bytes += (0..<Int.random(in: 1...64, using: &random)).map { _ in UInt8.random(in: 0...255, using: &random) }
        default:
            // A number replaced by an extreme one, the way a hand-edited or damaged file reads.
            let extremes = ["99999999999999999999", "-1", "1e999", "null", "\"x\"", "[]", "{}", "0.0000001", "4294967296"]
            if var text = String(data: seed, encoding: .utf8), let range = text.range(of: #"[0-9]+"#, options: .regularExpression) {
                text.replaceSubrange(range, with: extremes[Int.random(in: 0..<extremes.count, using: &random)])
                bytes = Array(text.utf8)
            }
        }
        return Data(bytes)
    }

    private func seeds() throws -> [Data] {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        return try [WidgetDataState.full, .sleepOnly, .learning(nightsSoFar: 3), .empty, .noPermission, .stale(hours: 30)].map { try WidgetSamples.snapshot($0, now: now, calendar: Self.calendar).encoded() }
    }

    @Test func aDamagedWidgetSnapshotIsReadAsNothingOrAsASnapshotThatEncodesAgain() throws {
        var random = SeededGenerator(state: 20_261_103)
        let seeds = try seeds()
        for seed in seeds { #expect(WidgetSnapshot.decode(seed) != nil, "the undamaged file reads") }
        var read = 0
        for _ in 0..<4_000 {
            let data = mutated(seeds.randomElement(using: &random)!, &random)
            if let snapshot = WidgetSnapshot.decode(data) {
                read += 1
                #expect((try? snapshot.encoded()) != nil, "what was read can be written")
            }
        }
        #expect(read < 4_000, "damage is noticed at least some of the time")
    }

    @Test func bytesThatWereNeverASnapshotAreNeverOne() {
        var random = SeededGenerator(state: 7)
        for _ in 0..<4_000 {
            let data = Data((0..<Int.random(in: 0...4_096, using: &random)).map { _ in UInt8.random(in: 0...255, using: &random) })
            #expect(WidgetSnapshot.decode(data) == nil)
            #expect(SleepSoundsState.decode(data) == nil)
        }
    }

    @Test func aDamagedSleepSoundsRecordIsReadAsNothingOrAsARecordThatEncodesAgain() throws {
        var random = SeededGenerator(state: 11)
        let seeds = try [SleepSoundsState(), SleepSoundsState(endsAt: Date(timeIntervalSince1970: 1_790_000_000))].map { try $0.encoded() }
        for seed in seeds { #expect(SleepSoundsState.decode(seed) != nil) }
        for _ in 0..<4_000 {
            if let state = SleepSoundsState.decode(mutated(seeds.randomElement(using: &random)!, &random)) { #expect((try? state.encoded()) != nil) }
        }
    }

    @Test func aFileOverTheSizeLimitIsNotRead() throws {
        let snapshot = try #require(try seeds().first)
        var big = snapshot
        big.append(Data(repeating: 0x20, count: WidgetSnapshot.maximumBytes))
        #expect(WidgetSnapshot.decode(big) == nil)
    }

    @Test func anOversizedFileOnDiskIsNotLoadedAndALegitimateOneStillIs() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "fuzz-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let snapshot = WidgetSamples.snapshot(.full, now: Date(timeIntervalSince1970: 1_790_000_000), calendar: Self.calendar)
        #expect(store.save(snapshot) && store.load() == snapshot, "a snapshot the app wrote loads")
        // The same bytes with padding past the limit, as a damaged or foreign file would be.
        let padded = try snapshot.encoded() + Data(repeating: 0x20, count: WidgetSnapshot.maximumBytes)
        try padded.write(to: store.fileURL)
        #expect(store.load() == nil, "a file over the limit is not read")
        try Data(repeating: 0x20, count: 5_000_000).write(to: store.fileURL)
        #expect(store.load() == nil, "and a huge one is not read into memory at all")
    }

    /// What the Watch is handed by WatchConnectivity is a dictionary of whatever the other side put in it.
    @Test func aContextOfAnyShapeIsAnsweredAndNeverReadAsAnotherFormat() throws {
        var random = SeededGenerator(state: 31)
        let valid = try WatchContext(snapshot: WidgetSamples.snapshot(.full, now: Date(timeIntervalSince1970: 1_790_000_000), calendar: Self.calendar), sentAt: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(WatchContext(dictionary: valid.dictionary) == valid)
        let keys = ["wire", "epoch", "sentAt", "snapshot", "x", ""]
        let numbers: [Any] = [0, 1, -1, Int.max, Int.min, 1.5, "1", true, Data(), NSNull(), [Any](), ["a": 1]]
        var accepted = 0
        for _ in 0..<10_000 {
            var dictionary: [String: Any] = [:]
            for key in keys where Bool.random(using: &random) {
                if key == "snapshot", Bool.random(using: &random) { dictionary[key] = mutated(try #require(valid.snapshotData), &random) } else { dictionary[key] = numbers.randomElement(using: &random)! }
            }
            if let context = WatchContext(dictionary: dictionary) {
                accepted += 1
                #expect(dictionary["wire"] as? Int == WatchContext.formatVersion, "another format is never read")
                #expect(context.effectiveEpoch >= 0, "an epoch below zero is no epoch")
                _ = context.snapshot
            }
        }
        #expect(accepted > 0)
    }

    /// Pieces that matter to a URL, joined at random after a scheme that is sometimes right.
    private func url(_ random: inout SeededGenerator) -> URL? {
        let schemes = ["noctis", "NOCTIS", "noctis-watch", "http", "https", "file", "javascript", "", "noctis ", "noc tis"]
        let hosts = ["recovery", "sleep", "tonight", "bedtime", "wind-down", "premium", "review", "insights", "coach", "%72ecovery", "RECOVERY", "recovery.evil.com", "..", "", "a@b", "[::1]", "xn--", "\u{202E}recovery"]
        let pieces = ["/", "//", "?", "&", "=", "#", "%", "%00", "%zz", "..", "context=widgets", "context=\(String(repeating: "a", count: 300))", "range=week", "night=2026-09-24T22:00:00Z", "id=weekly-2026-09-26", "kind=monthly", "\u{0}", "\n", " ", "\\", ":", "@", ":65536", "😀"]
        var text = schemes.randomElement(using: &random)! + "://" + hosts.randomElement(using: &random)!
        for _ in 0..<Int.random(in: 0...6, using: &random) { text += pieces.randomElement(using: &random)! }
        return URL(string: text)
    }

    @Test func noLinkIsEverAnythingButAnAnsweredQuestion() {
        var random = SeededGenerator(state: 99)
        var opened = 0
        for _ in 0..<20_000 {
            guard let link = url(&random) else { continue }
            _ = AppRoute(url: link)
            _ = WidgetLink(url: link)
            _ = PremiumLink(url: link)
            _ = WatchLink(url: link)
            if WidgetURLRouter.destination(for: link) != nil {
                opened += 1
                let components = URLComponents(url: link, resolvingAgainstBaseURL: false)
                #expect(components?.scheme?.lowercased() == "noctis", "\(link) opened something under another scheme")
                #expect(components?.user == nil && components?.password == nil && components?.port == nil, "\(link) opened something with credentials or a port")
            }
        }
        #expect(opened > 0, "the generator reaches real links")
    }

    @Test func theLinksNOCTISMakesAreAllAnswered() {
        for link in WidgetLink.allCases { #expect(WidgetURLRouter.destination(for: link.url) != nil) }
        for link in WatchLink.allCases { #expect(WatchLink(url: link.url) == link) }
    }
}
