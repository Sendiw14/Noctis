import Foundation
import Observation
import SwiftUI

/// One thing the delete-all does, in order.
public struct DeleteStep {
    public let id: String
    /// "Stopping sounds": what the sheet says while it runs.
    public let title: String
    public let run: @MainActor () async throws -> Void
    /// A sentence to show under the step once it has worked ("Apple Watch: wipe sent"); nil for none.
    public let note: (@MainActor () -> String?)?

    public init(id: String, title: String, run: @escaping @MainActor () async throws -> Void) {
        self.id = id
        self.title = title
        self.note = nil
        self.run = run
    }

    /// A step that says something about itself once it has worked.
    public init(id: String, title: String, note: @escaping @MainActor () -> String?, run: @escaping @MainActor () async throws -> Void) {
        self.id = id
        self.title = title
        self.note = note
        self.run = run
    }
}

/// What a deletion did, step by step. A step that fails is reported and the rest still run.
public nonisolated struct DeletionReport: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        /// Nil when the step worked.
        public let failure: String?
    }

    public var entries: [Entry] = []

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public var failures: [Entry] { entries.filter { $0.failure != nil } }
    public var succeeded: Bool { failures.isEmpty }
}

public enum DeletionRunner {
    /// Runs every step in order, whatever happens to the ones before; `progress` hears each step as it starts and as it ends.
    @MainActor
    public static func run(
        _ steps: [DeleteStep], progress: (_ id: String, _ finished: Bool, _ failure: String?) -> Void = { _, _, _ in }
    ) async -> DeletionReport {
        var report = DeletionReport()
        for step in steps {
            progress(step.id, false, nil)
            do {
                try await step.run()
                report.entries.append(.init(id: step.id, title: step.title, failure: nil))
                progress(step.id, true, nil)
            } catch {
                let message = String(describing: error)
                report.entries.append(.init(id: step.id, title: step.title, failure: message))
                progress(step.id, true, message)
            }
        }
        return report
    }
}

/// Data management: what NOCTIS keeps, one kind at a time or all of it, and a copy to take away (APP_RULES.md R41, R42). It knows no
/// store by name: the app gives it an eraser and an exporter for each inventory category, and the steps of "Delete all NOCTIS data".
@MainActor
@Observable
public final class DataManager {
    public typealias Eraser = @MainActor () async throws -> Void

    /// Set before the first step of "Delete all NOCTIS data" and cleared when every step has worked (S1B-B02): a launch that finds it set means the deletion was cut
    /// short (the app was killed, the iPhone restarted, a step failed) and finishes it. It lives under the `noctis.` prefix, so the preferences step clears it too.
    public nonisolated static let pendingDeleteAllKey = "noctis.deleteAll.pending"

    /// One row of the delete-all's progress.
    public enum StepState: Equatable, Sendable { case waiting, running, done, failed(String) }

    public let inventory: DataInventory
    public private(set) var isWorking = false
    /// What the last single-kind deletion did, for the line under its row.
    public private(set) var lastReport: DeletionReport?
    public private(set) var lastDeleted: DeletableGroup?
    /// The delete-all's steps and where each stands.
    public private(set) var steps: [(id: String, title: String, state: StepState)] = []
    /// What a finished step said about itself, by step id (the Watch's "wipe sent" or "will apply when your Watch connects").
    public private(set) var stepNotes: [String: String] = [:]
    public private(set) var deleteAllReport: DeletionReport?

    @ObservationIgnored private let roots: DataRoots
    @ObservationIgnored private let erasers: [DataCategoryID: Eraser]
    @ObservationIgnored private let providers: [DataCategoryID: DataExport.Provider]
    @ObservationIgnored private let deleteAllSteps: [DeleteStep]
    @ObservationIgnored private let appVersion: () -> String
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let compaction: StoreCompaction

    public init(
        inventory: DataInventory = .shared, roots: DataRoots = DataRoots(), erasers: [DataCategoryID: Eraser],
        providers: [DataCategoryID: DataExport.Provider], deleteAllSteps: [DeleteStep], appVersion: @escaping () -> String = { "NOCTIS" },
        clock: @escaping () -> Date = { Date() }, defaults: UserDefaults = NoctisUserDefaults.standard
    ) {
        self.defaults = defaults
        unfinishedSteps = (defaults.string(forKey: Self.unfinishedDeleteAllKey) ?? "").split(separator: ",").map(String.init)
        self.compaction = StoreCompaction(defaults: defaults)
        self.inventory = inventory
        self.roots = roots
        self.erasers = erasers
        self.providers = providers
        self.deleteAllSteps = deleteAllSteps
        self.appVersion = appVersion
        self.clock = clock
        // An export the last run left behind (the app was closed while the share sheet was up) goes at the start, as the inventory says.
        discardExport()
    }

    // MARK: Sizes

    /// "12 KB", "Nothing stored", or where it is kept when it shares a store.
    public func sizeText(for group: DeletableGroup) -> String {
        var bytes = 0
        var shared = false
        for category in inventory.categories(in: group) {
            switch inventory.size(of: category, roots: roots) {
            case .bytes(let value): bytes += value
            case .shared: shared = true
            case .notStored: break
            }
        }
        if shared && bytes == 0 { return "Kept with your profile" }
        return DataInventory.describe(bytes: bytes)
    }

    public var totalText: String { DataInventory.describe(bytes: inventory.totalBytes(roots: roots)) }

    // MARK: One kind

    /// Deletes (or resets) one group; the report says what happened to each of its categories.
    @discardableResult
    public func delete(_ group: DeletableGroup) async -> DeletionReport {
        isWorking = true
        defer { isWorking = false }
        let steps = group.categories.compactMap { id -> DeleteStep? in
            guard let eraser = erasers[id] else { return nil }
            return DeleteStep(id: id.rawValue, title: inventory[id].name, run: eraser)
        }
        let report =
            steps.isEmpty
            ? DeletionReport(entries: [.init(id: group.id, title: group.title, failure: "Nothing is wired to delete it.")])
            : await DeletionRunner.run(steps)
        lastReport = report
        lastDeleted = group
        // The rows are gone but their pages stay in the file until it is compacted: the next launch does it, before anything opens the database (S1B-B03).
        if report.entries.contains(where: { $0.failure == nil }), group.categories.contains(where: { holdsDatabase($0) }) { compaction.request() }
        return report
    }

    /// Whether a category keeps its rows in a SQLite database.
    private func holdsDatabase(_ id: DataCategoryID) -> Bool {
        inventory[id].locations.contains { if case .database = $0 { true } else { false } }
    }

    /// The database files the inventory lists, for compaction at launch.
    public static func databaseFiles(inventory: DataInventory = .shared, roots: DataRoots = DataRoots()) -> [URL] {
        inventory.categories.flatMap { category in
            category.locations.compactMap { location -> URL? in
                guard case .database(let directory, let path) = location else { return nil }
                return roots.url(directory).appending(path: path, directoryHint: .notDirectory)
            }
        }
    }

    // MARK: Everything

    /// How many launches finish an interrupted deletion before giving up (the first is the one right after it was cut short).
    public nonisolated static let maximumResumeAttempts = 3

    /// Whether a "Delete all NOCTIS data" was started and not finished. Read by the background refresher too, so a half-deleted app does not write its summary
    /// again from a Health wake (S1B-R-02).
    public nonisolated static func hasPendingDeleteAll(defaults: UserDefaults = NoctisUserDefaults.standard) -> Bool {
        defaults.integer(forKey: pendingDeleteAllKey) > 0
    }

    /// Set when the last resume gave up with steps still failing: their ids, comma-separated. It stays until a "Delete all NOCTIS data" works, and Data management
    /// says so (S1B-R-03): a deletion that did not finish is never forgotten.
    public nonisolated static let unfinishedDeleteAllKey = "noctis.deleteAll.unfinished"

    /// The steps the last resume could not finish, by step id (nothing personal); empty when nothing is outstanding. Survives a relaunch.
    public private(set) var unfinishedSteps: [String] = []

    /// The same steps by the name the delete-all sheet gave them ("Removing database files").
    public var unfinishedStepTitles: [String] {
        unfinishedSteps.map { id in deleteAllSteps.first { $0.id == id }?.title ?? id }
    }

    /// Deletes everything NOCTIS stores on this iPhone, in order. The caller then starts the app again (`restart`).
    public func deleteEverything() async -> DeletionReport {
        isWorking = true
        defer { isWorking = false }
        // Written first: if the app is cut off from here on, the next launch finishes the job (every step is safe to run again). A count already there stays.
        defaults.set(max(defaults.integer(forKey: Self.pendingDeleteAllKey), 1), forKey: Self.pendingDeleteAllKey)
        let report = await runDeleteAll()
        // The preferences step removes the marker with every other `noctis.` key; a deletion with a failed step puts it back so the next launch tries again.
        if report.succeeded {
            defaults.removeObject(forKey: Self.pendingDeleteAllKey)
            defaults.removeObject(forKey: Self.unfinishedDeleteAllKey)
            unfinishedSteps = []
        } else {
            defaults.set(1, forKey: Self.pendingDeleteAllKey)
        }
        return report
    }

    private func runDeleteAll() async -> DeletionReport {
        steps = deleteAllSteps.map { ($0.id, $0.title, .waiting) }
        stepNotes = [:]
        deleteAllReport = nil
        let report = await DeletionRunner.run(deleteAllSteps) { [weak self] id, finished, failure in
            guard let self, let index = self.steps.firstIndex(where: { $0.id == id }) else { return }
            self.steps[index].state = finished ? (failure.map { .failed($0) } ?? .done) : .running
            if finished, failure == nil, let note = self.deleteAllSteps.first(where: { $0.id == id })?.note?() { self.stepNotes[id] = note }
        }
        deleteAllReport = report
        return report
    }

    /// Whether a "Delete all NOCTIS data" was started and not finished.
    public var hasInterruptedDeletion: Bool { Self.hasPendingDeleteAll(defaults: defaults) }

    /// At launch: finishes a deletion that was cut short, and says whether it ran (the caller then starts the app over, as the sheet's Done does). It runs the
    /// steps once per call. A step that still fails keeps the marker for the next launch, up to `maximumResumeAttempts` launches in all; then the marker is
    /// replaced by the persistent record in `unfinishedSteps`, so a step that cannot work never makes every launch start over and is never forgotten either.
    public func resumeInterruptedDeletion() async -> Bool {
        let attempts = defaults.integer(forKey: Self.pendingDeleteAllKey)
        guard attempts > 0 else { return false }
        isWorking = true
        defer { isWorking = false }
        let report = await runDeleteAll()
        if report.succeeded {
            defaults.removeObject(forKey: Self.pendingDeleteAllKey)
            defaults.removeObject(forKey: Self.unfinishedDeleteAllKey)
            unfinishedSteps = []
        } else if attempts >= Self.maximumResumeAttempts {
            // Out of tries: the marker goes, and what is left is written down where Data management shows it (the preferences step has already run, so it is
            // written after the run).
            defaults.removeObject(forKey: Self.pendingDeleteAllKey)
            unfinishedSteps = report.failures.map(\.id)
            defaults.set(unfinishedSteps.joined(separator: ","), forKey: Self.unfinishedDeleteAllKey)
        } else {
            defaults.set(attempts + 1, forKey: Self.pendingDeleteAllKey)
            unfinishedSteps = report.failures.map(\.id)
        }
        resetDeleteAll()
        return true
    }

    /// Forgets the delete-all's progress (the sheet was closed before it ran).
    public func resetDeleteAll() {
        steps = []
        stepNotes = [:]
        deleteAllReport = nil
    }

    // MARK: Export

    /// The export, written to the temporary folder; it is deleted after the share sheet is done.
    public func exportFile() async throws -> URL {
        let data = try await DataExport.build(inventory: inventory, providers: providers, now: clock(), app: appVersion())
        return try DataExport.write(data, in: roots.url(.temporary))
    }

    /// Removes the export file, and a partial one if a write was cut short.
    public func discardExport() {
        DataExport.remove(in: roots.url(.temporary))
    }
}

// MARK: - Starting the app again

/// Starts the app over with fresh state, as the first launch would: after "Delete all NOCTIS data".
public struct RestartAction {
    public let perform: @MainActor () -> Void

    public init(_ perform: @escaping @MainActor () -> Void) {
        self.perform = perform
    }

    @MainActor public func callAsFunction() { perform() }
}

private struct RestartActionKey: EnvironmentKey {
    static let defaultValue = RestartAction {}
}

extension EnvironmentValues {
    public var restartApp: RestartAction {
        get { self[RestartActionKey.self] }
        set { self[RestartActionKey.self] = newValue }
    }
}
