import DesignSystem
import Foundation
import NoctisCore
import Observation
import ReviewKit
import SwiftUI

// The Reviews list (APP_RULES.md R63): the weeks and the months, newest first, each a card with its period, its headline number and whether it has been opened (a small
// lavender dot while new; never a count or a badge). Only reviews that were made are listed, and a past period with too few nights is listed as such.

@Observable
public final class ReviewsListViewModel {
    public enum Phase: Equatable {
        case loading
        case content(ReviewListContent)
        case noAccess
    }

    public private(set) var phase: Phase = .loading

    private let repository: ReviewRepository?
    private let profile: () -> UserProfileSnapshot
    private let weekday: () -> Int
    private let isUnlockedCheck: (Feature) -> Bool
    private let clock: () -> Date
    private let locale: Locale

    public init(
        repository: ReviewRepository?, profile: @escaping () -> UserProfileSnapshot, weekday: @escaping () -> Int = { 1 }, isUnlocked: @escaping (Feature) -> Bool = { _ in true },
        clock: @escaping () -> Date = { Date() }, locale: Locale = .autoupdatingCurrent
    ) {
        self.repository = repository
        self.profile = profile
        self.weekday = weekday
        self.isUnlockedCheck = isUnlocked
        self.clock = clock
        self.locale = locale
    }

    /// The monthly reviews are Premium: a lock glyph on their rows for the free plan (they open the story's one calm locked page).
    public var monthlyLocked: Bool { !isUnlockedCheck(.monthlyReview) }

    public func load() async {
        guard let repository else {
            phase = .noAccess
            return
        }
        let library = await repository.library()
        let now = clock()
        let calendar = await repository.calendar()
        let candidates = ReviewListBuilder.candidates(now: now, weekday: weekday(), calendar: calendar).filter { library[$0.id] == nil && $0.isComplete(at: now, calendar: calendar) }
        // One read of Apple Health, only if there is a period that was not made to ask about.
        let counts = candidates.isEmpty ? [:] : await repository.nightCounts(for: candidates, profile: profile()) ?? [:]
        let content = ReviewListBuilder.build(library: library, counts: counts, now: now, weekday: weekday(), calendar: calendar, format: ReviewFormat(locale: locale))
        phase = .content(content)
    }
}

struct ReviewsListScreen: View {
    let insights: InsightsViewModel
    @State private var model: ReviewsListViewModel
    @Environment(AppModel.self) private var appModel
    @State private var scrollPosition = ScrollPosition(edge: .top)

    init(insights: InsightsViewModel) {
        self.insights = insights
        _model = State(initialValue: insights.reviewsList())
    }

    var body: some View {
        TabScreenScaffold(
            .profile,
            presentation: .pushed,
            header: TabScreenHeader(
                dateCaption: "REVIEWS", title: "Reviews", showsTitle: false,
                summary: AnyView(
                    Text("Your weeks and months, newest first.")
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
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .accessibilityIdentifier("reviews.list")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            InsightsSkeletonView()
        case .noAccess:
            ReviewMessageCard(caption: "APPLE HEALTH", headline: "No Health data", detail: "NOCTIS can't read Apple Health yet. Connect it in Settings and your reviews will appear here.", identifier: "reviews.noAccess")
        case .content(let list):
            if list.isEmpty {
                ReviewMessageCard(
                    caption: "REVIEWS", headline: "Nothing here yet", detail: "Your weekly review appears once a week has at least 5 nights of sleep.", identifier: "reviews.empty"
                )
            } else {
                VStack(alignment: .leading, spacing: NoctisSpacing.lg) {
                    section("Weekly", rows: list.weekly)
                    section("Monthly", rows: list.monthly)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, rows: [ReviewListRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                Text(title)
                    .noctisFont(22, .bold, relativeTo: .title3)
                    .foregroundStyle(NoctisAppColor.ink)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: NoctisSpacing.sm) {
                    ForEach(rows) { row in
                        ReviewListRowView(row: row, locked: row.kind == .monthly && model.monthlyLocked) {
                            NoctisHaptics.selection()
                            appModel.insightsPath.append(.review(kind: row.kind, id: row.id))
                        }
                    }
                }
            }
        }
    }
}

/// One review's card: its period, its headline number and where it stands.
struct ReviewListRowView: View {
    let row: ReviewListRow
    /// A monthly review on the free plan: a lock glyph, and the row opens the story's one calm locked page.
    let locked: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            NoctisAppCard {
                HStack(spacing: NoctisSpacing.sm) {
                    NoctisIconTile(systemImage: "calendar", fill: row.kind == .weekly ? NoctisAppColor.blockLavender : NoctisAppColor.blockSage, foreground: NoctisAppColor.blockInk, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.headline)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(.noctisInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: NoctisSpacing.xs)
                    trailing
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? "\(row.spoken), Premium" : row.spoken)
        .accessibilityHint(locked ? "Opens what Premium includes." : "Opens this review.")
        .accessibilityIdentifier("reviews.row.\(row.id.description)")
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: NoctisSpacing.xs) {
            switch row.status {
            case .new:
                // New: a small lavender dot, never a count.
                Circle().fill(NoctisAppColor.blockLavender).frame(width: 10, height: 10).accessibilityHidden(true)
            case .opened:
                Text("Opened").noctisFont(13, relativeTo: .footnote).foregroundStyle(.noctisInk3)
            case .notEnough:
                Text("Not enough nights").noctisFont(13, relativeTo: .footnote).foregroundStyle(.noctisInk3).multilineTextAlignment(.trailing)
            }
            if locked { LockGlyph(size: 14).foregroundStyle(.noctisInk3) } else { NoctisRowChevron() }
        }
    }
}
