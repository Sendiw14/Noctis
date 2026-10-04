import Foundation
import HealthProviding

/// The Privacy Center's words, all of them made from the inventory (APP_RULES.md R41): the sections, and one category's page.
public nonisolated struct PrivacyCenterContent: Sendable, Equatable {
    public struct Line: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String?
        public let value: String?
        /// The category whose page this line opens.
        public let category: DataCategoryID?
    }

    public let headline: [PrivacyStatement]
    /// One line per kind of Health data NOCTIS reads, and why.
    public let reads: [Line]
    /// "It only reads…", when that is true.
    public let readsNote: String?
    public let stays: [Line]
    public let staysNote: String
    /// What happens through Apple, when the person uses an Apple service.
    public let leavesThroughApple: [Line]
    /// What leaves only if the person sends it.
    public let leavesIfYouSend: [Line]
    public let leavesNote: String
    public let coachSees: [String]
    public let coachNeverSees: String
    public let sync: String
    public let storedTotal: String
    public let sizes: [Line]
    public let deleteNote: String
    public let deletable: [Line]
    public let noAccount: String?
}

public nonisolated enum PrivacyCenterBuilder {
    /// `dataManagement`: whether the app has a Data management page to point at.
    public static func content(_ inventory: DataInventory, roots: DataRoots = DataRoots(), dataManagement: Bool = false) -> PrivacyCenterContent {
        let reads = HealthDataKind.allCases.map { PrivacyCenterContent.Line(id: $0.rawValue, title: $0.displayName, detail: $0.benefit, value: nil, category: nil) }
        let stays = inventory.categories.filter { $0.destination == .never }.map { category in
            PrivacyCenterContent.Line(id: category.id.rawValue, title: category.name, detail: protectionLine(category), value: nil, category: category.id)
        }
        let byApple = inventory.flows.filter { $0.trigger == .byApple }.map(line(for:))
        let ifYouSend = inventory.flows.filter { $0.trigger == .onlyWhenYouChoose }.map(line(for:))
        let sizes = inventory.categories.compactMap { category -> PrivacyCenterContent.Line? in
            let size = inventory.size(of: category, roots: roots)
            guard size != .notStored else { return nil }
            // Nothing in a place that holds nothing the person wrote is not worth a line.
            if size == .bytes(0), !category.holdsUserContent { return nil }
            return PrivacyCenterContent.Line(id: category.id.rawValue, title: category.name, detail: nil, value: sizeText(size), category: category.id)
        }
        let deletable = inventory.groups.map { group in
            PrivacyCenterContent.Line(id: group.id, title: group.title, detail: nil, value: group.verb.rawValue, category: group.categories.first)
        }
        return PrivacyCenterContent(
            headline: PrivacyStatements.headline(inventory),
            reads: reads,
            readsNote: PrivacyStatements.healthReadOnly(inventory) == nil
                ? nil
                : "NOCTIS only reads. It keeps no copy of these readings: only numbers worked out from them, which are listed below. \(PrivacyStatements.whenHealthIsRead(inventory))",
            stays: stays,
            staysNote: PrivacyStatements.storedOnDevice(inventory) == nil
                ? "Here is everything NOCTIS keeps, and where."
                : "All of this is stored on this iPhone. Tap a kind of data to see what it holds and how to delete it.",
            leavesThroughApple: byApple,
            leavesIfYouSend: ifYouSend,
            leavesNote: leavesNote(inventory),
            coachSees: PrivacyStatements.coachSees(inventory),
            coachNeverSees: PrivacyStatements.coachNeverSees(inventory),
            sync: PrivacyStatements.noSync(inventory)?.text ?? "Some of your data syncs between devices. See each kind of data for which.",
            storedTotal: DataInventory.describe(bytes: inventory.totalBytes(roots: roots)),
            sizes: sizes,
            deleteNote: dataManagement
                ? "Everything NOCTIS keeps on this iPhone can be deleted, one kind at a time or all at once, in Data management."
                : "Deleting NOCTIS from this iPhone removes everything it keeps, apart from what iOS and Apple's backups hold.",
            deletable: deletable,
            noAccount: PrivacyStatements.noAccount(inventory)?.text
        )
    }

    static func line(for flow: DataFlow) -> PrivacyCenterContent.Line {
        PrivacyCenterContent.Line(id: flow.id, title: flow.title, detail: flow.detail, value: nil, category: flow.categories.first)
    }

    static func leavesNote(_ inventory: DataInventory) -> String {
        if inventory.flows.isEmpty { return "Nothing leaves this iPhone." }
        if PrivacyStatements.nothingSoldOrShared(inventory) == nil { return "Some of your data goes to others. It is listed here." }
        return "NOCTIS sends nothing anywhere by itself. This is everything that can leave, and what makes it leave."
    }

    static func protectionLine(_ category: DataCategory) -> String {
        var parts: [String] = []
        switch category.protection {
        case .completeWhileLocked: parts.append("Unreadable while your iPhone is locked")
        case .standard: parts.append("Readable after first unlock")
        case .notOnDisk: parts.append("Never written to disk")
        case .appleManaged: parts.append("Kept by Apple")
        }
        if category.isOnDisk { parts.append(category.inBackup ? "In backups" : "Not in backups") }
        return parts.joined(separator: "\n")
    }

    static func sizeText(_ size: DataSize) -> String {
        switch size {
        case .bytes(let bytes): DataInventory.describe(bytes: bytes)
        case .shared(let bytes, _): "\(DataInventory.describe(bytes: bytes)), shared"
        case .notStored: "Not stored by NOCTIS"
        }
    }
}

/// One category's page, as words.
public nonisolated struct PrivacyCategoryContent: Sendable, Equatable {
    public let id: DataCategoryID
    public let name: String
    public let summary: String
    public let contents: [String]
    public let where_: [String]
    public let leaves: String
    public let syncs: String
    public let coach: [String]
    public let coachNote: String
    public let backups: String
    public let protection: String
    public let size: String
    public let deletion: String
    /// The Data management group that deletes it, if it has its own button.
    public let groupTitle: String?

    public static func make(_ category: DataCategory, in inventory: DataInventory, roots: DataRoots = DataRoots()) -> PrivacyCategoryContent {
        PrivacyCategoryContent(
            id: category.id, name: category.name, summary: category.summary, contents: category.contents,
            where_: category.locations.map(describe(_:)), leaves: leaves(category.destination),
            syncs: category.syncs ? "Yes: it syncs between your devices." : "No. It does not sync between devices.",
            coach: category.coach.lines,
            coachNote: category.coach.lines.isEmpty ? "No. Coach cannot see it." : "Coach can see these kinds of facts, never the readings themselves:",
            backups: backups(category), protection: PrivacyCenterBuilder.protectionLine(category).components(separatedBy: "\n").first ?? "",
            size: PrivacyCenterBuilder.sizeText(inventory.size(of: category, roots: roots)),
            deletion: deletion(category.deletion),
            groupTitle: { if case .button(let title) = category.deletion { return title } else { return nil } }()
        )
    }

    static func describe(_ location: DataLocation) -> String {
        switch location {
        case .file(_, let path): "A file on this iPhone: \(path)"
        case .folder(_, let path): "Files on this iPhone, in the folder \(path)"
        case .database(_, let path): "A database on this iPhone: \(path)"
        case .defaults(let keys): "Settings saved on this iPhone (\(keys.count) \(keys.count == 1 ? "value" : "values"))"
        case .system(let name): "Held by \(name), not by NOCTIS"
        case .memory: "Only in memory while the app is open"
        }
    }

    static func leaves(_ destination: DataDestination) -> String {
        switch destination {
        case .never: "No. NOCTIS sends it nowhere."
        case .apple(let service): "Only through \(service), which is Apple's, as part of what it does for you."
        case .onlyIfYouSend(let where_): "Only if you send it: \(where_)."
        case .thirdParty(let who): "Yes, to \(who)."
        }
    }

    static func backups(_ category: DataCategory) -> String {
        guard category.isOnDisk else { return "Not applicable: NOCTIS keeps nothing of it on this iPhone." }
        return category.inBackup
            ? "Included in iPhone backups made with iCloud or a computer, if you make them."
            : "Not included in backups."
    }

    static func deletion(_ deletion: DataDeletion) -> String {
        switch deletion {
        case .button(let title): "In Data management: \(title)."
        case .withEverything: "With \"Delete all NOCTIS data\" in Data management."
        case .inApple(let where_): "In \(where_), not in NOCTIS."
        case .automatic(let how): how
        }
    }
}
