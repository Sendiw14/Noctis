import DesignSystem
import Foundation
import HomeFeature
import InsightsKit
import NoctisCore
import SleepKit
import NoctisText

/// The chip row's choices: All, then a category each.
public nonisolated struct InsightChipContent: Sendable, Equatable, Identifiable {
    /// `nil` is "All".
    public let category: InsightCategory?
    public let title: String
    public var id: String { category?.rawValue ?? "all" }
}

/// One row of the Recent list.
public nonisolated struct InsightRowContent: Sendable, Equatable, Identifiable {
    public let id: String
    public let type: InsightType
    public let category: InsightCategory
    public let title: String
    /// One evidence line.
    public let line: String
    public let accessibilityLabel: String
}

public nonisolated struct InsightRowGroup: Sendable, Equatable, Identifiable {
    /// "This week", "Earlier".
    public let title: String
    public let rows: [InsightRowContent]
    public var id: String { title }
}

/// The top-ranked insight, as a story.
public nonisolated struct InsightFeaturedContent: Sendable, Equatable, Identifiable {
    public let id: String
    public let type: InsightType
    public let category: InsightCategory
    public let title: String
    public let numbers: [InsightNumber]
    public let join: InsightComparisonJoin
    public let interpretation: String
    public let chart: InsightChartData?
    public let accessibilityLabel: String
}

/// A record that stands, for the Your records row.
public nonisolated struct InsightRecordTile: Sendable, Equatable, Identifiable {
    public enum Tone: Sendable, Equatable {
        case sage
        case lavender
        case butter
    }

    public let type: InsightType
    /// "Longest night".
    public let title: String
    public let value: NoctisMetricValue
    /// "Sep 12".
    public let date: String
    public let tone: Tone
    public let accessibilityLabel: String
    public var id: String { type.rawValue }
}

public nonisolated struct InsightMilestoneRow: Sendable, Equatable, Identifiable {
    public let milestone: Int
    /// "Timing insights".
    public let title: String
    /// "Bedtime shifts and steady stretches."
    public let detail: String
    /// Ten dots: how many are filled.
    public let filled: Int
    public let dots: Int
    public let reached: Bool
    public var id: Int { milestone }
    public let accessibilityLabel: String
}

public nonisolated struct InsightsLearningContent: Sendable, Equatable {
    public let title: String
    public let detail: String
    public let nights: Int
    public let rows: [InsightMilestoneRow]
}

/// What the tab shows instead of insights when there's nothing to show.
public nonisolated enum InsightsStateContent: Sendable, Equatable {
    case connect(title: String, message: String, showsButton: Bool)
    case noSleepData(title: String, message: String)
    case failed(message: String)
}

/// A calm card for a filter with nothing in it, or a night with nothing new.
public nonisolated struct InsightsNoteContent: Sendable, Equatable {
    public let title: String
    public let detail: String
}

/// Everything the Insights tab lays out, built from a snapshot and a filter
/// (APP_RULES.md R20).
public nonisolated struct InsightsScreenContent: Sendable, Equatable {
    /// "WEDNESDAY, SEPTEMBER 30".
    public let dateCaption: String
    /// "3 new this week" or "We're still learning your pattern."
    public let summary: String
    public let chips: [InsightChipContent]
    public let state: InsightsStateContent?
    public let learning: InsightsLearningContent?
    public let featured: InsightFeaturedContent?
    public let groups: [InsightRowGroup]
    public let records: [InsightRecordTile]
    /// Nothing to show for this filter, or this night.
    public let note: InsightsNoteContent?
}

extension InsightsScreenContent {
    /// What a free person sees (R57): the featured story and the single most recent other insight, with none of the records. The rest, the category chips'
    /// lists, the records and History are Premium and are said once by one locked card; nothing here deletes or hides a stored insight, it only decides how many
    /// are drawn.
    public func limitedForFree() -> InsightsScreenContent {
        let firstRow = groups.first?.rows.first
        let kept = groups.first.flatMap { group in firstRow.map { [InsightRowGroup(title: group.title, rows: [$0])] } } ?? []
        return InsightsScreenContent(
            dateCaption: dateCaption, summary: summary, chips: chips, state: state, learning: learning, featured: featured, groups: kept, records: [], note: note
        )
    }

    /// Whether anything is drawn for the locked card to speak for: a list of insights, not a state or the learning card.
    public var showsInsights: Bool { state == nil && learning == nil }
}

public nonisolated enum InsightsScreenBuilder {
    /// The milestones the learning card counts toward.
    static let milestoneDetails: [(nights: Int, title: String, detail: String)] = [
        (7, "Timing insights", "Bedtime shifts and steady stretches."),
        (14, "Patterns", "How your bedtime and your sleep move together."),
        (30, "Trends", "Long-term records and where you are heading."),
    ]
    static let milestoneDots = 10

    public static func build(
        _ snapshot: InsightsSnapshot, filter: InsightCategory?, now: Date, calendar: Calendar, locale: Locale
    ) -> InsightsScreenContent {
        let format = HomeFormat(calendar: calendar, locale: locale)
        let caption = format.longDate(now).uppercased(with: locale)
        let chips = [InsightChipContent(category: nil, title: "All")] + InsightCategory.allCases.map { InsightChipContent(category: $0, title: $0.title) }
        func screen(summary: String, state: InsightsStateContent? = nil, learning: InsightsLearningContent? = nil, featured: InsightFeaturedContent? = nil,
                    groups: [InsightRowGroup] = [], records: [InsightRecordTile] = [], note: InsightsNoteContent? = nil, showsChips: Bool = true) -> InsightsScreenContent {
            InsightsScreenContent(
                dateCaption: caption, summary: summary, chips: showsChips ? chips : [], state: state, learning: learning, featured: featured,
                groups: groups, records: records, note: note
            )
        }

        switch snapshot.dataState {
        case .healthDataUnavailable, .permissionRequired, .empty, .failed:
            return screen(summary: stateSummary(snapshot.dataState), state: stateContent(snapshot.dataState), showsChips: false)
        case .learning(let nights):
            if nights == 0 { return screen(summary: stateSummary(.empty), state: stateContent(.empty), showsChips: false) }
            return screen(summary: "We're still learning your pattern.", learning: learning(nights: nights), showsChips: false)
        case .stale, .noSleepLastNight, .ready:
            break
        }

        let featured = snapshot.featured.map { featuredContent($0, format: format) }
        let showsFeatured = featured.map { filter == nil || $0.category == filter } ?? false
        // The featured story leads the list, so the list doesn't repeat it; a filter
        // that leaves the story out (another category) lists what it has.
        let rows = snapshot.recent
            .filter { $0.id != snapshot.featured?.id }
            .filter { filter == nil || $0.record.category == filter }
        let night = snapshot.night
        let contentRows = rows.map { row(from: $0, format: format) }
        let thisWeek = contentRows.enumerated().filter { index, _ in night.map { $0.days(from: rows[index].record.night) < 7 } ?? true }.map(\.element)
        let earlier = contentRows.filter { row in !thisWeek.contains { $0.id == row.id } }
        var groups: [InsightRowGroup] = []
        if !thisWeek.isEmpty { groups.append(InsightRowGroup(title: "This week", rows: thisWeek)) }
        if !earlier.isEmpty { groups.append(InsightRowGroup(title: "Earlier", rows: earlier)) }

        let tiles = filter == nil || filter == .longTerm ? recordTiles(snapshot.records, format: format) : []
        var note: InsightsNoteContent?
        if !showsFeatured, groups.isEmpty, tiles.isEmpty {
            if let filter {
                note = InsightsNoteContent(title: "No \(filter.title.lowercased()) insights yet", detail: "They appear when your data has something to say.")
            } else if snapshot.dataState == .noSleepLastNight {
                note = InsightsNoteContent(title: "No sleep recorded last night", detail: "New insights appear once a night is recorded.")
            } else {
                note = InsightsNoteContent(title: "Nothing new today", detail: "Your insights appear when your nights have something to say.")
            }
        } else if snapshot.dataState == .noSleepLastNight, filter == nil {
            note = InsightsNoteContent(title: "No sleep recorded last night", detail: "New insights appear once a night is recorded.")
        }
        return screen(
            summary: summary(snapshot.newThisWeek), featured: showsFeatured ? featured : nil, groups: groups, records: tiles, note: note
        )
    }

    // MARK: Summary

    static func summary(_ new: Int) -> String {
        new == 0 ? "You're all caught up." : "\(new) new this week"
    }

    static func stateSummary(_ state: HomeDataState) -> String {
        switch state {
        case .failed: "Insights are on hold for a moment."
        case .permissionRequired, .healthDataUnavailable: "Insights start with your first night."
        default: "Insights start with your first night."
        }
    }

    // MARK: States

    /// The same copy Home, Sleep and Recovery use.
    static func stateContent(_ state: HomeDataState) -> InsightsStateContent? {
        switch state {
        case .healthDataUnavailable:
            .connect(title: "Your first night starts here.", message: "Apple Health isn't available on this device.", showsButton: false)
        case .permissionRequired:
            .connect(title: "Your first night starts here.", message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true)
        case .empty, .learning(nightsSoFar: 0):
            .noSleepData(
                title: "No sleep data yet",
                message: "NOCTIS reads sleep from Apple Health. Track sleep with Apple Watch or set up Sleep in the Health app."
            )
        case .failed:
            .failed(message: "We couldn't read your latest sleep data.")
        case .stale, .learning, .noSleepLastNight, .ready:
            nil
        }
    }

    static func learning(nights: Int) -> InsightsLearningContent {
        let rows = milestoneDetails.map { item -> InsightMilestoneRow in
            let reached = nights >= item.nights
            let filled = min(Int((Double(min(nights, item.nights)) / Double(item.nights) * Double(milestoneDots)).rounded(.down)), milestoneDots)
            let progress = reached ? "Unlocked" : "\(nights) of \(item.nights) nights"
            return InsightMilestoneRow(
                milestone: item.nights, title: item.title, detail: item.detail, filled: reached ? milestoneDots : filled, dots: milestoneDots, reached: reached,
                accessibilityLabel: "\(item.title) unlock at \(item.nights) nights. \(progress)."
            )
        }
        return InsightsLearningContent(
            title: "Insights unlock as we learn your nights",
            detail: "\(NoctisCount.nights(nights)) recorded so far.",
            nights: nights, rows: rows
        )
    }

    // MARK: Insights

    static func featuredContent(_ record: InsightRecord, format: HomeFormat) -> InsightFeaturedContent {
        let words = InsightScreenBuilder.build(record, format: format)
        return InsightFeaturedContent(
            id: record.id, type: record.type, category: record.category, title: words.title, numbers: words.comparison, join: words.comparisonJoin,
            interpretation: words.interpretation,
            chart: InsightChartBuilder.chart(for: record, format: format),
            accessibilityLabel: "\(words.title). \(words.rowLine) \(words.interpretation)"
        )
    }

    static func row(from stored: StoredInsight, format: HomeFormat) -> InsightRowContent {
        let words = InsightScreenBuilder.build(stored.record, format: format)
        return InsightRowContent(
            id: stored.id, type: stored.record.type, category: stored.record.category, title: words.title, line: words.rowLine,
            accessibilityLabel: "\(words.title). \(words.rowLine)"
        )
    }

    // MARK: Records

    static func recordTiles(_ records: [StandingRecord], format: HomeFormat) -> [InsightRecordTile] {
        let byType = Dictionary(records.map { ($0.type, $0) }, uniquingKeysWith: { first, _ in first })
        var tiles: [InsightRecordTile] = []
        if let record = byType[.recordLongestNight] {
            tiles.append(tile(record, title: "Longest night", tone: .sage, value: HomeFormat.durationMetric(Int(record.value.rounded())), format: format))
        }
        if let record = byType[.recordBestConsistency] {
            tiles.append(tile(record, title: "Best consistency", tone: .lavender, value: HomeFormat.quantityMetric(Int(record.value.rounded()), .minuteShort), format: format))
        }
        if let record = byType[.recordHighestRecovery] {
            let score = Int(record.value.rounded())
            tiles.append(tile(record, title: "Highest recovery", tone: .butter, value: NoctisMetricValue(parts: [.number("\(score)")], spoken: "\(score) out of 100"), format: format))
        }
        return tiles
    }

    private static func tile(_ record: StandingRecord, title: String, tone: InsightRecordTile.Tone, value: NoctisMetricValue, format: HomeFormat) -> InsightRecordTile {
        let date = format.monthDay(record.night)
        return InsightRecordTile(
            type: record.type, title: title, value: value, date: date, tone: tone,
            accessibilityLabel: "\(title): \(value.spoken), \(date)."
        )
    }
}

// MARK: - An insight's page

/// Every part of one insight's page: the header, the evidence, the sentences,
/// how it was found and where it stands.
public nonisolated struct InsightDetailContent: Sendable, Equatable, Identifiable {
    public let id: String
    public let type: InsightType
    public let category: InsightCategory
    public let title: String
    /// "Wed, Sep 23".
    public let dateLine: String
    /// "Not useful" was chosen: the page says so and offers no second try.
    public let dismissed: Bool
    public let numbers: [InsightNumber]
    public let join: InsightComparisonJoin
    public let chart: InsightChartData?
    public let evidenceLines: [String]
    public let context: String
    public let interpretation: String
    public let whatToNotice: String
    public let whatYouCanTry: String?
    /// "Moderate confidence · based on 23 nights".
    public let confidenceLine: String
    /// Patterns only.
    public let notProofLine: String?
    public let method: InsightMethod
    public let accessibilityLabel: String
}

/// One insight in History.
public nonisolated struct InsightHistoryRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let type: InsightType
    public let category: InsightCategory
    public let title: String
    public let line: String
    /// "Sep 23".
    public let date: String
    /// Muted, with "Not useful" beside it.
    public let dismissed: Bool
    public let accessibilityLabel: String
}

public nonisolated struct InsightMonthGroup: Sendable, Equatable, Identifiable {
    /// "September 2026".
    public let title: String
    public let rows: [InsightHistoryRow]
    public var id: String { title }
}

/// Every insight so far, newest first, by month, for the chips' filter.
public nonisolated struct InsightHistoryContent: Sendable, Equatable {
    public let summary: String
    public let chips: [InsightChipContent]
    public let months: [InsightMonthGroup]
    public let note: InsightsNoteContent?
}

extension InsightsScreenBuilder {
    public static func detail(_ stored: StoredInsight, calendar: Calendar, locale: Locale) -> InsightDetailContent {
        let format = HomeFormat(calendar: calendar, locale: locale)
        let record = stored.record
        let words = InsightScreenBuilder.build(record, format: format)
        return InsightDetailContent(
            id: record.id, type: record.type, category: record.category, title: words.title, dateLine: words.dateLine,
            dismissed: stored.state == .dismissed, numbers: words.comparison, join: words.comparisonJoin,
            chart: InsightChartBuilder.chart(for: record, format: format), evidenceLines: words.evidenceLines,
            context: words.context, interpretation: words.interpretation, whatToNotice: words.whatToNotice,
            whatYouCanTry: words.whatYouCanTry, confidenceLine: words.confidenceLine, notProofLine: words.notProofLine,
            method: words.method, accessibilityLabel: words.accessibilityLabel
        )
    }

    /// "September 2026".
    static func monthTitle(_ night: SleepNightKey, format: HomeFormat) -> String {
        guard let date = format.date(night) else { return "" }
        return date.formatted(Date.FormatStyle(locale: format.locale, calendar: format.calendar, timeZone: format.calendar.timeZone).month(.wide).year())
    }

    public static func history(_ snapshot: InsightsSnapshot, filter: InsightCategory?, calendar: Calendar, locale: Locale) -> InsightHistoryContent {
        let format = HomeFormat(calendar: calendar, locale: locale)
        let chips = [InsightChipContent(category: nil, title: "All")] + InsightCategory.allCases.map { InsightChipContent(category: $0, title: $0.title) }
        let stored = snapshot.all.filter { filter == nil || $0.record.category == filter }
        var months: [InsightMonthGroup] = []
        var current: (title: String, rows: [InsightHistoryRow])?
        for entry in stored {
            let title = monthTitle(entry.record.night, format: format)
            let words = InsightScreenBuilder.build(entry.record, format: format)
            let dismissed = entry.state == .dismissed
            let row = InsightHistoryRow(
                id: entry.id, type: entry.record.type, category: entry.record.category, title: words.title, line: words.rowLine,
                date: format.monthDay(entry.record.night), dismissed: dismissed,
                accessibilityLabel: "\(words.title), \(format.weekdayMonthDay(entry.record.night)). \(words.rowLine)\(dismissed ? " Marked not useful." : "")"
            )
            if current?.title == title {
                current?.rows.append(row)
            } else {
                if let current { months.append(InsightMonthGroup(title: current.title, rows: current.rows)) }
                current = (title, [row])
            }
        }
        if let current { months.append(InsightMonthGroup(title: current.title, rows: current.rows)) }
        var note: InsightsNoteContent?
        if months.isEmpty {
            note = filter.map { InsightsNoteContent(title: "No \($0.title.lowercased()) insights yet", detail: "They appear when your data has something to say.") }
                ?? InsightsNoteContent(title: "No insights yet", detail: "Every insight NOCTIS finds is kept here.")
        }
        let count = stored.count
        return InsightHistoryContent(
            summary: count == 0 ? "Nothing yet." : "\(NoctisCount.insights(count)) so far.",
            chips: chips, months: months, note: note
        )
    }
}
