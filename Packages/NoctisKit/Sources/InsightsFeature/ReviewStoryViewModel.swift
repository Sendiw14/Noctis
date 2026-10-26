import DesignSystem
import Foundation
import NoctisCore
import Observation
import ReviewKit
import SwiftUI

// A review's story (APP_RULES.md R63): which page is showing, what the plan lets a person see, which pages have played their hero, and what to say when there is no story
// to tell. The views read this and nothing else (R20); every number and word on a page was made by `ReviewStoryBuilder`.

/// A page's flat color field and the inks on it. Cocoa ink on the color pages (the app's section fields, so their contrast is already held), ivory ink on the cocoa page, and
/// the paper's own ink on the paper.
extension ReviewPageTint {
    var fill: Color {
        switch self {
        case .apricot: NoctisAppColor.fieldApricot
        case .sage: NoctisAppColor.blockSage
        case .butter: NoctisAppColor.blockButter
        case .lavender: NoctisAppColor.blockLavender
        case .sand: NoctisAppColor.fieldSand
        case .cocoa: NoctisAppColor.nightPanel
        case .paper: NoctisAppColor.bg
        }
    }

    /// The tab-field section whose contrast numbers this color shares; nil for the cocoa and paper pages.
    var section: NoctisSection? {
        switch self {
        case .apricot: .home
        case .sage: .sleep
        case .lavender: .recovery
        case .butter: .insights
        case .sand: .profile
        case .cocoa, .paper: nil
        }
    }

    /// Titles and numbers.
    var ink: Color {
        switch self {
        case .cocoa: NoctisAppColor.nightInk
        case .paper: NoctisAppColor.ink
        default: NoctisAppColor.blockInk
        }
    }

    /// Quieter lines: the field's own 80% (raised where a field needs it), the night ink's 70%, the paper's ink2.
    func quietInk(dark: Bool, raised: Bool) -> Color {
        switch self {
        case .cocoa: NoctisAppColor.nightInk.opacity(raised ? 0.9 : 0.7)
        case .paper: raised ? NoctisAppColor.ink : NoctisAppColor.ink2
        default:
            NoctisAppColor.blockInk.opacity(raised ? 1 : (section?.quietOpacity(target: NoctisFieldInkStyle.summaryOpacity, dark: dark) ?? (dark ? 1 : 0.9)))
        }
    }

    /// The inverse: what a button's label is when its fill is the ink.
    var onInk: Color { fill }
}

/// What a story shows: its pages, or a message.
@Observable
public final class ReviewStoryViewModel {
    public enum Phase: Equatable {
        case loading
        case story(ReviewStory)
        case message(ReviewRoutePage)
    }

    public let kind: ReviewKind
    public private(set) var phase: Phase = .loading
    public private(set) var index = 0
    /// Which way the last page change went, for the slide.
    public private(set) var movedForward = true
    /// Bumped when the plan changes, so what a person sees is read again.
    public private(set) var planVersion = 0

    private let id: ReviewID?
    private let repository: ReviewRepository?
    private let profile: () -> UserProfileSnapshot
    private let weekday: () -> Int
    private let isUnlockedCheck: (Feature) -> Bool
    private let clock: () -> Date
    private let locale: Locale
    private let opened: () -> Void
    private let prepareInsights: () async -> Void
    private let availableInsights: (Set<String>) -> Set<String>
    private let startPage: String?
    private var heroPlayed: Set<String> = []

    public init(
        kind: ReviewKind, id: ReviewID?, repository: ReviewRepository?, profile: @escaping () -> UserProfileSnapshot, weekday: @escaping () -> Int = { 1 },
        isUnlocked: @escaping (Feature) -> Bool = { _ in true }, clock: @escaping () -> Date = { Date() }, locale: Locale = .autoupdatingCurrent,
        prepareInsights: @escaping () async -> Void = {}, availableInsights: @escaping (Set<String>) -> Set<String> = { $0 }, startPage: String? = nil,
        opened: @escaping () -> Void = {}
    ) {
        self.kind = kind
        self.id = id
        self.repository = repository
        self.profile = profile
        self.weekday = weekday
        self.isUnlockedCheck = isUnlocked
        self.clock = clock
        self.locale = locale
        self.prepareInsights = prepareInsights
        self.availableInsights = availableInsights
        self.startPage = startPage
        self.opened = opened
    }

    // MARK: What the plan lets a person see

    /// The feature a story is: every page of the weekly review, or the monthly review (the weekly cover is free).
    public var feature: Feature { kind == .weekly ? .weeklyReviewFull : .monthlyReview }

    public var isUnlocked: Bool {
        _ = planVersion
        return isUnlockedCheck(feature)
    }

    /// A free person's weekly cover ends with one locked card.
    public var showsLockedCard: Bool { kind == .weekly && !isUnlocked }

    public var story: ReviewStory? {
        if case .story(let story) = phase { story } else { nil }
    }

    public var pages: [ReviewStoryPage] { story?.visiblePages(unlocked: isUnlocked) ?? [] }

    public var current: ReviewStoryPage? {
        let pages = pages
        return pages.indices.contains(index) ? pages[index] : pages.first
    }

    public var shareContent: ReviewShareContent? { story?.share(unlocked: isUnlocked) }

    /// A share button is there when something shareable is shown: the cover and the sleep page, and a month's last page.
    public var canShare: Bool {
        guard shareContent != nil, let current else { return false }
        return current.isShareable || (kind == .monthly && isLast)
    }

    // MARK: Paging

    public var canGoBack: Bool { index > 0 }
    public var canGoNext: Bool { index < pages.count - 1 }
    public var isLast: Bool { !pages.isEmpty && index >= pages.count - 1 }

    public func goNext() {
        guard canGoNext else { return }
        movedForward = true
        index += 1
    }

    public func goBack() {
        guard canGoBack else { return }
        movedForward = false
        index -= 1
    }

    /// A swipe landed on a page.
    public func select(_ page: Int) {
        guard pages.indices.contains(page), page != index else { return }
        movedForward = page > index
        index = page
    }

    /// The plan changed (a purchase from the cover, or a lapse): the pages are read again, and the page a person is on stays.
    public func tierChanged() {
        planVersion += 1
        index = min(index, max(pages.count - 1, 0))
    }

    // MARK: Each page's hero plays once

    /// Whether a page has already played its hero: it is drawn at its end state, with no motion, on a revisit.
    public func hasPlayedHero(_ pageID: String) -> Bool { heroPlayed.contains(pageID) }

    public func claimHero(_ pageID: String) { heroPlayed.insert(pageID) }

    // MARK: Insights

    public var insightDetail: (String) -> InsightDetailContent? = { _ in nil }

    // MARK: Loading

    /// Makes (or finds) the review of the period the route names and draws what there is to say about it. A review that exists counts as opened, so its card on Home goes.
    public func load() async {
        phase = .loading
        guard let repository else {
            phase = .message(.failed(title: "Your review didn't load", line: "Apple Health didn't answer. Try again in a moment."))
            return
        }
        // The Insights tab's own insights first: a review made now points to them, and its insight page reads them.
        await prepareInsights()
        let calendar = await repository.calendar()
        let period = ReviewRoute.period(kind: kind, id: id, weekday: weekday(), now: clock(), calendar: calendar)
        let outcome = await repository.review(period, profile: profile())
        let format = ReviewFormat(locale: locale)
        if let page = ReviewRoute.page(for: outcome, period: period, format: format) {
            phase = .message(page)
            return
        }
        guard case .review(let stored) = outcome else { return }
        let story = ReviewStoryBuilder.build(stored.record, format: format)
        let ids = Set(
            story.pages.flatMap { page -> [String] in
                if case .insights(let content) = page.content { content.insightIDs } else { [] }
            })
        phase = .story(story.keepingInsights(availableInsights(ids)))
        if let startPage, let start = pages.firstIndex(where: { $0.kind.rawValue == startPage }) { index = start }
        await repository.markSeen(stored.id)
        opened()
    }
}
