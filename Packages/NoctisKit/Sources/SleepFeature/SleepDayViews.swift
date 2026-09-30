import DesignSystem
import HomeFeature
import NoctisCore
import SleepAnalysisKit
import SleepKit
import SwiftUI

/// Sleep, Day, under the field (which holds the night strip and the hero):
/// the night's landscape, its stages, what made up its quality, and the
/// details.
struct SleepDayView: View {
    let screen: SleepScreen
    let viewModel: SleepViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            if let day = screen.day {
                SleepDayContentView(day: day, viewModel: viewModel)
                    // The content morphs when another night is chosen.
                    .transition(.opacity)
            } else if let none = screen.noNight {
                SleepNoNightView(content: none)
                    .transition(.opacity)
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion), value: screen.selection.night)
    }
}

// MARK: - Night picker

/// The last 14 nights, weekday initial over day number, in 44pt-wide
/// targets, on the sage field. The selected night is a cocoa capsule.
struct SleepNightPicker: View {
    let items: [SleepPickerItem]
    let selected: SleepNightKey
    let choose: (SleepNightKey) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let itemWidth: CGFloat = 44
    static let itemHeight: CGFloat = 60

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NoctisSpacing.xxs) {
                    ForEach(items) { item in
                        cell(item)
                            .id(item.night)
                    }
                }
                .padding(.horizontal, NoctisSpacing.xxs)
            }
            .defaultScrollAnchor(.trailing)
            .scrollClipDisabled()
            .onChange(of: selected) { _, night in
                withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(night, anchor: .center)
                }
            }
        }
        .frame(height: Self.itemHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nights")
        .accessibilityIdentifier("sleep.nightPicker")
    }

    private func cell(_ item: SleepPickerItem) -> some View {
        let isSelected = item.night == selected
        return Button { choose(item.night) } label: {
            VStack(spacing: 2) {
                Text(item.initial)
                    .noctisFont(13, .medium, relativeTo: .footnote)
                Text(item.day)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? NoctisAppColor.nightInk : NoctisAppColor.blockInk)
            .opacity(item.hasData || isSelected ? 1 : 0.55)
            .frame(width: Self.itemWidth, height: Self.itemHeight)
            .background {
                if isSelected {
                    Capsule(style: .continuous).fill(NoctisAppColor.blockCocoa)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: isSelected)
    }
}

/// A night with nothing recorded.
struct SleepNoNightView: View {
    let content: SleepNoNightContent

    var body: some View {
        NoctisAppCard {
            HStack(spacing: NoctisSpacing.md) {
                DormantRingView(diameter: 72, glyphSize: 18, onField: true)
                    .frame(width: 72)
                DormantTextView(title: content.title, detail: content.detail, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([content.title, content.detail].compactMap { $0 }.joined(separator: " "))
        .accessibilityIdentifier("sleep.noNight")
    }
}

// MARK: - The night

struct SleepDayContentView: View {
    let day: SleepDayContent
    let viewModel: SleepViewModel
    @State private var laneFocus: NightLane?

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            if let learning = day.learning {
                SleepLearningCard(content: learning)
            }
            SleepNightPanel(day: day, reveal: viewModel.reveal, laneFocus: $laneFocus)
            if let stages = day.stages {
                SleepStageCard(content: stages, focus: laneFocus)
            }
            if let quality = day.quality {
                SleepQualityCard(content: quality)
            }
            if !day.details.isEmpty {
                SleepDetailsGrid(tiles: day.details)
            }
        }
        .onChange(of: day.night) { _, _ in laneFocus = nil }
    }
}

/// The duration at 72pt with "slept" and the time range, beside the
/// quality ring; on the sage field, no card.
struct SleepHeroView: View {
    let day: SleepDayContent
    let reveal: HomeRevealPhase
    let lowPower: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownMinutes: Int
    @State private var shownScore: Int

    static let ringDiameter: CGFloat = 110

    init(day: SleepDayContent, reveal: HomeRevealPhase, lowPower: Bool) {
        self.day = day
        self.reveal = reveal
        self.lowPower = lowPower
        let counts = HomeReveal.countsUp(lowPower: lowPower) && reveal == .pending
        _shownMinutes = State(initialValue: counts ? 0 : day.minutes)
        _shownScore = State(initialValue: counts ? 0 : (day.ring?.score ?? 0))
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: NoctisSpacing.md) {
                copy
                Spacer(minLength: 0)
                ring
            }
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                copy
                ring
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityIdentifier("sleep.hero")
        // The numbers count up with the reveal, and roll to the next
        // night's when another is chosen.
        .task(id: reveal) {
            guard reveal == .playing, HomeReveal.countsUp(lowPower: lowPower), !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(0.1))
            guard !Task.isCancelled else { return }
            withAnimation(NoctisMotion.draw(HomeReveal.ringDuration)) { showEnd() }
        }
        .onChange(of: reveal) { _, phase in
            // A skipped reveal lands on the end state at once.
            if phase == .none { showEnd() }
        }
        .onChange(of: day.minutes) { _, _ in
            withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) { showEnd() }
        }
    }

    private func showEnd() {
        shownMinutes = day.minutes
        shownScore = day.ring?.score ?? 0
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
            NoctisCaption(day.caption, style: .noctisFieldInk2)
            NoctisMetric(HomeFormat.durationMetric(shownMinutes), size: 72, tone: .block)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: Double(shownMinutes)))
            Text("slept")
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(.noctisFieldInk2)
            Text(day.timeRange)
                .noctisFont(15, .medium, relativeTo: .subheadline)
                .foregroundStyle(.noctisFieldInk)
        }
    }

    @ViewBuilder
    private var ring: some View {
        if let content = day.ring {
            VStack(spacing: NoctisSpacing.xxs) {
                NoctisRingLayout(maxDiameter: Self.ringDiameter, centerWidth: 0.68, centerHeight: 0.5) {
                    NoctisRecoveryRing(
                        segments: [segment(content)],
                        reveal: reveal.holdsStart ? 0 : 1,
                        showsUsual: content.typicalText != nil,
                        diameter: Self.ringDiameter,
                        lineWidth: 12
                    )
                    .environment(\.noctisRingTrack, NoctisAppColor.blockCocoa.opacity(0.15))
                    .animation(reduceMotion ? nil : NoctisMotion.draw(HomeReveal.ringDuration).delay(0.1), value: reveal)
                    VStack(spacing: 0) {
                        Text("\(shownScore)")
                            .noctisNumeral(34, .heavy)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(shownScore)))
                            .foregroundStyle(.noctisFieldInk)
                        Text("Quality")
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(.noctisFieldInk2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                .frame(width: Self.ringDiameter)
                if content.typicalText != nil {
                    Text("Tick = typical range")
                        .noctisFont(12, relativeTo: .caption)
                        .foregroundStyle(.noctisFieldInk2)
                }
            }
        } else {
            EmptyView()
        }
    }

    /// One segment around the whole ring; its angles come from the render
    /// model.
    private func segment(_ content: SleepQualityRingContent) -> NoctisRingSegment {
        NoctisRingSegment(color: NoctisAppColor.blockCocoa, weight: 1, fraction: content.fraction, usual: content.usual, arc: content.arc)
    }
}

/// While the baseline is still forming: dots for the nights recorded.
struct SleepLearningCard: View {
    let content: SleepLearningContent

    var body: some View {
        NoctisAppCard {
            HStack(spacing: NoctisSpacing.md) {
                DormantRingView(diameter: 72, glyphSize: 18, onField: true)
                    .frame(width: 72)
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    DormantTextView(title: "Learning your baseline", detail: content.text, alignment: .leading)
                    LearningDots(nights: content.nights, required: content.required)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Learning your baseline, \(content.nights) of \(content.required) nights recorded. Quality joins once there are \(content.required).")
        .accessibilityIdentifier("sleep.learning")
    }
}

// MARK: - Night panel

/// The night panel, taller: the landscape ribbon with its heart strip,
/// lane labels, time axis and scrub pill, and the stage totals under it.
/// A tapped stage total (or lane label) highlights that stage across the
/// night.
struct SleepNightPanel: View {
    let day: SleepDayContent
    let reveal: HomeRevealPhase
    @Binding var laneFocus: NightLane?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @NoctisScaledLength(relativeTo: .caption2) private var laneHeight: CGFloat = 41

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            NoctisCaption("THE NIGHT", style: .noctisNightInk2)
            NightLandscapeView(
                chart: day.chart,
                laneHeight: laneHeight,
                drawn: reveal.holdsStart ? 0 : 1,
                details: reveal.holdsStart ? 0 : 1,
                tapsTotals: true,
                reservesPillRow: true,
                laneFocus: $laneFocus
            )
            .animation(reduceMotion ? nil : NoctisMotion.draw(HomeReveal.nightDuration).delay(0.1), value: reveal)
            if let caption = day.chart.caption {
                Text(caption)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisNightInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .padding(NoctisSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous).fill(NoctisAppColor.nightPanel))
        .overlay(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous).strokeBorder(NoctisAppColor.nightBorder, lineWidth: 1))
        .noctisContrastBorder()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sleep.nightPanel")
    }
}

// MARK: - Stage breakdown

struct SleepStageCard: View {
    let content: SleepStageCardContent
    let focus: NightLane?

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                NoctisCaption("STAGES", style: .noctisInk3)
                // Every bar ends at the same place: the "usual" captions share a width.
                let reservesUsual = content.rows.contains { $0.usualText != nil }
                ForEach(content.rows, id: \.stage) { row in
                    SleepStageRow(row: row, dimmed: focus != nil && focus != row.stage.lane, reservesUsual: reservesUsual)
                }
                Text(content.footnote)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sleep.stages")
    }
}

/// The stage's icon tile, its name, duration and share, and a bar of the
/// share with a tick where your usual is ("usual 22%").
struct SleepStageRow: View {
    let row: SleepStageRowContent
    let dimmed: Bool
    var reservesUsual = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @NoctisScaledLength(relativeTo: .caption) private var usualWidth: CGFloat = 76

    var body: some View {
        HStack(alignment: .center, spacing: NoctisSpacing.sm) {
            NoctisIconTile(systemImage: row.stage.lane.symbol, fill: row.stage.lane.tint, foreground: NoctisAppColor.onFill, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.xs) {
                    Text(row.name)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                    Spacer(minLength: NoctisSpacing.xs)
                    NoctisMetric(row.duration, size: 17, relativeTo: .body)
                    Text(row.shareText)
                        .noctisFont(15, .medium, relativeTo: .subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.noctisInk2)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                HStack(spacing: NoctisSpacing.xs) {
                    ZStack {
                        NoctisSpanLayout(to: 1) { Capsule().fill(NoctisAppColor.track).frame(height: 8) }
                        NoctisSpanLayout(to: row.share, minimumWidth: 8) { Capsule().fill(row.stage.lane.tint).frame(height: 8) }
                        if let usual = row.usual {
                            NoctisFractionLayout {
                                RoundedRectangle(cornerRadius: 1).fill(NoctisAppColor.ink).frame(width: 2, height: 14)
                                    .noctisFraction(usual)
                            }
                        }
                    }
                    .frame(height: 14)
                    if reservesUsual {
                        Text(row.usualText ?? "")
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(.noctisInk3)
                            .lineLimit(1)
                            .frame(width: usualWidth, alignment: .trailing)
                    }
                }
            }
        }
        .opacity(dimmed ? 0.45 : 1)
        .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: dimmed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

// MARK: - Quality

struct SleepQualityCard: View {
    let content: SleepQualityCardContent
    @State private var expanded = false

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                NoctisCaption("SLEEP QUALITY", style: .noctisInk3)
                ForEach(content.factors, id: \.kind) { factor in
                    SleepFactorRow(factor: factor)
                }
                if !content.omitted.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(content.omitted, id: \.self) { sentence in
                            Text(sentence)
                                .noctisFont(12, relativeTo: .caption)
                                .foregroundStyle(.noctisInk3)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    Text("What changed?")
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                    Text(content.whatChanged)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                    Text(content.confidence)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        ForEach(content.calculation, id: \.self) { paragraph in
                            Text(paragraph)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(NoctisAppColor.ink2)
                        }
                        Text(content.modelVersion)
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(NoctisAppColor.ink3)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, NoctisSpacing.sm)
                } label: {
                    Text("How this is calculated")
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                }
                .tint(NoctisAppColor.ink2)
            }
        }
        .accessibilityIdentifier("sleep.quality")
    }
}

extension SleepQualityFactorKind {
    var symbol: String {
        switch self {
        case .duration: "moon.zzz.fill"
        case .continuity: "waveform"
        case .consistency: "clock.fill"
        case .stages: "square.stack.3d.up.fill"
        }
    }

    var tint: Color {
        switch self {
        case .duration: NoctisAppColor.sage
        case .continuity: NoctisAppColor.lavender
        case .consistency: NoctisAppColor.butter
        case .stages: NoctisAppColor.orange
        }
    }
}

struct SleepFactorRow: View {
    let factor: SleepFactorRowContent

    var body: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.sm) {
            NoctisIconTile(systemImage: factor.kind.symbol, fill: factor.kind.tint, foreground: NoctisAppColor.onFill, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(factor.name)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                    Spacer(minLength: NoctisSpacing.xs)
                    Text("\(factor.score)")
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .monospacedDigit()
                        .foregroundStyle(NoctisAppColor.ink)
                }
                ZStack {
                    NoctisSpanLayout(to: 1) { Capsule().fill(NoctisAppColor.track).frame(height: 8) }
                    NoctisSpanLayout(to: factor.fraction, minimumWidth: 8) { Capsule().fill(factor.kind.tint).frame(height: 8) }
                }
                .frame(height: 8)
                Text(factor.sentence)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(factor.name) \(factor.score). \(factor.sentence)")
    }
}

// MARK: - Details

/// Two columns of tiles; a tile with no value isn't made.
struct SleepDetailsGrid: View {
    let tiles: [SleepDetailTile]

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            NoctisCaption("DETAILS", style: .noctisInk3)
                .padding(.leading, NoctisSpacing.xxs)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: NoctisSpacing.sm, alignment: .top),
                    GridItem(.flexible(), spacing: NoctisSpacing.sm, alignment: .top),
                ],
                spacing: NoctisSpacing.sm
            ) {
                ForEach(tiles) { tile in
                    SleepDetailTileView(tile: tile)
                }
            }
        }
        .accessibilityIdentifier("sleep.details")
    }
}

struct SleepDetailTileView: View {
    let tile: SleepDetailTile
    /// Room for a value and a caption, so tiles in a row are one height.
    @NoctisScaledLength(relativeTo: .body) private var minHeight: CGFloat = 148

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            NoctisIconTile(systemImage: Self.symbol(tile.id), fill: Self.fill(tile.id), foreground: NoctisAppColor.onFill, size: 40)
                .padding(.bottom, NoctisSpacing.xxs)
            Text(tile.title)
                .noctisFont(13, .medium, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
            NoctisMetric(tile.value, size: 28)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let note = tile.note {
                Text(note)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
            }
        }
        .padding(NoctisSpacing.md)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous)
                .fill(NoctisAppColor.surface)
                .overlay(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.title) \(tile.value.spoken)" + (tile.note.map { ", \($0)" } ?? ""))
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case "inBed": "bed.double.fill"
        case "efficiency": "percent"
        case "bedtime": "moon.fill"
        case "wake": "sun.max.fill"
        case "awakenings": "eye.fill"
        case "awake": "timer"
        default: "moon.stars.fill"
        }
    }

    static func fill(_ id: String) -> Color {
        switch id {
        case "inBed", "bedtime": NoctisAppColor.nightDeep
        case "efficiency": NoctisAppColor.sage
        case "wake", "awake": NoctisAppColor.butter
        case "awakenings": NoctisAppColor.coreTint
        default: NoctisAppColor.lavender
        }
    }
}
