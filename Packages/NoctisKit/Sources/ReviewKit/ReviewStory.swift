import Foundation
import SleepKit

// What a review story draws (APP_RULES.md R63): every page's content as plain values, made by `ReviewStoryBuilder` from a `ReviewRecord` and nothing else. A page whose
// data does not exist is not in the story (never filled). Positions are shares of a chart (0...1) so a view only places them; every number and word is made here.

/// Which flat color a page is drawn on: the token names of the app's fields, never a color value.
public nonisolated enum ReviewPageTint: String, Sendable, Equatable {
    case apricot, sage, butter, lavender, sand
    /// Ivory ink on the cocoa night color.
    case cocoa
    /// The paper, with colored blocks on it.
    case paper
}

/// Which way a number moved, as an arrow. Plain ink: never red or green.
public nonisolated enum ReviewArrow: String, Sendable, Equatable {
    case up, down, flat
}

/// A week's or a month's first page: the average night and how it compares.
public nonisolated struct ReviewCoverPage: Sendable, Equatable {
    /// "Your week", "Your month".
    public let title: String
    public let dateRange: String
    public let averageMinutes: Int
    /// "+22 min vs the week before", or why there is no comparison.
    public let deltaText: String
    public let deltaArrow: ReviewArrow?
    /// One calm line: how many nights it rests on.
    public let context: String
    public let spokenAverage: String
}

/// One night's bar.
public nonisolated struct ReviewBar: Sendable, Equatable, Identifiable {
    public let morning: SleepNightKey
    /// The weekday's letter under a week's bar, or the day of the month.
    public let label: String
    public let minutes: Double?
    /// The bar's height as a share of the chart; nil without a night.
    public let fraction: Double?
    /// Deep, Core and REM as shares of the night; nil without stages.
    public let stages: ReviewBarStages?
    public let reachedNeed: Bool
    public let spoken: String

    public var id: SleepNightKey { morning }
}

public nonisolated struct ReviewBarStages: Sendable, Equatable {
    public let deep: Double
    public let core: Double
    public let rem: Double
}

/// A week's seven stage-stacked bars, or a month's slim ones, and the lines across them.
public nonisolated struct ReviewBarsPage: Sendable, Equatable {
    public let headline: String
    public let lines: [String]
    public let bars: [ReviewBar]
    /// The minutes at the top of the chart.
    public let topMinutes: Double
    public let needFraction: Double
    public let needText: String
    /// A month's average line: a share of the chart; nil for a week.
    public let averageFraction: Double?
    public let averageText: String?
    /// A month's bars are slim and have no stages.
    public let slim: Bool
}

public nonisolated struct ReviewTimingRow: Sendable, Equatable, Identifiable {
    public let morning: SleepNightKey
    public let label: String
    /// Positions along the shared axis, 0...1.
    public let bedtime: Double
    public let wake: Double

    public var id: SleepNightKey { morning }
}

public nonisolated struct ReviewAxisTick: Sendable, Equatable {
    public let position: Double
    public let label: String
}

/// The usual band: from the median less the spread to the median plus it, as positions on the axis.
public nonisolated struct ReviewBand: Sendable, Equatable {
    public let start: Double
    public let end: Double
}

/// Bedtimes and wake times of every night on one clock axis, with the band they usually fall in.
public nonisolated struct ReviewTimingPage: Sendable, Equatable {
    public let headline: String
    public let lines: [String]
    public let rows: [ReviewTimingRow]
    public let ticks: [ReviewAxisTick]
    public let bedtimeBand: ReviewBand
    public let wakeBand: ReviewBand
    public let spoken: String
}

/// A line over a run of mornings with a gap wherever a morning has no value.
public nonisolated struct ReviewLinePage: Sendable, Equatable {
    public let headline: String
    public let lines: [String]
    /// One per morning, as a share of the axis; nil where there is none.
    public let points: [Double?]
    public let axis: [ReviewAxisTick]
    /// "Rising", "Steady" or "Lower than earlier"; nil without enough scored nights to say.
    public let direction: String?
    public let directionArrow: ReviewArrow?
    public let spoken: String
}

/// One change, with both numbers.
public nonisolated struct ReviewChangeTile: Sendable, Equatable, Identifiable {
    /// "Biggest improvement", "Biggest change", "Change".
    public let caption: String
    public let metric: String
    public let from: String
    public let to: String
    public let arrow: ReviewArrow
    public let summary: String

    public var id: String { caption + metric }
}

/// What changed: up to two tiles for a week, up to three for a month, or one calm sentence when nothing moved.
public nonisolated struct ReviewChangesPage: Sendable, Equatable {
    public let headline: String
    public let tiles: [ReviewChangeTile]
    /// Said when nothing moved by half the person's own variation: "A steady week".
    public let steadySentence: String?
}

public nonisolated struct ReviewInsightsPage: Sendable, Equatable {
    public let headline: String
    public let insightIDs: [String]
}

/// What Coach can be asked about a focus (the app maps it to a question; nothing else is sent).
public nonisolated enum ReviewCoachTopic: String, Sendable, Equatable {
    case consistency, bedtime, recovery
}

public nonisolated struct ReviewFocusPage: Sendable, Equatable {
    public let headline: String
    public let lines: [String]
    public let coachTopic: ReviewCoachTopic?
}

public nonisolated struct ReviewRecordBlock: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable { case longestNight, highestRecovery }

    public let kind: Kind
    public let title: String
    /// Minutes asleep for the longest night; nil for a score.
    public let minutes: Int?
    /// The score for the highest recovery; nil for a night's length.
    public let score: Int?
    public let date: String
    /// "Equalled on 2 other nights"; nil without a tie.
    public let tie: String?
    public let spoken: String

    public var id: String { kind.rawValue }
}

public nonisolated struct ReviewRecordsPage: Sendable, Equatable {
    public let headline: String
    public let blocks: [ReviewRecordBlock]
}

public nonisolated struct ReviewStoryPage: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        // A week.
        case cover, sleep, consistency, recovery, changes, insight, focus
        // A month.
        case sleepPattern, recoveryPattern, timing, majorChanges, insights, records
        /// A free person's monthly review: one calm card.
        case locked
    }

    public enum Content: Sendable, Equatable {
        case cover(ReviewCoverPage)
        case bars(ReviewBarsPage)
        case timing(ReviewTimingPage)
        case line(ReviewLinePage)
        case changes(ReviewChangesPage)
        case insights(ReviewInsightsPage)
        case focus(ReviewFocusPage)
        case records(ReviewRecordsPage)
        case locked
    }

    public let kind: Kind
    public let tint: ReviewPageTint
    public let content: Content

    public var id: String { kind.rawValue }

    /// The pages the share card is made from.
    public var isShareable: Bool { kind == .cover || kind == .sleep || kind == .sleepPattern }
}

/// What the share card holds: the cover and the sleep page as they are on screen, and, only if the person flips "Include details", the heart numbers.
public nonisolated struct ReviewShareContent: Sendable, Equatable {
    public let title: String
    public let dateRange: String
    public let cover: ReviewCoverPage
    /// The sleep page's bars; nil where that page is not shown (the free plan).
    public let bars: ReviewBarsPage?
    /// "Recovery 71 · HRV 52 ms · Resting heart rate 55 bpm"; nil when there is none. Never on the card unless asked for.
    public let details: String?
    public let fileName: String

    /// The heart numbers, only when the person has switched "Include details" on; otherwise nothing, whatever the review holds.
    public func detailsText(includeDetails: Bool) -> String? { includeDetails ? details : nil }

    /// Everything the card says, for a test and for VoiceOver: the details only when asked for.
    public func spokenLines(includeDetails: Bool) -> [String] {
        [title, dateRange, cover.spokenAverage, cover.deltaText] + (bars.map { [$0.headline] } ?? []) + [detailsText(includeDetails: includeDetails)].compactMap { $0 }
    }
}

public nonisolated struct ReviewStory: Sendable, Equatable {
    public let id: ReviewID
    /// "Your week", "Your month".
    public let title: String
    public let dateRange: String
    /// Every page the record supports, in order (what Premium sees).
    public let pages: [ReviewStoryPage]
    public let nightsRecorded: Int
    public let nightsInPeriod: Int
    let fullShare: ReviewShareContent

    public var kind: ReviewKind { id.kind }

    /// The story without the insight pages whose insights are no longer there (one dismissed or deleted since): a page is never filled.
    public func keepingInsights(_ available: Set<String>) -> ReviewStory {
        var kept: [ReviewStoryPage] = []
        for page in pages {
            guard case .insights(let content) = page.content else {
                kept.append(page)
                continue
            }
            let ids = content.insightIDs.filter { available.contains($0) }
            if ids.isEmpty { continue }
            kept.append(ReviewStoryPage(kind: page.kind, tint: page.tint, content: .insights(ReviewInsightsPage(headline: content.headline, insightIDs: ids))))
        }
        return ReviewStory(id: id, title: title, dateRange: dateRange, pages: kept, nightsRecorded: nightsRecorded, nightsInPeriod: nightsInPeriod, fullShare: fullShare)
    }

    /// The pages a person sees: all of them for Premium; the weekly cover alone for the free plan (the cover ends with one locked card), and for a month one calm
    /// locked page.
    public func visiblePages(unlocked: Bool) -> [ReviewStoryPage] {
        guard !unlocked else { return pages }
        switch kind {
        case .weekly: return Array(pages.prefix(1))
        case .monthly: return [ReviewStoryPage(kind: .locked, tint: .paper, content: .locked)]
        }
    }

    /// The share card: from the cover and the sleep page where they are shown. A free person's weekly card has the cover only; a month's locked page has nothing to share.
    public func share(unlocked: Bool) -> ReviewShareContent? {
        if kind == .monthly, !unlocked { return nil }
        return unlocked ? fullShare : ReviewShareContent(title: fullShare.title, dateRange: fullShare.dateRange, cover: fullShare.cover, bars: nil, details: fullShare.details, fileName: fullShare.fileName)
    }
}

// MARK: - The reviews list

/// One line of the Reviews list.
public nonisolated struct ReviewListRow: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        /// Made and not opened: a small dot, never a count or a badge.
        case new
        case opened
        /// A past period that had too few nights: the nights it had and the nights it needs.
        case notEnough(have: Int, need: Int)
    }

    public let id: ReviewID
    /// "Sep 20 \u{2013} 26", "September 2026".
    public let title: String
    /// The headline number ("7h 42m a night on average"), or "4 of 5 nights".
    public let headline: String
    public let status: Status
    public let spoken: String

    public var kind: ReviewKind { id.kind }
}

/// The Reviews list: the weeks and the months, newest first. Only reviews that were made are listed, with past periods that had too few nights as their own "Not enough
/// nights" rows (the nights they had) so a gap is explained and not hidden. A period with no night at all is not listed.
public nonisolated struct ReviewListContent: Sendable, Equatable {
    public let weekly: [ReviewListRow]
    public let monthly: [ReviewListRow]

    public var isEmpty: Bool { weekly.isEmpty && monthly.isEmpty }
}

public nonisolated enum ReviewListBuilder {
    /// How far back the list looks for periods that had too few nights: what Health is read for.
    public static let weeklyLimit = 12
    public static let monthlyLimit = 3
    public static let lookbackDays = ReviewModel.priorNights * 3 + 14

    /// The periods that may have too few nights to list: the last weeks and months that are over and inside what is read from Health.
    public static func candidates(now: Date, weekday: Int, calendar: Calendar) -> [ReviewPeriod] {
        let today = ReviewPeriod.today(now, calendar: calendar)
        let earliest = today.adding(days: -lookbackDays)
        var periods: [ReviewPeriod] = []
        var week = ReviewPeriod.latestWeekly(now: now, weekday: weekday, calendar: calendar)
        for _ in 0..<weeklyLimit where week.firstMorning >= earliest {
            periods.append(week)
            week = week.previous
        }
        var month = ReviewPeriod.latestMonthly(now: now, calendar: calendar)
        for _ in 0..<monthlyLimit where month.firstMorning >= earliest {
            periods.append(month)
            month = month.previous
        }
        return periods
    }

    /// `counts` are the nights Health holds for each of `candidates` that was not made (nil where they could not be read).
    public static func build(library: ReviewLibrary, counts: [ReviewID: Int], now: Date, weekday: Int, calendar: Calendar, format: ReviewFormat = ReviewFormat()) -> ReviewListContent {
        var rows: [ReviewListRow] = library.all.map { stored in
            let record = stored.record
            let average = ReviewFormat.duration(record.sleep.averageMinutes)
            return ReviewListRow(
                id: stored.id, title: ReviewScreenBuilder.dateRange(record.period, format), headline: "\(average) a night", status: stored.state == .new ? .new : .opened,
                spoken: "\(ReviewScreenBuilder.dateRange(record.period, format)), \(ReviewFormat.spoken(record.sleep.averageMinutes)) a night on average, \(stored.state == .new ? "not opened yet" : "opened")"
            )
        }
        for period in candidates(now: now, weekday: weekday, calendar: calendar) where library[period.id] == nil && period.isComplete(at: now, calendar: calendar) {
            let need = period.kind.minimumNights
            guard let have = counts[period.id], have > 0, have < need else { continue }
            let range = ReviewScreenBuilder.dateRange(period, format)
            rows.append(ReviewListRow(
                id: period.id, title: range, headline: "\(have) of \(need) nights", status: .notEnough(have: have, need: need), spoken: "\(range), not enough nights, \(have) of \(need)"
            ))
        }
        // Newest first within a kind: by the last morning, then the id.
        rows.sort { $0.id.lastMorning != $1.id.lastMorning ? $0.id.lastMorning > $1.id.lastMorning : $0.id > $1.id }
        return ReviewListContent(weekly: rows.filter { $0.kind == .weekly }, monthly: rows.filter { $0.kind == .monthly })
    }
}
