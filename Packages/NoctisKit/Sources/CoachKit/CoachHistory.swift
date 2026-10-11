import Foundation
import NoctisCore
import SwiftData

// Coach's history: the questions a person asked and the validated answers they
// got, on this device and nowhere else. Never synced (no CloudKit database),
// complete file protection, excluded from backups, and erased by Data
// Management (one conversation, or all). A crisis exchange is never stored.
// What is stored is only what a person already saw: resolved `CoachAnswer`
// values and their own question text, never a model's raw output.

@Model
public final class AIConversation {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \AIMessage.conversation)
    public var messages: [AIMessage] = []

    public init(id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.createdAt = createdAt
        updatedAt = createdAt
    }
}

@Model
public final class AIMessage {
    public var id: UUID = UUID()
    public var createdAt: Date = Date.now
    /// What the person typed.
    public var question: String = ""
    /// The answer, as a person saw it: a JSON `CoachAnswer`.
    public var answerData: Data = Data()
    /// The answer's summary, for a list and for the next turn's context.
    public var answerSummary: String = ""
    /// "helpful" or "notHelpful", when the person said; kept here and nowhere else.
    public var feedbackRaw: String?
    public var conversation: AIConversation?

    public init(id: UUID = UUID(), createdAt: Date = .now, question: String, answer: CoachAnswer, data: Data) {
        self.id = id
        self.createdAt = createdAt
        self.question = question
        answerSummary = answer.summary
        answerData = data
    }
}

extension CoachAnswer {
    /// Only an answer built from the person's data is kept. A fixed reply (a
    /// crisis message, the medical redirect, "I can help with...", an apology)
    /// never is.
    public var isStorable: Bool { sourceKind != .scripted && intent != .crisis && helpLink == nil }
}

/// What a person said about an answer. Saved on this device, next to the
/// answer, and nowhere else.
public enum CoachFeedback: String, Sendable, Codable, Hashable {
    case helpful
    case notHelpful
}

/// One conversation in a list.
public struct CoachConversationSummary: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let updatedAt: Date
    public let firstQuestion: String
    public let turns: Int
}

/// One question and its answer, as stored.
public struct CoachStoredTurn: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let question: String
    public let answer: CoachAnswer
    public let feedback: CoachFeedback?
}

/// Where Coach's conversations are kept.
@ModelActor
public actor CoachHistoryStore {
    /// Starts an empty conversation.
    public func startConversation() -> UUID {
        let conversation = AIConversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        return conversation.id
    }

    /// Keeps a turn and returns its id; nil when it isn't kept: a fixed reply
    /// (crisis, medical, unknown), or a conversation that isn't there.
    @discardableResult
    public func append(question: String, answer: CoachAnswer, to id: UUID, at date: Date = .now) -> UUID? {
        guard answer.isStorable, let conversation = conversation(id), let data = try? JSONEncoder().encode(answer) else { return nil }
        let message = AIMessage(createdAt: date, question: question, answer: answer, data: data)
        message.conversation = conversation
        modelContext.insert(message)
        conversation.updatedAt = date
        try? modelContext.save()
        return message.id
    }

    /// What the person said about a stored answer (nil takes it back).
    public func setFeedback(_ feedback: CoachFeedback?, for messageID: UUID) {
        var descriptor = FetchDescriptor<AIMessage>(predicate: #Predicate { $0.id == messageID })
        descriptor.fetchLimit = 1
        guard let message = try? modelContext.fetch(descriptor).first else { return }
        message.feedbackRaw = feedback?.rawValue
        try? modelContext.save()
    }

    public func conversations() -> [CoachConversationSummary] {
        let all = (try? modelContext.fetch(FetchDescriptor<AIConversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        // A conversation nothing was kept from (every reply was fixed) has nothing to show.
        return all.filter { !$0.messages.isEmpty }.map { conversation in
            let ordered = conversation.messages.sorted { $0.createdAt < $1.createdAt }
            return CoachConversationSummary(
                id: conversation.id, updatedAt: conversation.updatedAt, firstQuestion: ordered.first?.question ?? "", turns: ordered.count
            )
        }
    }

    public func turns(in id: UUID) -> [CoachStoredTurn] {
        guard let conversation = conversation(id) else { return [] }
        return conversation.messages.sorted { $0.createdAt < $1.createdAt }.compactMap { message in
            guard let answer = try? JSONDecoder().decode(CoachAnswer.self, from: message.answerData) else { return nil }
            return CoachStoredTurn(
                id: message.id, createdAt: message.createdAt, question: message.question, answer: answer,
                feedback: message.feedbackRaw.flatMap(CoachFeedback.init(rawValue:))
            )
        }
    }

    /// The last turns as plain summaries, oldest first.
    public func recentTurns(in id: UUID, limit: Int = CoachContext.maxTurns) -> [CoachTurnSummary] {
        guard let conversation = conversation(id) else { return [] }
        return conversation.messages.sorted { $0.createdAt < $1.createdAt }.suffix(limit)
            .map { CoachTurnSummary(question: $0.question, answerSummary: $0.answerSummary) }
    }

    public func deleteConversation(_ id: UUID) {
        guard let conversation = conversation(id) else { return }
        modelContext.delete(conversation)
        try? modelContext.save()
    }

    public func deleteAll() {
        CoachHistoryErasure.deleteEverything(in: modelContext)
    }

    /// Every conversation as JSON, for "Export my data": when it started and ended, and each question with a short summary of
    /// its answer and what the person said about it. Not the structured answers themselves.
    public func exportJSON() -> Data {
        let all = (try? modelContext.fetch(FetchDescriptor<AIConversation>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let format = ISO8601DateFormatter()
        let conversations = all.filter { !$0.messages.isEmpty }.map { conversation -> [String: Any] in
            let turns = conversation.messages.sorted { $0.createdAt < $1.createdAt }.map { message -> [String: Any] in
                var turn: [String: Any] = ["asked": format.string(from: message.createdAt), "question": message.question, "answer": message.answerSummary]
                if let feedback = message.feedbackRaw { turn["feedback"] = feedback }
                return turn
            }
            return ["started": format.string(from: conversation.createdAt), "updated": format.string(from: conversation.updatedAt), "turns": turns]
        }
        return (try? JSONSerialization.data(withJSONObject: conversations)) ?? Data("[]".utf8)
    }

    public func messageCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<AIMessage>())) ?? 0
    }

    private func conversation(_ id: UUID) -> AIConversation? {
        var descriptor = FetchDescriptor<AIConversation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

/// Coach's history for Data Management: registered with `NoctisDataRegistry`,
/// so "delete all" reaches it like every other store.
public struct CoachHistoryErasure: NoctisErasable {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public var erasableName: String { "Coach history" }

    public func erase() {
        Self.deleteEverything(in: ModelContext(container))
    }

    /// Every message and every conversation, one by one: a batch delete can't
    /// honour the relationship between them.
    static func deleteEverything(in context: ModelContext) {
        for message in (try? context.fetch(FetchDescriptor<AIMessage>())) ?? [] { context.delete(message) }
        for conversation in (try? context.fetch(FetchDescriptor<AIConversation>())) ?? [] { context.delete(conversation) }
        try? context.save()
    }
}

/// The history store cannot be read right now because the iPhone is locked.
public struct CoachHistoryStoreLocked: Error {}

/// The container Coach's history lives in, apart from the app's other data.
public enum CoachHistoryContainer {
    public static let schema = Schema(versionedSchema: CoachHistorySchemaV1.self)

    /// "Noctis/CoachHistory" in Application Support.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Noctis", directoryHint: .isDirectory)
            .appending(path: "CoachHistory", directoryHint: .isDirectory)
    }

    /// With `inMemory`, nothing touches disk (tests). Otherwise the store sits
    /// in `directory` with complete file protection, out of backups, and with
    /// no CloudKit database: it never leaves the device.
    ///
    /// A store that will not open is set aside, never deleted, and a new one is made (`StoreRecovery`, APP_RULES.md R65): the conversations
    /// in it are not shown, and not lost. While the iPhone is locked nothing is moved, and this throws so the caller asks again later.
    public static func make(directory: URL? = nil, inMemory: Bool = false, recovery: StoreRecovery? = nil) throws -> ModelContainer {
        if inMemory { return try memoryContainer() }
        let folder = directory ?? defaultDirectory
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete]
        )
        let url = folder.appending(path: "coach-history.store", directoryHint: .notDirectory)
        let recovery = recovery ?? StoreRecovery.beside(folder: folder, up: 1)
        let (container, outcome) = try recovery.open(.coachHistory, at: url, make: { try diskContainer(at: $0) }, inMemory: { try memoryContainer() })
        // Locked: say so, so the next ask tries the real store again instead of keeping this stand-in for the whole run.
        if outcome == .lockedLeftInPlace { throw CoachHistoryStoreLocked() }
        protect(folder)
        return container
    }

    private static func diskContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration("CoachHistory", schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        let opened = try ModelContainer(for: schema, migrationPlan: CoachHistoryMigrationPlan.self, configurations: configuration)
        let context = ModelContext(opened)
        _ = try context.fetchCount(FetchDescriptor<AIConversation>())
        _ = try context.fetchCount(FetchDescriptor<AIMessage>())
        return opened
    }

    private static func memoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: schema, migrationPlan: CoachHistoryMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    /// Complete protection and no backup, on the folder and what is in it.
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

// MARK: - Versions (APP_RULES.md R65)

/// Version 1 of Coach's history store (`coach-history.store`).
public enum CoachHistorySchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [AIConversation.self, AIMessage.self] }
}

/// Every version of Coach's history store, oldest first.
public enum CoachHistoryMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [CoachHistorySchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
