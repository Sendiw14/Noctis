import Foundation
import HealthProviding

/// One plain sentence about privacy, and the categories it rests on.
public nonisolated struct PrivacyStatement: Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    /// The categories (and only they) that make it true.
    public let evidence: [DataCategoryID]
}

/// Every privacy statement the app shows is made here, from the inventory (APP_RULES.md R41). A statement is returned only
/// when the inventory backs it: add a category that syncs, or a destination that is a third party, and the statements that
/// would now be false are no longer returned, so no screen can show them.
public nonisolated enum PrivacyStatements {
    // MARK: What the inventory backs

    static func neverSyncs(_ inventory: DataInventory) -> Bool {
        inventory.categories.allSatisfy { !$0.syncs }
    }

    static func hasThirdParty(_ inventory: DataInventory) -> Bool {
        inventory.categories.contains { category in
            if case .thirdParty = category.destination { return true }
            return false
        }
    }

    /// What the person wrote or set stays where it is: nothing that holds it goes anywhere by itself.
    static func userContentStaysOnTheDevice(_ inventory: DataInventory) -> Bool {
        inventory.categories.filter(\.holdsUserContent).allSatisfy { $0.destination == .never }
    }

    /// Whether the code has a tracking, advertising or analytics SDK (the network scan lists every API it finds).
    static func hasTrackingSDK(_ inventory: DataInventory) -> Bool {
        let tokens = ["AdSupport", "AppTrackingTransparency", "ATTrackingManager", "Firebase", "Sentry", "Amplitude", "Mixpanel"]
        return inventory.networkUses.contains { use in tokens.contains { use.token.contains($0) } }
    }

    // MARK: The statements

    /// "NOCTIS reads your sleep and heart data from Apple Health. It never writes to Health."
    public static func healthReadOnly(_ inventory: DataInventory) -> PrivacyStatement? {
        guard inventory.facts.healthAccess == .readOnly else { return nil }
        return PrivacyStatement(id: "healthReadOnly", text: "NOCTIS reads your sleep and heart data from Apple Health. It never writes to Health.", evidence: [.appleHealth])
    }

    /// "Your data is stored on this iPhone."
    public static func storedOnDevice(_ inventory: DataInventory) -> PrivacyStatement? {
        guard neverSyncs(inventory), !hasThirdParty(inventory), userContentStaysOnTheDevice(inventory) else { return nil }
        return PrivacyStatement(
            id: "storedOnDevice", text: "Your data is stored on this iPhone.",
            evidence: inventory.categories.filter { $0.isOnDisk && $0.id != .exportFile }.map(\.id)
        )
    }

    /// "Coach answers are made on your iPhone or built from your data."
    public static func coachLocal(_ inventory: DataInventory) -> PrivacyStatement? {
        guard !inventory.facts.coachUsesRemoteModel else { return nil }
        return PrivacyStatement(id: "coachLocal", text: "Coach answers are made on your iPhone or built from your data.", evidence: [.appleHealth, .insightHistory, .profile])
    }

    /// "Nothing is sold or shared."
    public static func nothingSoldOrShared(_ inventory: DataInventory) -> PrivacyStatement? {
        guard !hasThirdParty(inventory), !hasTrackingSDK(inventory) else { return nil }
        return PrivacyStatement(id: "nothingSoldOrShared", text: "Nothing is sold or shared.", evidence: inventory.categories.map(\.id))
    }

    /// "Nothing syncs between devices."
    public static func noSync(_ inventory: DataInventory) -> PrivacyStatement? {
        guard neverSyncs(inventory) else { return nil }
        return PrivacyStatement(id: "noSync", text: "Nothing syncs between devices.", evidence: inventory.categories.map(\.id))
    }

    /// "NOCTIS has no account, so there is no account to delete."
    public static func noAccount(_ inventory: DataInventory) -> PrivacyStatement? {
        guard !inventory.facts.hasAccount else { return nil }
        return PrivacyStatement(id: "noAccount", text: "NOCTIS has no account, so there is no account to delete.", evidence: [])
    }

    /// The four at the top of the Privacy Center, in order, each only if the inventory backs it.
    public static func headline(_ inventory: DataInventory) -> [PrivacyStatement] {
        [healthReadOnly(inventory), storedOnDevice(inventory), coachLocal(inventory), nothingSoldOrShared(inventory)].compactMap { $0 }
    }

    // MARK: Words built from the inventory

    /// Coach's sheet: the kinds of facts a question can see.
    public static func coachSees(_ inventory: DataInventory) -> [String] { inventory.coachSees }

    /// "It never sees your name, your Apple Account, …, or what you wrote in the Journal."
    public static func coachNeverSees(_ inventory: DataInventory) -> String {
        let items = inventory.facts.coachNeverSees
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return "It never sees \(last)." }
        return "It never sees \(items.dropLast().joined(separator: ", ")), or \(last)."
    }

    /// Where Coach's answers are written, said only as far as the facts allow.
    public static func coachWritten(_ inventory: DataInventory) -> String? {
        guard !inventory.facts.coachUsesRemoteModel else { return nil }
        return "Answers are written on your iPhone by Apple Intelligence when it's available. Otherwise NOCTIS builds them from your data with no model at all. Nothing you ask and nothing about your health is sent to a server."
    }

    /// Coach's sheet: what is kept and how to delete it, from the Coach category.
    public static func coachStored(_ inventory: DataInventory) -> String {
        let category = inventory[.coachHistory]
        var parts = ["Your questions and Coach's answers are kept on this iPhone only."]
        if !category.syncs { parts.append("They aren't synced.") }
        if !category.inBackup { parts.append("They aren't in backups.") }
        if category.protection == .completeWhileLocked { parts.append("They are protected while your iPhone is locked.") }
        parts.append("Delete one conversation, or all of them, from History, or delete the whole history in Data management, in Settings.")
        return parts.joined(separator: " ")
    }

    // MARK: Lines other screens show

    /// "Your name stays on this iPhone." Only where the profile stays put.
    public static func nameStays(_ inventory: DataInventory) -> String? {
        let profile = inventory[.profile]
        guard profile.destination == .never, !profile.syncs else { return nil }
        return "Your name stays on this iPhone."
    }

    /// Onboarding's line under the Health request.
    public static func readOnlyNote(_ inventory: DataInventory) -> String? {
        guard healthReadOnly(inventory) != nil else { return nil }
        return "Read-only. You control access in the Health app at any time."
    }

    /// "How access works", last paragraph: what NOCTIS does with what it reads.
    public static func healthKeeps(_ inventory: DataInventory) -> String? {
        guard healthReadOnly(inventory) != nil else { return nil }
        let onDevice = storedOnDevice(inventory) != nil ? ", on this iPhone" : ""
        return "NOCTIS only reads. It never writes to Health, and it keeps only numbers worked out from it\(onDevice)."
    }

    /// Under the Journal: where it is kept, built from what the inventory says about it.
    public static func journalLine(_ inventory: DataInventory) -> String? {
        let category = inventory[.journal]
        guard category.destination == .never else { return nil }
        var first = "Kept only on this iPhone"
        if category.protection == .completeWhileLocked { first += ", and locked when it is" }
        var rest: [String] = []
        if !category.syncs { rest.append("Not synced") }
        if !category.inBackup { rest.append(rest.isEmpty ? "Not backed up" : "not backed up") }
        if category.coach == .none { rest.append((rest.isEmpty ? "N" : "and n") + "ever used by Coach or your insights") }
        return ([first + "."] + (rest.isEmpty ? [] : [rest.joined(separator: ", ") + "."])).joined(separator: " ")
    }

    /// Coach's empty History.
    public static func coachHistoryKept(_ inventory: DataInventory) -> String? {
        guard inventory[.coachHistory].destination == .never else { return nil }
        return "What you ask Coach, and the answers built from your data, are kept here on this iPhone only."
    }

    /// "Reminders never carry a number from your Health data."
    public static func remindersGeneric(_ inventory: DataInventory) -> String {
        _ = inventory[.reminders]
        return "Reminders never carry a number from your Health data."
    }

    /// When NOCTIS reads Apple Health: when the app is open and, if the inventory says Health wakes it, in the background for new sleep data.
    public static func whenHealthIsRead(_ inventory: DataInventory) -> String {
        inventory.facts.readsHealthInBackground
            ? "It reads Apple Health when you open the app, and in the background when Apple Health has new sleep data (iOS decides when), to keep your widgets up to date."
            : "It reads Apple Health when you open the app."
    }

    // MARK: Help

    /// Help's "Where is my data kept?", built from the inventory.
    public static func helpStorage(_ inventory: DataInventory) -> String {
        var parts: [String] = []
        if let stored = storedOnDevice(inventory) { parts.append(stored.text) }
        if let account = noAccount(inventory) { parts.append(account.text.replacingOccurrences(of: ", so there is no account to delete", with: "")) }
        if nothingSoldOrShared(inventory) != nil { parts.append("It sends your sleep and Health data nowhere.") }
        parts.append("\(whenHealthIsRead(inventory)) It keeps only numbers worked out from it, plus what you set or write.")
        if let sync = noSync(inventory) { parts.append(sync.text) }
        if let backup = inventory.flows.first(where: { $0.id == "deviceBackup" }) { parts.append(backup.detail) }
        parts.append("The Privacy Center, in Settings, lists everything NOCTIS keeps and what each part holds.")
        return parts.joined(separator: " ")
    }

    /// Help's Coach answer: where its answers are written.
    public static func coachShort(_ inventory: DataInventory) -> String {
        inventory.facts.coachUsesRemoteModel
            ? "Answers may be written by a model that runs off your iPhone."
            : "Answers are written on your iPhone, and nothing you ask is sent to a server."
    }

    /// Help's "How do I delete my data?", built from the inventory's own groups.
    public static func helpDelete(_ inventory: DataInventory) -> String {
        let deletes = inventory.groups.filter { $0.verb == .delete }.map(\.title)
        let resets = inventory.groups.filter { $0.verb == .reset }.map { $0.title.lowercased() }
        func list(_ items: [String]) -> String {
            guard let last = items.last else { return "" }
            return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " and " + last
        }
        var parts = ["In Settings, Data management deletes \(list(deletes)), one kind at a time, and resets \(list(resets)). Each asks first and says what it removes."]
        parts.append("\"Delete all NOCTIS data\" removes everything NOCTIS stores on this iPhone and starts the app over. \"Export my data\" makes a copy first, if you want one.")
        if let account = noAccount(inventory) { parts.append(account.text) }
        parts.append("Your health data lives in Apple Health, so to remove it, delete it there. Deleting NOCTIS from your iPhone also removes everything NOCTIS keeps.")
        return parts.joined(separator: " ")
    }

    /// Onboarding's welcome tag: only while the app really keeps data on the iPhone, reads Health without writing, and shares nothing.
    public static func privateByDesign(_ inventory: DataInventory) -> String? {
        guard healthReadOnly(inventory) != nil, storedOnDevice(inventory) != nil, nothingSoldOrShared(inventory) != nil else { return nil }
        return "Private by design"
    }
}

