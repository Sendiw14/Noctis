import DesignSystem
import HomeFeature
import InsightsKit
import NoctisCore
import PremiumKit
import ReviewKit
import SwiftUI
import NoctisText

/// A review's story (APP_RULES.md R63): a full-screen page pushed over Insights with the tab bar hidden, a horizontally paged story with progress segments across the top, a
/// Close button, a Share button where something shareable is shown, and Back and Next buttons, so nothing depends on a gesture alone. A swipe pages it, and a tap on the left or
/// right third of the screen goes back or on. There are no timers and nothing advances by itself. Reduce Motion: fades only.
public struct ReviewStoryScreen: View {
    /// Made once for this page (a navigation destination is built again whenever the stack changes, and a new model would start loading again).
    @State private var model: ReviewStoryViewModel
    let insights: InsightsViewModel

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.featureGate) private var gate
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var scaledBottomInset: CGFloat = 68
    @State private var position: Int?
    @State private var width: CGFloat = 0
    @State private var safe = EdgeInsets()
    @State private var sharing = false

    public init(kind: ReviewKind, id: ReviewID?, insights: InsightsViewModel) {
        _model = State(initialValue: insights.reviewStory(kind: kind, id: id))
        self.insights = insights
    }

    public var body: some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .task {
                model.insightDetail = { insights.detail(id: $0) }
                await model.load()
            }
            .onChange(of: gate.tier) { model.tierChanged() }
            .sheet(isPresented: $sharing) {
                if let content = model.shareContent { ReviewSharePreviewSheet(content: content) }
            }
            .accessibilityIdentifier("review.story.\(model.kind.rawValue)")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            statePage { InsightsSkeletonView().padding(.horizontal, NoctisSpacing.lg) }
        case .message(let page):
            statePage { ReviewMessageView(page: page) { Task { await model.load() } } }
        case .story:
            story
        }
    }

    // MARK: A message, with a way out

    private func statePage<Content: View>(@ViewBuilder _ body: () -> Content) -> some View {
        ZStack(alignment: .top) {
            NoctisAppColor.bg.ignoresSafeArea()
            VStack(spacing: NoctisSpacing.md) {
                HStack {
                    closeButton(ink: NoctisAppColor.ink, fill: NoctisAppColor.bg)
                    Spacer()
                }
                .padding(.horizontal, NoctisSpacing.sm)
                body()
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: The story

    private var story: some View {
        let tint = model.current?.tint ?? .paper
        let ink = tint.ink
        return ZStack {
            pager
            // The chrome sits over the pages: progress and buttons on top, Back and Next below.
            VStack(spacing: 0) {
                top(ink: ink, fill: tint.fill)
                    .background(alignment: .bottom) { band(tint.fill, fadesAbove: false).ignoresSafeArea(edges: .top) }
                Spacer(minLength: 0)
                bottom(tint: tint)
                    .background(alignment: .top) { band(tint.fill, fadesAbove: true).ignoresSafeArea(edges: .bottom) }
            }
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safe = $0 }
        .onChange(of: model.index) {
            guard position != model.index else { return }
            withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) { position = model.index }
        }
        .onChange(of: position) {
            if let position, position != model.index { model.select(position) }
        }
        .onAppear { position = model.index }
    }

    private var pager: some View {
        let pages = model.pages
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    pageView(page, isCurrent: index == model.index)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .all)
        // Reduce Motion: the pages cross-fade; swiping still goes back and on.
        .scrollDisabled(reduceMotion)
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // A tap on the left or right third goes back or on. A button on a page takes its own tap first.
        .gesture(
            SpatialTapGesture().onEnded { tap in
                guard width > 0 else { return }
                if tap.location.x < width / 3 { model.goBack() } else if tap.location.x > width * 2 / 3 { model.goNext() }
            }
        )
        .overlay {
            if reduceMotion { fadedPage }
        }
    }

    /// Under Reduce Motion the sliding pages are hidden behind one page that fades.
    @ViewBuilder
    private var fadedPage: some View {
        if let page = model.current {
            pageView(page, isCurrent: true)
                .id(page.id)
                .transition(.opacity)
                .gesture(
                    DragGesture(minimumDistance: 24).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        if value.translation.width < 0 { model.goNext() } else { model.goBack() }
                    }
                )
                .animation(NoctisMotion.reduced, value: model.index)
        }
    }

    // MARK: Pages

    private func pageView(_ page: ReviewStoryPage, isCurrent: Bool) -> some View {
        ReviewPageHost(page: page, isCurrent: isCurrent, model: model) { style, revealed in
            pageContent(page, style: style, revealed: revealed)
                // Room for the progress and the buttons above, and Back and Next below.
                .padding(.top, safe.top + Self.topInset)
                .padding(.bottom, safe.bottom + bottomInset)
        }
    }

    @ViewBuilder
    private func pageContent(_ page: ReviewStoryPage, style: ReviewPageStyle, revealed: Bool) -> some View {
        switch page.content {
        case .cover(let cover):
            ReviewCoverPageView(
                page: cover, style: style, revealed: revealed,
                locked: model.showsLockedCard ? LockedCopy.card(for: .weeklyReview) : nil
            ) { appModel.presentPaywall(for: model.feature) }
        case .bars(let bars):
            ReviewBarsPageView(page: bars, caption: page.kind == .sleep ? "Sleep" : "Sleep pattern", style: style, revealed: revealed)
        case .timing(let timing):
            ReviewTimingPageView(page: timing, caption: page.kind == .consistency ? "Consistency" : "Consistency and timing", style: style, revealed: revealed)
        case .line(let line):
            ReviewLinePageView(page: line, caption: page.kind == .recovery ? "Recovery" : "Recovery pattern", style: style, revealed: revealed)
        case .changes(let changes):
            ReviewChangesPageView(page: changes, caption: page.kind == .changes ? "What changed" : "Major changes", style: style, revealed: revealed)
        case .insights(let insight):
            ReviewInsightPageView(
                page: insight, caption: NoctisCount.insightCaption(insight.insightIDs.count), style: style, detail: { model.insightDetail($0) },
                open: { appModel.insightsPath.append(.insight(id: $0)) }
            )
        case .focus(let focus):
            ReviewFocusPageView(page: focus, caption: "Next", style: style) { topic in appModel.open(.coach(question: Self.question(for: topic))) }
        case .records(let records):
            ReviewRecordsPageView(page: records, caption: "Records", style: style)
        case .locked:
            ReviewLockedPageView(style: style, card: LockedCopy.card(for: .monthlyReview)) { appModel.presentPaywall(for: model.feature) }
        }
    }

    /// What Coach is asked about a focus: its own question, nothing from the review.
    static func question(for topic: ReviewCoachTopic) -> CoachQuestion {
        switch topic {
        case .consistency: .consistency
        case .bedtime: .bedtime
        case .recovery: .recovery(.lower)
        }
    }

    // MARK: Chrome

    /// The progress segments (3pt, no timers), and under them Close and Share, 44pt each.
    static let topInset: CGFloat = 64
    static let bottomInset: CGFloat = 68

    /// Back and Next grow with the text size, so the room under a page does: at AX5 a 58pt button sat on the page's last line (QA part 3,
    /// QA-070). Capped, so a short page does not become all inset.
    private var bottomInset: CGFloat { min(scaledBottomInset, Self.bottomInset * 1.7) }

    /// The page's own colour behind the chrome, with a 24pt fade where the page's text arrives at it: a paragraph that runs on under Back and Next
    /// (or up under the progress and Close) goes into a band instead of through the buttons (QA part 3, QA-070).
    private func band(_ color: Color, fadesAbove: Bool) -> some View {
        ZStack(alignment: fadesAbove ? .top : .bottom) {
            color
            LinearGradient(
                colors: fadesAbove ? [color.opacity(0), color] : [color, color.opacity(0)], startPoint: .top, endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: fadesAbove ? -24 : 24)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A button's flat circle: the page's own color with the ink at 12% over it, so a page scrolling under it never shows through.
    private func buttonBack(ink: Color, fill: Color) -> some View {
        ZStack {
            Circle().fill(fill)
            Circle().fill(ink.opacity(0.12))
        }
    }

    private func top(ink: Color, fill: Color) -> some View {
        VStack(spacing: NoctisSpacing.xs) {
            HStack(spacing: 4) {
                ForEach(0..<max(model.pages.count, 1), id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(ink.opacity(0.25))
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous).fill(ink).opacity(index <= model.index ? 1 : 0)
                        }
                        .frame(height: 3)
                }
            }
            .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: model.index)
            .padding(.horizontal, NoctisSpacing.lg)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(min(model.index + 1, max(model.pages.count, 1))) of \(max(model.pages.count, 1))")
            HStack {
                closeButton(ink: ink, fill: fill)
                Spacer()
                if model.canShare { shareButton(ink: ink, fill: fill) }
            }
            .padding(.horizontal, NoctisSpacing.sm)
        }
        .padding(.top, NoctisSpacing.xs)
    }

    private func closeButton(ink: Color, fill: Color) -> some View {
        Button {
            NoctisHaptics.selection()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .noctisIcon(16, .bold)
                .foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .background { buttonBack(ink: ink, fill: fill) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("review.close")
    }

    private func shareButton(ink: Color, fill: Color) -> some View {
        Button {
            NoctisHaptics.selection()
            sharing = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .noctisIcon(16, .bold)
                .foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .background { buttonBack(ink: ink, fill: fill) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
        .accessibilityHint("Opens a preview of the card to share.")
        .accessibilityIdentifier("review.share")
    }

    /// Back and Next, 44pt each; Next is Done on the last page.
    private func bottom(tint: ReviewPageTint) -> some View {
        HStack {
            if model.canGoBack {
                Button {
                    NoctisHaptics.selection()
                    model.goBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward").noctisIcon(14, .bold)
                        Text("Back").noctisFont(17, .semibold, relativeTo: .body)
                    }
                    .foregroundStyle(tint.ink)
                    .padding(.horizontal, NoctisSpacing.md)
                    .frame(minHeight: 44)
                    .background(tint.fill, in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.back")
            }
            Spacer()
            Button {
                NoctisHaptics.selection()
                if model.isLast { dismiss() } else { model.goNext() }
            } label: {
                HStack(spacing: 4) {
                    Text(model.isLast ? "Done" : "Next").noctisFont(17, .semibold, relativeTo: .body)
                    if !model.isLast { Image(systemName: "chevron.forward").noctisIcon(14, .bold) }
                }
                .foregroundStyle(tint.onInk)
                .padding(.horizontal, NoctisSpacing.lg)
                .frame(minHeight: 44)
                .background(tint.ink, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(model.isLast ? "review.done" : "review.next")
        }
        .padding(.horizontal, NoctisSpacing.md)
        .padding(.bottom, NoctisSpacing.sm)
    }
}

/// What a review says when there is no story to tell: the count, no Health, a failed read with Try again.
struct ReviewMessageView: View {
    let page: ReviewRoutePage
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            switch page {
            case .notEnough(let content):
                ReviewMessageCard(caption: content.dateRange.uppercased(), headline: content.count, detail: content.detail, identifier: "review.notEnough", prominent: true)
            case .notOver(let content):
                ReviewMessageCard(caption: content.dateRange.uppercased(), headline: content.count, detail: content.detail, identifier: "review.notOver")
            case .noAccess(let title, let line):
                ReviewMessageCard(caption: "APPLE HEALTH", headline: title, detail: line, identifier: "review.noAccess")
            case .failed(let title, let line):
                ReviewMessageCard(caption: "APPLE HEALTH", headline: title, detail: line, identifier: "review.failed")
                Button {
                    NoctisHaptics.selection()
                    retry()
                } label: {
                    Text("Try again")
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ctaLabel)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(NoctisAppColor.ctaFill, in: Capsule(style: .continuous))
                }
                .buttonStyle(NoctisCardButtonStyle())
                .accessibilityIdentifier("review.retry")
            }
        }
        .padding(.horizontal, NoctisSpacing.lg)
        .frame(maxWidth: 560, alignment: .leading)
    }
}
