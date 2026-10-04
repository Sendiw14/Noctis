import Foundation
import JournalKit
import Observation
import SwiftUI

/// What Reflect and the Journal read and do (APP_RULES.md R35). The draft is only ever in memory and is
/// forgotten the moment the screen is left, saved or not; what is saved goes to the journal's own store and
/// nowhere else. Nothing here is logged, counted or sent: this type has no logger, no analytics and no
/// network, and `JournalPrivacyTests` holds it to that.
@MainActor
@Observable
public final class JournalViewModel {
    public enum Availability: Sendable, Equatable {
        case ready
        /// The store can't be opened right now (the phone is locked, or the disk is full).
        case unavailable
    }

    public var draft = JournalDraft()
    public private(set) var entries: [JournalEntrySnapshot] = []
    public private(set) var availability: Availability = .ready
    public var showsJournal = false

    /// What Reflect adjusts to when a value is first stepped from nothing: the middle.
    public static let startingValue = 3

    @ObservationIgnored private let store: any JournalStoring
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: (String) -> Void

    public init(
        store: any JournalStoring, now: @escaping () -> Date = { Date() },
        announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        self.store = store
        self.now = now
        self.announce = announce
    }

    // MARK: Reflecting

    /// Something to save: a value or some words.
    public var canSave: Bool { !draft.isEmpty }

    /// A tap on step `value`: sets it, and a tap on the step already chosen clears it.
    public func choose(_ value: Int, for measure: JournalMeasure) {
        guard JournalDraft.valueRange.contains(value) else { return }
        draft.set(draft.value(measure) == value ? nil : value, for: measure)
    }

    /// VoiceOver's increment and decrement: from nothing the first step is the middle.
    public func step(_ measure: JournalMeasure, by delta: Int) {
        guard let current = draft.value(measure) else {
            draft.set(Self.startingValue, for: measure)
            return
        }
        draft.set(min(max(current + delta, JournalDraft.valueRange.lowerBound), JournalDraft.valueRange.upperBound), for: measure)
    }

    public func clear(_ measure: JournalMeasure) {
        draft.set(nil, for: measure)
    }

    /// Keeps the note inside its limit as it is typed.
    public func limitText() {
        if draft.text.count > JournalDraft.maxTextLength { draft.text = String(draft.text.prefix(JournalDraft.maxTextLength)) }
    }

    /// Saves the draft as an entry. False if there is nothing to save or the store can't be opened;
    /// the draft is kept in that case, so nothing written is lost to a locked phone.
    @discardableResult
    public func save() -> Bool {
        guard canSave else { return false }
        do {
            _ = try store.add(draft, at: now())
            draft = JournalDraft()
            availability = .ready
            announce(ReflectCopy.saved)
            return true
        } catch {
            availability = .unavailable
            return false
        }
    }

    // MARK: The journal

    public func openJournal() {
        showsJournal = true
        load()
    }

    public func closeJournal() {
        showsJournal = false
        entries = []
    }

    public func load() {
        do {
            entries = try store.entries()
            availability = .ready
        } catch {
            entries = []
            availability = .unavailable
        }
    }

    /// One entry.
    public func delete(_ id: UUID) {
        do {
            try store.delete(id: id)
            load()
        } catch {
            availability = .unavailable
        }
    }

    /// Every entry. The screens ask first.
    public func deleteAll() {
        do {
            try store.deleteAll()
            entries = []
            availability = .ready
        } catch {
            availability = .unavailable
        }
    }

    /// The screens were left: what was typed and what was read is forgotten.
    public func leave() {
        draft = JournalDraft()
        showsJournal = false
        entries = []
    }
}

#if DEBUG
extension JournalViewModel {
    /// For `-mockJournal ...:journal`: open on the list.
    public func debugOpenJournal() {
        openJournal()
    }

    /// For `-mockJournal ...:draft`: a form with some of it filled in.
    public func debugFillDraft() {
        draft = JournalDraft(energy: 4, mood: 3, focus: nil, text: "A calm evening. Ready for bed.")
    }
}
#endif
