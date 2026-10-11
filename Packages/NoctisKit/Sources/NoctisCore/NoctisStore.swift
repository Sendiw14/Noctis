import Foundation
import SwiftData

/// Opens the app's own database (`default.store`: the profile, the wake alarm's settings, the wind-down record) through its versioned schema, and
/// recovers from a file that will not open (`StoreRecovery`, APP_RULES.md R65). It never throws and never stops the app.
public nonisolated enum NoctisStore {
    /// Where the database has always been: SwiftData's default location, in Application Support.
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store", directoryHint: .notDirectory)
    }

    /// The database at `url`, as its current version, with the plan that can bring an older one forward. Never synced.
    public static func container(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: NoctisCurrentSchema.self)
        let configuration = ModelConfiguration("default", schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        let opened = try ModelContainer(for: schema, migrationPlan: NoctisMigrationPlan.self, configurations: configuration)
        // A file that opens but cannot be read (truncated pages) is as unusable as one that does not open: look at every table once.
        let context = ModelContext(opened)
        _ = try context.fetchCount(FetchDescriptor<UserProfileRecord>())
        _ = try context.fetchCount(FetchDescriptor<AlarmConfiguration>())
        _ = try context.fetchCount(FetchDescriptor<WindDownSession>())
        return opened
    }

    /// Nothing on disk: tests, previews, and the last resort when the file cannot be opened or replaced.
    public static func inMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: NoctisCurrentSchema.self)
        return try ModelContainer(for: schema, migrationPlan: NoctisMigrationPlan.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    /// Opens the database for the app. A damaged file is set aside and the app starts empty; a locked one is left alone and the app runs in memory.
    public static func open(at url: URL = defaultURL, recovery: StoreRecovery? = nil) -> (container: ModelContainer, outcome: StoreOpenOutcome) {
        // Beside the database's own folder: `Noctis/Quarantine` in Application Support, and a test's folder when a test gives one.
        let recovery = recovery ?? StoreRecovery(quarantineRoot: url.deletingLastPathComponent().appending(path: StoreRecovery.folderPath, directoryHint: .isDirectory))
        if let result = try? recovery.open(.app, at: url, make: { try container(at: $0) }, inMemory: { try inMemory() }) {
            return result
        }
        // An in-memory container of the app's own schema cannot fail short of a model that is not valid, which every test that opens one would hit.
        return (try! inMemory(), .runningInMemory)
    }
}
