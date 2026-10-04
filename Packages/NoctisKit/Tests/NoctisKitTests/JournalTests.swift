import Foundation
import SwiftData
import Testing

@testable import CoachKit
@testable import JournalKit
@testable import NightFeature
@testable import NoctisCore

// Reflect and the Journal (APP_RULES.md R35): the draft's rules, the store (local, protected, out of
// backups, erasable), the view model, and the guards that keep the journal away from everything else.

nonisolated struct JournalDraftTests {
    @Test func aDraftWithNothingInItIsEmpty() {
        #expect(JournalDraft().isEmpty)
        #expect(JournalDraft(text: "   \n  ").isEmpty, "only blanks is nothing")
        #expect(JournalDraft(energy: 9).isEmpty, "out of range is nothing")
        #expect(!JournalDraft(energy: 1).isEmpty)
        #expect(!JournalDraft(text: "hello").isEmpty)
    }

    @Test func valuesStayInsideOneToFiveAndTextIsTrimmedAndCut() {
        let draft = JournalDraft(energy: 0, mood: 6, focus: 5, text: "  hello  \n").normalized()
        #expect(draft.energy == nil && draft.mood == nil && draft.focus == 5)
        #expect(draft.text == "hello")
        let long = JournalDraft(text: String(repeating: "a", count: 5_000)).normalized()
        #expect(long.text.count == JournalDraft.maxTextLength)
        #expect(JournalDraft.valueRange == 1...5)
    }

    @Test func aValueIsSetAndReadByItsMeasure() {
        var draft = JournalDraft()
        for (index, measure) in JournalMeasure.allCases.enumerated() { draft.set(index + 2, for: measure) }
        #expect(draft.energy == 2 && draft.mood == 3 && draft.focus == 4)
        #expect(JournalMeasure.allCases.map(\.title) == ["Energy", "Mood", "Focus"])
        draft.set(nil, for: .mood)
        #expect(draft.value(.mood) == nil)
    }

    @Test func aSnapshotListsOnlyTheValuesThatWereSet() {
        let entry = JournalEntrySnapshot(id: UUID(), date: Date(), energy: 3, mood: nil, focus: 5, text: "")
        #expect(entry.values.map(\.measure) == [.energy, .focus] && entry.values.map(\.value) == [3, 5])
        #expect(ReflectCopy.valuesLine(entry) == "Energy 3 · Focus 5")
        #expect(ReflectCopy.spokenValuesLine(entry) == "Energy 3 of 5, Focus 5 of 5")
        let none = JournalEntrySnapshot(id: UUID(), date: Date(), energy: nil, mood: nil, focus: nil, text: "x")
        #expect(ReflectCopy.valuesLine(none) == nil)
    }
}

@MainActor
struct JournalStoreTests {
    static func folder() -> URL {
        URL.temporaryDirectory.appending(path: "journal-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    static func store(_ folder: URL) -> JournalStore {
        JournalStore(provider: JournalContainerProvider(directory: folder))
    }

    @Test func anEntryIsSavedWithItsValuesAndWordsAndListedNewestFirst() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Self.store(folder)
        let early = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try store.add(JournalDraft(energy: 2, text: "first"), at: early)
        _ = try store.add(JournalDraft(energy: 4, mood: 5, focus: 1, text: "  second  "), at: early.addingTimeInterval(86_400))
        let entries = try store.entries()
        #expect(entries.map(\.text) == ["second", "first"])
        #expect(entries[0].energy == 4 && entries[0].mood == 5 && entries[0].focus == 1 && entries[0].date == early.addingTimeInterval(86_400))
        #expect(entries[1].mood == nil && entries[1].focus == nil)
    }

    @Test func anEmptyDraftIsNeverSaved() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Self.store(folder)
        #expect(try store.add(JournalDraft(), at: Date()) == nil)
        #expect(try store.add(JournalDraft(text: "  "), at: Date()) == nil)
        #expect(try store.entries().isEmpty)
    }

    @Test func oneEntryCanBeDeletedAndTheOthersStay() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Self.store(folder)
        let a = try #require(try store.add(JournalDraft(text: "a"), at: Date(timeIntervalSince1970: 1_000)))
        _ = try store.add(JournalDraft(text: "b"), at: Date(timeIntervalSince1970: 2_000))
        try store.delete(id: a.id)
        #expect(try store.entries().map(\.text) == ["b"])
        try store.delete(id: UUID())
        #expect(try store.entries().count == 1, "deleting what is not there changes nothing")
    }

    @Test func deleteAllRemovesEveryEntry() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Self.store(folder)
        for i in 0..<5 { _ = try store.add(JournalDraft(mood: 3, text: "n\(i)"), at: Date(timeIntervalSince1970: Double(i))) }
        try store.deleteAll()
        #expect(try store.entries().isEmpty)
        _ = try store.add(JournalDraft(text: "after"), at: Date())
        #expect(try store.entries().map(\.text) == ["after"], "and it works again")
    }

    @Test func whatIsSavedIsThereWhenTheStoreIsOpenedAgain() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let store = Self.store(folder)
            _ = try store.add(JournalDraft(energy: 3, text: "kept"), at: Date(timeIntervalSince1970: 5))
        }
        let again = Self.store(folder)
        #expect(try again.entries().map(\.text) == ["kept"])
    }

    @Test func theStoreIsLocalOnlyProtectedAndOutOfBackups() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try JournalContainer.make(directory: folder)
        let configuration = try #require(container.configurations.first)
        #expect(String(describing: configuration.cloudKitDatabase) == String(describing: ModelConfiguration.CloudKitDatabase.none), "never synced")
        #expect(String(describing: configuration.cloudKitDatabase) != String(describing: ModelConfiguration.CloudKitDatabase.automatic))
        #expect(configuration.url.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path)

        let context = ModelContext(container)
        let entry = JournalEntry()
        entry.text = "private"
        context.insert(entry)
        try context.save()
        JournalContainer.protect(folder)

        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isExcludedFromBackupKey])
        #expect(!files.isEmpty)
        for file in files {
            #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, Comment(rawValue: file.lastPathComponent))
            // Complete protection, where the platform reports it (the simulator doesn't always).
            let protection = try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType
            if let protection { #expect(protection == .complete, Comment(rawValue: file.lastPathComponent)) }
        }
        let folderProtection = try FileManager.default.attributesOfItem(atPath: folder.path)[.protectionKey] as? FileProtectionType
        if let folderProtection { #expect(folderProtection == .complete) }
    }

    @Test func writingKeepsTheNewFilesProtectedToo() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Self.store(folder)
        _ = try store.add(JournalDraft(text: "one"), at: Date())
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isExcludedFromBackupKey])
        #expect(files.count >= 1)
        for file in files {
            #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, Comment(rawValue: file.lastPathComponent))
        }
    }

    @Test func theSchemaHoldsOnlyTheJournalEntry() {
        #expect(JournalContainer.schema.entities.map(\.name) == ["JournalEntry"])
    }

    @Test func theContainerIsOpenedOnFirstUseNotBefore() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = JournalContainerProvider(directory: folder)
        let store = JournalStore(provider: provider)
        #expect(!FileManager.default.fileExists(atPath: folder.path), "nothing is made at launch")
        _ = try store.entries()
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func aStoreThatCannotBeOpenedThrowsAndTriesAgainNextTime() throws {
        // A file where the folder should be: the store cannot be made.
        let blocker = URL.temporaryDirectory.appending(path: "journal-blocker-\(UUID().uuidString)", directoryHint: .notDirectory)
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let provider = JournalContainerProvider(directory: blocker.appending(path: "inside", directoryHint: .isDirectory))
        let store = JournalStore(provider: provider)
        #expect(throws: (any Error).self) { try store.entries() }
        #expect(throws: (any Error).self) { try store.add(JournalDraft(text: "x"), at: Date()) }
    }

    @Test func dataManagementErasesTheJournalThroughTheRegistry() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = JournalContainerProvider(directory: folder)
        let store = JournalStore(provider: provider)
        _ = try store.add(JournalDraft(text: "a"), at: Date(timeIntervalSince1970: 1))
        _ = try store.add(JournalDraft(text: "b"), at: Date(timeIntervalSince1970: 2))
        let erasure = JournalErasure(provider: provider)
        #expect(erasure.erasableName == "Journal")
        let registry = NoctisDataRegistry()
        registry.register(erasure)
        #expect(registry.stores.map(\.erasableName) == ["Journal"])
        registry.eraseAll()
        #expect(try store.entries().isEmpty)
        registry.eraseAll()
        #expect(try store.entries().isEmpty, "erasing twice is harmless")
    }

    @Test func theMemoryStoreBehavesLikeTheRealOne() throws {
        let store = MemoryJournalStore()
        #expect(try store.add(JournalDraft(), at: Date()) == nil)
        let a = try #require(try store.add(JournalDraft(energy: 9, mood: 4, text: " a "), at: Date(timeIntervalSince1970: 1)))
        _ = try store.add(JournalDraft(text: "b"), at: Date(timeIntervalSince1970: 2))
        #expect(a.energy == nil && a.mood == 4 && a.text == "a")
        #expect(try store.entries().map(\.text) == ["b", "a"])
        try store.delete(id: a.id)
        #expect(try store.entries().map(\.text) == ["b"])
        try store.deleteAll()
        #expect(try store.entries().isEmpty)
        store.failing = true
        #expect(throws: JournalError.unavailable) { try store.entries() }
    }
}

@MainActor
struct JournalViewModelTests {
    final class Log {
        var announcements: [String] = []
    }

    static func make(entries: [JournalEntrySnapshot] = [], now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> (JournalViewModel, MemoryJournalStore, Log) {
        let store = MemoryJournalStore(entries)
        let log = Log()
        let model = JournalViewModel(store: store, now: { now }, announce: { log.announcements.append($0) })
        return (model, store, log)
    }

    @Test func startsEmptyAndCannotSaveNothing() {
        let (model, store, _) = Self.make()
        #expect(model.draft.isEmpty && !model.canSave && !model.showsJournal && model.entries.isEmpty)
        #expect(!model.save())
        #expect(store.stored.isEmpty)
    }

    @Test func aTapSetsAStepAndATapOnTheSameStepClearsIt() {
        let (model, _, _) = Self.make()
        model.choose(4, for: .mood)
        #expect(model.draft.mood == 4 && model.canSave)
        model.choose(2, for: .mood)
        #expect(model.draft.mood == 2)
        model.choose(2, for: .mood)
        #expect(model.draft.mood == nil && !model.canSave)
        model.choose(0, for: .energy)
        model.choose(6, for: .energy)
        #expect(model.draft.energy == nil, "only 1 to 5")
    }

    @Test func voiceOverStepsFromTheMiddleAndStaysInsideTheScale() {
        let (model, _, _) = Self.make()
        model.step(.focus, by: 1)
        #expect(model.draft.focus == 3)
        model.step(.focus, by: 1); model.step(.focus, by: 1); model.step(.focus, by: 1)
        #expect(model.draft.focus == 5)
        model.step(.focus, by: -1)
        #expect(model.draft.focus == 4)
        for _ in 0..<10 { model.step(.focus, by: -1) }
        #expect(model.draft.focus == 1)
        model.clear(.focus)
        #expect(model.draft.focus == nil)
        model.step(.energy, by: -1)
        #expect(model.draft.energy == 3, "from nothing the first step is the middle either way")
    }

    @Test func anyOneThingIsEnoughToSave() {
        let (a, storeA, _) = Self.make()
        a.choose(3, for: .energy)
        #expect(a.save() && storeA.stored.count == 1)
        let (b, storeB, _) = Self.make()
        b.draft.text = "just words"
        #expect(b.save() && storeB.stored.first?.text == "just words")
        let (c, _, _) = Self.make()
        c.draft.text = "   \n "
        #expect(!c.canSave)
    }

    @Test func savingStoresAtTheMomentClearsTheDraftAndAnnouncesIt() {
        let moment = Date(timeIntervalSince1970: 1_900_000_000)
        let (model, store, log) = Self.make(now: moment)
        model.choose(5, for: .mood)
        model.draft.text = "good"
        #expect(model.save())
        #expect(store.stored.first?.date == moment && store.stored.first?.mood == 5 && store.stored.first?.text == "good")
        #expect(model.draft.isEmpty)
        #expect(log.announcements == ["Saved"])
    }

    @Test func aStoreThatCannotBeOpenedKeepsWhatWasTypedAndSaysSoQuietly() {
        let (model, store, log) = Self.make()
        store.failing = true
        model.draft.text = "important"
        model.choose(2, for: .energy)
        #expect(!model.save())
        #expect(model.availability == .unavailable)
        #expect(model.draft.text == "important" && model.draft.energy == 2, "nothing written is lost to a locked phone")
        #expect(log.announcements.isEmpty)
        store.failing = false
        #expect(model.save() && model.availability == .ready && store.stored.count == 1)
    }

    @Test func theNoteIsKeptInsideItsLimit() {
        let (model, _, _) = Self.make()
        model.draft.text = String(repeating: "b", count: 1_500)
        model.limitText()
        #expect(model.draft.text.count == JournalDraft.maxTextLength)
    }

    @Test func leavingForgetsTheDraftTheListAndTheOpenJournal() {
        let (model, store, _) = Self.make(entries: [JournalEntrySnapshot(id: UUID(), date: Date(), energy: 1, mood: nil, focus: nil, text: "x")])
        model.draft.text = "not saved"
        model.openJournal()
        #expect(model.showsJournal && model.entries.count == 1)
        model.leave()
        #expect(model.draft.isEmpty && !model.showsJournal && model.entries.isEmpty)
        #expect(store.stored.count == 1, "skipping saves nothing, and nothing else changes")
    }

    @Test func theJournalListsNewestFirstAndDeletesOneOrAll() {
        let entries = (0..<4).map {
            JournalEntrySnapshot(id: UUID(), date: Date(timeIntervalSince1970: Double($0) * 1_000), energy: nil, mood: $0 + 1, focus: nil, text: "e\($0)")
        }
        let (model, store, _) = Self.make(entries: entries)
        model.openJournal()
        #expect(model.entries.map(\.text) == ["e3", "e2", "e1", "e0"])
        model.delete(entries[2].id)
        #expect(model.entries.map(\.text) == ["e3", "e1", "e0"] && store.stored.count == 3)
        model.deleteAll()
        #expect(model.entries.isEmpty && store.stored.isEmpty)
        model.closeJournal()
        #expect(!model.showsJournal)
    }

    @Test func aJournalThatCannotBeOpenedShowsNothingAndSaysSo() {
        let (model, store, _) = Self.make(entries: [JournalEntrySnapshot(id: UUID(), date: Date(), energy: 1, mood: nil, focus: nil, text: "x")])
        store.failing = true
        model.openJournal()
        #expect(model.entries.isEmpty && model.availability == .unavailable)
        store.failing = false
        model.load()
        #expect(model.entries.count == 1 && model.availability == .ready)
    }

    @Test func theWordsNeverCountScoreOrScold() {
        let words = [
            ReflectCopy.title, ReflectCopy.line, ReflectCopy.notePrompt, ReflectCopy.save, ReflectCopy.skip, ReflectCopy.journal, ReflectCopy.privacyLine,
            ReflectCopy.emptyTitle, ReflectCopy.emptyLine, ReflectCopy.unavailable, ReflectCopy.deleteAllMessage, ReflectCopy.deleteAllTitle,
        ].joined(separator: " ").lowercased()
        for banned in ["streak", "score", "in a row", "missed", "forgot", "haven't", "fail", "behind", "should", "must", "goal", "correlat", "compared"] {
            #expect(!words.contains(banned), Comment(rawValue: "the Reflect copy says \"\(banned)\""))
        }
        #expect(ReflectCopy.line.contains("optional"))
        #expect(ReflectCopy.deleteAllMessage.contains("It can't be undone"))
        #expect(ReflectCopy.deleteAllMessage.contains("not affected"), "it says what is not deleted too")
    }
}

// MARK: - Kept away from everything else

/// The journal is its own target; only the Reflect screens and the app's wiring may know it exists. Nothing
/// that reads sleep, recovery, insights, Coach or analytics, and nothing that draws a share card, can see it.
nonisolated struct JournalPrivacyTests {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var sources: URL { packageRoot.appendingPathComponent("Sources") }

    /// Every Swift file under Sources, with its path from there.
    static func sourceFiles() -> [(path: String, text: String)] {
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { return [] }
        var result: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                result.append((url.path.replacingOccurrences(of: sources.path + "/", with: ""), text))
            }
        }
        return result
    }

    /// The code of a file: no comment lines and no trailing comments.
    static func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { return "" }
            if let range = line.range(of: " //") { return String(line[..<range.lowerBound]) }
            return String(line)
        }.joined(separator: "\n")
    }

    /// The data inventory (APP_RULES.md R41) describes every store, the Journal's included, so it names it, in strings:
    /// the category's words, its entity and its owner. It holds no entry and has no way to read one: only the target's
    /// dependencies decide that, and `onlyTheReflectScreensAndTheAppDependOnTheJournalTarget` still holds them.
    static let catalogue: Set<String> = ["NoctisCore/DataInventory+Shared.swift"]

    static func journalFiles(_ path: String) -> Bool {
        path.hasPrefix("JournalKit/") || path.hasPrefix("NightFeature/Journal") || path.hasPrefix("NightFeature/Reflect")
    }

    /// The only files outside the journal's own that may name it: the wind-down's wiring and the app's.
    static let wiring: Set<String> = ["NightFeature/WindDownScreen.swift", "AppRoot/AppContainer.swift", "AppRoot/RootView.swift"]

    @Test func onlyTheReflectScreensAndTheAppDependOnTheJournalTarget() throws {
        let manifest = try String(contentsOf: Self.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        var owners: Set<String> = []
        var search = manifest.startIndex..<manifest.endIndex
        while let hit = manifest.range(of: "\"JournalKit\"", range: search) {
            // The target or product that this mention is inside: the nearest `name: "..."` before it.
            let before = manifest[manifest.startIndex..<hit.lowerBound]
            if before.hasSuffix("name: ") {
                // The mention is a target's or a product's own name.
                owners.insert("JournalKit")
            } else if let name = before.range(of: "name: \"", options: .backwards) {
                let rest = before[name.upperBound...]
                owners.insert(String(rest.prefix { $0 != "\"" }))
            }
            search = hit.upperBound..<manifest.endIndex
        }
        #expect(owners == ["JournalKit", "NightFeature", "AppRoot", "NoctisKitTests"], Comment(rawValue: "who names it: \(owners.sorted())"))
        for forbidden in ["CoachKit", "CoachFeature", "InsightsKit", "InsightsFeature", "HomeFeature", "SleepKit", "RecoveryKit", "SleepAnalysisKit", "SleepFeature", "RecoveryFeature"] {
            #expect(!owners.contains(forbidden), Comment(rawValue: "\(forbidden) must not see the journal"))
        }
    }

    @Test func theJournalTargetDependsOnNothingButTheErasureProtocol() throws {
        let manifest = try String(contentsOf: Self.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        let start = try #require(manifest.range(of: "name: \"JournalKit\",\n"))
        let block = manifest[start.upperBound...].prefix { $0 != ")" }
        #expect(block.contains("dependencies: [\"NoctisCore\"]"), Comment(rawValue: String(block)))
    }

    @Test func noFileOutsideTheReflectScreensAndTheWiringNamesTheJournal() {
        let files = Self.sourceFiles()
        #expect(files.count > 100, "the scan found the sources")
        let names = ["JournalKit", "JournalEntry", "JournalStore", "JournalDraft", "JournalViewModel", "JournalErasure", "JournalContainer", "Journal"]
        for file in files where !Self.journalFiles(file.path) && !Self.wiring.contains(file.path) && !Self.catalogue.contains(file.path) {
            let code = Self.code(file.text)
            for name in names {
                #expect(!code.contains(name), Comment(rawValue: "\(file.path) names \(name)"))
            }
        }
    }

    @Test func theWiringFilesOnlyWireItAndTheWindDownScreenOnlyOpensIt() {
        let files = Dictionary(uniqueKeysWithValues: Self.sourceFiles().map { ($0.path, Self.code($0.text)) })
        // The wind-down screen opens the Reflect panel and does nothing else with it.
        let screen = files["NightFeature/WindDownScreen.swift"] ?? ""
        #expect(!screen.contains("JournalEntry") && !screen.contains("JournalStore") && !screen.contains("JournalContainer"))
        // The app's container makes the store, registers its erasure and makes the view model; it reads no entry.
        let container = files["AppRoot/AppContainer.swift"] ?? ""
        #expect(container.contains("JournalErasure(provider: journalProvider)"))
        #expect(!container.contains(".entries()") || container.contains("sampleJournal"))
        #expect(!(files["AppRoot/RootView.swift"] ?? "").contains("JournalEntry"))
    }

    @Test func theJournalsOwnFilesNeverLogCountSendOrShare() {
        let forbidden = [
            "Logger", "os_log", "OSLog", "print(", "NSLog", "debugPrint", "dump(", "NoctisAnalytics", "NoctisSignpost", "URLSession", "URLRequest",
            "CloudKit", "NSUbiquitous", "UIActivityViewController", "ShareLink", "UIPasteboard", "ImageRenderer", "MFMail", "AIService", "CoachContext",
        ]
        let own = Self.sourceFiles().filter { Self.journalFiles($0.path) }
        #expect(own.count >= 5, "the scan found the journal's files")
        for file in own {
            let code = Self.code(file.text)
            for word in forbidden {
                #expect(!code.contains(word), Comment(rawValue: "\(file.path) uses \(word)"))
            }
        }
    }

    @Test func analyticsHasNoJournalEvent() {
        let analytics = Self.sourceFiles().filter { $0.path.hasPrefix("NoctisCore/Analytics") }
        #expect(!analytics.isEmpty)
        for file in analytics {
            let lowered = file.text.lowercased()
            for word in ["journal", "reflect", "mood", "energy", "focus"] {
                #expect(!lowered.contains(word), Comment(rawValue: "\(file.path) mentions \(word)"))
            }
        }
    }

    @Test func theCoachContextBuilderNeverReadsTheJournal() async throws {
        // Structure: Coach's own sources cannot even name the journal.
        for file in Self.sourceFiles() where file.path.hasPrefix("CoachKit/") || file.path.hasPrefix("CoachFeature/") {
            #expect(!Self.code(file.text).contains("Journal"), Comment(rawValue: "\(file.path) names the journal"))
        }
        // Behaviour: with a journal full of words in the same process, no context Coach builds holds any of them.
        let marker = "ZXQ-JOURNAL-MARKER-4417"
        let store = await MainActor.run { MemoryJournalStore() }
        await MainActor.run {
            for i in 0..<3 { _ = try? store.add(JournalDraft(energy: 5, mood: 1, focus: 3, text: "\(marker) \(i)"), at: Date()) }
        }
        for intent in CoachIntent.allCases {
            let context = await CoachFixture.context(intent)
            let encoded = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
            #expect(!encoded.contains(marker), Comment(rawValue: "\(intent) carries journal text"))
            #expect(!encoded.lowercased().contains("journal"), Comment(rawValue: "\(intent) mentions the journal"))
        }
    }

    @Test func nothingRelatesTheJournalToSleepOrRecovery() {
        // The journal's snapshot carries only what the person typed: no night, no score, no factor.
        let mirror = Mirror(reflecting: JournalEntrySnapshot(id: UUID(), date: Date(), energy: 1, mood: 1, focus: 1, text: ""))
        #expect(mirror.children.compactMap(\.label).sorted() == ["date", "energy", "focus", "id", "mood", "text"])
        let model = Mirror(reflecting: JournalEntry())
        let labels = model.children.compactMap(\.label)
        for label in labels {
            #expect(!label.lowercased().contains("sleep") && !label.lowercased().contains("recovery"), Comment(rawValue: label))
        }
    }
}
