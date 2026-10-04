import DesignSystem
import HomeFeature
import InsightsKit
import NoctisCore
import SwiftUI

// MARK: - Category style

/// A category's color and glyph: the icon tile beside a row, the small tile
/// on the featured story.
struct InsightCategoryStyle {
    let fill: Color
    let foreground: Color
    let systemImage: String

    static func of(_ category: InsightCategory) -> InsightCategoryStyle {
        switch category {
        case .sleep: InsightCategoryStyle(fill: NoctisAppColor.blockSage, foreground: NoctisAppColor.blockInk, systemImage: "moon.zzz")
        case .recovery: InsightCategoryStyle(fill: NoctisAppColor.blockLavender, foreground: NoctisAppColor.blockInk, systemImage: "heart")
        case .timing: InsightCategoryStyle(fill: NoctisAppColor.blockButter, foreground: NoctisAppColor.blockInk, systemImage: "clock")
        case .consistency: InsightCategoryStyle(fill: NoctisAppColor.coreTint, foreground: NoctisAppColor.blockInk, systemImage: "calendar")
        case .heart: InsightCategoryStyle(fill: NoctisAppColor.fieldRose, foreground: NoctisAppColor.blockInk, systemImage: "waveform.path.ecg")
        case .longTerm: InsightCategoryStyle(fill: NoctisAppColor.blockCocoa, foreground: NoctisPaper.bg, systemImage: "chart.line.uptrend.xyaxis")
        }
    }
}

struct InsightCategoryTile: View {
    let category: InsightCategory
    var size: CGFloat = 40

    var body: some View {
        let style = InsightCategoryStyle.of(category)
        NoctisIconTile(systemImage: style.systemImage, fill: style.fill, foreground: style.foreground, size: size)
    }
}

// MARK: - Chips

/// All, Sleep, Recovery, Timing, Consistency, Heart, Long-term: a row that
/// scrolls sideways, each chip a 44pt target. The selected chip is cocoa
/// (ivory in Dark), and slides from one chip to the next with a spring.
struct InsightChipRow: View {
    let chips: [InsightChipContent]
    let selected: InsightCategory?
    let select: (InsightCategory?) -> Void
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: NoctisSpacing.xs) {
                    ForEach(chips) { chip in
                        chipButton(chip)
                            .id(chip.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onChange(of: selected) { _, category in
                withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(category?.rawValue ?? "all", anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.chips")
    }

    private func chipButton(_ chip: InsightChipContent) -> some View {
        let isSelected = chip.category == selected
        return Button {
            NoctisHaptics.snapLight()
            select(chip.category)
        } label: {
            Text(chip.title)
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(isSelected ? NoctisAppColor.ctaLabel : NoctisAppColor.ink2)
                .padding(.horizontal, NoctisSpacing.md)
                .frame(minHeight: 44)
                .background {
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(NoctisAppColor.surface)
                            .overlay(Capsule(style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(NoctisAppColor.ctaFill)
                                .matchedGeometryEffect(id: "selectedChip", in: selection)
                        }
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chip.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("insights.chip.\(chip.id)")
    }
}

// MARK: - Featured story

extension NoctisMetricValue {
    /// The value with every whole number counted up to `progress` (0...1): 0
    /// at the start, itself at 1. A number that isn't a plain integer (a clock
    /// time) stays as it is.
    nonisolated func counting(_ progress: Double) -> NoctisMetricValue {
        NoctisMetricValue(
            parts: parts.map { part in
                guard case .number(let text) = part, let value = Int(text) else { return part }
                return .number(String(Int((Double(value) * min(max(progress, 0), 1)).rounded())))
            },
            spoken: spoken
        )
    }
}

/// A 44pt number that counts up as `progress` moves (an animatable, so every
/// frame redraws it).
struct InsightCountingMetric: View, Animatable {
    let value: NoctisMetricValue
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        NoctisMetric(value.counting(progress), size: 44, relativeTo: .largeTitle, tone: .nightPanel)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            // The number is read whole, whatever it shows while counting.
            .accessibilityLabel(value.spoken)
    }
}

/// The two numbers of the featured story: an arrow between them for a change
/// (usual to last night), "vs" for two groups side by side. They count up on
/// the day's first open.
struct InsightComparisonView: View {
    let numbers: [InsightNumber]
    let join: InsightComparisonJoin
    let reveal: HomeRevealPhase
    let lowPower: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var progress: Double

    init(numbers: [InsightNumber], join: InsightComparisonJoin, reveal: HomeRevealPhase, lowPower: Bool) {
        self.numbers = numbers
        self.join = join
        self.reveal = reveal
        self.lowPower = lowPower
        _progress = State(initialValue: HomeReveal.countsUp(lowPower: lowPower) && reveal == .pending ? 0 : 1)
    }

    var body: some View {
        Group {
            if numbers.count >= 2 {
                if typeSize.isAccessibilitySize {
                    // Large text: one under the other.
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        column(numbers[0])
                        joinView
                        column(numbers[1])
                    }
                } else {
                    // One row, each number giving up a little size before it wraps or drops a line.
                    HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                        column(numbers[0])
                        joinView.frame(height: 44 * 1.15)
                        column(numbers[1])
                    }
                }
            } else if let only = numbers.first {
                column(only)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(numbers.map { "\($0.label) \($0.value.spoken)" }.joined(separator: join == .arrow ? ", then " : " compared with "))
        .task(id: reveal) {
            guard reveal == .playing, HomeReveal.countsUp(lowPower: lowPower), !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(0.1))
            guard !Task.isCancelled else { return }
            withAnimation(NoctisMotion.draw(HomeReveal.ringDuration)) { progress = 1 }
            try? await Task.sleep(for: .seconds(HomeReveal.ringDuration))
            guard !Task.isCancelled else { return }
            NoctisHaptics.soft()
        }
        .onChange(of: reveal) { _, phase in
            // A skipped reveal lands on the end state at once.
            if phase == .none { progress = 1 }
        }
        .onChange(of: numbers) { _, _ in progress = 1 }
    }

    @ViewBuilder
    private var joinView: some View {
        switch join {
        case .arrow:
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NoctisAppColor.butter)
                .accessibilityHidden(true)
        case .versus:
            Text("vs")
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(NoctisAppColor.butter)
                .accessibilityHidden(true)
        }
    }

    private func column(_ number: InsightNumber) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InsightCountingMetric(value: number.value, progress: progress)
            caption(number.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .noctisFont(13, .medium, relativeTo: .footnote)
            .foregroundStyle(NoctisNightInkStyle())
    }
}

/// The featured story: a cocoa block with ivory text and butter accents, the
/// top-ranked insight as a title, two big numbers, a line and a chart. The
/// whole card opens it.
struct InsightFeaturedCard: View {
    let content: InsightFeaturedContent
    let reveal: HomeRevealPhase
    let lowPower: Bool
    let zoom: Namespace.ID
    let viewModel: InsightsViewModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                HStack(spacing: NoctisSpacing.sm) {
                    InsightCategoryTile(category: content.category, size: 36)
                    Text(content.category.title.uppercased())
                        .noctisFont(13, .semibold, relativeTo: .footnote)
                        .tracking(1)
                        .foregroundStyle(NoctisAppColor.butter)
                }
                Text(content.title)
                    .noctisFont(24, .bold, relativeTo: .title2)
                    .foregroundStyle(NoctisPaper.bg)
                    .fixedSize(horizontal: false, vertical: true)
                if !content.numbers.isEmpty {
                    InsightComparisonView(numbers: content.numbers, join: content.join, reveal: reveal, lowPower: lowPower)
                }
                Text(content.interpretation)
                    .noctisFont(17, relativeTo: .body)
                    .foregroundStyle(NoctisNightInkStyle())
                    .fixedSize(horizontal: false, vertical: true)
                if let chart = content.chart {
                    InsightChartView(content: chart, style: .featured)
                        .padding(.top, NoctisSpacing.xxs)
                }
                HStack(spacing: 6) {
                    Text("Read more")
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisPaper.bg)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NoctisAppColor.butter)
                }
                .frame(minHeight: 44)
            }
            .padding(NoctisSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoctisAppColor.blockCocoa, in: RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
            .noctisContrastBorder()
        }
        .buttonStyle(NoctisCardButtonStyle())
        .matchedTransitionSource(id: content.id, in: zoom)
        .insightContextMenu(id: content.id, type: content.type, viewModel: viewModel, open: open)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint("Opens the full insight.")
        .accessibilityIdentifier("insights.featured")
    }
}

// MARK: - Recent

/// "Recent": the latest insight of each kind, grouped "This week" and
/// "Earlier", each group a card of rows.
struct InsightRowsSection: View {
    let groups: [InsightRowGroup]
    let zoom: Namespace.ID
    let viewModel: InsightsViewModel
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            Text("Recent")
                .noctisFont(22, .bold, relativeTo: .title3)
                .foregroundStyle(NoctisAppColor.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    Text(group.title)
                        .noctisFont(13, .semibold, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .padding(.leading, NoctisSpacing.xxs)
                    NoctisAppCard {
                        VStack(spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    Rectangle().fill(NoctisAppColor.hairline).frame(height: 1)
                                }
                                InsightRowView(row: row, zoom: zoom, viewModel: viewModel) { open(row.id) }
                                    .transition(.opacity.combined(with: .offset(y: 8)))
                            }
                        }
                    }
                }
            }
        }
        // A container's identifier would replace every row's own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.recent")
    }
}

struct InsightRowView: View {
    let row: InsightRowContent
    let zoom: Namespace.ID
    let viewModel: InsightsViewModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: NoctisSpacing.sm) {
                InsightCategoryTile(category: row.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.line)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.noctisInk3)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, NoctisSpacing.sm)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: row.id, in: zoom)
        .insightContextMenu(id: row.id, type: row.type, viewModel: viewModel, open: open)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHint("Opens the insight.")
        .accessibilityIdentifier("insights.row.\(row.id)")
    }
}

// MARK: - Your records

/// Three tiles on sage, lavender and butter blocks: the longest night, the
/// steadiest week and the highest recovery, each with the day it was set.
struct InsightRecordsSection: View {
    let tiles: [InsightRecordTile]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            Text("Your records")
                .noctisFont(22, .bold, relativeTo: .title3)
                .foregroundStyle(NoctisAppColor.ink)
                .accessibilityAddTraits(.isHeader)
            Group {
                if typeSize.isAccessibilitySize {
                    ScrollView(.horizontal) {
                        HStack(spacing: NoctisSpacing.xs) {
                            ForEach(tiles) { tile in
                                InsightRecordTileView(tile: tile).frame(width: 220)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                } else {
                    HStack(alignment: .top, spacing: NoctisSpacing.xs) {
                        ForEach(tiles) { tile in
                            InsightRecordTileView(tile: tile)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.records")
    }
}

struct InsightRecordTileView: View {
    let tile: InsightRecordTile

    private var fill: Color {
        switch tile.tone {
        case .sage: NoctisAppColor.blockSage
        case .lavender: NoctisAppColor.blockLavender
        case .butter: NoctisAppColor.blockButter
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
            Text(tile.title)
                .noctisFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(NoctisAppColor.blockInk)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            NoctisMetric(tile.value, size: 30, relativeTo: .title, tone: .block)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, NoctisSpacing.xxs)
            Text(tile.date)
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(NoctisAppColor.blockInk)
        }
        .padding(NoctisSpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(fill, in: RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
        .noctisContrastBorder(cornerRadius: NoctisRadius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
        .accessibilityIdentifier("insights.record.\(tile.id)")
    }
}

// MARK: - Learning, notes, states

/// Under 7 nights: what unlocks, and how far along each is.
struct InsightsLearningCard: View {
    let content: InsightsLearningContent

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    Text(content.title)
                        .noctisFont(22, .semibold, relativeTo: .title3)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(content.detail)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                }
                VStack(spacing: 0) {
                    ForEach(Array(content.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle().fill(NoctisAppColor.hairline).frame(height: 1)
                        }
                        InsightMilestoneRowView(row: row)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.learning")
    }
}

struct InsightMilestoneRowView: View {
    let row: InsightMilestoneRow

    var body: some View {
        HStack(spacing: NoctisSpacing.sm) {
            NoctisIconTile(
                systemImage: row.reached ? "checkmark" : "lock",
                fill: row.reached ? NoctisAppColor.blockSage : NoctisAppColor.track,
                foreground: row.reached ? NoctisAppColor.blockInk : NoctisAppColor.ink3,
                size: 40
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(row.detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    ForEach(0..<row.dots, id: \.self) { index in
                        Circle()
                            .fill(index < row.filled ? NoctisAppColor.progressDot : NoctisAppColor.track)
                            .frame(width: 8, height: 8)
                    }
                    Text("\(row.milestone) nights")
                        .noctisFont(12, .medium, relativeTo: .caption)
                        .foregroundStyle(.noctisInk3)
                        .padding(.leading, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, NoctisSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityIdentifier("insights.milestone.\(row.milestone)")
    }
}

/// A calm card for a filter with nothing in it.
struct InsightsNoteCard: View {
    let note: InsightsNoteContent

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                Text(note.title)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(note.detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("insights.note")
    }
}

/// Nothing to show yet: what's going on, and its one action.
struct InsightsStateView: View {
    let state: InsightsStateContent
    let viewModel: InsightsViewModel
    @Environment(\.openURL) private var openURL
    @State private var connecting = false

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            NoctisIconTile(systemImage: "lightbulb", fill: NoctisAppColor.blockButter, foreground: NoctisAppColor.blockInk, size: 72)
            switch state {
            case .connect(let title, let message, let showsButton):
                text(title, message)
                if showsButton {
                    NoctisCTA("Connect Apple Health", isLoading: connecting, adaptive: true) {
                        connecting = true
                        Task {
                            await viewModel.connectAppleHealth()
                            connecting = false
                        }
                    }
                    HealthDataSettingsLink()
                }
            case .noSleepData(let title, let message):
                text(title, message)
                if let health = URL(string: "x-apple-health://") {
                    NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                        .accessibilityHint("Opens the Health app.")
                }
                HealthDataSettingsLink()
            case .failed(let message):
                text(message, nil)
                NoctisCTA("Try again", icon: "arrow.clockwise", adaptive: true) {
                    Task { await viewModel.refresh() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NoctisSpacing.xl)
        .accessibilityIdentifier("insights.state")
    }

    private func text(_ title: String, _ detail: String?) -> some View {
        VStack(spacing: NoctisSpacing.xs) {
            Text(title)
                .noctisFont(22, .semibold, relativeTo: .title3)
                .foregroundStyle(NoctisAppColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Track-colored blocks shaped like what is loading while the first snapshot
/// loads; a slow pulse, none under Reduce Motion or Low Power Mode.
struct InsightsSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    var lowPower: Bool { HomeViewModel.systemLowPower() }

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            HStack(spacing: NoctisSpacing.xs) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(NoctisAppColor.track).frame(width: 84, height: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            block(height: 330)
            block(height: 96)
            block(height: 96)
        }
        .frame(maxWidth: .infinity)
        .opacity(dimmed ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion, !lowPower else { return }
            withAnimation(NoctisMotion.pulse) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your insights")
        .accessibilityIdentifier("insights.skeleton")
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
            .fill(NoctisAppColor.track)
            .frame(height: height)
    }
}
