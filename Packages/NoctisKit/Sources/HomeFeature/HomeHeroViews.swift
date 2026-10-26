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
    let actions: HomeActions

    var body: some View {
        Group {
            switch content {
            case .scored(let scored):
                ScoredHeroView(content: scored, viewModel: viewModel, zoomNamespace: zoomNamespace, actions: actions)
            case .learning(let nights, let required, let text):
                LearningHeroView(nights: nights, required: required, text: text)
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
/// and the factor capsules.
///
/// - Morning reveal: the ring fills segment by segment (0.9s, `.drawIn`),
///   the score counts up and lands with a medium haptic, and the capsules
///   rise 60ms apart.
/// - A capsule tap first highlights its segment (the rest fade to 40%,
///   0.4s), then zooms into detail at that factor.
/// - A long press offers Open Recovery and Share today over a preview of
///   the detail.
/// - A live update re-fills only the segments that changed.
/// - Scrolling away shrinks the ring (to 0.85) and fades it.
struct ScoredHeroView: View {
    let content: ScoredRecoveryContent
    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID
    let actions: HomeActions

    @Environment(\.homeReveal) private var reveal
    @Environment(\.homeMorph) private var morph
    @Environment(\.homeLowPower) private var lowPower
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focused: RecoveryFactorKind?
    /// Between the reveal starting and the score landing: the score holds
    /// at 0 while dusk lifts (a numeric transition ignores delays).
    @State private var awaitingCount = false

    static let ringDiameter: CGFloat = 260
    static let narrowRingDiameter: CGFloat = 220
    /// Offered less than this, the ring uses its narrow size (an SE).
    static let narrowBelowWidth: CGFloat = 350
    static let ringLineWidth: CGFloat = 22
    /// The ring's draw-in and the score's count-up: one spring with no
    /// bounce, about 0.9s, so a tap or a skip can cut it mid-flight.
    static let introAnimation = NoctisMotion.draw(HomeReveal.ringDuration)
    /// How long a capsule's segment stays highlighted before detail opens.
    static let focusDuration = 0.4

    var body: some View {
        #if DEBUG
        let _ = HomeBodyProbe.hit("ScoredHero")
        #endif
        VStack(spacing: NoctisSpacing.md) {
            HomeCollapseEffect(viewModel: viewModel) { ring.background { HomePaperDisc() } }

            // Exactly one line under the ring, then why (when a factor is
            // outside its normal range).
            VStack(spacing: NoctisSpacing.xs) {
                HStack(spacing: NoctisSpacing.xs) {
                    if let chip = content.chip {
                        DeltaChipView(chip: chip)
                    }
                    Text(content.comparisonPhrase)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
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

            if let caption = content.confidenceCaption {
                Text(caption)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FactorCapsulesView(factors: content.factors, open: focus)

            // The ring's 'usual' ticks and their caption are not drawn (the owner's call, QA part 6): the segments and the number say it.
        }
        // Cancelled with the view, so a skipped reveal never lands a haptic.
        .task(id: reveal) {
            guard reveal == .playing, !reduceMotion else { return }
            if HomeReveal.countsUp(lowPower: lowPower) {
                awaitingCount = true
                try? await Task.sleep(for: .seconds(HomeRevealPhase.contentDelay))
                guard !Task.isCancelled else { return }
                // The score counts up with the ring…
                withAnimation(Self.introAnimation) { awaitingCount = false }
                try? await Task.sleep(for: .seconds(HomeReveal.ringDuration))
            } else {
                // Low Power Mode: the score is already there; only the
                // landing's haptic waits for the ring.
                try? await Task.sleep(for: .seconds(HomeRevealPhase.contentDelay + HomeReveal.ringDuration))
            }
            guard !Task.isCancelled else { return }
            // …and lands.
            NoctisHaptics.medium()
        }
    }

    private var ring: some View {
        Button {
            actions.openRecoveryDetail(nil)
        } label: {
            NoctisRingLayout(
                maxDiameter: Self.ringDiameter,
                narrowDiameter: Self.narrowRingDiameter,
                narrowBelowWidth: Self.narrowBelowWidth
            ) {
                NoctisRecoveryRing(
                    segments: segments,
                    reveal: reveal.holdsStart ? 0 : 1,
                    highlight: focused.flatMap { kind in content.segments.firstIndex { $0.kind == kind } },
                    dim: focused == nil ? 0 : 1,
                    showsUsual: false,
                    diameter: Self.ringDiameter,
                    lineWidth: Self.ringLineWidth
                )
                .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: focused)
                .animation(reduceMotion ? nil : Self.introAnimation.delay(HomeRevealPhase.contentDelay), value: reveal)
                VStack(spacing: 0) {
                    Text("\(shownScore)")
                        .noctisNumeral(88, .heavy)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shownScore)))
                        .foregroundStyle(NoctisAppColor.ink)
                        .animation(reduceMotion ? nil : NoctisMotion.settle, value: content.score)
                    Text("Recovery")
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .homeMorph(.recoveryRing, in: morph)
            .matchedTransitionSource(id: HomeView.recoveryZoomID, in: zoomNamespace)
        }
        .buttonStyle(NoctisCardButtonStyle())
        .contextMenu {
            Button("Open Recovery", systemImage: "heart") { actions.openRecoveryDetail(nil) }
            Button("Share today", systemImage: "square.and.arrow.up", action: actions.share)
        } preview: {
            RecoveryPreviewCard(content: content, rows: viewModel.screen?.detail?.rows ?? [])
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint("Opens recovery details.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open Recovery") { actions.openRecoveryDetail(nil) }
        .accessibilityAction(named: "Share today", actions.share)
        .accessibilityIdentifier(viewModel.revealPlayed ? "home.hero.revealed" : "home.hero")
    }

    private var shownScore: Int {
        guard HomeReveal.countsUp(lowPower: lowPower) else { return content.score }
        return reveal.holdsStart || awaitingCount ? 0 : content.score
    }

    private var segments: [NoctisRingSegment] {
        content.segments.map(\.ringSegment)
    }

    /// Highlight the capsule's segment, then open that factor's page.
    private func focus(_ kind: RecoveryFactorKind) {
        focused = kind
        let hold = reduceMotion ? 0.2 : Self.focusDuration
        Task {
            try? await Task.sleep(for: .seconds(hold))
            actions.openRecoveryFactor(kind)
            // Back to normal under the zoom, before it returns.
            try? await Task.sleep(for: .seconds(0.6))
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { focused = nil }
        }
    }
}

/// The ring's long-press preview: Recovery in detail, in brief.
struct RecoveryPreviewCard: View {
    let content: ScoredRecoveryContent
    let rows: [FactorDetailRow]

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            HStack(spacing: NoctisSpacing.md) {
                NoctisRingLayout(maxDiameter: 96) {
                    NoctisRecoveryRing(
                        segments: content.segments.map(\.ringSegment),
                        diameter: 96,
                        lineWidth: 10
                    )
                    Text("\(content.score)")
                        .noctisNumeral(34, .heavy)
                        .foregroundStyle(NoctisAppColor.ink)
                }
                .frame(width: 96)
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    NoctisCaption("RECOVERY", style: .noctisInk3)
                    HStack(spacing: NoctisSpacing.xs) {
                        if let chip = content.chip { DeltaChipView(chip: chip) }
                        Text(content.comparisonPhrase)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(.noctisInk2)
                    }
                }
            }
            VStack(spacing: NoctisSpacing.xs) {
                ForEach(rows, id: \.kind) { row in
                    HStack(spacing: NoctisSpacing.xs) {
                        Circle().fill(row.kind.tint).frame(width: 8, height: 8)
                        Text(row.name)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                        NoctisMetric(row.value, size: 15, relativeTo: .subheadline)
                        if let suffix = row.valueSuffix {
                            Text(suffix)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(NoctisAppColor.ink)
                        }
                        Spacer(minLength: NoctisSpacing.xs)
                        Text("\(row.score)")
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                    }
                }
            }
        }
        .padding(NoctisSpacing.lg)
        .frame(width: 320, alignment: .leading)
        .background(NoctisAppColor.bg)
    }
}

public struct DeltaChipView: View {
    let chip: DeltaChip

    public init(chip: DeltaChip) {
        self.chip = chip
    }

    public var body: some View {
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
/// accessibility sizes or when the row can't fit, and one column when even
/// the grid can't (the largest sizes). Each opens Recovery detail at that
/// factor. In the morning reveal they rise 12pt into place, 60ms apart.
struct FactorCapsulesView: View {
    let factors: [FactorCell]
    let open: (RecoveryFactorKind) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.homeReveal) private var reveal
    @Environment(\.homeLowPower) private var lowPower
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: NoctisSpacing.xs) {
                    ForEach(Array(factors.enumerated()), id: \.element.kind) { index, factor in capsule(factor, index: index) }
                }
            }
            grid
            VStack(spacing: NoctisSpacing.xs) {
                ForEach(Array(factors.enumerated()), id: \.element.kind) { index, factor in capsule(factor, index: index) }
            }
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: NoctisSpacing.xs, verticalSpacing: NoctisSpacing.xs) {
            ForEach(Array(stride(from: 0, to: factors.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + 2, factors.count), id: \.self) { index in capsule(factors[index], index: index) }
                }
            }
        }
    }

    private func capsule(_ factor: FactorCell, index: Int) -> some View {
        Button {
            open(factor.kind)
        } label: {
            VStack(spacing: NoctisSpacing.xxs) {
                Circle().fill(factor.kind.tint).frame(width: 8, height: 8)
                Text(factor.name)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize()
                Text("\(factor.score)")
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
            }
            .padding(.vertical, NoctisSpacing.sm)
            .padding(.horizontal, NoctisSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(NoctisAppColor.surface, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(contrast == .increased ? NoctisAppColor.ink : NoctisAppColor.hairline, lineWidth: contrast == .increased ? 1.5 : 1)
            )
        }
        .buttonStyle(NoctisCardButtonStyle())
        .opacity(reveal.holdsStart ? 0 : 1)
        .offset(y: reveal.holdsStart ? HomeReveal.rise : 0)
        .animation(
            reduceMotion ? nil : NoctisMotion.settle.delay(HomeRevealPhase.contentDelay + HomeReveal.capsuleDelay(index, lowPower: lowPower)),
            value: reveal
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(factor.spoken)
        .accessibilityHint("Opens recovery details at \(factor.name).")
        .accessibilityAddTraits(.isButton)
    }
}

/// The ring before there's a score: track only, with a moon so it reads
/// as waiting, not broken. 160pt on the hero, 72pt in the compact card.
public struct DormantRingView: View {
    var diameter: CGFloat = 160
    var glyphSize: CGFloat = 28
    /// Sleep and Recovery draw it in cocoa at .2 under their color field;
    /// Home keeps the paper's track.
    var onField = false

    public init(diameter: CGFloat = 160, glyphSize: CGFloat = 28, onField: Bool = false) {
        self.diameter = diameter
        self.glyphSize = glyphSize
        self.onField = onField
    }

    public var body: some View {
        NoctisRingLayout(maxDiameter: diameter) {
            NoctisRecoveryRing(segments: [], diameter: diameter, lineWidth: diameter * 18 / 160)
                .environment(\.noctisRingTrack, onField ? NoctisAppColor.cocoa.opacity(0.2) : nil)
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

/// Learning your baseline: the dormant ring, then one dot per night
/// needed (recorded nights filled), "Learning your baseline" and "3 of 5
/// nights".
struct LearningHeroView: View {
    let nights: Int
    let required: Int
    let text: String

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            DormantRingView()
            LearningDots(nights: nights, required: required)
            DormantTextView(title: "Learning your baseline", detail: text, alignment: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Learning your baseline, \(nights) of \(required) nights recorded.")
    }
}

/// 10pt dots, 8pt apart: cocoa (lavender in Dark) for each night recorded,
/// track for the rest.
public struct LearningDots: View {
    let nights: Int
    let required: Int

    public init(nights: Int, required: Int) {
        self.nights = nights
        self.required = required
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<required, id: \.self) { index in
                Circle()
                    .fill(index < nights ? NoctisAppColor.progressDot : NoctisAppColor.track)
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A state with nothing to score, on the paper: the dormant ring, what's
/// going on, and its one action if it has one.
struct DormantHeroView: View {
    let title: String?
    let detail: String?
    var titleSize: CGFloat = 17
    var action: DormantAction?

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            DormantRingView()
            DormantTextView(title: title, detail: detail, titleSize: titleSize, alignment: .center)
            if let action {
                DormantActionView(action: action)
            }
        }
    }
}

public struct DormantTextView: View {
    let title: String?
    let detail: String?
    var titleSize: CGFloat = 17
    var alignment: TextAlignment = .center

    public init(title: String?, detail: String?, titleSize: CGFloat = 17, alignment: TextAlignment = .center) {
        self.title = title
        self.detail = detail
        self.titleSize = titleSize
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: NoctisSpacing.xxs) {
            if let title {
                Text(title)
                    .noctisFont(titleSize, .semibold, relativeTo: titleSize > 17 ? .title3 : .body)
                    .foregroundStyle(NoctisAppColor.ink)
            }
            if let detail {
                Text(detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
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
            HealthDataSettingsLink()
        case .openHealth:
            if let health = URL(string: "x-apple-health://") {
                NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                    .accessibilityHint("Opens the Health app.")
            }
            HealthDataSettingsLink()
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
/// countdown (or "Bedtime was …"), the night strip and the plan. Read as
/// one summary; shrinks and fades as it scrolls away.
struct EveningHeroView: View {
    let content: EveningHeroContent
    let viewModel: HomeViewModel

    var body: some View {
        HomeCollapseEffect(viewModel: viewModel, anchor: .topLeading) {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption(content.caption, style: .noctisInk3)
                // The window is longer than one time: it sits at the size Tonight draws it.
                NoctisMetric(content.time, size: content.isWindow ? 56 : 88)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                EveningCountdownView(times: content.times)
                NightStripView(content: content)
                    .padding(.vertical, NoctisSpacing.xs)
                Text(content.detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .modifier(HomeClockLabel { summary(at: $0) })
        .accessibilityIdentifier("home.eveningHero")
    }

    /// "Bedtime 11:00 PM, in 2h 14m. Tonight's sleep window, 11:00 PM to
    /// 7:00 AM. Wake 7:00 AM · 8h need."
    private func summary(at now: Date) -> String {
        let lead = content.times.countdownMetric(at: now).map { "Bedtime \(content.times.bedtimeText), in \($0.spoken)." } ?? "\(content.times.passedText)."
        let window = content.isWindow ? "Bedtime window \(content.time.spoken)." : nil
        return [window, lead, content.stripAccessibilityLabel, content.detail].compactMap { $0 }.joined(separator: " ")
    }
}

/// "in 2h 14m", counting down: the one line of the evening hero that reads
/// the minute clock.
struct EveningCountdownView: View {
    let times: TonightTimes
    @Environment(\.homeClock) private var clock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        #if DEBUG
        let _ = HomeBodyProbe.hit("EveningCountdown")
        #endif
        let now = clock?.minute ?? .now
        if let minutes = times.minutesLeft(at: now), let countdown = times.countdownMetric(at: now) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("in")
                    .noctisFont(22, .semibold, relativeTo: .title3)
                    .foregroundStyle(NoctisAppColor.orangeText)
                NoctisMetric(countdown, size: 22, relativeTo: .title3, tone: .accent)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : NoctisMotion.settle, value: minutes)
            }
        } else {
            Text(times.passedText)
                .noctisFont(22, .semibold, relativeTo: .title3)
                .foregroundStyle(.noctisInk2)
        }
    }
}

/// 6 PM to 10 AM: a lavender span from bedtime to wake, and a cocoa "now"
/// marker that moves with the minute. Only the marker is inside the
/// minute's `TimelineView`; the track and the span are drawn once.
struct NightStripView: View {
    let content: EveningHeroContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The tick labels are placed by fraction of the strip; at accessibility sizes four of them (6 PM, 12 AM, 6 AM, 10 AM) do not fit side by
    /// side ("6 AM10 AM" ran into one on a 17 Pro at AX3), so the strip keeps its first and its last one: the window itself is read in the
    /// line under it ("Wake 7:00 AM · 8h need") and in the bedtime above.
    private var labels: [EveningHeroContent.StripLabel] {
        let all = content.stripLabels
        guard dynamicTypeSize.isAccessibilitySize, all.count > 2 else { return all }
        return [all[0], all[all.count - 1]]
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                NoctisSpanLayout(to: 1) { Capsule().fill(NoctisAppColor.ringTrack).frame(height: 10) }
                NoctisSpanLayout(from: content.times.bedtimeFraction, to: content.times.wakeFraction, minimumWidth: 10) {
                    Capsule().fill(NoctisAppColor.lavender).frame(height: 10)
                }
                TimelineView(.everyMinute) { timeline in
                    NoctisFractionLayout {
                        if let fraction = content.times.nowFraction(at: timeline.date) {
                            Capsule().fill(NoctisAppColor.cocoa).frame(width: 4, height: 22)
                                .noctisFraction(fraction)
                        }
                    }
                }
            }
            .frame(height: 22)
            NoctisFractionLayout {
                ForEach(labels, id: \.position) { label in
                    Text(label.text)
                        .noctisFont(12, .medium, relativeTo: .caption2)
                        .foregroundStyle(.noctisInk3)
                        .noctisFraction(label.position)
                }
            }
        }
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
    @Environment(\.homeMorph) private var morph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch content {
        case .scored(let scored):
            Button {
                openDetail(nil)
            } label: {
                NoctisAppCard {
                    HStack(spacing: NoctisSpacing.md) {
                        NoctisRingLayout(maxDiameter: 72) {
                            NoctisRecoveryRing(
                                segments: scored.segments.map(\.ringSegment),
                                diameter: 72,
                                lineWidth: 9
                            )
                        }
                        .frame(width: 72)
                        // The day ring shrinks into this one in the mode morph.
                        .homeMorph(.recoveryRing, in: morph)
                        .matchedTransitionSource(id: HomeView.recoveryZoomID, in: zoomNamespace)
                        VStack(alignment: .leading, spacing: 2) {
                            NoctisCaption("RECOVERY", style: .noctisInk3)
                            HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.xs) {
                                NoctisMetric(NoctisMetricValue(parts: [.number("\(scored.score)")], spoken: "\(scored.score)"), size: 34)
                                    .monospacedDigit()
                                    .contentTransition(.numericText(value: Double(scored.score)))
                                    .animation(reduceMotion ? nil : NoctisMotion.settle, value: scored.score)
                                if let chip = scored.chip {
                                    DeltaChipView(chip: chip)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .noctisIcon(15)
                            .foregroundStyle(.noctisInk3)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(NoctisCardButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(scored.accessibilityLabel)
            .accessibilityHint("Opens recovery details.")
            .accessibilityAddTraits(.isButton)
        case .learning(let nights, let required, let text):
            learningRow(nights: nights, required: required, text: text)
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

    /// The ring beside the words; above them at accessibility sizes, where a 72pt ring beside the text left it a column of about 150pt
    /// (seven lines for "NOCTIS reads sleep from Apple Health..." on an SE at AX5).
    private func ringAndText<Text: View>(@ViewBuilder text: () -> Text) -> some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoctisSpacing.md))
            : AnyLayout(HStackLayout(spacing: NoctisSpacing.md))
        return layout {
            DormantRingView(diameter: 72, glyphSize: 18)
                .frame(width: 72)
            text()
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
    }

    private func learningRow(nights: Int, required: Int, text: String) -> some View {
        NoctisAppCard {
            ringAndText {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    DormantTextView(title: "Learning your baseline", detail: text, alignment: .leading)
                    LearningDots(nights: nights, required: required)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Learning your baseline, \(nights) of \(required) nights recorded.")
    }

    private func row(title: String?, detail: String?, action: DormantAction?) -> some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                ringAndText {
                    DormantTextView(title: title, detail: detail, alignment: .leading)
                }
                if let action {
                    DormantActionView(action: action)
                }
            }
        }
    }
}
