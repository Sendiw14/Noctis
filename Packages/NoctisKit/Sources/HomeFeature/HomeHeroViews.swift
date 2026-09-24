import DesignSystem
import NoctisCore
import RecoveryKit
import SwiftUI

// MARK: - Day hero

/// Day mode's hero, directly on the paper: the Recovery ring when there's
/// a score, otherwise the dormant ring with what's going on.
struct DayHeroView: View {
    let content: RecoveryCardContent
    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID
    let openDetail: (RecoveryFactorKind?) -> Void

    var body: some View {
        Group {
            switch content {
            case .scored(let scored):
                ScoredHeroView(content: scored, viewModel: viewModel, zoomNamespace: zoomNamespace, openDetail: openDetail)
            case .learning(let nights, let required, let text):
                DormantHeroView(progress: Double(nights) / Double(required), title: nil, detail: text)
            case .connect(let title, let message, let showsButton):
                DormantHeroView(title: title, detail: message, titleSize: 22, action: showsButton ? .connect(viewModel) : nil)
            case .noSleepData(let title, let message):
                DormantHeroView(title: title, detail: message, titleSize: 22, action: .openHealth)
            case .noSleep(let title, let detail):
                DormantHeroView(title: title, detail: detail)
            case .stale(let title, let detail):
                DormantHeroView(title: title, detail: detail)
            case .failed(let message):
                FailedHeroView(message: message, viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The scored ring (260pt, 220pt in narrow spaces; 22pt stroke), exactly
/// one line under it, a confidence caption only below high confidence,
/// and the factor capsules. The first time each day it draws itself in
/// (0.9s, `.drawIn`), the score counts up, and a medium haptic lands.
struct ScoredHeroView: View {
    let content: ScoredRecoveryContent
    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID
    let openDetail: (RecoveryFactorKind?) -> Void

    @State private var reveal: Double
    @State private var shownScore: Int

    static let ringDiameter: CGFloat = 260
    static let narrowRingDiameter: CGFloat = 220
    /// Offered less than this, the ring uses its narrow size (an SE).
    static let narrowBelowWidth: CGFloat = 350
    static let ringLineWidth: CGFloat = 22
    /// `NoctisMotion.drawIn`'s curve, run over 0.9s.
    static let introAnimation = NoctisMotion.drawIn.speed(1.2 / 0.9)

    init(content: ScoredRecoveryContent, viewModel: HomeViewModel, zoomNamespace: Namespace.ID, openDetail: @escaping (RecoveryFactorKind?) -> Void) {
        self.content = content
        self.viewModel = viewModel
        self.zoomNamespace = zoomNamespace
        self.openDetail = openDetail
        let intro = viewModel.introPending
        _reveal = State(initialValue: intro ? 0 : 1)
        _shownScore = State(initialValue: intro ? 0 : content.score)
    }

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            Button { openDetail(nil) } label: {
                NoctisRingLayout(
                    maxDiameter: Self.ringDiameter,
                    narrowDiameter: Self.narrowRingDiameter,
                    narrowBelowWidth: Self.narrowBelowWidth
                ) {
                    NoctisRecoveryRing(segments: segments, reveal: reveal, diameter: Self.ringDiameter, lineWidth: Self.ringLineWidth)
                    VStack(spacing: 0) {
                        Text("\(shownScore)")
                            .noctisNumeral(88, .heavy)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(shownScore)))
                            .foregroundStyle(NoctisAppColor.ink)
                        Text("Recovery")
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                .matchedTransitionSource(id: HomeView.recoveryZoomID, in: zoomNamespace)
            }
            .buttonStyle(NoctisCardButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(content.accessibilityLabel)
            .accessibilityHint("Opens recovery details.")
            .accessibilityAddTraits(.isButton)

            // Exactly one line under the ring.
            HStack(spacing: NoctisSpacing.xs) {
                if let chip = content.chip {
                    DeltaChipView(chip: chip)
                }
                Text(content.comparisonPhrase)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink2)
            }
            .accessibilityElement(children: .combine)

            if let caption = content.confidenceCaption {
                Text(caption)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.ink3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FactorCapsulesView(factors: content.factors) { openDetail($0) }
        }
        .task { playIntroIfPending() }
        .onChange(of: content.score) { _, score in
            withAnimation(NoctisMotion.settle) { shownScore = score }
        }
    }

    private var segments: [NoctisRingSegment] {
        content.segments.map { NoctisRingSegment(color: $0.kind.tint, weight: $0.weight, fraction: $0.fraction) }
    }

    private func playIntroIfPending() {
        guard viewModel.consumeIntro() else { return }
        withAnimation(Self.introAnimation) {
            reveal = 1
            shownScore = content.score
        } completion: {
            NoctisHaptics.medium()
        }
    }
}

struct DeltaChipView: View {
    let chip: DeltaChip

    var body: some View {
        Text(chip.text)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .foregroundStyle(NoctisAppColor.ink)
            .padding(.horizontal, NoctisSpacing.sm)
            .padding(.vertical, 6)
            .background(fill, in: Capsule(style: .continuous))
    }

    private var fill: Color {
        switch chip.tone {
        case .above: NoctisAppColor.sage.opacity(0.3)
        case .inLine: NoctisAppColor.track
        case .below: NoctisAppColor.orange.opacity(0.28)
        }
    }
}

/// Four capsules (dot, name, score) in one row; a 2×2 grid at
/// accessibility sizes or when the row can't fit. Each opens Recovery
/// detail at that factor.
struct FactorCapsulesView: View {
    let factors: [FactorCell]
    let open: (RecoveryFactorKind) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            grid
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NoctisSpacing.xs) {
                    ForEach(factors, id: \.kind) { capsule($0) }
                }
                grid
            }
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: NoctisSpacing.xs, verticalSpacing: NoctisSpacing.xs) {
            ForEach(Array(stride(from: 0, to: factors.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(factors[start..<min(start + 2, factors.count)], id: \.kind) { capsule($0) }
                }
            }
        }
    }

    private func capsule(_ factor: FactorCell) -> some View {
        Button { open(factor.kind) } label: {
            VStack(spacing: NoctisSpacing.xxs) {
                Circle().fill(factor.kind.tint).frame(width: 8, height: 8)
                Text(factor.name)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.ink2)
                    .fixedSize()
                Text("\(factor.score)")
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
            }
            .padding(.vertical, NoctisSpacing.sm)
            .padding(.horizontal, NoctisSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(NoctisAppColor.surface, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(factor.name) \(factor.score)")
        .accessibilityHint("Opens recovery details at \(factor.name).")
        .accessibilityAddTraits(.isButton)
    }
}

/// The ring before there's a score: track only (a thin cocoa arc while
/// learning), with a moon so it reads as waiting, not broken. 160pt on
/// the hero, 72pt in the compact card.
struct DormantRingView: View {
    var progress: Double?
    var diameter: CGFloat = 160
    var glyphSize: CGFloat = 28

    var body: some View {
        NoctisRingLayout(maxDiameter: diameter) {
            NoctisRecoveryRing(segments: [], progress: progress, diameter: diameter, lineWidth: diameter * 18 / 160)
            Image(systemName: "moon.zzz")
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundStyle(NoctisAppColor.ink3)
        }
        .accessibilityHidden(true)
    }
}

enum DormantAction {
    case connect(HomeViewModel)
    case openHealth
}

/// A state with nothing to score, on the paper: the dormant ring, what's
/// going on, and its one action if it has one.
struct DormantHeroView: View {
    var progress: Double?
    let title: String?
    let detail: String?
    var titleSize: CGFloat = 17
    var action: DormantAction?

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            DormantRingView(progress: progress)
            DormantTextView(title: title, detail: detail, titleSize: titleSize, alignment: .center)
            if let action {
                DormantActionView(action: action)
            }
        }
    }
}

struct DormantTextView: View {
    let title: String?
    let detail: String?
    var titleSize: CGFloat = 17
    var alignment: TextAlignment = .center

    var body: some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: NoctisSpacing.xxs) {
            if let title {
                Text(title)
                    .noctisFont(titleSize, .semibold, relativeTo: titleSize > 17 ? .title3 : .body)
                    .foregroundStyle(NoctisAppColor.ink)
            }
            if let detail {
                Text(detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink2)
            }
        }
        .multilineTextAlignment(alignment)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct DormantActionView: View {
    let action: DormantAction
    @Environment(\.openURL) private var openURL
    @State private var connecting = false

    var body: some View {
        switch action {
        case .connect(let viewModel):
            NoctisCTA("Connect Apple Health", isLoading: connecting, adaptive: true) {
                connecting = true
                Task {
                    await viewModel.connectAppleHealth()
                    connecting = false
                }
            }
        case .openHealth:
            if let health = URL(string: "x-apple-health://") {
                NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                    .accessibilityHint("Opens the Health app.")
            }
        }
    }
}

struct FailedHeroView: View {
    let message: String
    let viewModel: HomeViewModel

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(NoctisAppColor.orangeText)
                .accessibilityHidden(true)
            Text(message)
                .noctisFont(17, .semibold, relativeTo: .body)
                .foregroundStyle(NoctisAppColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            NoctisCTA("Try again", icon: "arrow.clockwise", adaptive: true) {
                Task { await viewModel.refresh() }
            }
        }
    }
}

// MARK: - Evening hero

/// Evening mode's hero, on the paper: tonight's bedtime large, a minute
/// countdown (or "Bedtime was …"), the night strip and the plan.
struct EveningHeroView: View {
    let content: EveningHeroContent
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            NoctisCaption("BEDTIME", color: NoctisAppColor.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(content.time)
                    .noctisNumeral(88, .heavy)
                    .foregroundStyle(NoctisAppColor.ink)
                if !content.period.isEmpty {
                    Text(content.period)
                        .noctisFont(28, .bold, relativeTo: .title)
                        .foregroundStyle(NoctisAppColor.ink)
                }
            }
            .accessibilityElement(children: .combine)
            if let minutes = content.times.minutesLeft(at: now), let countdown = content.times.countdown(at: now) {
                Text(countdown)
                    .noctisFont(22, .semibold, relativeTo: .title3)
                    .monospacedDigit()
                    .foregroundStyle(NoctisAppColor.orangeText)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : NoctisMotion.settle, value: minutes)
            } else {
                Text(content.times.passedText)
                    .noctisFont(22, .semibold, relativeTo: .title3)
                    .foregroundStyle(NoctisAppColor.ink2)
            }
            NightStripView(content: content, now: now)
                .padding(.vertical, NoctisSpacing.xs)
            Text(content.detail)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(NoctisAppColor.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 6 PM to 10 AM: a lavender span from bedtime to wake, and a cocoa "now"
/// marker that moves with the minute.
struct NightStripView: View {
    let content: EveningHeroContent
    let now: Date

    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                let barHeight: CGFloat = 10
                let track = CGRect(x: 0, y: (size.height - barHeight) / 2, width: size.width, height: barHeight)
                context.fill(Path(roundedRect: track, cornerRadius: barHeight / 2), with: .color(NoctisAppColor.ringTrack))
                let start = content.times.bedtimeFraction * size.width
                let end = content.times.wakeFraction * size.width
                let span = CGRect(x: start, y: track.minY, width: max(end - start, barHeight), height: barHeight)
                context.fill(Path(roundedRect: span, cornerRadius: barHeight / 2), with: .color(NoctisAppColor.lavender))
                if let fraction = content.times.nowFraction(at: now) {
                    let marker = CGRect(x: fraction * size.width - 2, y: 0, width: 4, height: size.height)
                    context.fill(Path(roundedRect: marker, cornerRadius: 2), with: .color(NoctisAppColor.cocoa))
                }
            }
            .frame(height: 22)
            NoctisFractionLayout {
                ForEach(content.stripLabels, id: \.position) { label in
                    Text(label.text)
                        .noctisFont(11, .medium, relativeTo: .caption2)
                        .foregroundStyle(NoctisAppColor.ink3)
                        .noctisFraction(label.position)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.stripAccessibilityLabel)
    }
}

// MARK: - Compact Recovery (evening)

/// Evening's Recovery, below the Tonight hero: a 72pt ring, the score and
/// the delta chip in one row, zooming into detail like the day ring.
/// States show the small dormant ring and their message.
struct CompactRecoveryCard: View {
    let content: RecoveryCardContent
    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID
    let openDetail: (RecoveryFactorKind?) -> Void

    var body: some View {
        switch content {
        case .scored(let scored):
            Button { openDetail(nil) } label: {
                NoctisAppCard {
                    HStack(spacing: NoctisSpacing.md) {
                        NoctisRingLayout(maxDiameter: 72) {
                            NoctisRecoveryRing(
                                segments: scored.segments.map { NoctisRingSegment(color: $0.kind.tint, weight: $0.weight, fraction: $0.fraction) },
                                diameter: 72,
                                lineWidth: 9
                            )
                        }
                        .frame(width: 72)
                        .matchedTransitionSource(id: HomeView.recoveryZoomID, in: zoomNamespace)
                        VStack(alignment: .leading, spacing: 2) {
                            NoctisCaption("RECOVERY", color: NoctisAppColor.ink3)
                            HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.xs) {
                                Text("\(scored.score)")
                                    .noctisFont(34, .heavy, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
                                    .foregroundStyle(NoctisAppColor.ink)
                                if let chip = scored.chip {
                                    DeltaChipView(chip: chip)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .noctisIcon(15)
                            .foregroundStyle(NoctisAppColor.ink3)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(NoctisCardButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(scored.accessibilityLabel)
            .accessibilityHint("Opens recovery details.")
            .accessibilityAddTraits(.isButton)
            // The draw-in belongs to the day hero; evening just uses up
            // the day's turn so it can't play later.
            .task { _ = viewModel.consumeIntro() }
        case .learning(let nights, let required, let text):
            row(progress: Double(nights) / Double(required), title: nil, detail: text, action: nil)
        case .connect(let title, let message, let showsButton):
            row(title: title, detail: message, action: showsButton ? .connect(viewModel) : nil)
        case .noSleepData(let title, let message):
            row(title: title, detail: message, action: .openHealth)
        case .noSleep(let title, let detail):
            row(title: title, detail: detail, action: nil)
        case .stale(let title, let detail):
            row(title: title, detail: detail, action: nil)
        case .failed(let message):
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    DormantTextView(title: message, detail: nil, alignment: .leading)
                    NoctisCTA("Try again", icon: "arrow.clockwise", adaptive: true) {
                        Task { await viewModel.refresh() }
                    }
                }
            }
        }
    }

    private func row(progress: Double? = nil, title: String?, detail: String?, action: DormantAction?) -> some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                HStack(spacing: NoctisSpacing.md) {
                    DormantRingView(progress: progress, diameter: 72, glyphSize: 18)
                        .frame(width: 72)
                    DormantTextView(title: title, detail: detail, alignment: .leading)
                    Spacer(minLength: 0)
                }
                if let action {
                    DormantActionView(action: action)
                }
            }
        }
    }
}
