import Foundation

// The one list of what NOCTIS keeps (APP_RULES.md R41). Every privacy statement the app shows (the Privacy Center, Data
// management, Coach's "How Coach uses your data", Help) is generated from this list, and tests hold the list to the code:
// every SwiftData entity, every defaults key and every file location is in it, and nothing is said to leave the device
// unless the code has a way to make it leave. A statement the list cannot back up does not ship.

/// Where the app's files live.
public nonisolated enum DataDirectory: String, Sendable, CaseIterable {
    case applicationSupport
    case caches
    case documents
    case temporary

    /// The directory on this device.
    public var url: URL {
        switch self {
        case .applicationSupport: URL.applicationSupportDirectory
        case .caches: URL.cachesDirectory
        case .documents: URL.documentsDirectory
        case .temporary: URL.temporaryDirectory
        }
    }
}

/// One place a category's data is kept.
public nonisolated enum DataLocation: Sendable, Equatable {
    /// A file, by its path under `directory`.
    case file(DataDirectory, String)
    /// A folder and everything under it.
    case folder(DataDirectory, String)
    /// A SwiftData store, by the path of its `.store` file; the store's `-wal`, `-shm` and support files belong to it.
    case database(DataDirectory, String)
    /// Keys in the app's `UserDefaults`.
    case defaults([String])
    /// Held by an Apple service, not by NOCTIS: Apple Health, the notification centre, AlarmKit, the App Store.
    case system(String)
    /// Only while the app is running.
    case memory
}

/// Whether a category's data goes anywhere.
public nonisolated enum DataDestination: Sendable, Equatable {
    /// Nowhere: it stays on this iPhone.
    case never
    /// To an Apple service, as a part of what that service is for (the App Store, for a purchase).
    case apple(String)
    /// Only if the person sends it themselves.
    case onlyIfYouSend(String)
    /// To a company that is not Apple. NOCTIS has no such destination: if one is ever added, "Nothing is sold or shared" and
    /// "Your data is stored on this iPhone" stop being said until the inventory is changed on purpose.
    case thirdParty(String)
}

/// What Coach can see of a category: the kinds of facts, never their values.
public nonisolated enum CoachAccess: Sendable, Equatable {
    case none
    /// Plain-words descriptions of the facts it can see (one sentence each).
    case facts([String])

    public var lines: [String] {
        if case .facts(let lines) = self { return lines }
        return []
    }
}

/// How a category's data is protected on disk.
public nonisolated enum DataProtection: Sendable, Equatable {
    /// Unreadable while the iPhone is locked (`NSFileProtectionComplete`).
    case completeWhileLocked
    /// iOS's default: readable once the iPhone has been unlocked after it started.
    case standard
    /// Not on disk at all.
    case notOnDisk
    /// Protected by the Apple service that holds it.
    case appleManaged
}

/// How a category is deleted.
public nonisolated enum DataDeletion: Sendable, Equatable {
    /// Its own button in Data management.
    case button(String)
    /// Only with "Delete all NOCTIS data".
    case withEverything
    /// In an Apple app or service, not in NOCTIS.
    case inApple(String)
    /// By itself, with no action to take.
    case automatic(String)
}

/// Whether a category is in the export file.
public nonisolated enum DataExportRule: Sendable, Equatable {
    /// Under this key in the export.
    case included(String)
    /// Not stored by NOCTIS, so not in the export, and why.
    case notStored(String)
}

public nonisolated enum DataCategoryID: String, Sendable, CaseIterable, Hashable, Codable, Identifiable {
    case appleHealth
    case cachedSummaries
    case insightHistory
    case memorySummaries
    case profile
    case preferences
    case soundSettings
    case appState
    case alarm
    case windDownHistory
    case journal
    case coachHistory
    case reminders
    case diagnosticLog
    case purchases
    case systemFiles
    case exportFile

    public var id: String { rawValue }
}

/// One kind of data: what it is, where it lives, who can see it, and how to get rid of it.
public nonisolated struct DataCategory: Sendable, Identifiable, Equatable {
    public let id: DataCategoryID
    public let name: String
    /// What it is, in a sentence or two.
    public let summary: String
    /// What it holds, one line each.
    public let contents: [String]
    public let locations: [DataLocation]
    /// The SwiftData entities it is made of.
    public let entities: [String]
    /// Identifiers of the notifications it schedules.
    public let notificationIdentifiers: [String]
    public let destination: DataDestination
    public let syncs: Bool
    public let coach: CoachAccess
    public let inBackup: Bool
    public let protection: DataProtection
    public let deletion: DataDeletion
    /// The file that owns it in the code.
    public let owner: String
    /// Something the person wrote, set or chose (as opposed to something worked out from Health, or something Apple holds).
    public let holdsUserContent: Bool
    public let export: DataExportRule

    public init(
        _ id: DataCategoryID, name: String, summary: String, contents: [String], locations: [DataLocation], entities: [String] = [],
        notificationIdentifiers: [String] = [], destination: DataDestination = .never, syncs: Bool = false, coach: CoachAccess = .none,
        inBackup: Bool, protection: DataProtection, deletion: DataDeletion, owner: String, holdsUserContent: Bool, export: DataExportRule
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.contents = contents
        self.locations = locations
        self.entities = entities
        self.notificationIdentifiers = notificationIdentifiers
        self.destination = destination
        self.syncs = syncs
        self.coach = coach
        self.inBackup = inBackup
        self.protection = protection
        self.deletion = deletion
        self.owner = owner
        self.holdsUserContent = holdsUserContent
        self.export = export
    }

    /// Every defaults key it holds.
    public var defaultsKeys: [String] {
        locations.flatMap { location -> [String] in
            if case .defaults(let keys) = location { return keys }
            return []
        }
    }

    /// Whether any of its data is a file or a database on this iPhone.
    public var isOnDisk: Bool {
        locations.contains { location in
            switch location {
            case .file, .folder, .database: true
            case .defaults: true
            case .system, .memory: false
            }
        }
    }
}

/// Something that may leave this iPhone, and what makes it leave.
public nonisolated struct DataFlow: Sendable, Identifiable, Equatable {
    public enum Trigger: Sendable, Equatable {
        /// Only when the person chooses to send or share it.
        case onlyWhenYouChoose
        /// By Apple, not by NOCTIS, if the person uses the Apple service.
        case byApple
    }

    public let id: String
    public let title: String
    public let detail: String
    public let trigger: Trigger
    /// The categories it carries.
    public let categories: [DataCategoryID]
}

/// A use of a system API that can reach a network, and the category it is for. The code is scanned for these.
public nonisolated struct NetworkUse: Sendable, Equatable {
    /// A token that appears in the code of a file that uses the API: `import StoreKit`.
    public let token: String
    /// What it is for, in plain words.
    public let purpose: String
    /// Source files (under `Sources/`) that use it.
    public let files: [String]
    /// The categories it may carry; none for an API that carries nothing of the person's.
    public let categories: [DataCategoryID]
}

/// A set of categories deleted together, with what the confirmation says (APP_RULES.md R37).
public nonisolated struct DeletableGroup: Sendable, Identifiable, Equatable {
    public enum Verb: String, Sendable { case delete = "Delete", reset = "Reset" }

    public let id: String
    public let title: String
    public let verb: Verb
    public let categories: [DataCategoryID]
    /// "Every entry you have written in the Journal."
    public let removes: String
    /// "Your sleep data and the rest of NOCTIS are not affected."
    public let keeps: String
    /// "from this iPhone".
    public let from: String
}

/// Facts about the app that are not about one category; each is held to the code by a test.
public nonisolated struct DataInventoryFacts: Sendable, Equatable {
    public enum HealthAccess: Sendable, Equatable { case readOnly, readWrite }

    public let healthAccess: HealthAccess
    /// Whether the app has an account of any kind (a sign-in, a profile on a server).
    public let hasAccount: Bool
    /// Whether a model that runs off this iPhone can be asked to write Coach's answers.
    public let coachUsesRemoteModel: Bool
    /// What Coach never sees, in words that follow "It never sees".
    public let coachNeverSees: [String]

    public init(healthAccess: HealthAccess, hasAccount: Bool, coachUsesRemoteModel: Bool, coachNeverSees: [String]) {
        self.healthAccess = healthAccess
        self.hasAccount = hasAccount
        self.coachUsesRemoteModel = coachUsesRemoteModel
        self.coachNeverSees = coachNeverSees
    }
}

public nonisolated struct DataInventory: Sendable {
    public let categories: [DataCategory]
    public let flows: [DataFlow]
    public let networkUses: [NetworkUse]
    public let groups: [DeletableGroup]
    /// Defaults keys the code removes without ever writing (older versions' keys).
    public let retiredKeys: [String]
    public let facts: DataInventoryFacts

    public init(
        categories: [DataCategory], flows: [DataFlow], networkUses: [NetworkUse], groups: [DeletableGroup], retiredKeys: [String],
        facts: DataInventoryFacts
    ) {
        self.categories = categories
        self.flows = flows
        self.networkUses = networkUses
        self.groups = groups
        self.retiredKeys = retiredKeys
        self.facts = facts
    }

    public subscript(_ id: DataCategoryID) -> DataCategory {
        guard let category = categories.first(where: { $0.id == id }) else { preconditionFailure("\(id) is not in the inventory") }
        return category
    }

    // MARK: Derived

    public var swiftDataEntities: [String] { categories.flatMap(\.entities) }
    public var defaultsKeys: [String] { categories.flatMap(\.defaultsKeys) + retiredKeys }
    public var notificationIdentifiers: [String] { categories.flatMap(\.notificationIdentifiers) }
    public func categories(in group: DeletableGroup) -> [DataCategory] { group.categories.map { self[$0] } }

    /// Whether anything is said to leave the device by itself (not only if the person sends it).
    public var anythingLeavesByItself: Bool {
        categories.contains { category in
            switch category.destination {
            case .apple, .thirdParty: true
            case .never, .onlyIfYouSend: false
            }
        }
    }

    /// The categories Coach can see something of, in the inventory's order.
    public var coachCategories: [DataCategory] { categories.filter { !$0.coach.lines.isEmpty } }
    public var coachSees: [String] { coachCategories.flatMap { $0.coach.lines } }

    // MARK: Matching files to categories

    /// The category whose location holds the file at `path` (relative to `directory`), if any.
    public func category(forFile path: String, in directory: DataDirectory) -> DataCategoryID? {
        for category in categories {
            for location in category.locations {
                switch location {
                case .file(let dir, let relative) where dir == directory:
                    if path == relative { return category.id }
                case .folder(let dir, let relative) where dir == directory:
                    if path == relative || path.hasPrefix(relative + "/") { return category.id }
                case .database(let dir, let relative) where dir == directory:
                    let name = (relative as NSString).lastPathComponent
                    let folder = (relative as NSString).deletingLastPathComponent
                    let prefix = folder.isEmpty ? "" : folder + "/"
                    // The store, its journal files and its support folder (`.default_SUPPORT` for `default.store`).
                    let base = (name as NSString).deletingPathExtension
                    if path == relative || path.hasPrefix(relative + "-") || path.hasPrefix(prefix + "." + base + "_SUPPORT") { return category.id }
                default: break
                }
            }
        }
        return nil
    }

    /// The files in `paths` that no category owns.
    public func unregistered(files paths: [String], in directory: DataDirectory) -> [String] {
        paths.filter { category(forFile: $0, in: directory) == nil }
    }
}
