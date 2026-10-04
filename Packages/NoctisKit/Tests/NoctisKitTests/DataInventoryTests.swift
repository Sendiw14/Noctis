import Foundation
import SwiftData
import Testing

@testable import CoachKit
@testable import HomeFeature
@testable import InsightsKit
@testable import JournalKit
@testable import NoctisCore

private let inventory = DataInventory.shared

/// The code, for the scans: every Swift file under the package's sources and the app, comments removed.
private nonisolated func sources() -> [(path: String, code: String)] {
    RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App"]).map { ($0.path, RawDefaultsTests.code($0.text)) }
}

private nonisolated func relative(_ path: String) -> String {
    path.replacingOccurrences(of: "Packages/NoctisKit/Sources/", with: "")
}

// MARK: - The list itself

struct DataInventoryShapeTests {
    @Test func everyCategoryIdIsDescribedOnceWithPlainWords() {
        #expect(inventory.categories.map(\.id) == DataCategoryID.allCases, "one entry per id, in the enum's order")
        for category in inventory.categories {
            #expect(!category.name.isEmpty && category.summary.hasSuffix("."), Comment(rawValue: "\(category.id) needs a name and a sentence"))
            #expect(!category.contents.isEmpty && !category.locations.isEmpty && !category.owner.isEmpty, Comment(rawValue: "\(category.id)"))
        }
    }

    @Test func everyOwnerIsAFileInTheCode() {
        let paths = Set(sources().map { relative($0.path) })
        for category in inventory.categories {
            #expect(paths.contains(category.owner), Comment(rawValue: "\(category.id) is owned by \(category.owner), which is not a source file"))
        }
    }

    @Test func aCategoryThatHoldsWhatThePersonWroteOrSetIsInTheExport() {
        for category in inventory.categories where category.holdsUserContent {
            guard case .included = category.export else {
                Issue.record(Comment(rawValue: "\(category.id) holds user content but is not exported"))
                continue
            }
        }
        var keys: [String] = []
        for category in inventory.categories {
            if case .included(let key) = category.export { keys.append(key) }
        }
        #expect(Set(keys).count == keys.count, "export keys are unique")
    }

    @Test func aButtonCategoryHasAGroupOfTheSameName() {
        let titles = Set(inventory.groups.map(\.title))
        for category in inventory.categories {
            if case .button(let title) = category.deletion { #expect(titles.contains(title), Comment(rawValue: "\(category.id): no group named \(title)")) }
        }
        for group in inventory.groups {
            #expect(!group.categories.isEmpty && !group.removes.isEmpty && group.keeps.contains("not affected") || group.keeps.contains("kept") || group.keeps.contains("untouched"))
            for id in group.categories { _ = inventory[id] }
        }
    }

    @Test func aFlowOnlyCarriesCategoriesThatExist() {
        let ids = Set(inventory.categories.map(\.id))
        for flow in inventory.flows {
            #expect(!flow.detail.isEmpty && flow.categories.allSatisfy(ids.contains), Comment(rawValue: flow.id))
        }
    }

    @Test func coachSeesFactsOnlyFromCategoriesThatSayItDoes() {
        let names = Set(inventory.coachCategories.map(\.id))
        #expect(names == [.appleHealth, .insightHistory, .profile])
        #expect(inventory[.journal].coach == .none && inventory[.coachHistory].coach == .none)
        #expect(inventory.coachSees.allSatisfy { $0.hasSuffix(".") })
    }
}

// MARK: - (a) Every SwiftData entity is registered

struct DataInventoryEntityTests {
    /// Every class marked `@Model` in the code.
    nonisolated static func modelClasses() -> Set<String> {
        var names: Set<String> = []
        for file in sources() {
            guard let regex = try? NSRegularExpression(pattern: #"@Model\s*\n\s*(?:public\s+)?(?:final\s+)?class\s+(\w+)"#) else { continue }
            let range = NSRange(file.code.startIndex..., in: file.code)
            for match in regex.matches(in: file.code, range: range) {
                if let name = Range(match.range(at: 1), in: file.code) { names.insert(String(file.code[name])) }
            }
        }
        return names
    }

    @Test func everyModelClassInTheCodeIsInTheInventory() {
        let found = Self.modelClasses()
        #expect(found.count >= 6, "the scan found the models")
        #expect(found == Set(inventory.swiftDataEntities), "models in code: \(found.sorted()), in the inventory: \(inventory.swiftDataEntities.sorted())")
    }

    @Test func theSchemasTheAppOpensHoldOnlyRegisteredEntities() {
        let registered = Set(inventory.swiftDataEntities)
        for schema in [JournalContainer.schema, CoachHistoryContainer.schema] {
            #expect(Set(schema.entities.map(\.name)).isSubset(of: registered))
        }
        #expect(Set(JournalContainer.schema.entities.map(\.name)) == Set(inventory[.journal].entities))
        #expect(Set(CoachHistoryContainer.schema.entities.map(\.name)) == Set(inventory[.coachHistory].entities))
        // The app's own store: the three models AppContainer opens.
        let appStore = Set(["UserProfileRecord", "AlarmConfiguration", "WindDownSession"])
        #expect(appStore.isSubset(of: registered))
        let container = sources().first { relative($0.path) == "AppRoot/AppContainer.swift" }?.code ?? ""
        for name in appStore { #expect(container.contains("\(name).self"), Comment(rawValue: "AppContainer no longer opens \(name)")) }
    }

    @Test func everyStoreIsLocalWithNoCloudKitDatabase() {
        for file in sources() where !file.path.hasSuffix("HomePreviews.swift") {
            var searchRange = file.code.startIndex..<file.code.endIndex
            while let found = file.code.range(of: "ModelConfiguration(", range: searchRange) {
                let call = file.code[found.lowerBound...].prefix(260)
                #expect(call.contains("cloudKitDatabase: .none") || call.contains("isStoredInMemoryOnly: true, cloudKitDatabase"), Comment(rawValue: "\(file.path) opens a store that might sync"))
                searchRange = found.upperBound..<file.code.endIndex
            }
        }
    }
}

// MARK: - (b) Every defaults key is registered

struct DataInventoryKeyTests {
    /// Every `"noctis.…"` string in the code that is not an accessibility identifier.
    nonisolated static func keysInCode() -> [String: [String]] {
        var found: [String: [String]] = [:]
        guard let regex = try? NSRegularExpression(pattern: #""(noctis\.[A-Za-z0-9_.-]+)""#) else { return found }
        for file in sources() where !file.path.hasSuffix("HomePreviews.swift") {
            for line in file.code.split(separator: "\n") where !line.contains("accessibilityIdentifier") {
                let text = String(line)
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let range = Range(match.range(at: 1), in: text) { found[String(text[range]), default: []].append(file.path) }
                }
            }
        }
        return found
    }

    @Test func everyKeyTheCodeNamesIsInTheInventory() {
        let registered = Set(inventory.defaultsKeys + inventory.notificationIdentifiers)
        let found = Self.keysInCode()
        #expect(found.count > 30, "the scan found the keys")
        for (key, files) in found {
            #expect(registered.contains(key), Comment(rawValue: "\(key) (in \(files.first ?? "?")) is not in the inventory"))
        }
    }

    @Test func everyKeyInTheInventoryIsStillInTheCode() {
        let found = Set(Self.keysInCode().keys)
        for key in inventory.defaultsKeys + inventory.notificationIdentifiers {
            #expect(found.contains(key), Comment(rawValue: "\(key) is in the inventory but no code names it"))
        }
    }

    @Test func eachKeyIsInOneCategoryOnly() {
        let all = inventory.defaultsKeys + inventory.notificationIdentifiers
        #expect(Set(all).count == all.count)
    }

    @Test func theTypedPreferencesWrapperKeysAreAllRegistered() throws {
        let wrapper = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisCore/AppPreferences.swift"), encoding: .utf8)
        let keys = Self.keys(in: wrapper)
        #expect(keys.count == 16, "the wrapper has sixteen keys")
        let registered = Set(inventory[.preferences].defaultsKeys)
        #expect(Set(keys) == registered, "wrapper: \(keys.sorted()), inventory: \(registered.sorted())")
    }

    nonisolated static func keys(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"static let \w+ = "(noctis\.[A-Za-z0-9_.-]+)""#) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    @Test func notificationIdentifiersAreTheOnesTheSchedulerOwnsAndTheTrialReminder() {
        let owned = Set(NotificationPlan.identifiers + ["noctis.notification.trialEnding"])
        #expect(Set(inventory[.reminders].notificationIdentifiers) == owned)
    }
}

// MARK: - (c) Every file belongs to a registered place

struct DataInventoryFileTests {
    private func makeRoot() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "noctis-inventory-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func files(under root: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return walker.compactMap { item -> String? in
            guard let url = item as? URL, (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
            return url.path.replacingOccurrences(of: root.path + "/", with: "")
        }
    }

    /// Opens each store the app opens, in a throwaway Application Support, puts something in it, and lists what is on disk.
    @MainActor
    @Test func everyFileTheStoresWriteBelongsToACategory() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // The profile, alarm and wind-down store: SwiftData's default place, `default.store`.
        let appStore = try ModelContainer(
            for: UserProfileRecord.self, AlarmConfiguration.self, WindDownSession.self,
            configurations: ModelConfiguration(url: root.appending(path: "default.store"), cloudKitDatabase: .none)
        )
        let context = ModelContext(appStore)
        context.insert(UserProfileRecord())
        context.insert(AlarmConfiguration())
        context.insert(WindDownSession())
        try context.save()

        // The journal and Coach's history: folders of their own.
        let journal = try JournalContainer.make(directory: root.appending(path: "Noctis/Journal", directoryHint: .isDirectory))
        let journalContext = ModelContext(journal)
        journalContext.insert(JournalEntry())
        try journalContext.save()
        let coach = try CoachHistoryContainer.make(directory: root.appending(path: "Noctis/CoachHistory", directoryHint: .isDirectory))
        let coachContext = ModelContext(coach)
        coachContext.insert(AIConversation())
        try coachContext.save()

        // The two derived files.
        let insights = InsightFileStore(directory: root.appending(path: "Noctis", directoryHint: .isDirectory))
        insights.save(InsightLibrary())
        let snapshot = HomeSnapshotStore(directory: root.appending(path: "Noctis", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: snapshot.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: snapshot.fileURL)

        let written = files(under: root)
        #expect(written.count >= 8, "the stores wrote their files: \(written.sorted())")
        let stray = inventory.unregistered(files: written, in: .applicationSupport)
        #expect(stray.isEmpty, "files no category owns: \(stray.sorted())")
        for path in written {
            #expect(inventory.category(forFile: path, in: .applicationSupport) != nil, Comment(rawValue: path))
        }
        // And each category owns what it should.
        #expect(inventory.category(forFile: "default.store", in: .applicationSupport) != nil)
        #expect(inventory.category(forFile: "Noctis/Journal/journal.store-wal", in: .applicationSupport) == .journal)
        #expect(inventory.category(forFile: "Noctis/CoachHistory/coach-history.store", in: .applicationSupport) == .coachHistory)
        #expect(inventory.category(forFile: "Noctis/insights.json", in: .applicationSupport) == .insightHistory)
        #expect(inventory.category(forFile: "Noctis/home-snapshot.json", in: .applicationSupport) == .cachedSummaries)
        #expect(inventory.category(forFile: "Noctis/notes.txt", in: .applicationSupport) == nil, "an unknown file is not owned")
        #expect(inventory.category(forFile: "anything.db", in: .caches) == nil && inventory.category(forFile: "x", in: .documents) == nil)
    }

    @Test func eachFileStoresOwnPathIsTheOneTheInventoryNames() {
        let root = URL(fileURLWithPath: "/tmp/noctis-paths", isDirectory: true)
        let folder = root.appending(path: "Noctis", directoryHint: .isDirectory)
        #expect(HomeSnapshotStore(directory: folder).fileURL.path == root.path + "/Noctis/home-snapshot.json")
        #expect(InsightFileStore(directory: folder).fileURL.path == root.path + "/Noctis/insights.json")
        let support = URL.applicationSupportDirectory.path + "/"
        #expect(JournalContainer.defaultDirectory.path.replacingOccurrences(of: support, with: "") == "Noctis/Journal")
        #expect(CoachHistoryContainer.defaultDirectory.path.replacingOccurrences(of: support, with: "") == "Noctis/CoachHistory")
        #expect(inventory[.cachedSummaries].locations == [.file(.applicationSupport, "Noctis/home-snapshot.json")])
        #expect(inventory[.insightHistory].locations == [.file(.applicationSupport, "Noctis/insights.json")])
        #expect(inventory[.journal].locations == [.database(.applicationSupport, "Noctis/Journal/journal.store")])
        #expect(inventory[.coachHistory].locations == [.database(.applicationSupport, "Noctis/CoachHistory/coach-history.store")])
    }

    /// The files the app left in its container after a launch with mock data on the simulator (2026-10-04): the real listing,
    /// as a fixture, so the inventory is held to what iOS and the stores really write, not only to what the code intends.
    static let observedApplicationSupport = [
        "default.store", "default.store-wal", "default.store-shm", "Noctis/home-snapshot.json", "Noctis/insights.json",
        "Noctis/CoachHistory/coach-history.store", "Noctis/CoachHistory/coach-history.store-wal", "Noctis/CoachHistory/coach-history.store-shm",
        "Noctis/Journal/journal.store", "Noctis/Journal/journal.store-wal", "Noctis/Journal/journal.store-shm",
    ]
    static let observedCaches = [
        "com.noctis.app/com.apple.metal/libraries.list", "com.noctis.app/com.apple.metal/functions.data",
        "com.noctis.app/com.apple.metal/functions.list", "com.noctis.app/com.apple.metal/libraries.data",
    ]

    @Test func everyFileSeenInARealContainerBelongsToACategory() {
        #expect(inventory.unregistered(files: Self.observedApplicationSupport, in: .applicationSupport).isEmpty)
        #expect(inventory.unregistered(files: Self.observedCaches, in: .caches).isEmpty)
        #expect(inventory.category(forFile: Self.observedCaches[0], in: .caches) == .systemFiles)
        #expect(inventory.category(forFile: "com.other/x", in: .caches) == nil)
    }

    @Test func anExportIsWrittenToTheTemporaryFolderOnly() {
        #expect(inventory[.exportFile].locations == [.file(.temporary, "NOCTIS-export.json")])
        #expect(DataDirectory.allCases.count == 4)
    }

    @Test func sizesAreFileSizesAndASharedStoreIsOneSize() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: support.appending(path: "Noctis"), withIntermediateDirectories: true)
        try Data(count: 2048).write(to: support.appending(path: "Noctis/home-snapshot.json"))
        try Data(count: 4096).write(to: support.appending(path: "default.store"))
        try Data(count: 1024).write(to: support.appending(path: "default.store-wal"))
        let suite = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? NoctisUserDefaults.standard
        suite.set("dark", forKey: "noctis.pref.appearance")
        let roots = DataRoots(directories: [.applicationSupport: support], defaults: suite)

        #expect(inventory.size(of: inventory[.cachedSummaries], roots: roots) == .bytes(2048))
        #expect(inventory.size(of: inventory[.profile], roots: roots) == .shared(5120, with: [.alarm, .windDownHistory]))
        #expect(inventory.size(of: inventory[.alarm], roots: roots) == .shared(5120, with: [.profile, .windDownHistory]))
        #expect(inventory.size(of: inventory[.journal], roots: roots) == .bytes(0), "nothing there yet")
        #expect(inventory.size(of: inventory[.appleHealth], roots: roots) == .notStored)
        #expect(inventory.size(of: inventory[.memorySummaries], roots: roots) == .notStored)
        if case .bytes(let preferences) = inventory.size(of: inventory[.preferences], roots: roots) { #expect(preferences > 0 && preferences < 200) } else { Issue.record("preferences have a size") }
        #expect(inventory.totalBytes(roots: roots) >= 2048 + 5120, "the shared store is counted once")
        #expect(DataInventory.describe(bytes: 0) == "Nothing stored" && DataInventory.describe(bytes: 300) == "Less than 1 KB")
        #expect(DataInventory.describe(bytes: 2048).contains("KB"))
    }
}

// MARK: - (d) Nothing leaves the device unless the code can make it

struct DataInventoryNetworkTests {
    /// APIs that can reach a network, or sync, or sign someone in, or track.
    static let tokens = [
        "URLSession", "URLRequest", "import CloudKit", "CKContainer", "NSUbiquitousKeyValueStore", "NWConnection", "NWPathMonitor", "import Network",
        "WKWebView", "import WebKit", "SFSafariViewController", "import SafariServices", "ASWebAuthenticationSession", "import AuthenticationServices",
        "import AdSupport", "import AppTrackingTransparency", "ATTrackingManager", "import StoreKit", "import MessageUI", "import FirebaseCore",
        "import Sentry", "import Amplitude", "import Mixpanel", "CFNetwork", "import CoreTelephony",
    ]

    @Test func everyUseOfANetworkCapableAPIIsListedInTheInventory() {
        var usedBy: [String: Set<String>] = [:]
        // The inventory names these APIs as strings; that is not a use.
        for file in sources() where !relative(file.path).hasPrefix("NoctisCore/DataInventory") {
            for token in Self.tokens where file.code.contains(token) { usedBy[token, default: []].insert(relative(file.path)) }
        }
        for (token, files) in usedBy {
            let declared = inventory.networkUses.first { $0.token == token }
            #expect(declared != nil, Comment(rawValue: "\(token) is used in \(files.sorted()) and is not in the inventory"))
            if let declared {
                #expect(files == Set(declared.files), Comment(rawValue: "\(token): code uses \(files.sorted()), inventory lists \(declared.files.sorted())"))
            }
        }
        for use in inventory.networkUses {
            #expect(usedBy[use.token] != nil, Comment(rawValue: "\(use.token) is in the inventory but no code uses it"))
        }
    }

    @Test func noCategoryLeavesTheDeviceUnlessAListedAPIOrFlowCarriesIt() {
        for category in inventory.categories {
            switch category.destination {
            case .never: continue
            case .apple:
                #expect(inventory.networkUses.contains { $0.categories.contains(category.id) }, Comment(rawValue: "\(category.id) goes to Apple with no API listed"))
            case .onlyIfYouSend:
                #expect(inventory.flows.contains { $0.trigger == .onlyWhenYouChoose && $0.categories.contains(category.id) }, Comment(rawValue: "\(category.id) is sent by the person, with no flow listed"))
            }
        }
        // And nothing syncs.
        #expect(inventory.categories.allSatisfy { !$0.syncs })
        for use in inventory.networkUses { for id in use.categories { #expect(inventory[id].destination != .never, Comment(rawValue: "\(use.token) carries \(id), which is said to stay")) } }
    }

    @Test func theAppHasNoICloudOrNetworkEntitlements() throws {
        let entitlements = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/Noctis.entitlements"), encoding: .utf8)
        for key in ["com.apple.developer.icloud", "com.apple.developer.ubiquity", "com.apple.security.network", "aps-environment", "com.apple.developer.associated-domains"] {
            #expect(!entitlements.contains(key), Comment(rawValue: "the entitlements hold \(key)"))
        }
        #expect(entitlements.contains("com.apple.developer.healthkit"))
    }

    @Test func healthIsOnlyEverRead() {
        for file in sources() where relative(file.path).hasPrefix("HealthProviding/") {
            #expect(file.code.range(of: #"toShare:\s*\[[^\]]"#, options: .regularExpression) == nil, Comment(rawValue: "\(file.path) asks to share"))
            #expect(!file.code.contains(".save(") && !file.code.contains("saveObject") && !file.code.contains("HKQuantitySample("), Comment(rawValue: "\(file.path) writes to Health"))
            if file.code.contains("toShare:") { #expect(file.code.contains("toShare: []") || file.code.contains("toShare: nil") || file.code.contains("toShare: Set()")) }
        }
        let project = (try? String(contentsOf: RawDefaultsTests.root.appendingPathComponent("project.yml"), encoding: .utf8)) ?? ""
        #expect(project.contains("com.apple.developer.healthkit.access: []"))
        #expect(!project.contains("NSHealthUpdateUsageDescription"), "no permission to write is asked for")
    }

    @Test func thereIsNoAccountAndNoSignIn() {
        for file in sources() {
            for token in ["ASAuthorization", "SignInWith", "Auth0", "import FirebaseAuth"] { #expect(!file.code.contains(token), Comment(rawValue: "\(file.path) has \(token)")) }
        }
    }

    @Test func theOnlyLogIsTheDevicesOwnAndHoldsNoHealthValue() {
        for file in sources() {
            #expect(!file.code.contains("print(\"") || file.path.contains("Debug") || file.path.contains("Probe") || file.code.contains("#if DEBUG"), Comment(rawValue: "\(file.path) prints"))
        }
        let events = NoctisAnalyticsEvent.rawValue("paywall_viewed")
        #expect(events != nil)
    }
}

private extension NoctisAnalyticsEvent {
    static func rawValue(_ value: String) -> NoctisAnalyticsEvent? { NoctisAnalyticsEvent(rawValue: value) }
}
