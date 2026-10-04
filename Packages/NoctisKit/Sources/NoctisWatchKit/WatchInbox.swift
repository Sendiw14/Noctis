import Foundation
import NoctisWidgetKit

/// What the Watch keeps of what the iPhone sent (APP_RULES.md R50, R51, R52): the latest snapshot, when it arrived, and the highest data epoch it
/// has ever seen, in files in the Watch's own App Group container. The files are written atomically, are readable once the Watch has been unlocked
/// after it started (a complication has to read them) and are kept out of backups. Nothing here reads Health: it stores bytes the iPhone made.
///
/// The epoch rule is what makes "Delete all NOCTIS data" reach the Watch: a context with a lower epoch than the Watch holds is ignored (it is older
/// than the delete); a greater one wipes the Watch's copy first and then applies whatever came with it.
public nonisolated final class WatchInbox: Sendable {
    /// What a context did.
    public enum Outcome: Equatable, Sendable {
        /// The snapshot is stored.
        case stored
        /// The Watch held an older epoch: its copy was wiped, and `thenStored` says whether the context carried a new snapshot.
        case wiped(thenStored: Bool)
        /// The iPhone has no summary: the Watch dropped its copy too.
        case cleared
        /// A lower epoch than the Watch holds: older than a delete it already applied.
        case ignoredOlderEpoch
        /// A snapshot older than the one held, in the same epoch.
        case ignoredOlderSnapshot
        /// Bytes this build cannot read (another snapshot version): what the Watch holds stays.
        case ignoredUnreadable
    }

    /// The small record next to the snapshot.
    struct Receipt: Codable, Equatable, Sendable {
        var epoch: Int64
        /// When the held snapshot arrived on the Watch; nil with none.
        var receivedAt: Date?
        /// When the held snapshot was made on the iPhone.
        var generatedAt: Date?

        enum CodingKeys: String, CodingKey { case epoch = "e", receivedAt = "r", generatedAt = "g" }
    }

    public static let receiptFileName = "WatchReceipt.json"

    private let snapshotStore: WidgetSnapshotStore
    private let receiptURL: URL

    public init(directory: URL) {
        snapshotStore = WidgetSnapshotStore(directory: directory)
        receiptURL = directory.appending(path: Self.receiptFileName, directoryHint: .notDirectory)
    }

    /// The inbox in the App Group's container (the Watch app's and its complications' own copy); nil where there is none.
    public convenience init?() {
        guard let container = WidgetSnapshotStore.containerURL else { return nil }
        self.init(directory: container)
    }

    // MARK: Reading

    /// The held snapshot and when it arrived; nil with none (never sent, wiped, or another version).
    public func load() -> (snapshot: WidgetSnapshot, receivedAt: Date?)? {
        guard let snapshot = snapshotStore.load() else { return nil }
        return (snapshot, receipt.receivedAt)
    }

    /// The highest epoch ever applied (0 before any).
    public var epoch: Int64 { receipt.epoch }

    private var receipt: Receipt {
        guard let data = try? Data(contentsOf: receiptURL), let receipt = try? JSONDecoder.receipt.decode(Receipt.self, from: data) else {
            return Receipt(epoch: 0, receivedAt: nil, generatedAt: nil)
        }
        return receipt
    }

    // MARK: Receiving

    /// Applies what the iPhone sent, by the epoch rule.
    @discardableResult
    public func receive(_ context: WatchContext, now: Date) -> Outcome {
        var held = receipt
        let incoming = context.effectiveEpoch
        if incoming < held.epoch { return .ignoredOlderEpoch }

        var wiped = false
        if incoming > held.epoch {
            snapshotStore.delete()
            held = Receipt(epoch: incoming, receivedAt: nil, generatedAt: nil)
            save(held)
            wiped = true
        }

        // No summary at all: the iPhone deleted it (the epoch has not moved, or it just did).
        guard let data = context.snapshotData else {
            if !wiped {
                snapshotStore.delete()
                held.receivedAt = nil
                held.generatedAt = nil
                save(held)
            }
            return wiped ? .wiped(thenStored: false) : .cleared
        }
        guard let snapshot = context.snapshot, data.count <= WidgetSnapshot.maximumBytes else {
            return wiped ? .wiped(thenStored: false) : .ignoredUnreadable
        }
        if !wiped, let generated = held.generatedAt, snapshot.generatedAt < generated { return .ignoredOlderSnapshot }

        guard snapshotStore.save(snapshot) else { return wiped ? .wiped(thenStored: false) : .ignoredUnreadable }
        held.receivedAt = now
        held.generatedAt = snapshot.generatedAt
        save(held)
        return wiped ? .wiped(thenStored: true) : .stored
    }

    /// Removes everything held, keeping the highest epoch seen (it must outlive the data it wiped).
    public func wipeKeepingEpoch() {
        snapshotStore.delete()
        save(Receipt(epoch: receipt.epoch, receivedAt: nil, generatedAt: nil))
    }

    private func save(_ receipt: Receipt) {
        guard let data = try? JSONEncoder.receipt.encode(receipt) else { return }
        do {
            try FileManager.default.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: receiptURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = receiptURL
            try url.setResourceValues(values)
        } catch {
            // Nothing to do: the next context writes it again.
        }
    }
}

private extension JSONEncoder {
    static var receipt: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var receipt: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// Waiting for the background task's work to finish (APP_RULES.md R50). SwiftUI's `.backgroundTask(.watchConnectivity)` completes the system's task
/// when its closure returns, so the closure must return only once the pending context has been delivered to the session's delegate, and must always
/// return, or the Watch would be kept awake until the system gives up.
public nonisolated enum WatchBackgroundDrain {
    /// True when `hasContentPending` went false within `timeout`; false when time ran out. Either way it returns.
    public static func wait(
        hasContentPending: @Sendable () -> Bool, timeout: TimeInterval = 15, poll: TimeInterval = 0.25, sleep: @Sendable (TimeInterval) async -> Void
    ) async -> Bool {
        var waited: TimeInterval = 0
        while hasContentPending() {
            if waited >= timeout { return false }
            await sleep(poll)
            waited += poll
        }
        return true
    }
}
