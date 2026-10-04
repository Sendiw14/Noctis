import Foundation
import NoctisCore
import SwiftData

/// Where the entries are kept and read. Throws (and says nothing about the content) if the store can't
/// be opened, which happens while the phone is locked: the file is protected until it is unlocked.
@MainActor
public protocol JournalStoring: AnyObject {
    /// Newest first.
    func entries() throws -> [JournalEntrySnapshot]
    /// Saves a draft as an entry, or nothing (nil) if the draft is empty.
    func add(_ draft: JournalDraft, at date: Date) throws -> JournalEntrySnapshot?
    /// One entry.
    func delete(id: UUID) throws
    /// Every entry.
    func deleteAll() throws
}

/// The container the journal lives in, apart from the app's other data and from Coach's history.
public enum JournalContainer {
    public static let schema = Schema([JournalEntry.self])

    /// "Noctis/Journal" in Application Support.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Noctis", directoryHint: .isDirectory)
            .appending(path: "Journal", directoryHint: .isDirectory)
    }

    /// With `inMemory`, nothing touches disk (tests, screenshots). Otherwise the store sits in `directory`
    /// with complete file protection, out of backups, and with no CloudKit database: it never leaves the device.
    public static func make(directory: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        let folder = directory ?? defaultDirectory
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete]
        )
        let configuration = ModelConfiguration(
            "Journal", schema: schema, url: folder.appending(path: "journal.store", directoryHint: .notDirectory),
            allowsSave: true, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        protect(folder)
        return container
    }

    /// Complete protection and no backup, on the folder and on every file in it (the database and its
    /// write-ahead log, which only exists once something is written).
    public static func protect(_ folder: URL) {
        let manager = FileManager.default
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = folder
        try? target.setResourceValues(values)
        try? manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: folder.path)
        for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] {
            var file = folder.appending(path: name, directoryHint: .notDirectory)
            try? file.setResourceValues(values)
            try? manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
        }
    }
}

/// Opens the journal's container the first time something needs it, not at launch: a launch in the
/// background while the phone is locked (the store is unreadable then) must not fail or crash, and the
/// journal is only ever wanted when the person is looking at the screen.
public final class JournalContainerProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var opened: ModelContainer?
    private let directory: URL?
    private let inMemory: Bool

    public init(directory: URL? = nil, inMemory: Bool = false) {
        self.directory = directory
        self.inMemory = inMemory
    }

    /// The container, made on first use; throws if it can't be (and tries again next time).
    public func container() throws -> ModelContainer {
        try lock.withLock {
            if let opened { return opened }
            let made = try JournalContainer.make(directory: directory, inMemory: inMemory)
            opened = made
            return made
        }
    }

    /// Re-applies protection after a write, when it is on disk.
    func protect() {
        guard !inMemory else { return }
        JournalContainer.protect(directory ?? JournalContainer.defaultDirectory)
    }
}

/// Reads and writes the entries, for the Reflect screens.
@MainActor
public final class JournalStore: JournalStoring {
    private let provider: JournalContainerProvider
    private var context: ModelContext?

    public init(provider: JournalContainerProvider) {
        self.provider = provider
    }

    private func openContext() throws -> ModelContext {
        if let context { return context }
        let made = ModelContext(try provider.container())
        context = made
        return made
    }

    public func entries() throws -> [JournalEntrySnapshot] {
        let context = try openContext()
        let descriptor = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return try context.fetch(descriptor).map(JournalEntrySnapshot.init)
    }

    public func add(_ draft: JournalDraft, at date: Date = Date()) throws -> JournalEntrySnapshot? {
        let draft = draft.normalized()
        guard !draft.isEmpty else { return nil }
        let context = try openContext()
        let entry = JournalEntry()
        entry.date = date
        entry.energy = draft.energy
        entry.mood = draft.mood
        entry.focus = draft.focus
        entry.text = draft.text
        context.insert(entry)
        try context.save()
        provider.protect()
        return JournalEntrySnapshot(entry)
    }

    public func delete(id: UUID) throws {
        let context = try openContext()
        var descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        for entry in try context.fetch(descriptor) { context.delete(entry) }
        try context.save()
    }

    public func deleteAll() throws {
        try JournalErasure.deleteEverything(in: try openContext())
    }
}

/// Plain memory, for tests and screenshots. Keeps nothing past the process, writes nothing to disk.
@MainActor
public final class MemoryJournalStore: JournalStoring {
    public private(set) var stored: [JournalEntrySnapshot]
    public var failing = false

    public init(_ entries: [JournalEntrySnapshot] = []) {
        stored = entries
    }

    public func entries() throws -> [JournalEntrySnapshot] {
        if failing { throw JournalError.unavailable }
        return stored.sorted { $0.date > $1.date }
    }

    public func add(_ draft: JournalDraft, at date: Date = Date()) throws -> JournalEntrySnapshot? {
        if failing { throw JournalError.unavailable }
        let draft = draft.normalized()
        guard !draft.isEmpty else { return nil }
        let entry = JournalEntrySnapshot(id: UUID(), date: date, energy: draft.energy, mood: draft.mood, focus: draft.focus, text: draft.text)
        stored.append(entry)
        return entry
    }

    public func delete(id: UUID) throws {
        if failing { throw JournalError.unavailable }
        stored.removeAll { $0.id == id }
    }

    public func deleteAll() throws {
        if failing { throw JournalError.unavailable }
        stored.removeAll()
    }
}

public enum JournalError: Error, Equatable {
    /// The store can't be opened right now (the phone is locked, or the disk is full).
    case unavailable
}

/// The journal for Data Management: registered with `NoctisDataRegistry`, so "delete all" reaches it like
/// every other store. It opens the store if it must: what an earlier launch kept has to be reachable.
public struct JournalErasure: NoctisErasable {
    private let provider: JournalContainerProvider

    public init(provider: JournalContainerProvider) {
        self.provider = provider
    }

    public var erasableName: String { "Journal" }

    public func erase() {
        guard let container = try? provider.container() else { return }
        try? Self.deleteEverything(in: ModelContext(container))
        provider.protect()
    }

    static func deleteEverything(in context: ModelContext) throws {
        for entry in try context.fetch(FetchDescriptor<JournalEntry>()) { context.delete(entry) }
        try context.save()
    }
}
