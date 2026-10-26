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

    public init(
        inventory: DataInventory = .shared, roots: DataRoots = DataRoots(), erasers: [DataCategoryID: Eraser],
        providers: [DataCategoryID: DataExport.Provider], deleteAllSteps: [DeleteStep], appVersion: @escaping () -> String = { "NOCTIS" },
        clock: @escaping () -> Date = { Date() }
    ) {
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
        return report
    }

    // MARK: Everything

    /// Deletes everything NOCTIS stores on this iPhone, in order. The caller then starts the app again (`restart`).
    public func deleteEverything() async -> DeletionReport {
        isWorking = true
        defer { isWorking = false }
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
        let url = roots.url(.temporary).appending(path: DataExport.fileName, directoryHint: .notDirectory)
        try data.write(to: url, options: [.atomic])
        return url
    }

    /// Removes the export file.
    public func discardExport() {
        try? FileManager.default.removeItem(at: roots.url(.temporary).appending(path: DataExport.fileName, directoryHint: .notDirectory))
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
