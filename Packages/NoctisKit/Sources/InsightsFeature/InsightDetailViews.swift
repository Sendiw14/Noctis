import DesignSystem
import HomeFeature
import InsightsKit
import NoctisCore
import SwiftUI

/// One insight's page, pushed over the tab (zooming from the card it came
/// from): a header block in the category's color, the evidence at full width,
/// the sentences, how it was found, and two ways to say it wasn't for you.
/// A page in a navigation stack, not a sheet. It reads only the view model's
/// content (APP_RULES.md R20).
public struct InsightDetailScreen: View {
    let viewModel: InsightsViewModel
    let id: String

    @Environment(\.dismiss) private var closePage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsed = false

    public init(viewModel: InsightsViewModel, id: String) {
        self.viewModel = viewModel
        self.id = id
    }

    public var body: some View {
        ScrollView {
            Group {
                if let content = viewModel.detail(id: id) {
                    InsightDetailBody(content: content) { act($0, content) }
                        // Not useful and Hide collapse the page as it closes.
                        .opacity(collapsed ? 0 : 1)
                        .scaleEffect(collapsed && !reduceMotion ? 0.94 : 1, anchor: .top)
                } else if viewModel.snapshot != nil {
                    Text("This insight isn't available any more.")
                        .noctisFont(17, relativeTo: .body)
                        .foregroundStyle(.noctisInk2)
                        .padding(NoctisSpacing.xl)
                } else {
                    InsightsSkeletonView()
                }
            }
            .frame(maxWidth: InsightsScreen.contentMaxWidth)
            .padding(.horizontal, NoctisSpacing.lg)
            .padding(.top, NoctisSpacing.xs)
            .padding(.bottom, NoctisSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
        .navigationTitle(viewModel.detail(id: id)?.category.title ?? "Insight")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.onAppear()
            viewModel.markSeen(id: id)
        }
        .accessibilityIdentifier("insights.detail")
    }

    /// A soft haptic, the page folds away, the change is made and the page
    /// closes.
    private func act(_ action: InsightDetailAction, _ content: InsightDetailContent) {
        guard !collapsed else { return }
        NoctisHaptics.soft()
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) { collapsed = true }
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.3))
            switch action {
            case .notUseful: await viewModel.dismiss(id: content.id)
            case .hide: await viewModel.hide(content.type)
            }
            closePage()
        }
    }
}

enum InsightDetailAction {
    case notUseful
    case hide
}

/// The page's content, in order.
struct InsightDetailBody: View {
    let content: InsightDetailContent
    let act: (InsightDetailAction) -> Void
    @State private var methodOpen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            InsightDetailHeader(content: content)
            evidence
            sentences
            if let attempt = content.whatYouCanTry {
                NoctisColorBlock(fill: NoctisAppColor.blockButter) {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                        NoctisCaption("WHAT YOU CAN TRY", style: .noctisFieldInk2)
                        Text(attempt)
                            .noctisFont(17, .medium, relativeTo: .body)
                            .foregroundStyle(.noctisFieldInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("insights.try")
            }
            confidence
            CoachAskButton("Ask Coach about this", question: .insight(content.type), identifier: "insights.askCoach")
            method
            actions
        }
    }

    // MARK: Evidence

    private var evidence: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                NoctisCaption("EVIDENCE", style: .noctisInk3)
                if let chart = content.chart {
                    InsightChartView(content: chart, style: .detail)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(content.accessibilityLabel)
                        .accessibilityIdentifier("insights.chart")
                }
                VStack(spacing: NoctisSpacing.xs) {
                    ForEach(Array(content.evidenceLines.enumerated()), id: \.offset) { _, line in
                        let parts = line.components(separatedBy: " · ")
                        HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.md) {
                            Text(parts.first ?? line)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(.noctisInk2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Text(parts.count > 1 ? parts[1] : "")
                                .noctisFont(15, .semibold, relativeTo: .subheadline)
                                .foregroundStyle(NoctisAppColor.ink)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.evidence")
    }

    // MARK: Sentences

    private var sentences: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                section("Context", content.context)
                Rectangle().fill(NoctisAppColor.hairline).frame(height: 1)
                section("Interpretation", content.interpretation)
                if let notProof = content.notProofLine {
                    Text(notProof)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("insights.notProof")
                }
                Rectangle().fill(NoctisAppColor.hairline).frame(height: 1)
                section("What to notice", content.whatToNotice)
            }
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
            Text(title)
                .noctisFont(17, .semibold, relativeTo: .headline)
                .foregroundStyle(NoctisAppColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .noctisFont(17, relativeTo: .body)
                .foregroundStyle(.noctisInk2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Confidence

    private var confidence: some View {
        HStack(spacing: NoctisSpacing.xs) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.noctisInk3)
                .accessibilityHidden(true)
            Text(content.confidenceLine)
                .noctisFont(13, .medium, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, NoctisSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("insights.confidence")
    }

    // MARK: How this was found

    private var method: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                Button {
                    NoctisHaptics.snapLight()
                    withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) { methodOpen.toggle() }
                } label: {
                    HStack {
                        Text("How this was found")
                            .noctisFont(17, .semibold, relativeTo: .headline)
                            .foregroundStyle(NoctisAppColor.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.noctisInk3)
                            .rotationEffect(.degrees(methodOpen ? 180 : 0))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(methodOpen ? "Expanded" : "Collapsed")
                .accessibilityHint(methodOpen ? "Hides the rule." : "Shows the rule.")
                if methodOpen {
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        Text(content.method.rule)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(.noctisInk2)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                            ForEach(Array(content.method.thresholds.enumerated()), id: \.offset) { _, threshold in
                                HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.xs) {
                                    Circle().fill(NoctisAppColor.ink3).frame(width: 5, height: 5).offset(y: -3)
                                    Text(threshold)
                                        .noctisFont(15, relativeTo: .subheadline)
                                        .foregroundStyle(.noctisInk2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        Text(content.method.nights)
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.method")
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: NoctisSpacing.xs) {
            if content.dismissed {
                HStack(spacing: NoctisSpacing.xs) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Marked not useful")
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                }
                .foregroundStyle(.noctisInk3)
                .frame(maxWidth: .infinity, minHeight: 52)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("insights.dismissed")
            } else {
                Button {
                    act(.notUseful)
                } label: {
                    HStack(spacing: NoctisSpacing.xs) {
                        Image(systemName: "hand.thumbsdown")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Not useful")
                            .noctisFont(17, .semibold, relativeTo: .body)
                    }
                    .foregroundStyle(NoctisAppColor.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule(style: .continuous).fill(NoctisAppColor.surface))
                    .overlay(Capsule(style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Removes this insight from your list. It won't be shown again for this evidence.")
                .accessibilityIdentifier("insights.notUseful")
            }
            NoctisTextButton("Hide insights like this", adaptive: true) { act(.hide) }
                .accessibilityHint("Stops showing this kind of insight anywhere.")
                .accessibilityIdentifier("insights.hide")
        }
        .padding(.top, NoctisSpacing.xs)
    }
}

/// The header block in the category's color: the title, the day, and the
/// two numbers.
struct InsightDetailHeader: View {
    let content: InsightDetailContent
    @Environment(\.dynamicTypeSize) private var typeSize

    private var onDark: Bool { content.category == .longTerm }
    private var ink: Color { onDark ? NoctisPaper.bg : NoctisAppColor.blockInk }

    var body: some View {
        NoctisColorBlock(fill: InsightCategoryStyle.of(content.category).fill) {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(spacing: NoctisSpacing.xs) {
                    Image(systemName: InsightCategoryStyle.of(content.category).systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(content.category.title.uppercased())
                        .noctisFont(13, .semibold, relativeTo: .footnote)
                        .tracking(1)
                    Spacer(minLength: 0)
                    Text(content.dateLine)
                        .noctisFont(13, .medium, relativeTo: .footnote)
                }
                .foregroundStyle(ink.opacity(0.85))
                Text(content.title)
                    .noctisFont(28, .bold, relativeTo: .title)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !content.numbers.isEmpty {
                    numbers
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(content.title). \(content.dateLine). " + content.numbers.map { "\($0.label) \($0.value.spoken)" }.joined(separator: ", "))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("insights.header")
    }

    private var numbers: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    ForEach(Array(content.numbers.enumerated()), id: \.offset) { _, number in
                        labeled(number)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                    ForEach(Array(content.numbers.enumerated()), id: \.offset) { index, number in
                        if index > 0 { join.frame(height: 40 * 1.15) }
                        labeled(number)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func labeled(_ number: InsightNumber) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NoctisMetric(number.value, size: 40, relativeTo: .largeTitle, tone: onDark ? .nightPanel : .block)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(number.label)
                .noctisFont(13, .medium, relativeTo: .footnote)
                .foregroundStyle(ink.opacity(0.85))
        }
    }

    @ViewBuilder
    private var join: some View {
        switch content.join {
        case .arrow:
            Image(systemName: "arrow.forward")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ink)
                .accessibilityHidden(true)
        case .versus:
            Text("vs")
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(ink)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - History

/// Every insight so far, newest first, by month; the chips filter it, and a
/// dismissed one stays, muted, with "Not useful" beside it. Tapping one opens
/// the same page.
public struct InsightHistoryScreen: View {
    let viewModel: InsightsViewModel
    let zoom: Namespace.ID
    let open: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(edge: .top)

    public init(viewModel: InsightsViewModel, zoom: Namespace.ID, open: @escaping (String) -> Void) {
        self.viewModel = viewModel
        self.zoom = zoom
        self.open = open
    }

    public var body: some View {
        TabScreenScaffold(
            .insights,
            presentation: .pushed,
            header: TabScreenHeader(
                dateCaption: "EVERY INSIGHT",
                title: "History",
                showsTitle: false,
                summary: AnyView(
                    Text(viewModel.history?.summary ?? " ")
                        .noctisFont(17, relativeTo: .body)
                        .foregroundStyle(.noctisFieldInk2)
                        .accessibilityIdentifier("insights.history.summary")
                )
            ),
            contentTop: .below(NoctisSpacing.md),
            scrollPosition: $scrollPosition
        ) {
            if let history = viewModel.history {
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    InsightChipRow(chips: history.chips, selected: viewModel.historyFilter) { viewModel.select(historyFilter: $0) }
                    VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                        if let note = history.note {
                            InsightsNoteCard(note: note)
                                .transition(.opacity)
                        }
                        ForEach(history.months) { month in
                            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                                Text(month.title)
                                    .noctisFont(22, .bold, relativeTo: .title3)
                                    .foregroundStyle(NoctisAppColor.ink)
                                    .accessibilityAddTraits(.isHeader)
                                NoctisAppCard {
                                    VStack(spacing: 0) {
                                        ForEach(Array(month.rows.enumerated()), id: \.element.id) { index, row in
                                            if index > 0 { Rectangle().fill(NoctisAppColor.hairline).frame(height: 1) }
                                            InsightHistoryRowView(row: row, zoom: zoom, viewModel: viewModel) { open(row.id) }
                                                .transition(.opacity.combined(with: .offset(y: 8)))
                                        }
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .offset(y: 12)))
                        }
                    }
                    .animation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion), value: history)
                }
            } else {
                InsightsSkeletonView()
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .accessibilityIdentifier("insights.history.screen")
    }
}

struct InsightHistoryRowView: View {
    let row: InsightHistoryRow
    let zoom: Namespace.ID
    let viewModel: InsightsViewModel
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) {
            HStack(spacing: NoctisSpacing.sm) {
                InsightCategoryTile(category: row.category)
                    .opacity(row.dismissed ? 0.45 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.xs) {
                        Text(row.title)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(row.dismissed ? AnyShapeStyle(.noctisInk3) : AnyShapeStyle(NoctisAppColor.ink))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(row.line)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(row.dismissed ? .noctisInk3 : .noctisInk2)
                        .multilineTextAlignment(.leading)
                        // The whole line at accessibility sizes (it was cut to "Deep sleep was 4% of la..." at AX5 on an SE).
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: NoctisSpacing.xs) {
                        Text(row.date)
                            .noctisFont(13, .medium, relativeTo: .footnote)
                            .foregroundStyle(.noctisInk3)
                        if row.dismissed {
                            Text("Not useful")
                                .noctisFont(12, .semibold, relativeTo: .caption)
                                .foregroundStyle(.noctisInk3)
                                .padding(.horizontal, NoctisSpacing.xs)
                                .padding(.vertical, 2)
                                .background(Capsule(style: .continuous).fill(NoctisAppColor.track))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.noctisInk3)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, NoctisSpacing.sm)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "history-\(row.id)", in: zoom)
        .insightContextMenu(id: row.id, type: row.type, viewModel: viewModel, dismissible: !row.dismissed, open: open)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHint("Opens the insight.")
        .accessibilityIdentifier("insights.history.row.\(row.id)")
    }
}

// MARK: - Long-press menu

extension View {
    /// The long-press menu on an insight's card: Open, Not useful, Hide
    /// insights like this.
    func insightContextMenu(id: String, type: InsightType, viewModel: InsightsViewModel, dismissible: Bool = true, open: @escaping () -> Void) -> some View {
        contextMenu {
            Button("Open", systemImage: "arrow.up.forward.square", action: open)
            if dismissible {
                Button("Not useful", systemImage: "hand.thumbsdown") {
                    NoctisHaptics.soft()
                    Task { await viewModel.dismiss(id: id) }
                }
            }
            Button("Hide insights like this", systemImage: "eye.slash") {
                NoctisHaptics.soft()
                Task { await viewModel.hide(type) }
            }
        }
    }
}
