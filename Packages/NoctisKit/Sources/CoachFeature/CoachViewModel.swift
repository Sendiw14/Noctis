import CoachKit
import DesignSystem
import Foundation
import HomeFeature
import NoctisCore
import Observation
import SwiftUI

/// One question in the conversation on screen, and what came of it.
public struct CoachTurn: Identifiable, Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// "Reading your latest data…"
        case loading
        /// A validated answer (or a fixed reply).
        case answered(CoachAnswer)
        /// Not even the template could answer: an inline card with Try again.
        case failed
    }

    public let id: UUID
    public let question: String
    public var phase: Phase
    /// The stored turn's id, when the exchange was kept: feedback is saved against it.
    public var messageID: UUID?
    public var feedback: CoachFeedback?
    /// The answer's reveal has played: it never plays twice.
    public var revealed: Bool

    public init(id: UUID = UUID(), question: String, phase: Phase = .loading, messageID: UUID? = nil, feedback: CoachFeedback? = nil, revealed: Bool = false) {
        self.id = id
        self.question = question
        self.phase = phase
        self.messageID = messageID
        self.feedback = feedback
        self.revealed = revealed
    }

    public var answer: CoachAnswer? {
        if case .answered(let answer) = phase { answer } else { nil }
    }
}

/// Remembers, once, that the first-run card has been dealt with. Stored under
/// `noctis.` so `-noctisResetState` clears it.
public final class CoachFirstRunGate {
    public static let key = "noctis.coach.firstRunSeen"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isSeen: Bool { defaults.bool(forKey: Self.key) }
    public func markSeen() { defaults.set(true, forKey: Self.key) }
}

/// The Coach tab's view model: builds the hub from the app's snapshots, holds
/// the conversation on screen, and asks `AIService`. Views read this and
/// nothing else (APP_RULES.md R20). It never sees a model's raw text: a turn
/// holds only a validated `CoachAnswer`.
@Observable
public final class CoachViewModel {
    /// The longest question a person can send.
    public static let maxLength = 200
    /// The key of this tab's once-a-day field wash.
    public static let washKey = "noctis.coach.lastWashDay"

    /// Nil until the first build (the tab shows its skeleton).
    public private(set) var hub: CoachHubContent?
    public private(set) var turns: [CoachTurn] = []
    public private(set) var conversationID: UUID?
    public private(set) var draft = ""
    /// A question is being answered: nothing more can be sent.
    public private(set) var isSending = false
    public private(set) var fieldEntrance: NoctisFieldEntrance = .none
    /// The privacy sheet is open.
    public var showsPrivacy = false
    /// The stored conversations, by day; nil until History has been opened.
    public private(set) var history: CoachHistoryContent?

    private let service: any CoachAnswering
    private let dataSource: any CoachDataSource
    private let store: CoachHistoryStore?
    private let profile: () -> UserProfileSnapshot
    private let connectHealth: () async -> Void
    private let firstRun: CoachFirstRunGate
    private let washGate: HomeIntroGate
    private let clock: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private let minimumLoading: Duration
    private let reduceMotion: () -> Bool
    private var sending: Task<Void, Never>?

    public init(
        service: any CoachAnswering,
        dataSource: any CoachDataSource,
        history: CoachHistoryStore? = nil,
        profile: @escaping () -> UserProfileSnapshot,
        connectHealth: @escaping () async -> Void = {},
        firstRun: CoachFirstRunGate = CoachFirstRunGate(),
        washGate: HomeIntroGate = HomeIntroGate(key: CoachViewModel.washKey),
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        minimumLoading: Duration = .milliseconds(700),
        reduceMotion: @escaping () -> Bool = { HomeViewModel.systemReduceMotion() }
    ) {
        self.service = service
        self.dataSource = dataSource
        store = history
        self.profile = profile
        self.connectHealth = connectHealth
        self.firstRun = firstRun
        self.washGate = washGate
        self.clock = clock
        self.calendar = calendar
        self.locale = locale
        self.minimumLoading = minimumLoading
        self.reduceMotion = reduceMotion
        fieldEntrance = washGate.isClaimed(now: clock(), calendar: calendar) ? .fade : .wash
    }

    /// The field has arrived: today's wash is spent.
    public func fieldEntered() {
        _ = washGate.claim(now: clock(), calendar: calendar)
        fieldEntrance = .none
    }

    private var format: HomeFormat { HomeFormat(calendar: calendar, locale: locale) }

    // MARK: - The hub

    /// The tab is on screen: builds the hub from what the tabs already know.
    public func onAppear() async {
        await loadHub()
    }

    public func refresh() async {
        await loadHub()
    }

    private func loadHub() async {
        let person = profile()
        let snapshots = await dataSource.snapshots(profile: person)
        let now = clock()
        let facts = CoachContextBuilder(format: format).allFacts(snapshots: snapshots, profile: person)
        let evening = HomeScreenBuilder.mode(now: now, plan: snapshots.home?.tonight ?? TonightPlan(profile: person), calendar: calendar) == .evening
        let suggestions = CoachSuggestionRanker.rank(facts: facts, state: CoachContextBuilder.dataState(snapshots), evening: evening)
        let availability = await service.modelAvailability()
        let content = CoachHubBuilder.build(
            suggestions: suggestions,
            dataState: snapshots.home?.dataState ?? snapshots.sleep?.dataState,
            availability: availability,
            showsFirstRun: !firstRun.isSeen,
            now: now,
            format: format
        )
        if hub != content { hub = content }
    }

    /// "Connect Apple Health": onboarding's authorization flow, then a fresh read.
    public func connectAppleHealth() async {
        await connectHealth()
        await loadHub()
    }

    /// The first-run card has done its job (its button, or its close).
    public func dismissFirstRun() {
        firstRun.markSeen()
        guard let hub, hub.showsFirstRun else { return }
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion())) {
            self.hub = CoachHubContent(
                dateCaption: hub.dateCaption, cards: hub.cards, state: hub.state, learningNote: hub.learningNote,
                appleIntelligenceUnavailable: hub.appleIntelligenceUnavailable, showsTurnOnAppleIntelligence: hub.showsTurnOnAppleIntelligence,
                showsFirstRun: false
            )
        }
    }

    public func openPrivacy() {
        dismissFirstRun()
        showsPrivacy = true
    }

    // MARK: - The text field

    /// What is typed: at most `maxLength` characters.
    public func setDraft(_ text: String) {
        draft = text.count > Self.maxLength ? String(text.prefix(Self.maxLength)) : text
    }

    /// Whether Send does anything: something is typed and nothing is being answered.
    public var canSend: Bool { !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Asking

    /// A question from the hub (a card, a route): a new conversation.
    @discardableResult
    public func startConversation(asking question: CoachQuestion) -> Bool {
        startConversation(asking: CoachQuestionText.text(question))
    }

    /// A question from the hub's text field, or a chip: a new conversation.
    @discardableResult
    public func startConversation(asking text: String) -> Bool {
        guard !isSending, ask(text, continuing: false) else { return false }
        draft = ""
        return true
    }

    /// The text field under an answer: the conversation goes on.
    @discardableResult
    public func followUp(_ text: String? = nil) -> Bool {
        let question = text ?? draft
        guard !isSending, ask(question, continuing: true) else { return false }
        if text == nil { draft = "" }
        return true
    }

    public func followUp(_ question: CoachQuestion) {
        followUp(CoachQuestionText.text(question))
    }

    /// Try again, from a failed answer.
    public func retry(_ id: UUID) {
        guard !isSending, let index = turns.firstIndex(where: { $0.id == id }), turns[index].phase == .failed else { return }
        let question = turns[index].question
        turns.remove(at: index)
        _ = ask(question, continuing: true)
    }

    /// Whether the conversation's last answer has come (a follow-up can be sent).
    public var lastTurn: CoachTurn? { turns.last }

    /// The questions offered above the input: what usually comes next after the latest answer (at most three), once it has come.
    public var followUpQuestions: [CoachQuestion] {
        guard !isSending, let answer = turns.last?.answer, answer.sourceKind != .scripted else { return [] }
        return CoachFollowUps.questions(after: answer.intent)
    }

    /// The conversation's page title: the question that began it.
    public var title: String { turns.first?.question ?? "Coach" }

    private func ask(_ text: String, continuing: Bool) -> Bool {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !question.isEmpty else { return false }
        let bounded = question.count > Self.maxLength ? String(question.prefix(Self.maxLength)) : question
        if !continuing {
            sending?.cancel()
            turns = []
            conversationID = nil
        }
        firstRun.markSeen()
        isSending = true
        let turn = CoachTurn(question: bounded)
        turns.append(turn)
        let started = ContinuousClock.now
        sending = Task { [weak self] in
            await self?.answer(turn.id, question: bounded, started: started)
        }
        return true
    }

    private func answer(_ id: UUID, question: String, started: ContinuousClock.Instant) async {
        if conversationID == nil, let store { conversationID = await store.startConversation() }
        let result = await service.answer(to: question, conversationID: conversationID)
        // A skeleton that flashes and is gone reads as a glitch: it stays for a moment.
        let shown = ContinuousClock.now - started
        if shown < minimumLoading { try? await Task.sleep(for: minimumLoading - shown) }
        guard !Task.isCancelled, let index = turns.firstIndex(where: { $0.id == id }) else {
            isSending = false
            return
        }
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion())) {
            turns[index].messageID = result.messageID
            turns[index].phase = result.outcome == .unavailable ? .failed : .answered(result.answer)
        }
        isSending = false
        NoctisHaptics.soft()
    }

    /// The answer's reveal has played.
    public func markRevealed(_ id: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == id }), !turns[index].revealed else { return }
        turns[index].revealed = true
    }

    // MARK: - Feedback

    /// "Helpful" or "Not helpful": kept on this device, next to the answer. Pressing the same one again takes it back.
    public func setFeedback(_ feedback: CoachFeedback, for id: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == id }), let messageID = turns[index].messageID else { return }
        let next: CoachFeedback? = turns[index].feedback == feedback ? nil : feedback
        turns[index].feedback = next
        NoctisHaptics.selection()
        Task { await store?.setFeedback(next, for: messageID) }
    }

    // MARK: - History

    /// Whether Coach is keeping conversations at all.
    public var keepsHistory: Bool { store != nil }

    /// Reads the stored conversations, and only those.
    public func loadHistory() async {
        let summaries = await store?.conversations() ?? []
        let content = CoachHistoryBuilder.build(summaries, now: clock(), format: format)
        if history != content { history = content }
    }

    /// Opens a stored conversation: its questions and answers as they were
    /// kept, ready for a follow-up. False when it is gone.
    @discardableResult
    public func openConversation(_ id: UUID) async -> Bool {
        guard let store else { return false }
        let stored = await store.turns(in: id)
        guard !stored.isEmpty else { return false }
        sending?.cancel()
        isSending = false
        conversationID = id
        turns = stored.map {
            CoachTurn(question: $0.question, phase: .answered($0.answer), messageID: $0.id, feedback: $0.feedback, revealed: true)
        }
        return true
    }

    /// One conversation, swiped away.
    public func deleteConversation(_ id: UUID) async {
        await store?.deleteConversation(id)
        if conversationID == id { endConversation() }
        await loadHistory()
    }

    /// "Delete all conversations", once confirmed.
    public func deleteAllConversations() async {
        await store?.deleteAll()
        endConversation()
        await loadHistory()
        NoctisHaptics.success()
    }

    /// Leaving the conversation: the next question starts a new one.
    public func endConversation() {
        sending?.cancel()
        isSending = false
        turns = []
        conversationID = nil
    }
}
