import DesignSystem
import HomeFeature
import InsightsKit
import NoctisCore
import ReviewKit
import SwiftUI

// The pages of a review story (APP_RULES.md R63): each a flat color field with cocoa ink (ivory on the cocoa page), a 28pt-radius content area where a chart needs one, and
// a hero that plays once, the first time the page is the one showing, then stays at its end state. Every number and word was made by `ReviewStoryBuilder`.

/// The inks on a page's field, in the current appearance.
struct ReviewPageStyle {
    let tint: ReviewPageTint
    let dark: Bool
    let raised: Bool

    var ink: Color { tint.ink }
    var quiet: Color { tint.quietInk(dark: dark, raised: raised) }
}

/// A number counting up from zero as `progress` moves (an animatable, so every frame redraws it).
private struct ReviewCountingMetric: View, Animatable {
    let value: NoctisMetricValue
    let size: CGFloat
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        NoctisMetric(value.counting(progress), size: size, relativeTo: .largeTitle, tone: .block)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(value.spoken)
    }
}

extension NoctisMetricValue {
    /// A written value ("6h 42m", "32 min", "52 ms", "71") as its parts, so its units are set the way every number's are (R4).
    nonisolated init(reading text: String) {
        var parts: [Part] = []
        var number = ""
        var unit = ""
        func flush() {
            if !number.isEmpty { parts.append(.number(number)) }
            if !unit.isEmpty { parts.append(.unit(unit)) }
            number = ""
            unit = ""
        }
        for character in text {
            if character.isNumber || (character == "." && !number.isEmpty) {
                if !unit.isEmpty { flush() }
                number.append(character)
            } else if character == " " {
                flush()
                if !parts.isEmpty { parts.append(.space) }
            } else {
                if !number.isEmpty {
                    parts.append(.number(number))
                    number = ""
                }
                unit.append(character)
            }
        }
        flush()
        while case .space? = parts.last { parts.removeLast() }
        self.init(parts: parts, spoken: text)
    }
}

// MARK: - The host of one page

/// A page's field and its scrolling content, with room above for the progress and the buttons and below for Back and Next. The hero's `revealed` state turns true the first time
/// the page is the one showing (and is true from the start on a revisit, and under Reduce Motion).
struct ReviewPageHost<Content: View>: View {
    let page: ReviewStoryPage
    let isCurrent: Bool
    let model: ReviewStoryViewModel
    @ViewBuilder let content: (ReviewPageStyle, Bool) -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed: Bool

    init(page: ReviewStoryPage, isCurrent: Bool, model: ReviewStoryViewModel, @ViewBuilder content: @escaping (ReviewPageStyle, Bool) -> Content) {
        self.page = page
        self.isCurrent = isCurrent
        self.model = model
        self.content = content
        _revealed = State(initialValue: model.hasPlayedHero(page.id))
    }

    private var style: ReviewPageStyle { ReviewPageStyle(tint: page.tint, dark: colorScheme == .dark, raised: contrast == .increased) }

    var body: some View {
        ZStack {
            page.tint.fill.ignoresSafeArea()
            ScrollView {
                content(style, revealed || reduceMotion)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, NoctisSpacing.lg)
                    .padding(.top, NoctisSpacing.sm)
                    .padding(.bottom, NoctisSpacing.lg)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            // Flat fills only: no soft edge where the page scrolls under the status bar or the buttons.
            .scrollEdgeEffectHidden(true, for: .all)
        }
        .task(id: isCurrent) {
            guard isCurrent, !revealed else { return }
            model.claimHero(page.id)
            // After the page has settled into view.
            try? await Task.sleep(for: .seconds(0.25))
            revealed = true
        }
    }
}

// MARK: - Shared parts

private struct ReviewCaption: View {
    let text: String
    let style: ReviewPageStyle

    var body: some View {
        Text(text.uppercased())
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .tracking(13 * 0.08)
            .foregroundStyle(style.quiet)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ReviewHeadline: View {
    let text: String
    let style: ReviewPageStyle
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .noctisFont(size, .bold, relativeTo: .title)
            .foregroundStyle(style.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ReviewLine: View {
    let text: String
    let style: ReviewPageStyle

    var body: some View {
        Text(text)
            .noctisFont(16, relativeTo: .body)
            .foregroundStyle(style.quiet)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A chart's 28pt-radius content area: the app's card, so the gaps between a bar's stages are the card and not the field.
private struct ReviewChartCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NoctisAppCard { content }
    }
}

// MARK: - Cover

struct ReviewCoverPageView: View {
    let page: ReviewCoverPage
    let style: ReviewPageStyle
    let revealed: Bool
    /// A free person's weekly cover ends with one locked card.
    let locked: LockedCopy.Card?
    let unlock: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ReviewCaption(text: page.dateRange, style: style)
            ReviewHeadline(text: page.title, style: style, size: 34)
            Spacer(minLength: NoctisSpacing.xl)
            ReviewCountingMetric(value: HomeFormat.durationMetric(page.averageMinutes), size: 72, progress: revealed ? 1 : 0)
                .animation(reduceMotion ? nil : NoctisMotion.draw(1.0), value: revealed)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(page.spokenAverage)
            Text("average a night")
                .noctisFont(17, relativeTo: .body)
                .foregroundStyle(style.quiet)
            HStack(spacing: NoctisSpacing.xs) {
                if let arrow = page.deltaArrow { ReviewArrowGlyph(arrow: arrow, size: 17) }
                Text(page.deltaText)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(style.ink)
            ReviewLine(text: page.context, style: style)
            if let locked {
                ReviewUnlockCard(card: locked, unlock: unlock)
                    .padding(.top, NoctisSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sleep, and a month's sleep pattern

struct ReviewBarsPageView: View {
    let page: ReviewBarsPage
    let caption: String
    let style: ReviewPageStyle
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ReviewCaption(text: caption, style: style)
            ReviewHeadline(text: page.headline, style: style)
            ReviewChartCard { ReviewBarsChart(page: page, revealed: revealed) }
            ForEach(page.lines, id: \.self) { ReviewLine(text: $0, style: style) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Consistency and timing

struct ReviewTimingPageView: View {
    let page: ReviewTimingPage
    let caption: String
    let style: ReviewPageStyle
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ReviewCaption(text: caption, style: style)
            ReviewHeadline(text: page.headline, style: style)
            ReviewChartCard { ReviewTimingChart(page: page, revealed: revealed) }
            ForEach(page.lines, id: \.self) { ReviewLine(text: $0, style: style) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Recovery

struct ReviewLinePageView: View {
    let page: ReviewLinePage
    let caption: String
    let style: ReviewPageStyle
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ReviewCaption(text: caption, style: style)
            ReviewHeadline(text: page.headline, style: style)
            if let direction = page.direction {
                HStack(spacing: NoctisSpacing.xs) {
                    if let arrow = page.directionArrow { ReviewArrowGlyph(arrow: arrow, size: 17) }
                    Text(direction).noctisFont(17, .semibold, relativeTo: .body)
                }
                .foregroundStyle(style.ink)
            }
            ReviewChartCard { ReviewLineChart(page: page, revealed: revealed) }
            ForEach(page.lines, id: \.self) { ReviewLine(text: $0, style: style) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - What changed

struct ReviewChangesPageView: View {
    let page: ReviewChangesPage
    let caption: String
    let style: ReviewPageStyle
    let revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ReviewCaption(text: caption, style: style)
            // A steady period is one calm tile: its words are the tile's, not a headline over it.
            if page.steadySentence == nil { ReviewHeadline(text: page.headline, style: style) }
            if let sentence = page.steadySentence {
                // Nothing moved by half the person's own variation: one calm tile and a sentence, never a highlight.
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        HStack(spacing: NoctisSpacing.xs) {
                            ReviewArrowGlyph(arrow: .flat, size: 20)
                            Text(page.headline).noctisFont(22, .bold, relativeTo: .title3)
                        }
                        .foregroundStyle(NoctisAppColor.ink)
                        Text(sentence)
                            .noctisFont(16, relativeTo: .body)
                            .foregroundStyle(.noctisInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ForEach(Array(page.tiles.enumerated()), id: \.element.id) { index, tile in
                    ReviewTileView(tile: tile)
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed || reduceMotion ? 0 : 12)
                        .animation(reduceMotion ? nil : NoctisMotion.settle.delay(0.06 * Double(index)), value: revealed)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReviewTileView: View {
    let tile: ReviewChangeTile

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption(tile.caption.uppercased(), style: NoctisInkStyle(.tertiary))
                Text(tile.metric)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.xs) {
                    NoctisMetric(NoctisMetricValue(reading: tile.from), size: 22, weight: .semibold, relativeTo: .title3)
                        .foregroundStyle(NoctisAppColor.ink2)
                    ReviewArrowGlyph(arrow: tile.arrow, size: 17).foregroundStyle(NoctisAppColor.ink)
                    NoctisMetric(NoctisMetricValue(reading: tile.to), size: 28, relativeTo: .title2)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
        }
        // Both numbers are on the tile; the sentence that says them is what VoiceOver reads.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.caption). \(tile.summary)")
    }
}

// MARK: - Insights

/// The top insight: its evidence chart in the Insights style, on the cocoa page, and a Read more button that opens its page.
struct ReviewInsightPageView: View {
    let page: ReviewInsightsPage
    let caption: String
    let style: ReviewPageStyle
    let detail: (String) -> InsightDetailContent?
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ReviewCaption(text: caption, style: style)
            if page.insightIDs.count == 1, let id = page.insightIDs.first, let content = detail(id) {
                single(content, id: id)
            } else {
                ReviewHeadline(text: page.headline, style: style)
                ForEach(page.insightIDs, id: \.self) { id in
                    if let content = detail(id) { row(content, id: id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func single(_ content: InsightDetailContent, id: String) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            HStack(spacing: NoctisSpacing.sm) {
                InsightCategoryTile(category: content.category)
                Text(content.category.title.uppercased())
                    .noctisFont(13, .semibold, relativeTo: .footnote)
                    .tracking(13 * 0.08)
                    .foregroundStyle(style.quiet)
            }
            ReviewHeadline(text: content.title, style: style)
            if let chart = content.chart {
                InsightChartView(content: chart, style: .featured)
                    .frame(maxWidth: .infinity)
                    // The chart draws its axis labels to its edges: room, so none runs out of the page's margin.
                    .padding(.horizontal, NoctisSpacing.md)
            }
            if let line = content.evidenceLines.first {
                ReviewLine(text: line, style: style)
            }
            readMore(id: id, title: content.title)
        }
    }

    private func row(_ content: InsightDetailContent, id: String) -> some View {
        Button {
            NoctisHaptics.selection()
            open(id)
        } label: {
            HStack(spacing: NoctisSpacing.sm) {
                InsightCategoryTile(category: content.category)
                Text(content.title)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(style.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: NoctisSpacing.xs)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(style.quiet)
                    .accessibilityHidden(true)
            }
            .padding(NoctisSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(style.ink.opacity(0.1), in: RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityLabel(content.title)
        .accessibilityHint("Opens this insight.")
        .accessibilityIdentifier("review.insight.\(id)")
    }

    private func readMore(id: String, title: String) -> some View {
        Button {
            NoctisHaptics.selection()
            open(id)
        } label: {
            HStack(spacing: 6) {
                Text("Read more").noctisFont(17, .semibold, relativeTo: .body)
                Image(systemName: "chevron.forward").noctisIcon(14)
            }
            .foregroundStyle(style.ink)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read more about \(title)")
        .accessibilityIdentifier("review.readMore")
    }
}

// MARK: - Next focus

struct ReviewFocusPageView: View {
    let page: ReviewFocusPage
    let caption: String
    let style: ReviewPageStyle
    let askCoach: (ReviewCoachTopic) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ReviewCaption(text: caption, style: style)
            NoctisColorBlock(fill: NoctisAppColor.blockLavender) {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    Text(page.headline)
                        .noctisFont(26, .bold, relativeTo: .title2)
                        .foregroundStyle(NoctisAppColor.blockInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(page.lines, id: \.self) { line in
                        Text(line)
                            .noctisFont(16, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.blockInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let topic = page.coachTopic {
                Button {
                    NoctisHaptics.selection()
                    askCoach(topic)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").noctisIcon(15)
                        Text("Ask Coach about this").noctisFont(17, .semibold, relativeTo: .body)
                    }
                    .foregroundStyle(style.ink)
                    .padding(.horizontal, NoctisSpacing.md)
                    .frame(minHeight: 44)
                    .overlay(Capsule(style: .continuous).strokeBorder(style.ink.opacity(0.35), lineWidth: 1.5))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Coach with a question about this.")
                .accessibilityIdentifier("review.askCoach")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - A month's records

struct ReviewRecordsPageView: View {
    let page: ReviewRecordsPage
    let caption: String
    let style: ReviewPageStyle

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ReviewCaption(text: caption, style: style)
            ReviewHeadline(text: page.headline, style: style)
            ForEach(page.blocks) { block in
                NoctisColorBlock(fill: block.kind == .longestNight ? NoctisAppColor.blockSage : NoctisAppColor.blockLavender) {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        NoctisCaption(block.title.uppercased(), style: NoctisAppColor.blockInk)
                        if let minutes = block.minutes {
                            NoctisMetric(HomeFormat.durationMetric(minutes), size: 44, relativeTo: .largeTitle, tone: .block)
                        } else if let score = block.score {
                            NoctisMetric(NoctisMetricValue(parts: [.number("\(score)")], spoken: "\(score)"), size: 44, relativeTo: .largeTitle, tone: .block)
                        }
                        Text(block.date)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.blockInk)
                        if let tie = block.tie {
                            Text(tie)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(NoctisAppColor.blockInk)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(block.spoken)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - A free person's month

struct ReviewLockedPageView: View {
    let style: ReviewPageStyle
    let card: LockedCopy.Card?
    let unlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ReviewCaption(text: "Your month", style: style)
            if let card { ReviewUnlockCard(card: card, unlock: unlock) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one locked card a review's story ever shows (the weekly cover's, or a free month's only page): its button is the one way to the paywall (R64).
private struct ReviewUnlockCard: View {
    let card: LockedCopy.Card
    let unlock: () -> Void

    var body: some View {
        LockedCard(title: card.title, line: card.line, identifier: "review.locked", action: unlock)
    }
}
