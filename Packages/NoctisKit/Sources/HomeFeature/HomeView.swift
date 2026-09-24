import DesignSystem
import NoctisCore
import RecoveryKit
import SwiftUI

/// The Home tab: Home in a navigation stack that pushes Recovery (zooming
/// out of the ring) and Profile.
public struct HomeTabView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoom
    private let viewModel: HomeViewModel

    public init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.homePath) {
            HomeView(viewModel: viewModel, zoomNamespace: zoom)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .recoveryDetail:
                        RecoveryDetailView(viewModel: viewModel)
                            .navigationTransition(.zoom(sourceID: HomeView.recoveryZoomID, in: zoom))
                    case .profile:
                        // R19: Profile isn't built yet (ROADMAP.md).
                        NoctisComingSoonView(title: "Profile", systemImage: "person.crop.circle")
                    }
                }
        }
    }
}

/// "How am I today?" — one top-aligned scroll: header, then Recovery,
/// Last night, Insight, Tonight and This week. Reads only
/// `HomeViewModel.header` and `.screen` (APP_RULES.md R20).
struct HomeView: View {
    static let recoveryZoomID = "recovery"

    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeaderView(header: viewModel.header) {
                    model.homePath.append(.profile)
                }
                // R6: content starts 24pt below the title.
                Color.clear.frame(height: NoctisSpacing.xl)
                if let screen = viewModel.screen {
                    cards(screen)
                } else {
                    HomeSkeletonView()
                }
            }
            .padding(.horizontal, NoctisSpacing.lg)
            .padding(.top, NoctisSpacing.xs)
            .padding(.bottom, NoctisSpacing.xl)
        }
        // R14: cards keep their shadows at the scroll view's edges.
        .scrollClipDisabled()
        // Nothing may show behind the status bar.
        .noctisStatusBarGuard()
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.onAppear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.updateClock() }
        }
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
    }

    private func cards(_ screen: HomeScreen) -> some View {
        VStack(spacing: NoctisSpacing.md) {
            RecoveryCardView(
                content: screen.recovery,
                viewModel: viewModel,
                zoomNamespace: zoomNamespace,
                openDetail: { model.homePath.append(.recoveryDetail) }
            )
            if let lastNight = screen.lastNight {
                LastNightCardView(content: lastNight) { model.open(.sleep) }
            }
            if let insight = screen.insight {
                InsightCardView(content: insight)
            }
            TonightCardView(content: screen.tonight)
            if let week = screen.week {
                WeekCardView(content: week) { model.open(.sleep) }
            }
        }
    }
}

// MARK: - Header

struct HomeHeaderView: View {
    let header: HomeHeader
    let openProfile: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.sm) {
            VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                Text("\(Text(header.greetingLead))\(Text(header.greetingEmphasis).foregroundStyle(NoctisAppColor.orangeText))\(Text(header.greetingTrail))")
                    .noctisFont(34, .bold, relativeTo: .largeTitle)
                    .tracking(-0.6)
                    .foregroundStyle(NoctisAppColor.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(header.date)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink2)
                if let updated = header.updated {
                    Text(updated)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(NoctisAppColor.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: openProfile) {
                Circle()
                    .fill(NoctisAppColor.track)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NoctisAppColor.ink2)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
            .accessibilityHint("Opens your profile.")
        }
    }
}

// MARK: - Recovery

struct RecoveryCardView: View {
    let content: RecoveryCardContent
    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID
    let openDetail: () -> Void

    var body: some View {
        switch content {
        case .scored(let scored):
            Button(action: openDetail) {
                NoctisAppCard {
                    ScoredRecoveryView(content: scored, viewModel: viewModel, zoomNamespace: zoomNamespace)
                }
            }
            .buttonStyle(NoctisCardButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(scored.accessibilityLabel)
            .accessibilityHint("Opens recovery details.")
            .accessibilityAddTraits(.isButton)
        case .learning(let nights, let required, let text):
            NoctisAppCard {
                VStack(spacing: NoctisSpacing.md) {
                    DormantRingView(progress: Double(nights) / Double(required))
                    Text(text)
                        .noctisFont(15, .medium, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.replacingOccurrences(of: " · ", with: ", "))
        case .connect(let title, let message, let showsButton):
            ConnectCardView(title: title, message: message, showsButton: showsButton, viewModel: viewModel)
        case .noSleepData(let title, let message):
            DormantNoticeView(title: title, detail: message, titleSize: 22, opensHealth: true)
        case .noSleep(let title, let detail):
            DormantNoticeView(title: title, detail: detail)
        case .stale(let title, let detail):
            DormantNoticeView(title: title, detail: detail)
        case .failed(let message):
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.xs) {
                        Image(systemName: "exclamationmark.circle")
                            .noctisIcon(17)
                            .foregroundStyle(NoctisAppColor.orangeText)
                            .accessibilityHidden(true)
                        Text(message)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    NoctisCTA("Try again", icon: "arrow.clockwise", adaptive: true) {
                        Task { await viewModel.refresh() }
                    }
                }
            }
        }
    }
}

/// The scored ring with its score, chip, sentence, confidence and factor
/// row. The first time each day it draws itself in (0.9s, `.drawIn`),
/// the score counts up, and a medium haptic lands with it.
struct ScoredRecoveryView: View {
    let content: ScoredRecoveryContent
    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var reveal: Double
    @State private var shownScore: Int

    static let ringDiameter: CGFloat = 200
    static let ringLineWidth: CGFloat = 18
    /// The space inside the ring the score and its label must fit.
    static let centerSize = CGSize(width: 140, height: 104)
    /// `NoctisMotion.drawIn`'s curve, run over 0.9s.
    static let introAnimation = NoctisMotion.drawIn.speed(1.2 / 0.9)

    init(content: ScoredRecoveryContent, viewModel: HomeViewModel, zoomNamespace: Namespace.ID) {
        self.content = content
        self.viewModel = viewModel
        self.zoomNamespace = zoomNamespace
        let intro = viewModel.introPending
        _reveal = State(initialValue: intro ? 0 : 1)
        _shownScore = State(initialValue: intro ? 0 : content.score)
    }

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            ZStack {
                NoctisRecoveryRing(segments: segments, reveal: reveal, diameter: Self.ringDiameter, lineWidth: Self.ringLineWidth)
                VStack(spacing: 0) {
                    Text("\(shownScore)")
                        .noctisNumeral(64, .heavy)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shownScore)))
                        .foregroundStyle(NoctisAppColor.ink)
                    Text("Recovery")
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                // R4: the ring is a fixed hero graphic, so its center text
                // shrinks to fit inside it at large sizes.
                .frame(width: Self.centerSize.width, height: Self.centerSize.height)
            }
            .matchedTransitionSource(id: HomeView.recoveryZoomID, in: zoomNamespace)

            if let chip = content.chip {
                DeltaChipView(chip: chip)
            }
            VStack(spacing: NoctisSpacing.xxs) {
                Text(content.sentence)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(content.confidence)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.ink3)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            FactorRowView(factors: content.factors)
        }
        .frame(maxWidth: .infinity)
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

/// Dot, name and score per factor: four columns, stacked at
/// accessibility sizes (R4).
struct FactorRowView: View {
    let factors: [FactorCell]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                ForEach(factors, id: \.kind) { factor in
                    HStack(spacing: NoctisSpacing.xs) {
                        dot(factor.kind)
                        Text(factor.name)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink2)
                        Spacer(minLength: NoctisSpacing.xs)
                        Text("\(factor.score)")
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: NoctisSpacing.xxs) {
                ForEach(factors, id: \.kind) { factor in
                    VStack(spacing: NoctisSpacing.xxs) {
                        dot(factor.kind)
                        Text(factor.name)
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(NoctisAppColor.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("\(factor.score)")
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func dot(_ kind: RecoveryFactorKind) -> some View {
        Circle().fill(kind.tint).frame(width: 8, height: 8)
    }
}

/// The ring before there's a score: 160pt, track only (a thin cocoa arc
/// while learning), with a moon so it reads as waiting, not broken.
struct DormantRingView: View {
    var progress: Double?

    var body: some View {
        ZStack {
            NoctisRecoveryRing(segments: [], progress: progress, diameter: 160)
            Image(systemName: "moon.zzz")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(NoctisAppColor.ink3)
        }
        .accessibilityHidden(true)
    }
}

/// The recovery card when there's nothing to score: the dormant ring and
/// what's going on — optionally with "Open Health".
struct DormantNoticeView: View {
    let title: String
    let detail: String?
    var titleSize: CGFloat = 17
    var opensHealth = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NoctisAppCard {
            VStack(spacing: NoctisSpacing.md) {
                DormantRingView()
                VStack(spacing: NoctisSpacing.xxs) {
                    Text(title)
                        .noctisFont(titleSize, .semibold, relativeTo: titleSize > 17 ? .title3 : .body)
                        .foregroundStyle(NoctisAppColor.ink)
                    if let detail {
                        Text(detail)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink2)
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                if opensHealth, let health = URL(string: "x-apple-health://") {
                    NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                        .accessibilityHint("Opens the Health app.")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ConnectCardView: View {
    let title: String
    let message: String
    let showsButton: Bool
    let viewModel: HomeViewModel
    @State private var connecting = false

    var body: some View {
        NoctisAppCard {
            VStack(spacing: NoctisSpacing.md) {
                DormantRingView()
                VStack(spacing: NoctisSpacing.xxs) {
                    Text(title)
                        .noctisFont(22, .semibold, relativeTo: .title3)
                        .foregroundStyle(NoctisAppColor.ink)
                    Text(message)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink2)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                if showsButton {
                    NoctisCTA("Connect Apple Health", isLoading: connecting, adaptive: true) {
                        connecting = true
                        Task {
                            await viewModel.connectAppleHealth()
                            connecting = false
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Last night

struct LastNightCardView: View {
    let content: LastNightCardContent
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    Text("Last night")
                        .noctisFont(15, .medium, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink2)
                    VStack(alignment: .leading, spacing: 2) {
                        durationLine
                        Text(content.timeRange)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink2)
                    }
                    StageStripView(strip: content.strip)
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint("Opens the Sleep tab.")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var durationLine: some View {
        let duration = Text(content.duration)
            .noctisFont(40, .heavy, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
            .foregroundStyle(NoctisAppColor.ink)
        let slept = Text("slept")
            .noctisFont(15, relativeTo: .subheadline)
            .foregroundStyle(NoctisAppColor.ink2)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) { duration; slept }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) { duration; slept }
        }
    }
}

/// The night as a 14pt capsule: stages in place, hairline gaps between
/// them, the track showing through wherever the data has a gap.
struct StageStripView: View {
    let strip: StageStripContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch strip {
        case .stages(let segments, let legend):
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                Canvas { context, size in
                    draw(segments, in: context, size: size)
                }
                .frame(height: 14)
                .accessibilityHidden(true)
                legendView(legend)
            }
        case .noStages(let caption):
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                Capsule(style: .continuous)
                    .fill(NoctisAppColor.sage)
                    .frame(height: 14)
                Text(caption)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func draw(_ segments: [StripSegment], in context: GraphicsContext, size: CGSize) {
        let capsule = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
        var context = context
        context.clip(to: capsule)
        context.fill(capsule, with: .color(NoctisAppColor.track))
        for segment in segments {
            let rect = CGRect(x: segment.start * size.width, y: 0, width: (segment.end - segment.start) * size.width, height: size.height)
            context.fill(Path(rect), with: .color(segment.stage.tint))
        }
        // Hairline gaps where one stage hands over to the next.
        for (previous, next) in zip(segments, segments.dropFirst()) where abs(next.start - previous.end) < 1e-6 {
            let x = next.start * size.width
            context.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)), with: .color(NoctisAppColor.surface))
        }
    }

    @ViewBuilder
    private func legendView(_ legend: [StripStage]) -> some View {
        let items = ForEach(legend, id: \.self) { stage in
            // 6pt between dot and word at every size.
            HStack(spacing: 6) {
                Circle().fill(stage.tint).frame(width: 8, height: 8)
                Text(stage.name)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.ink3)
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: NoctisSpacing.xxs) { items }
        } else {
            HStack(spacing: NoctisSpacing.sm) { items }
        }
    }
}

// MARK: - Insight and Tonight

struct InsightCardView: View {
    let content: InsightCardContent

    var body: some View {
        NoctisAppCard {
            HStack(alignment: .top, spacing: 14) {
                NoctisIconTile(systemImage: "lightbulb.fill", fill: NoctisAppColor.butter, foreground: NoctisAppColor.onFill, size: 40)
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    Text(content.title)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                    Text(content.message)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink2)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TonightCardView: View {
    let content: TonightCardContent

    var body: some View {
        NoctisAppCard {
            HStack(alignment: .top, spacing: 14) {
                NoctisIconTile(systemImage: "moon.fill", fill: NoctisAppColor.lavender, foreground: NoctisAppColor.onFill, size: 40)
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    Text("Tonight")
                        .noctisFont(15, .medium, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink2)
                    Text(content.bedtime)
                        .noctisFont(22, .semibold, relativeTo: .title3)
                        .foregroundStyle(NoctisAppColor.ink)
                    Text(content.detail)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink2)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - This week

struct WeekCardView: View {
    let content: WeekCardContent
    let open: () -> Void

    static let chartHeight: CGFloat = 110
    static let barWidth: CGFloat = 16

    var body: some View {
        Button(action: open) {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("This week")
                            .noctisFont(15, .medium, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink2)
                        Spacer(minLength: NoctisSpacing.xs)
                        HStack(spacing: 6) {
                            DashedLine()
                                .stroke(NoctisAppColor.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                .frame(width: 16, height: 1.5)
                            Text(content.needLabel)
                                .noctisFont(13, relativeTo: .footnote)
                                .foregroundStyle(NoctisAppColor.ink3)
                        }
                    }
                    chart
                    if let average = content.average {
                        Text(average)
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                    }
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint("Opens the Sleep tab.")
        .accessibilityAddTraits(.isButton)
    }

    private var chart: some View {
        VStack(spacing: NoctisSpacing.xs) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(content.bars.enumerated()), id: \.offset) { _, bar in
                        barView(bar).frame(maxWidth: .infinity)
                    }
                }
                DashedLine()
                    .stroke(NoctisAppColor.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(height: 1.5)
                    .padding(.bottom, Self.chartHeight * content.needFraction)
            }
            .frame(height: Self.chartHeight)
            HStack(spacing: 0) {
                ForEach(Array(content.bars.enumerated()), id: \.offset) { _, bar in
                    Text(bar.label)
                        .noctisFont(13, bar.isLastNight ? .semibold : .medium, relativeTo: .footnote)
                        .foregroundStyle(bar.isLastNight ? NoctisAppColor.ink : NoctisAppColor.ink3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// A track the full chart height; nights with data fill from the
    /// bottom (never a zero-height bar), nights without stay empty.
    private func barView(_ bar: WeekBar) -> some View {
        ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(NoctisAppColor.track)
            if let fraction = bar.fraction {
                Capsule(style: .continuous)
                    .fill(bar.isLastNight ? NoctisAppColor.cocoa : NoctisAppColor.sage)
                    .frame(height: max(Self.chartHeight * fraction, Self.barWidth))
            }
        }
        .frame(width: Self.barWidth, height: Self.chartHeight)
    }
}

nonisolated struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Loading

/// Skeleton blocks in the track color while the first snapshot loads; a
/// slow pulse, none under Reduce Motion.
struct HomeSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            block(height: 380)
            block(height: 170)
            block(height: 120)
        }
        .opacity(dimmed ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your sleep data")
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
            .fill(NoctisAppColor.track)
            .frame(height: height)
    }
}

// MARK: - Colors

extension RecoveryFactorKind {
    /// Sleep sage, HRV lavender, resting HR orange, consistency butter.
    var tint: Color {
        switch self {
        case .sleepDuration: NoctisAppColor.sage
        case .hrv: NoctisAppColor.lavender
        case .restingHeartRate: NoctisAppColor.orange
        case .sleepConsistency: NoctisAppColor.butter
        }
    }
}

extension StripStage {
    /// Deep cocoa, core orange, REM sage, awake butter — the Sample ring's.
    var tint: Color {
        switch self {
        case .deep: NoctisAppColor.stageDeep
        case .core: NoctisAppColor.stageCore
        case .rem: NoctisAppColor.stageREM
        case .awake: NoctisAppColor.stageAwake
        case .asleep: NoctisAppColor.sage
        }
    }
}
