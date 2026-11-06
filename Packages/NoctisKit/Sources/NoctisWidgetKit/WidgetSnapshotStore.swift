import Foundation

/// Where the snapshot lives and how it is written (APP_RULES.md R44). The App Group container is the only shared storage
/// NOCTIS has: the app writes one small file there and an extension reads it, nothing else is shared and no
/// `UserDefaults` suite is. A test holds the whole package to that.
///
/// The file is written atomically, with `completeUntilFirstUserAuthentication` protection (a widget has to read it while
/// the iPhone is locked, after the first unlock since it started) and is excluded from backups.
public nonisolated final class WidgetSnapshotStore: Sendable {
    /// The App Group, made from the app's bundle ID. It is in both targets' entitlements (`project.yml`).
    public static let appGroupIdentifier = "group.com.noctis.app"
    public static let fileName = "WidgetSnapshot.json"

    public let fileURL: URL

    /// A store in `directory` (tests, previews, and the App Group's container).
    public init(directory: URL) {
        fileURL = directory.appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    /// The App Group's container; nil where the group is not available (an unsigned build, a unit test host).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// The store in the App Group's container; nil where there is none.
    public convenience init?() {
        guard let container = Self.containerURL else { return nil }
        self.init(directory: container)
    }

    /// The saved snapshot; nil when there is none, it cannot be read, or it was written by another version.
    public func load() -> WidgetSnapshot? {
        // The size first: a file over the limit is not read into a widget's small memory at all.
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= WidgetSnapshot.maximumBytes,
            let data = try? Data(contentsOf: fileURL)
        else { return nil }
        return WidgetSnapshot.decode(data)
    }

    /// Writes `snapshot`. False when it is over `WidgetSnapshot.maximumBytes` or could not be written (the old file stays).
    @discardableResult
    public func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let data = try? snapshot.encoded(), data.count <= WidgetSnapshot.maximumBytes else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = fileURL
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    /// Deletes the file. Nothing to delete is not an error.
    public func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Whether the file exists.
    public var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}
