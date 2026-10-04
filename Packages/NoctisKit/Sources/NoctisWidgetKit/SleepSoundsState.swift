import Foundation

// What the "Sleep sounds" control reads (APP_RULES.md R48): whether a sound is playing now. The control is drawn by an extension, which never
// holds the audio, so the app that does holds a very small record of the truth in the App Group and asks the system to redraw the control
// when it changes. The record exists only while a sound plays: no file means nothing is playing, so "stopped", "deleted" and "never played"
// are the same thing and nothing about what was played, when or for how long is kept.

/// A sound is playing. That, and when its sleep timer ends if one is set, is all there is.
public nonisolated struct SleepSoundsState: Codable, Equatable, Sendable {
    /// Another version is read as "nothing playing".
    public static let currentVersion = 1
    /// A record is far smaller than this; the store refuses more.
    public static let maximumBytes = 512

    public var version: Int
    /// When the sleep timer ends, if one is set. Past this time the record is wrong whatever the file says, so a reader treats it as stopped.
    public var endsAt: Date?

    public init(endsAt: Date? = nil, version: Int = SleepSoundsState.currentVersion) {
        self.version = version
        self.endsAt = endsAt
    }

    /// Whether the control shows "on" at `now`: the record is ours, and its timer has not ended.
    public func isPlaying(at now: Date) -> Bool {
        guard version == Self.currentVersion else { return false }
        if let endsAt, endsAt <= now { return false }
        return true
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> SleepSoundsState? {
        guard data.count <= maximumBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let state = try? decoder.decode(SleepSoundsState.self, from: data), state.version == currentVersion else { return nil }
        return state
    }
}

/// The record's file in the App Group, written as the widgets' snapshot is (atomically, readable once the iPhone has been unlocked since it
/// started, kept out of backups). The group is named in `WidgetSnapshotStore` alone; this reuses its container.
public nonisolated final class SleepSoundsStore: Sendable {
    public static let fileName = "SleepSoundsState.json"

    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    /// The store in the App Group's container; nil where there is none.
    public convenience init?() {
        guard let container = WidgetSnapshotStore.containerURL else { return nil }
        self.init(directory: container)
    }

    /// The record, or nil when no sound is playing (no file), it cannot be read, or it is another version's.
    public func load() -> SleepSoundsState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return SleepSoundsState.decode(data)
    }

    /// Whether the control shows "on" now.
    public func isPlaying(at now: Date = Date()) -> Bool {
        load()?.isPlaying(at: now) ?? false
    }

    /// Writes `state`. False when it could not be written (the old file stays).
    @discardableResult
    public func save(_ state: SleepSoundsState) -> Bool {
        guard let data = try? state.encoded(), data.count <= SleepSoundsState.maximumBytes else { return false }
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

    /// Deletes the file: nothing is playing. Nothing to delete is not an error.
    public func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}

/// The two controls' identifiers, so the app can ask the system to redraw one by kind.
public nonisolated enum ControlKind {
    public static let windDown = "com.noctis.app.control.wind-down"
    public static let sleepSounds = "com.noctis.app.control.sleep-sounds"
}
