import Foundation
import PremiumKit
import ReviewKit

// The weekly and monthly review cards on Home (APP_RULES.md R63), and what a link or a notification that opens a review lands on. Pure rules and one provider: no view
// decides anything.

/// What a Home card says. Calm: the title and the dates. No count, no badge, no urgency.
public nonisolated struct HomeReviewCard: Sendable, Equatable, Identifiable {
    public let id: ReviewID
    /// "Your weekly review".
    public let title: String
    /// "Sep 20 – 26", "September 2026".
    public let detail: String

    public var kind: ReviewKind { id.kind }

    /// The feature the card opens: the weekly review's cover is free, the monthly review is Premium (a lock glyph on its card for the free plan).
    public var feature: Feature { kind == .weekly ? .weeklyReviewCover : .monthlyReview }

    public var accessibilityLabel: String { "\(title), \(detail)" }

    public init(id: ReviewID, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public nonisolated enum ReviewCardPolicy {
    /// A card appears when its period ends and goes after this many days if it was never opened: a week's from its review day, a month's for the first days of the
    /// month.
    public static let visibleDays = 3

    /// Whether `now` is inside the card's days: from the period's end (the first moment of the morning after it) until three days have passed.
    public static func isInWindow(_ period: ReviewPeriod, now: Date, calendar: Calendar) -> Bool {
        let start = period.completeAt(calendar: calendar)
        guard now >= start, let end = calendar.date(byAdding: .day, value: visibleDays, to: start) else { return false }
        return now < end
    }

    /// Whether a kept review's card shows now: inside its days, and not opened yet.
    public static func isShown(_ stored: StoredReview, now: Date, calendar: Calendar) -> Bool {
        stored.state == .new && isInWindow(stored.record.period, now: now, calendar: calendar)
    }

    public static func card(for period: ReviewPeriod, format: ReviewFormat) -> HomeReviewCard {
        HomeReviewCard(id: period.id, title: ReviewScreenBuilder.title(kind: period.kind), detail: ReviewScreenBuilder.dateRange(period, format))
    }
}

/// Which review cards Home shows. A review is looked up before it is made: a kept one is never made again here (only opening it inside its first 24 hours does that),
/// and a period with too few nights is asked about at most once in `retryAfter`, so Health changes do not read Health again and again.
public actor ReviewCardProvider {
    private let repository: ReviewRepository
    private let clock: @Sendable () -> Date
    private let retryAfter: TimeInterval
    private var attempts: [ReviewID: Date] = [:]
    /// Reviews the person has just deleted: their cards do not come back by themselves.
    private var deleted: Set<ReviewID> = []

    public init(repository: ReviewRepository, retryAfter: TimeInterval = 600, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.retryAfter = retryAfter
        self.clock = clock
    }

    /// Nothing is made up: a card is there only for a review that exists, inside its days, not yet opened. Weekly first.
    public func cards(profile: UserProfileSnapshot, weekday: Int, locale: Locale = .autoupdatingCurrent) async -> [HomeReviewCard] {
        let now = clock()
        let calendar = await repository.calendar()
        let format = ReviewFormat(locale: locale)
        var cards: [HomeReviewCard] = []
        for period in [await repository.latestWeekly(weekday: weekday), await repository.latestMonthly()] {
            guard ReviewCardPolicy.isInWindow(period, now: now, calendar: calendar), !deleted.contains(period.id) else { continue }
            if let stored = await repository.stored(period.id) {
                if ReviewCardPolicy.isShown(stored, now: now, calendar: calendar) { cards.append(ReviewCardPolicy.card(for: period, format: format)) }
                continue
            }
            if let last = attempts[period.id], now.timeIntervalSince(last) < retryAfter { continue }
            attempts[period.id] = now
            if case .review(let stored) = await repository.review(period, profile: profile), ReviewCardPolicy.isShown(stored, now: now, calendar: calendar) {
                cards.append(ReviewCardPolicy.card(for: period, format: format))
            }
        }
        return cards
    }

    /// Data management deleted the reviews: the cards of the week and month that have just ended do not make the review again on their own (opening one still does).
    public func reviewsDeleted(weekday: Int) async {
        attempts = [:]
        deleted.insert(await repository.latestWeekly(weekday: weekday).id)
        deleted.insert(await repository.latestMonthly().id)
    }
}

// MARK: - What opening a review lands on

/// What a review's page says when there is no story to tell (APP_RULES.md R63): too few nights with the real count, a period not over, no Apple Health, a failed read.
public nonisolated enum ReviewRoutePage: Sendable, Equatable {
    /// The period has too few nights: "4 of 5 nights so far".
    case notEnough(ReviewNotReadyContent)
    /// The period is not over (only a link made by hand reaches it).
    case notOver(ReviewNotReadyContent)
    /// NOCTIS cannot read Apple Health.
    case noAccess(title: String, line: String)
    /// Reading Apple Health failed: "Try again".
    case failed(title: String, line: String)
}

public nonisolated enum ReviewRoute {
    /// The period a route names: the one its id names, or the latest of its kind (a week by the person's review day, or the previous month).
    public static func period(kind: ReviewKind, id: ReviewID?, weekday: Int, now: Date, calendar: Calendar) -> ReviewPeriod {
        if let id, let period = ReviewPeriod.period(for: id) { return period }
        switch kind {
        case .weekly: return ReviewPeriod.latestWeekly(now: now, weekday: weekday, calendar: calendar)
        case .monthly: return ReviewPeriod.latestMonthly(now: now, calendar: calendar)
        }
    }

    /// The page for an outcome that has no review to show; nil when there is one (its story is drawn).
    public static func page(for outcome: ReviewOutcome, period: ReviewPeriod, format: ReviewFormat) -> ReviewRoutePage? {
        switch outcome {
        case .review:
            return nil
        case .notEnoughNights(let have, let need):
            return .notEnough(ReviewScreenBuilder.notReady(period: period, have: have, need: need, format: format))
        case .notComplete:
            return .notOver(ReviewScreenBuilder.notOver(period: period, format: format))
        case .noAccess:
            return .noAccess(title: "No Health data", line: "NOCTIS can't read Apple Health yet. Connect it in Settings and your reviews will appear here.")
        case .unavailable:
            return .failed(title: "Your review didn't load", line: "Apple Health didn't answer. Try again in a moment.")
        }
    }
}
