import Foundation
import SwiftData

// The journal's one model (APP_RULES.md R35): what a person chose to note about a day. It stays on this
// device: its own store, complete file protection, out of backups, no CloudKit. It is a target of its own
// that only the Reflect screens and the app's wiring depend on, so nothing that reads sleep, recovery,
// insights, Coach or analytics can see it, and a test holds the package to that.

@Model
public final class JournalEntry {
    public var id: UUID = UUID()
    public var date: Date = Date.now
    /// 1 to 5, or nothing: every value is optional.
    public var energy: Int?
    public var mood: Int?
    public var focus: Int?
    public var text: String = ""

    public init() {}
}

/// The three things Reflect asks about, each from Low (1) to High (5).
public enum JournalMeasure: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case energy
    case mood
    case focus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .energy: "Energy"
        case .mood: "Mood"
        case .focus: "Focus"
        }
    }
}

/// An entry as the screens see it: plain values, no model object to hold on to.
public struct JournalEntrySnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let energy: Int?
    public let mood: Int?
    public let focus: Int?
    public let text: String

    public init(id: UUID, date: Date, energy: Int?, mood: Int?, focus: Int?, text: String) {
        self.id = id
        self.date = date
        self.energy = energy
        self.mood = mood
        self.focus = focus
        self.text = text
    }

    init(_ entry: JournalEntry) {
        self.init(id: entry.id, date: entry.date, energy: entry.energy, mood: entry.mood, focus: entry.focus, text: entry.text)
    }

    public func value(_ measure: JournalMeasure) -> Int? {
        switch measure {
        case .energy: energy
        case .mood: mood
        case .focus: focus
        }
    }

    /// The values that were set, in the order Reflect asks them.
    public var values: [(measure: JournalMeasure, value: Int)] {
        JournalMeasure.allCases.compactMap { measure in value(measure).map { (measure, $0) } }
    }
}

/// What the person has filled in before saving. Nothing in it is required, and an empty one is never saved.
public struct JournalDraft: Sendable, Equatable {
    public static let valueRange = 1...5
    public static let maxTextLength = 1000

    public var energy: Int?
    public var mood: Int?
    public var focus: Int?
    public var text: String

    public init(energy: Int? = nil, mood: Int? = nil, focus: Int? = nil, text: String = "") {
        self.energy = energy
        self.mood = mood
        self.focus = focus
        self.text = text
    }

    public func value(_ measure: JournalMeasure) -> Int? {
        switch measure {
        case .energy: energy
        case .mood: mood
        case .focus: focus
        }
    }

    public mutating func set(_ value: Int?, for measure: JournalMeasure) {
        switch measure {
        case .energy: energy = value
        case .mood: mood = value
        case .focus: focus = value
        }
    }

    /// Values kept inside 1...5 (anything else is nothing), the text trimmed and cut to its limit.
    public func normalized() -> JournalDraft {
        func clean(_ value: Int?) -> Int? { value.flatMap { Self.valueRange.contains($0) ? $0 : nil } }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return JournalDraft(energy: clean(energy), mood: clean(mood), focus: clean(focus), text: String(trimmed.prefix(Self.maxTextLength)))
    }

    /// Nothing to save: no value and no words.
    public var isEmpty: Bool {
        let draft = normalized()
        return draft.energy == nil && draft.mood == nil && draft.focus == nil && draft.text.isEmpty
    }
}
