import Foundation
import SwiftData
import Testing

@testable import CoachKit
@testable import NoctisCore

/// Coach's stored conversations: local, private, erasable, and never a crisis.
struct CoachHistoryTests {
    private func store() throws -> (CoachHistoryStore, ModelContainer) {
        let container = try CoachHistoryContainer.make(inMemory: true)
        return (CoachHistoryStore(modelContainer: container), container)
    }

    private func answer(_ summary: String = "Your recovery is 72 today.", intent: CoachIntent = .recoveryChange) -> CoachAnswer {
        CoachAnswer(
            sourceKind: .fromYourData, intent: intent, summary: summary, confidence: .high,
            footer: "Coach shares patterns from your data. It isn't medical advice.")
    }

    // MARK: - Storing

    @Test func aTurnIsStoredAndReadBackAsItWas() async throws {
        let (store, _) = try store()
        let id = await store.startConversation()
        let kept = await store.append(question: "Why is my recovery lower?", answer: answer(), to: id)
        #expect(kept != nil)
        let turns = await store.turns(in: id)
        #expect(turns.count == 1)
        #expect(turns[0].question == "Why is my recovery lower?")
        #expect(turns[0].answer == answer())
        #expect(await store.messageCount() == 1)
    }

    @Test func aCrisisExchangeIsNeverStored() async throws {
        let (store, _) = try store()
        let id = await store.startConversation()
        let crisis = CoachScriptedAnswers.answer(.crisis)
        #expect(!crisis.isStorable)
        #expect(await store.append(question: "I want to die", answer: crisis, to: id) == nil)
        #expect(await store.append(question: "anything", answer: answer(intent: .crisis), to: id) == nil)
        #expect(await store.messageCount() == 0)
        #expect(await store.conversations().isEmpty, "a conversation nothing was kept from has nothing to show")
    }

    @Test func aTurnForAConversationThatIsntThereIsNotStored() async throws {
        let (store, _) = try store()
        #expect(await store.append(question: "q", answer: answer(), to: UUID()) == nil)
        #expect(await store.messageCount() == 0)
    }

    @Test func conversationsListNewestFirstWithTheirFirstQuestion() async throws {
        let (store, _) = try store()
        let a = await store.startConversation()
        let b = await store.startConversation()
        let early = Date(timeIntervalSince1970: 1_000_000)
        await store.append(question: "first a", answer: answer(), to: a, at: early)
        await store.append(question: "second a", answer: answer(), to: a, at: early.addingTimeInterval(10))
        await store.append(question: "only b", answer: answer(), to: b, at: early.addingTimeInterval(100))
        let list = await store.conversations()
        #expect(list.map(\.id) == [b, a])
        #expect(list.map(\.firstQuestion) == ["only b", "first a"])
        #expect(list.map(\.turns) == [1, 2])
    }

    @Test func recentTurnsAreThePlainSummariesOldestFirst() async throws {
        let (store, _) = try store()
        let id = await store.startConversation()
        let start = Date(timeIntervalSince1970: 2_000_000)
        for index in 0..<4 {
            await store.append(question: "q\(index)", answer: answer("summary \(index)"), to: id, at: start.addingTimeInterval(Double(index)))
        }
        let recent = await store.recentTurns(in: id)
        #expect(recent == [CoachTurnSummary(question: "q2", answerSummary: "summary 2"), CoachTurnSummary(question: "q3", answerSummary: "summary 3")])
        #expect(await store.recentTurns(in: id, limit: 1).map(\.question) == ["q3"])
        #expect(await store.recentTurns(in: UUID()).isEmpty)
    }

    // MARK: - Deleting

    @Test func oneConversationCanBeDeletedAndTheOthersStay() async throws {
        let (store, _) = try store()
        let a = await store.startConversation()
        let b = await store.startConversation()
        await store.append(question: "a1", answer: answer(), to: a)
        await store.append(question: "b1", answer: answer(), to: b)
        await store.deleteConversation(a)
        #expect(await store.conversations().map(\.id) == [b])
        #expect(await store.turns(in: a).isEmpty)
        #expect(await store.messageCount() == 1, "its messages go with it")
        await store.deleteConversation(a)
        #expect(await store.messageCount() == 1)
    }

    @Test func deleteAllLeavesNothing() async throws {
        let (store, _) = try store()
        for index in 0..<3 {
            let id = await store.startConversation()
            await store.append(question: "q\(index)", answer: answer(), to: id)
        }
        await store.deleteAll()
        #expect(await store.conversations().isEmpty)
        #expect(await store.messageCount() == 0)
    }

    @Test func dataManagementsErasureReachesCoachHistory() async throws {
        let (store, container) = try store()
        let id = await store.startConversation()
        await store.append(question: "q", answer: answer(), to: id)
        #expect(await store.messageCount() == 1)

        let registry = NoctisDataRegistry()
        registry.register(CoachHistoryErasure(container: container))
        #expect(registry.stores.map(\.erasableName) == ["Coach history"])
        registry.eraseAll()
        #expect(await store.conversations().isEmpty)
        #expect(await store.messageCount() == 0)
        registry.eraseAll()
    }

    // MARK: - Where it lives

    @Test func theStoreIsLocalOnlyProtectedAndOutOfBackups() throws {
        let folder = URL.temporaryDirectory.appending(path: "coach-history-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try CoachHistoryContainer.make(directory: folder)
        let configuration = try #require(container.configurations.first)
        // `CloudKitDatabase` isn't Equatable: compare what each one says it is.
        #expect(String(describing: configuration.cloudKitDatabase) == String(describing: ModelConfiguration.CloudKitDatabase.none), "never synced")
        #expect(String(describing: configuration.cloudKitDatabase) != String(describing: ModelConfiguration.CloudKitDatabase.automatic))
        #expect(configuration.url.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path)

        let context = ModelContext(container)
        context.insert(AIConversation())
        try context.save()

        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isExcludedFromBackupKey])
        #expect(!files.isEmpty)
        for file in files {
            #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, Comment(rawValue: file.lastPathComponent))
        }
        // Complete protection, where the platform reports it (the simulator doesn't always).
        let protection = try FileManager.default.attributesOfItem(atPath: folder.path)[.protectionKey] as? FileProtectionType
        if let protection { #expect(protection == .complete) }
    }

    @Test func theSchemaHoldsOnlyTheTwoCoachModels() {
        #expect(CoachHistoryContainer.schema.entities.map(\.name).sorted() == ["AIConversation", "AIMessage"])
    }

    @Test func whatIsStoredIsResolvedTextNeverATokenOrADraft() async throws {
        let (store, _) = try store()
        let id = await store.startConversation()
        let context = await CoachFixture.context(.recoveryChange, .lower)
        let draft = TemplateCoachProvider(locale: CoachFixture.locale).compose(intent: .recoveryChange, context: context)
        #expect(draft.summary.contains("{{"))
        let resolved = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .fromYourData, locale: CoachFixture.locale))
        await store.append(question: "q", answer: resolved, to: id)
        let stored = try #require(await store.turns(in: id).first)
        #expect(!stored.answer.allText.joined().contains("{{"))
        #expect(stored.answer.summary == resolved.summary)
    }
}
