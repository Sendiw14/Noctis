import Foundation
import Testing

@testable import CoachFeature
@testable import HealthProviding
@testable import NightFeature
@testable import NoctisCore
@testable import ProfileFeature

private let shared = DataInventory.shared

/// The inventory with one thing changed, to see what stops being said.
private func changed(
    categories transform: (DataCategory) -> DataCategory = { $0 }, facts: DataInventoryFacts? = nil, networkUses: [NetworkUse]? = nil
) -> DataInventory {
    DataInventory(
        categories: shared.categories.map(transform), flows: shared.flows, networkUses: networkUses ?? shared.networkUses, groups: shared.groups,
        retiredKeys: shared.retiredKeys, facts: facts ?? shared.facts
    )
}

private func with(_ category: DataCategory, destination: DataDestination? = nil, syncs: Bool? = nil) -> DataCategory {
    DataCategory(
        category.id, name: category.name, summary: category.summary, contents: category.contents, locations: category.locations,
        entities: category.entities, notificationIdentifiers: category.notificationIdentifiers, destination: destination ?? category.destination,
        syncs: syncs ?? category.syncs, coach: category.coach, inBackup: category.inBackup, protection: category.protection, deletion: category.deletion,
        owner: category.owner, holdsUserContent: category.holdsUserContent, export: category.export
    )
}

// MARK: - The statements

struct PrivacyStatementTests {
    @Test func theHeadlineStatementsAreTheOnesThatAreTrue() {
        let texts = PrivacyStatements.headline(shared).map(\.text)
        #expect(texts == [
            "NOCTIS reads your sleep and heart data from Apple Health. It never writes to Health.",
            "Your data is stored on this iPhone.",
            "A summary of your recovery and sleep is sent to your Apple Watch.",
            "Coach answers are made on your iPhone or built from your data.",
            "Nothing is sold or shared.",
        ])
        #expect(PrivacyStatements.noSync(shared)?.text == "Nothing syncs between devices.")
        #expect(PrivacyStatements.noAccount(shared)?.text == "NOCTIS has no account, so there is no account to delete.")
    }

    @Test func aStatementIsWithheldTheMomentTheInventoryCannotBackItUp() {
        // A category that syncs: nothing is "stored on this iPhone" or "never synced" any more.
        let syncing = changed { $0.id == .preferences ? with($0, syncs: true) : $0 }
        #expect(PrivacyStatements.storedOnDevice(syncing) == nil && PrivacyStatements.noSync(syncing) == nil)
        #expect(PrivacyStatements.nothingSoldOrShared(syncing) != nil, "syncing is not selling")

        // What a person wrote goes somewhere: not "stored on this iPhone".
        let leaking = changed { $0.id == .journal ? with($0, destination: .onlyIfYouSend("a friend")) : $0 }
        #expect(PrivacyStatements.storedOnDevice(leaking) == nil)

        // A third party: neither "stored on this iPhone" nor "nothing is sold or shared".
        let sold = changed { $0.id == .insightHistory ? with($0, destination: .thirdParty("an analytics company")) : $0 }
        #expect(PrivacyStatements.storedOnDevice(sold) == nil && PrivacyStatements.nothingSoldOrShared(sold) == nil)
        #expect(PrivacyStatements.headline(sold).map(\.id) == ["healthReadOnly", "coachLocal"])

        // A tracking SDK among the network uses.
        let tracked = changed(networkUses: shared.networkUses + [NetworkUse(token: "import FirebaseCore", purpose: "analytics", files: [], categories: [])])
        #expect(PrivacyStatements.nothingSoldOrShared(tracked) == nil)

        // Facts.
        let facts = shared.facts
        let writes = changed(facts: DataInventoryFacts(healthAccess: .readWrite, hasAccount: facts.hasAccount, coachUsesRemoteModel: false, coachNeverSees: facts.coachNeverSees))
        #expect(PrivacyStatements.healthReadOnly(writes) == nil && PrivacyStatements.readOnlyNote(writes) == nil && PrivacyStatements.healthKeeps(writes) == nil)
        let remote = changed(facts: DataInventoryFacts(healthAccess: .readOnly, hasAccount: false, coachUsesRemoteModel: true, coachNeverSees: facts.coachNeverSees))
        #expect(PrivacyStatements.coachLocal(remote) == nil && PrivacyStatements.coachWritten(remote) == nil)
        #expect(PrivacyStatements.coachShort(remote).contains("off your iPhone"))
        let account = changed(facts: DataInventoryFacts(healthAccess: .readOnly, hasAccount: true, coachUsesRemoteModel: false, coachNeverSees: facts.coachNeverSees))
        #expect(PrivacyStatements.noAccount(account) == nil)
    }

    @Test func theWelcomeTagIsShownOnlyWhileTheInventoryBacksIt() {
        #expect(PrivacyStatements.privateByDesign(shared) == "Private by design")
        let sold = changed { $0.id == .insightHistory ? with($0, destination: .thirdParty("a company")) : $0 }
        #expect(PrivacyStatements.privateByDesign(sold) == nil)
        let syncing = changed { $0.id == .journal ? with($0, syncs: true) : $0 }
        #expect(PrivacyStatements.privateByDesign(syncing) == nil)
    }

    @Test func eachStatementNamesTheCategoriesItRestsOn() {
        let health = PrivacyStatements.healthReadOnly(shared)
        #expect(health?.evidence == [.appleHealth])
        let stored = PrivacyStatements.storedOnDevice(shared)
        #expect(stored?.evidence.contains(.journal) == true && stored?.evidence.contains(.profile) == true)
        #expect(stored?.evidence.contains(.exportFile) == false && stored?.evidence.contains(.appleHealth) == false)
    }

    @Test func theLinesOtherScreensShowComeFromTheInventory() {
        #expect(PrivacyStatements.journalLine(shared) == "Kept only on this iPhone, and locked when it is. Not synced, not backed up, and never used by Coach or your insights.")
        #expect(ReflectCopy.privacyLine == PrivacyStatements.journalLine(shared))
        #expect(CoachHistoryContent.emptyMessage == "What you ask Coach, and the answers built from your data, are kept here on this iPhone only.")
        #expect(PrivacyStatements.nameStays(shared) == "Your name stays on this iPhone.")
        #expect(PrivacyStatements.readOnlyNote(shared) == "Read-only. You control access in the Health app at any time.")
        #expect(PrivacyStatements.healthKeeps(shared) == "NOCTIS only reads. It never writes to Health, and it keeps only numbers worked out from it, on this iPhone.")
        #expect(NotificationsCopy.privacyNote == "Reminders never carry a number from your Health data.")
        #expect(HealthCopy.howAccessWorks.last == PrivacyStatements.healthKeeps(shared))
        // And they go when the inventory stops backing them.
        let syncs = changed { $0.id == .journal ? with($0, syncs: true) : $0 }
        #expect(PrivacyStatements.journalLine(syncs)?.contains("Not synced") == false)
        let out = changed { $0.id == .profile ? with($0, destination: .thirdParty("a server")) : $0 }
        #expect(PrivacyStatements.nameStays(out) == nil)
    }

    @Test func coachsSheetIsWrittenFromTheInventory() {
        #expect(CoachPrivacySheet.sees == shared.coachSees)
        #expect(CoachPrivacySheet.sees.count == 6)
        #expect(CoachPrivacySheet.neverSees == "It never sees your name, your Apple Account, individual Health readings or when they were taken, which app or device recorded them, or what you wrote in the Journal.")
        #expect(CoachPrivacySheet.written?.contains("Nothing you ask and nothing about your health is sent to a server") == true)
        #expect(CoachPrivacySheet.stored.contains("aren't synced") && CoachPrivacySheet.stored.contains("aren't in backups") && CoachPrivacySheet.stored.contains("protected while your iPhone is locked"))
    }

    @Test func helpsPrivacyAnswersAreMadeFromTheInventory() {
        let storage = HelpCatalog.answer("storage")
        #expect(storage.hasPrefix("Your data is stored on this iPhone. NOCTIS has no account."))
        #expect(storage.contains("Nothing syncs between devices.") && storage.contains("Device backups") == false && storage.contains("backup"))
        #expect(!storage.contains("{"))
        let coach = HelpCatalog.answer("coach")
        #expect(!coach.contains("{") && coach.contains("nothing you ask is sent to a server") && coach.contains("It never sees your name"))
        for entry in HelpCatalog.entries { #expect(!entry.answer.contains("{"), Comment(rawValue: entry.key)) }
    }
}

// MARK: - The page

struct PrivacyCenterContentTests {
    private let content = PrivacyCenterBuilder.content(shared)

    @Test func theSectionsAreWhatTheInventorySays() {
        #expect(content.headline.count == 5)
        #expect(content.reads.map(\.title) == HealthDataKind.allCases.map(\.displayName), "one line for each kind NOCTIS reads")
        #expect(content.reads.allSatisfy { $0.detail?.isEmpty == false })
        #expect(content.readsNote?.hasPrefix("NOCTIS only reads.") == true)
        #expect(content.sync == "Nothing syncs between devices.")
        #expect(content.noAccount == "NOCTIS has no account, so there is no account to delete.")
        #expect(content.coachSees == shared.coachSees && content.coachNeverSees.hasPrefix("It never sees your name"))
    }

    @Test func whatStaysIsEveryCategoryThatGoesNowhereAndEachOpensItsPage() {
        let ids = content.stays.compactMap(\.category)
        #expect(!ids.contains(.purchases) && !ids.contains(.exportFile))
        #expect(ids.contains(.journal) && ids.contains(.coachHistory) && ids.contains(.profile) && ids.contains(.appleHealth))
        #expect(content.stays.count == ids.count)
        #expect(content.staysNote.hasPrefix("All of this is stored on this iPhone."))
    }

    @Test func whatMayLeaveIsTheFlowsSplitByWhoMakesItLeave() {
        #expect(content.leavesIfYouSend.map(\.id) == ["supportEmail", "exportFile", "shareCard"])
        #expect(content.leavesThroughApple.map(\.id) == ["appStore", "deviceBackup"])
        #expect(content.leavesToWatch.map(\.id) == ["appleWatch"])
        #expect(content.leavesNote.hasPrefix("NOCTIS sends a summary to your own Apple Watch by itself, and nothing anywhere else."))
        let sold = changed { $0.id == .insightHistory ? with($0, destination: .thirdParty("a company")) : $0 }
        #expect(PrivacyCenterBuilder.content(sold).leavesNote == "Some of your data goes to others. It is listed here.")
    }

    @Test func sizesCoverEveryCategoryOnThisIPhoneAndTheTotalIsTheSumOfWhatIsThere() throws {
        let root = URL.temporaryDirectory.appending(path: "noctis-privacy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "Noctis"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(count: 3000).write(to: root.appending(path: "Noctis/home-snapshot.json"))
        let suite = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? NoctisUserDefaults.standard
        suite.set("dark", forKey: "noctis.pref.appearance")
        let page = PrivacyCenterBuilder.content(shared, roots: DataRoots(directories: [.applicationSupport: root], defaults: suite))
        let ids = Set(page.sizes.compactMap(\.category))
        #expect(ids.contains(.preferences) && ids.contains(.journal) && ids.contains(.cachedSummaries))
        #expect(!ids.contains(.insightHistory), "nothing in a place that holds nothing the person wrote is not listed")
        #expect(!ids.contains(.appleHealth) && !ids.contains(.memorySummaries) && !ids.contains(.reminders), "Apple's or memory only")
        #expect(page.sizes.first { $0.category == .cachedSummaries }?.value == "3 KB" || page.sizes.first { $0.category == .cachedSummaries }?.value?.contains("KB") == true)
        #expect(page.sizes.first { $0.category == .journal }?.value == "Nothing stored", "the Journal says so when it is empty")
        #expect(page.storedTotal.contains("KB"))
        #expect(content.deletable.map(\.title) == ["Journal", "Coach history", "Insights history", "Reviews", "Wind-down history", "Cached summaries", "Preferences and goals", "Files set aside"])
        #expect(content.deleteNote.hasPrefix("Deleting NOCTIS from this iPhone"), "no Data management page yet to point at")
        #expect(PrivacyCenterBuilder.content(shared, dataManagement: true).deleteNote.contains("Data management"))
    }

    @Test func categoriesInOneSharedStoreAreOneRowNotTheSameFigureTwice() throws {
        let root = URL.temporaryDirectory.appending(path: "noctis-privacy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(count: 5000).write(to: root.appending(path: "default.store"))
        let page = PrivacyCenterBuilder.content(shared, roots: DataRoots(directories: [.applicationSupport: root], defaults: NoctisUserDefaults.standard))
        let shares = page.sizes.filter { $0.value?.hasSuffix("shared") == true }
        let values = shares.compactMap(\.value)
        #expect(Set(values).count == values.count || shares.isEmpty, "no two rows print the same shared size")
        let row = try #require(page.sizes.first { $0.title.contains("wind-down history") }, "the shared store's row is there")
        #expect(row.title.hasSuffix("wake alarm and wind-down history"), Comment(rawValue: row.title))
        #expect(!page.sizes.contains { $0.title == "Wind-down history" || $0.title == "Wake alarm" }, "no row of its own for either")
    }

    @Test func everyCategoryHasACompletePage() {
        for category in shared.categories {
            let page = PrivacyCategoryContent.make(category, in: shared)
            #expect(!page.summary.isEmpty && !page.contents.isEmpty && !page.where_.isEmpty, Comment(rawValue: "\(category.id)"))
            #expect(!page.leaves.isEmpty && !page.syncs.isEmpty && !page.backups.isEmpty && !page.protection.isEmpty && !page.size.isEmpty && !page.deletion.isEmpty, Comment(rawValue: "\(category.id)"))
            #expect(page.syncs == "No. It does not sync between devices.")
        }
        let journal = PrivacyCategoryContent.make(shared[.journal], in: shared)
        #expect(journal.leaves == "No. NOCTIS sends it nowhere." && journal.backups == "Not included in backups.")
        #expect(journal.coachNote == "No. Coach cannot see it." && journal.coach.isEmpty)
        #expect(journal.protection == "Unreadable while your iPhone is locked" && journal.groupTitle == "Journal")
        let profile = PrivacyCategoryContent.make(shared[.profile], in: shared)
        #expect(profile.backups.hasPrefix("Included in iPhone backups") && profile.coach.count == 1)
        let health = PrivacyCategoryContent.make(shared[.appleHealth], in: shared)
        #expect(health.backups.hasPrefix("Not applicable") && health.deletion == "In the Health app, not in NOCTIS.")
        let purchases = PrivacyCategoryContent.make(shared[.purchases], in: shared)
        #expect(purchases.leaves == "Only through the App Store, which is Apple's, as part of what it does for you.")
    }
}

// MARK: - Every privacy statement comes from the inventory

nonisolated struct PrivacyWordsComeFromTheInventoryTests {
    /// Where a privacy sentence may be written out: the inventory, and what builds words from it.
    static let allowed: Set<String> = [
        "NoctisCore/DataInventory.swift", "NoctisCore/DataInventory+Shared.swift", "NoctisCore/PrivacyStatements.swift", "NoctisCore/PrivacyCenterContent.swift",
        // The Privacy Center's own headings ("What stays on this iPhone"); every sentence under them comes from `PrivacyCenterContent`.
        "ProfileFeature/PrivacyViews.swift",
    ]
    static let phrases = [
        "never sent", "never sends", "stays on this", "stay on this", "kept only on this", "kept on this iphone", "only on this iphone", "on this iphone only",
        "not synced", "aren't synced", "isn't synced", "never writes", "read-only", "no account", "sent to a server", "never leaves", "nothing is sold",
        "never shared", "not backed up", "aren't in backups", "stored on this iphone", "private by design",
    ]

    @Test func noScreenWritesAPrivacyClaimOfItsOwn() {
        var checked = 0
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources"]) {
            let path = file.path.replacingOccurrences(of: "Packages/NoctisKit/Sources/", with: "")
            guard !Self.allowed.contains(path) else { continue }
            checked += 1
            // Only strings count: a claim in a comment is not shown to anyone.
            let strings = RawDefaultsTests.code(file.text).split(separator: "\n").filter { $0.contains("\"") }.joined(separator: "\n").lowercased()
            for phrase in Self.phrases {
                #expect(!strings.contains(phrase), Comment(rawValue: "\(path) says \"\(phrase)\" instead of taking it from the inventory"))
            }
        }
        #expect(checked > 150)
    }

    @Test func theCatalogsHoldNoPrivacyClaimsEither() throws {
        for path in ["Packages/NoctisKit/Sources/ProfileFeature/Resources/Help.xcstrings"] {
            let text = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent(path), encoding: .utf8).lowercased()
            // Help's storage answer is a stub; the rest may talk about the models and the app, not about where data goes.
            for phrase in ["sent to a server", "never leaves", "not synced", "stays on this"] { #expect(!text.contains(phrase), Comment(rawValue: "Help.xcstrings says \"\(phrase)\"")) }
        }
    }
}
