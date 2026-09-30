import CoachKit
import Foundation
import HomeFeature

/// One stored conversation in the list.
public nonisolated struct CoachHistoryRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The question that began it.
    public let title: String
    /// "3 questions · 9:41 PM".
    public let detail: String
}

/// The conversations of one day.
public nonisolated struct CoachHistoryDay: Sendable, Equatable, Identifiable {
    /// "2026-09-28".
    public let id: String
    /// "Today", "Yesterday", "Mon, Sep 28".
    public let title: String
    public let rows: [CoachHistoryRow]
}

/// Everything History shows (APP_RULES.md R20): the stored conversations, by
/// day, newest first, with the words written here.
public nonisolated struct CoachHistoryContent: Sendable, Equatable {
    public let days: [CoachHistoryDay]

    public static let emptyTitle = "No conversations yet"
    public static let emptyMessage = "What you ask Coach, and the answers built from your data, are kept here on this iPhone only."
    public static let deleteAllTitle = "Delete all conversations"
    public static let deleteAllMessage = "Every question and answer Coach has kept is removed from this iPhone. This can't be undone."

    public var isEmpty: Bool { days.isEmpty }
    public var conversationCount: Int { days.reduce(0) { $0 + $1.rows.count } }
}

public nonisolated enum CoachHistoryBuilder {
    public static func build(_ conversations: [CoachConversationSummary], now: Date, format: HomeFormat) -> CoachHistoryContent {
        let calendar = format.calendar
        var order: [String] = []
        var groups: [String: (date: Date, rows: [CoachHistoryRow])] = [:]
        for conversation in conversations.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let key = dayKey(conversation.updatedAt, calendar)
            if groups[key] == nil {
                groups[key] = (conversation.updatedAt, [])
                order.append(key)
            }
            groups[key]?.rows.append(CoachHistoryRow(id: conversation.id, title: conversation.firstQuestion, detail: detail(conversation, format: format)))
        }
        let days = order.compactMap { key -> CoachHistoryDay? in
            guard let group = groups[key] else { return nil }
            return CoachHistoryDay(id: key, title: title(for: group.date, now: now, format: format), rows: group.rows)
        }
        return CoachHistoryContent(days: days)
    }

    static func detail(_ conversation: CoachConversationSummary, format: HomeFormat) -> String {
        let count = conversation.turns.formatted(.number.locale(format.locale))
        let questions = conversation.turns == 1 ? "\(count) question" : "\(count) questions"
        return "\(questions) · \(format.clock(conversation.updatedAt, in: format.calendar.timeZone))"
    }

    static func title(for date: Date, now: Date, format: HomeFormat) -> String {
        let calendar = format.calendar
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return format.shortDate(date)
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
