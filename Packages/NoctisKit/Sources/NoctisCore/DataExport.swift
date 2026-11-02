import Foundation

public nonisolated enum DataExportError: Error, Equatable {
    /// An inventory category that is meant to be in the export has nothing to provide it.
    case missingProvider(DataCategoryID)
    case notJSON(DataCategoryID)
}

/// "Export my data": one JSON file of everything NOCTIS stores that is the person's or worked out for them (APP_RULES.md R41). The
/// inventory decides what is in it: each category that says `.included(key)` must have a provider, and no other is written. It never
/// holds a raw Apple Health reading, because NOCTIS keeps none.
public nonisolated enum DataExport {
    public static let fileName = "NOCTIS-export.json"
    /// The name the file has while it is being written. It is renamed onto `fileName` only when whole, so a write that is cut short leaves this name
    /// and no other, and every cleanup removes it.
    public static let partialFileName = fileName + ".partial"
    public static let about =
        "A copy of what NOCTIS stores on this iPhone: your profile, preferences, goals, alarm settings, wind-down history, journal, Coach conversations and the numbers NOCTIS worked out from Apple Health. It never holds raw Apple Health readings, because NOCTIS does not keep them."

    public typealias Provider = @MainActor () async throws -> Any

    /// The file's bytes: pretty-printed, keys sorted, so two exports of the same data are the same text.
    @MainActor
    public static func build(inventory: DataInventory, providers: [DataCategoryID: Provider], now: Date = Date(), app: String) async throws -> Data {
        var categories: [String: Any] = [:]
        for category in inventory.categories {
            guard case .included(let key) = category.export else { continue }
            guard let provider = providers[category.id] else { throw DataExportError.missingProvider(category.id) }
            let value = try await provider()
            guard JSONSerialization.isValidJSONObject([key: value]) else { throw DataExportError.notJSON(category.id) }
            categories[key] = value
        }
        let document: [String: Any] = ["app": app, "exportedAt": ISO8601DateFormatter().string(from: now), "about": about, "categories": categories]
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: Writing and removing the file

    /// Writes `data` as `fileName` in `directory`. Complete file protection (the class the Journal and Coach files have, because this file holds the same
    /// text): unreadable while the iPhone is locked. Written under `partialFileName` and renamed onto the final name, so the final file is whole or absent,
    /// and an export made before is replaced in one step. A failure removes the partial file and throws.
    public static func write(_ data: Data, in directory: URL) throws -> URL {
        let manager = FileManager.default
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        let partial = directory.appending(path: partialFileName, directoryHint: .notDirectory)
        do {
            try? manager.removeItem(at: partial)
            try data.write(to: partial, options: [.completeFileProtection])
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: partial)
            } else {
                try manager.moveItem(at: partial, to: url)
            }
            return url
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
    }

    /// Removes the export and any partial file a cut-short write left in `directory`.
    public static func remove(in directory: URL) {
        for name in [fileName, partialFileName] {
            try? FileManager.default.removeItem(at: directory.appending(path: name, directoryHint: .notDirectory))
        }
    }

    // MARK: Helpers for providers

    /// The values stored under `keys` in `defaults`, by key.
    public static func defaultsObject(keys: [String], defaults: UserDefaults) -> [String: Any] {
        var object: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key), JSONSerialization.isValidJSONObject([key: value]) { object[key] = value }
        }
        return object
    }

    /// Any `Encodable` as JSON values, dates as ISO 8601.
    public static func object(from value: some Encodable) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    /// A JSON file's contents as values; empty when there is no file or it can't be read.
    public static func fileObject(at url: URL) -> Any {
        guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) else { return [String: Any]() }
        return object
    }
}
