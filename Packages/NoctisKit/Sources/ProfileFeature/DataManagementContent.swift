import Foundation
import NoctisCore

/// The words of Data management: what each confirmation says (APP_RULES.md R37, R42). Everything it says about what is removed comes from the
/// inventory's own groups.
public nonisolated enum DataManagementCopy {
    /// What a confirmation says: what goes, what stays, where it goes from, and that it can't be undone.
    public static func message(for group: DeletableGroup) -> String {
        let end = group.verb == .delete ? "This is deleted from \(group.from) and can't be undone." : "This is reset on \(group.from) and can't be undone."
        return "\(group.removes) \(group.keeps) \(end)"
    }

    public static let exportTitle = "Export my data"
    /// What the file holds, and where it goes (the inventory's own words for the export flow).
    public static func exportNote(_ inventory: DataInventory = .shared) -> String {
        let flow = inventory.flows.first { $0.id == "exportFile" }?.detail ?? ""
        return "\(DataExport.about) \(flow)"
    }

    // MARK: Delete all

    public static let deleteAllTitle = "Delete all NOCTIS data?"
    public static let deleteAllButton = "Delete all NOCTIS data"
    public static let deleteAllConfirm = "Delete everything"
    public static let deleteAllCardText = "Deletes everything NOCTIS stores on this iPhone and starts the app over, as if it were new."

    /// "Everything NOCTIS stores on this iPhone:", and each kind of data by name.
    public static func deleteAllRemoves(_ inventory: DataInventory) -> (lead: String, items: [String]) {
        let items = inventory.categories.compactMap { category -> String? in
            switch category.deletion {
            case .button, .withEverything: category.name
            case .inApple, .automatic: nil
            }
        }
        return ("Everything NOCTIS stores on this iPhone:", items)
    }

    public static let deleteAllKeeps = [
        "Your Apple Health data is untouched.",
        "Your subscription isn't canceled; manage it in Settings.",
    ]
    public static let manageSubscription = "Manage subscription"
    public static let deleteAllClosing = "This can't be undone. NOCTIS starts over at the beginning."

    public static let deleteAllDone = "Everything NOCTIS kept was deleted from this iPhone."
    public static let deleteAllPartial = "Most of it was deleted, but these steps didn't finish:"
    public static let done = "Done"
    public static let cancel = "Cancel"

    /// The line under a row after a deletion: "Journal deleted.", or what went wrong.
    public static func result(_ report: DeletionReport, group: DeletableGroup) -> String {
        report.succeeded
            ? group.done : "\(group.title) couldn't be \(group.verb == .delete ? "deleted" : "reset"): \(report.failures.first?.failure ?? "unknown error")."
    }
}
