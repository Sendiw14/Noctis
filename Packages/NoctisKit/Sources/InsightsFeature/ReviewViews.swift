import DesignSystem
import NoctisCore
import Observation
import ReviewKit
import SwiftUI

// The Reviews row on the Insights tab, the Reviews list and a review's page, until the screens that draw a review exist (the next part): a real review is announced and
// the page says it is coming (APP_RULES.md R19, ROADMAP.md); too few nights is said plainly, with the real count. Every sentence comes from `ReviewRoute` and
// `ReviewScreenBuilder`, never from a view.

/// What a review's page holds while it is made, and then. Reads the review through `ReviewRepository`, so a link, a notification and a Home card agree.
@Observable
public final class ReviewRouteViewModel {
    public enum State: Equatable {
        case loading
        case page(ReviewRoutePage)
    }

    public private(set) var state: State = .loading
    public let kind: ReviewKind

    private let id: ReviewID?
    private let repository: ReviewRepository?
    private let profile: () -> UserProfileSnapshot
    private let weekday: () -> Int
    private let clock: () -> Date
    private let locale: Locale
    private let opened: () -> Void

    public init(
        kind: ReviewKind, id: ReviewID?, repository: ReviewRepository?, profile: @escaping () -> UserProfileSnapshot, weekday: @escaping () -> Int = { 1 },
        clock: @escaping () -> Date = { Date() }, locale: Locale = .autoupdatingCurrent, opened: @escaping () -> Void = {}
    ) {
        self.kind = kind
        self.id = id
        self.repository = repository
        self.profile = profile
        self.weekday = weekday
        self.clock = clock
        self.locale = locale
        self.opened = opened
    }

    /// Makes (or finds) the review of the period the route names, and shows what there is to say about it. A review that exists counts as opened, so its card on Home goes.
    public func load() async {
        guard let repository else {
            state = .page(.unavailable(title: "Your sleep can't be read right now", line: "Open the Health data page in Settings to check NOCTIS can read it, then come back."))
            return
        }
        let calendar = await repository.calendar()
        let period = ReviewRoute.period(kind: kind, id: id, weekday: weekday(), now: clock(), calendar: calendar)
        let outcome = await repository.review(period, profile: profile())
        state = .page(ReviewRoute.page(for: outcome, period: period, format: ReviewFormat(locale: locale)))
        if case .review(let stored) = outcome {
            await repository.markSeen(stored.id)
            opened()
        }
    }
}

/// The Reviews row, above Recent: opens the Reviews list.
struct InsightsReviewsRow: View {
    let open: () -> Void

    var body: some View {
        NoctisRowCard {
            NoctisLinkRow(
                systemImage: "calendar", fill: NoctisAppColor.blockLavender, title: "Reviews", detail: "Your weekly and monthly reviews", hint: "Opens your reviews.",
                identifier: "insights.reviews", action: open
            )
        }
    }
}

/// The Reviews list: a "Coming soon" card until the list is built.
struct ReviewsListScreen: View {
    @State private var scrollPosition = ScrollPosition(edge: .top)

    var body: some View {
        TabScreenScaffold(
            .insights,
            presentation: .pushed,
            header: TabScreenHeader(
                dateCaption: "REVIEWS", title: "Reviews", showsTitle: false,
                summary: AnyView(
                    Text("Your weekly and monthly reviews.")
                        .noctisFont(17, relativeTo: .body)
                        .foregroundStyle(.noctisFieldInk2)
                )
            ),
            contentTop: .below(NoctisSpacing.md),
            scrollPosition: $scrollPosition
        ) {
            ReviewMessageCard(caption: "COMING SOON", headline: "Reviews are coming.", detail: "A list of every weekly and monthly review will be here.", identifier: "reviews.comingSoon")
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("reviews.list")
    }
}

/// One review's page: what the route found.
struct ReviewRouteScreen: View {
    let model: ReviewRouteViewModel
    @State private var scrollPosition = ScrollPosition(edge: .top)

    var body: some View {
        TabScreenScaffold(
            .insights,
            presentation: .pushed,
            header: TabScreenHeader(
                dateCaption: dateCaption, title: title, showsTitle: false,
                summary: AnyView(
                    Text(summary)
                        .noctisFont(17, relativeTo: .body)
                        .foregroundStyle(.noctisFieldInk2)
                )
            ),
            contentTop: .below(NoctisSpacing.md),
            scrollPosition: $scrollPosition
        ) {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .accessibilityIdentifier("reviews.review.\(model.kind.rawValue)")
    }

    /// The page's name (the navigation bar): the review's own.
    private var title: String {
        if case .page(.comingSoon(let title, _, _)) = model.state { return title }
        return ReviewScreenBuilder.title(kind: model.kind)
    }

    /// The line under it: what there is to say, once it is known (never the title again).
    private var summary: String {
        switch model.state {
        case .loading, .page(.comingSoon): " "
        case .page(.notEnough(let content)), .page(.notOver(let content)): content.title
        case .page(.unavailable(let title, _)): title
        }
    }

    private var dateCaption: String {
        switch model.state {
        case .loading, .page(.unavailable): " "
        case .page(.comingSoon(_, let range, _)): range.uppercased()
        case .page(.notEnough(let content)), .page(.notOver(let content)): content.dateRange.uppercased()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            InsightsSkeletonView()
        case .page(.notEnough(let content)), .page(.notOver(let content)):
            ReviewMessageCard(caption: "YOUR \(model.kind == .weekly ? "WEEK" : "MONTH")", headline: content.count, detail: content.detail, identifier: "reviews.notEnough", prominent: true)
        case .page(.comingSoon(_, _, let line)):
            ReviewMessageCard(caption: "COMING SOON", headline: "Your review is ready.", detail: line, identifier: "reviews.comingSoon")
        case .page(.unavailable(_, let line)):
            ReviewMessageCard(caption: "HEALTH DATA", headline: "Not available right now.", detail: line, identifier: "reviews.unavailable")
        }
    }
}

/// A calm card with a caption, a line and a sentence: the count, or the word that the screen is coming.
struct ReviewMessageCard: View {
    let caption: String
    let headline: String
    let detail: String
    let identifier: String
    /// The headline is a number ("4 of 5 nights"): set large.
    var prominent = false

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption(caption, style: .noctisInk3)
                Text(headline)
                    .noctisFont(prominent ? 34 : 22, .bold, relativeTo: prominent ? .largeTitle : .title3)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
