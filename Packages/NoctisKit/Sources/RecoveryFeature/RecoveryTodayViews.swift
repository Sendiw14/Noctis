import DesignSystem
import HomeFeature
import NoctisCore
import RecoveryKit
import SwiftUI

/// Today: the ring, how the score was built, a card per factor, how far to
/// trust it, and how it's calculated.
struct RecoveryTodayView: View {
    let today: RecoveryTodayContent
    let viewModel: RecoveryViewModel
    let openFactor: (RecoveryFactorKind, RecoveryFactorRange) -> Void

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            RecoveryHeroView(content: today.scored, highlight: today.highlight, reveal: viewModel.reveal, lowPower: viewModel.isLowPower)
            RecoveryBuildCard(build: today.build)
            ForEach(today.factors, id: \.kind) { row in
                RecoveryFactorCard(row: row) { openFactor(row.kind, .fortnight) }
                    .id(row.kind)
            }
            RecoveryConfidenceCard(content: today.confidence)
            RecoveryCalculationCard(paragraphs: today.calculation, modelVersion: today.modelVersion)
        }
    }
}

// MARK: - Hero

/// The scored ring on the paper: 260pt (220 in narrow spaces), a tick at
/// each factor's usual, then exactly one line under it (the delta chip and
/// how it compares), why when a factor is outside its normal range, and a
/// confidence caption when it isn't high.
struct RecoveryHeroView: View {
    let content: ScoredRecoveryContent
    /// "Highest in 30 days", when today's score has earned it.
    let highlight: String?
    let reveal: HomeRevealPhase
    let lowPower: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownScore: Int

    static let ringDiameter: CGFloat = 260
    static let narrowRingDiameter: CGFloat = 220
    static let narrowBelowWidth: CGFloat = 350
    static let ringLineWidth: CGFloat = 22
    /// The paper disc the ring sits on reaches this far past it, so the ring
    /// stands on paper where it rides up over the field.
    static let discMargin = TabScreenScaffold<EmptyView>.discMargin

    init(content: ScoredRecoveryContent, highlight: String? = nil, reveal: HomeRevealPhase, lowPower: Bool) {
        self.content = content
        self.highlight = highlight
        self.reveal = reveal
        self.lowPower = lowPower
        _shownScore = State(initialValue: HomeReveal.countsUp(lowPower: lowPower) && reveal == .pending ? 0 : content.score)
    }

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            ring
            VStack(spacing: NoctisSpacing.xs) {
                // The chip and its phrase in one row when they fit; one under the other when they do not ("−17 vs your us…" on an SE at AX5).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NoctisSpacing.xs) { deltaChip; comparison }
                    VStack(spacing: NoctisSpacing.xxs) { deltaChip; comparison }
                }
                if let why = content.why {
                    Text(why)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            CoachAskButton("Ask Coach why", question: content.coachQuestion, identifier: "recovery.askCoach")
            if let highlight {
                NoctisHighlightCapsule(highlight)
                    .transition(.opacity)
            }
            if let caption = content.confidenceCaption {
                Text(caption)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let caption = content.usualCaption {
                Text(caption)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recovery.hero")
        // The score counts up with the ring, and rolls to a new score.
        .task(id: reveal) {
            guard reveal == .playing, HomeReveal.countsUp(lowPower: lowPower), !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(0.1))
            guard !Task.isCancelled else { return }
            withAnimation(NoctisMotion.draw(HomeReveal.ringDuration)) { shownScore = content.score }
            try? await Task.sleep(for: .seconds(HomeReveal.ringDuration))
            guard !Task.isCancelled else { return }
            NoctisHaptics.medium()
        }
        .onChange(of: reveal) { _, phase in
            // A skipped reveal lands on the end state at once.
            if phase == .none { shownScore = content.score }
        }
        .onChange(of: content.score) { _, _ in
            withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) { shownScore = content.score }
        }
    }

    @ViewBuilder
    private var deltaChip: some View {
        if let chip = content.chip { DeltaChipView(chip: chip) }
    }

    private var comparison: some View {
        Text(content.comparisonPhrase)
            .noctisFont(15, relativeTo: .subheadline)
            .foregroundStyle(.noctisInk2)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var ring: some View {
        NoctisRingLayout(maxDiameter: Self.ringDiameter, narrowDiameter: Self.narrowRingDiameter, narrowBelowWidth: Self.narrowBelowWidth) {
            NoctisRecoveryRing(
                segments: content.segments.map(\.ringSegment),
                reveal: reveal.holdsStart ? 0 : 1,
                showsUsual: content.usualCaption != nil,
                diameter: Self.ringDiameter,
                lineWidth: Self.ringLineWidth
            )
            .animation(reduceMotion ? nil : NoctisMotion.draw(HomeReveal.ringDuration).delay(0.1), value: reveal)
            VStack(spacing: 0) {
                Text("\(shownScore)")
                    .noctisNumeral(88, .heavy)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(shownScore)))
                    .foregroundStyle(NoctisAppColor.ink)
                Text("Recovery")
                    // Capped at 1.3x: the ring has one diameter, and at AX5 the word grew into the gap in the arc where the 'usual' tick sits.
                    .noctisFont(15, relativeTo: .subheadline, maxScale: 1.3)
                    .foregroundStyle(.noctisInk2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .background { Circle().fill(NoctisAppColor.bg).padding(-Self.discMargin) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }
}

// MARK: - How today's score was built

/// One stacked bar, 20pt tall, on a 0-100 scale: a segment per factor in
/// its ring color, as wide as its points; under it a row per factor (dot,
/// name, points, and how far from usual), and the total at the bar's right
/// end.
struct RecoveryBuildCard: View {
    let build: RecoveryBuildContent

    static let barHeight: CGFloat = 20

    var body: some View {
        NoctisColorBlock(fill: NoctisAppColor.blockLavender) {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                NoctisCaption("HOW TODAY'S SCORE WAS BUILT", style: .noctisFieldInk2)
                HStack(spacing: NoctisSpacing.sm) {
                    bar
                    Text(build.totalText)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .monospacedDigit()
                        .foregroundStyle(.noctisFieldInk)
                        .fixedSize()
                }
                VStack(spacing: NoctisSpacing.sm) {
                    ForEach(build.rows) { row in
                        rowView(row)
                    }
                }
                if let note = build.capNote {
                    Text(note)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(.noctisFieldInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(NoctisSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NoctisAppColor.blockInk.opacity(0.12), in: RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
                        .accessibilityIdentifier("recovery.cap")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(build.accessibilityLabel)
        .accessibilityIdentifier("recovery.build")
    }

    /// The segments keep their ring colors; a 2pt cocoa outline keeps the
    /// lavender one from vanishing into the block.
    private var bar: some View {
        ZStack {
            NoctisSpanLayout(to: 1) {
                Capsule().fill(NoctisAppColor.blockInk.opacity(0.12)).frame(height: Self.barHeight)
            }
            ForEach(build.rows) { row in
                NoctisSpanLayout(from: row.start, to: row.start + row.width, minimumWidth: 4) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(row.kind.tint)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(NoctisAppColor.blockCocoa, lineWidth: 2))
                        .frame(height: Self.barHeight)
                        .padding(.horizontal, 1)
                }
            }
        }
        .frame(height: Self.barHeight)
    }

    private func rowView(_ row: RecoveryBuildRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.xs) {
            Circle().fill(row.kind.tint).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(NoctisAppColor.blockCocoa, lineWidth: 1.5))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(row.name)
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(.noctisFieldInk)
            Spacer(minLength: NoctisSpacing.xs)
            if let usual = row.usualText {
                Text(usual)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisFieldInk2)
            }
            Text(row.pointsText)
                .noctisFont(17, .semibold, relativeTo: .body)
                .monospacedDigit()
                .foregroundStyle(.noctisFieldInk)
                .frame(minWidth: 40, alignment: .trailing)
        }
    }
}

// MARK: - Factor cards

/// A factor: its name, today's value, the baseline, the score, the last 14
/// nights against the normal range, and one plain sentence. The whole card
/// opens that factor's detail.
struct RecoveryFactorCard: View {
    let row: FactorDetailRow
    let open: () -> Void
    @Environment(\.featureGate) private var gate

    var body: some View {
        Button {
            NoctisHaptics.light()
            open()
        } label: {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                        NoctisIconTile(systemImage: row.kind.symbol, fill: row.kind.tint, foreground: NoctisAppColor.onFill, size: 40)
                        VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                            // One line when it fits; the name over its value when it does not (Bold Text on a 17 Pro: "Consistenc / y 30m off"
                            // broke the word in the name to make room for the value).
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) { nameAndValue }
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(row.name)
                                        .noctisFont(17, .semibold, relativeTo: .body)
                                        .foregroundStyle(NoctisAppColor.ink)
                                    HStack(alignment: .firstTextBaseline, spacing: 6) { valueAndSuffix }
                                }
                            }
                            Text(row.baseline)
                                .noctisFont(13, relativeTo: .footnote)
                                .foregroundStyle(.noctisInk3)
                            Text(row.sentence)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(.noctisInk2)
                                .padding(.top, 2)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: NoctisSpacing.xs)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(row.score)")
                                .noctisFont(22, .semibold, relativeTo: .title3)
                                .foregroundStyle(NoctisAppColor.ink)
                            Text("score")
                                .noctisFont(13, relativeTo: .footnote)
                                .foregroundStyle(.noctisInk3)
                        }
                        // A lock where the chevron would be, while the detail is Premium: the tap opens what Premium includes (R58).
                        if gate.isUnlocked(.recoveryFactorDetail) {
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.noctisInk3)
                                .padding(.top, 6)
                                .accessibilityHidden(true)
                        } else {
                            LockGlyph(size: 13).foregroundStyle(.noctisInk3).padding(.top, 6)
                        }
                    }
                    if let sparkline = row.sparkline {
                        FactorSparkline(content: sparkline, tint: row.kind.tint, lineTint: row.kind.lineTint)
                            .frame(height: FactorSparkline.height)
                    }
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHint(gate.isUnlocked(.recoveryFactorDetail) ? "Opens the details." : "Premium. Opens what Premium includes.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("recovery.factor.\(row.kind.rawValue)")
    }

    @ViewBuilder
    private var nameAndValue: some View {
        Text(row.name)
            .noctisFont(17, .semibold, relativeTo: .body)
            .foregroundStyle(NoctisAppColor.ink)
        valueAndSuffix
    }

    @ViewBuilder
    private var valueAndSuffix: some View {
        NoctisMetric(row.value, size: 17, relativeTo: .body)
        if let suffix = row.valueSuffix {
            Text(suffix)
                .noctisFont(17, .semibold, relativeTo: .body)
                .foregroundStyle(NoctisAppColor.ink)
        }
    }
}

// MARK: - Confidence

/// The tier in plain words, which signals counted and which didn't and
/// why, how many nights it's built on, and the one step that would firm it
/// up. Calm and factual.
struct RecoveryConfidenceCard: View {
    let content: RecoveryConfidenceContent

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                NoctisCaption("CONFIDENCE", style: .noctisInk3)
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    Text(content.tier)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                    Text(content.sentence)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    ForEach(content.checklist) { item in
                        HStack(alignment: .center, spacing: NoctisSpacing.sm) {
                            // Counted: the factor's own color. Not counted: the track, muted.
                            NoctisIconTile(
                                systemImage: item.kind.symbol,
                                fill: item.isUsed ? item.kind.tint : NoctisAppColor.track,
                                foreground: item.isUsed ? NoctisAppColor.onFill : NoctisAppColor.ink3,
                                size: 40
                            )
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.name)
                                    .noctisFont(15, .medium, relativeTo: .subheadline)
                                    .foregroundStyle(item.isUsed ? NoctisAppColor.ink : NoctisAppColor.ink2)
                                    // One line, whole: "Consistenc / y" at AX5 on an SE; it scales down to its word before it breaks it.
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                if let reason = item.reason {
                                    Text(reason)
                                        .noctisFont(13, relativeTo: .footnote)
                                        .foregroundStyle(.noctisInk3)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text(content.basedOn)
                    .noctisFont(13, .medium, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
                    .fixedSize(horizontal: false, vertical: true)
                if let step = content.nextStep {
                    Text(step)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(NoctisSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NoctisAppColor.track, in: RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
                        .accessibilityIdentifier("recovery.nextStep")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityIdentifier("recovery.confidence")
    }
}

// MARK: - How this is calculated

struct RecoveryCalculationCard: View {
    let paragraphs: [String]
    let modelVersion: String
    @State private var expanded = false

    var body: some View {
        NoctisAppCard {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    ForEach(paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink2)
                    }
                    Text(modelVersion)
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
        .accessibilityIdentifier("recovery.calculation")
    }
}
