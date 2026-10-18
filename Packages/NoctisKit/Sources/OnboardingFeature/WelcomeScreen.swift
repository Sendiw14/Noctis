import DesignSystem
import NoctisCore
import NoctisText
import SwiftUI

private struct ConstellationSpoke {
    let fill: Color
    let glyph: String
    /// Degrees, screen convention (0 = right, 90 = down).
    let angleDegrees: Double
}

/// The other four `GoalScreen` options, in their own colors/glyphs, around
/// the sleep tile at the center — a flat, static preview of what's coming,
/// not a solar-system animation (no orbit, no rotation).
private let constellationSpokes: [ConstellationSpoke] = [
    ConstellationSpoke(fill: NoctisPaper.orange, glyph: "bolt.fill", angleDegrees: -45), // upper-right
    ConstellationSpoke(fill: NoctisPaper.sage, glyph: "heart.fill", angleDegrees: 45), // lower-right
    ConstellationSpoke(fill: NoctisPaper.butter, glyph: "clock.arrow.2.circlepath", angleDegrees: 135), // lower-left
    ConstellationSpoke(fill: NoctisPaper.cocoa, glyph: "scope", angleDegrees: 225), // upper-left
]

private struct WelcomeInfoColumn {
    let icon: String
    let label: String
}

/// "Private by design" is a privacy claim, so it is shown only while the data inventory backs it (APP_RULES.md R41).
private var welcomeInfoColumns: [WelcomeInfoColumn] {
    [
        PrivacyStatements.privateByDesign(.shared).map { WelcomeInfoColumn(icon: "lock.fill", label: $0) },
        WelcomeInfoColumn(icon: "heart.text.square.fill", label: "Works with Apple Health"),
        WelcomeInfoColumn(icon: "clock.fill", label: "2-minute setup"),
    ].compactMap { $0 }
}

/// Step 0 — the same flat ivory paper language as every other onboarding
/// screen (ONBOARDING_RULES.md's Direction paragraph). No top bar (R7
/// hides it on Welcome) since there's no step to show progress against
/// yet. The hero is a static flat "constellation" (R6: fills ~45% of
/// height) — the sleep tile anchoring the other four goal tiles around it
/// on hairline spokes — deliberately denser than the old single-tile hero,
/// which read as too thin next to Goal/Plan's own visual weight.
struct WelcomeScreen: View {
    let onBegin: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var hasAppeared = false
    @State private var centerScale: CGFloat = 0.9
    @State private var centerOpacity: Double = 0
    @State private var bounceCenter = false
    @State private var spokeScale: [CGFloat] = Array(repeating: 0.9, count: 4)
    @State private var spokeOpacity: [Double] = Array(repeating: 0, count: 4)
    @State private var spokeBounce: [Bool] = Array(repeating: false, count: 4)
    @State private var lineProgress: [CGFloat] = Array(repeating: 0, count: 4)
    @State private var textRisen = false
    @State private var cardRisen = false
    @State private var viewportHeight: CGFloat = 700
    /// Natural height of hero+title+card alone (no spacers) — measured
    /// separately from `viewportHeight` so leftover space (when content
    /// is shorter than the viewport) can be split 1 part above / 2 parts
    /// below rather than the old two-equal-Spacer 50/50 split, which read
    /// as dead-centered rather than optically balanced.
    @State private var contentHeight: CGFloat = 500
    @State private var showsBottomFade = false
    @State private var showsTopFade = false
    @State private var scrollFrames = NoctisScrollFrames()
    /// R14's resting cut (see `NoctisScrollEdges.restingBand`), and the
    /// viewport as measured without it.
    @State private var restBand: CGFloat = 0
    @State private var unbandedViewportHeight: CGFloat = 0

    private static let constellationSize: CGFloat = 260
    private static let centerDiameter: CGFloat = 180
    private static let spokeDiameter: CGFloat = 56
    /// Center radius (90) + a ~20pt hairline reveal + spoke radius (28) —
    /// at the old 150pt distance the spoke tiles sat close enough to the
    /// center circle that the connecting hairline was nearly invisible.
    private static let spokeDistance: CGFloat = 138

    var body: some View {
        ZStack {
            PaperBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: topLeftoverShare)
                    VStack(spacing: NoctisScrollEdges.blockGap(NoctisSpacing.lg, dynamicTypeSize)) {
                        heroConstellation
                        titleTaglineBlock
                            .noctisTextBlock()
                        infoCard
                        Text(NoctisMedicalNotice.statement)
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(NoctisPaper.ink3)
                            .multilineTextAlignment(.center)
                            .noctisTextBlock()
                    }
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear { contentHeight = geometry.size.height }
                                .onChange(of: geometry.size.height) { _, newHeight in contentHeight = newHeight }
                        }
                    )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, NoctisSpacing.xl)
                .frame(minHeight: viewportHeight, alignment: .top)
                .noctisScrollFrames(scrollFrames)
            }
            .scrollBounceBehavior(.basedOnSize)
            // R14: each fade shows only while content actually extends past
            // that edge.
            .onScrollGeometryChange(for: [Bool].self) { geometry in
                let visibleTop = geometry.visibleRect.minY + geometry.contentInsets.top
                let visibleBottom = geometry.visibleRect.maxY - geometry.contentInsets.bottom
                return [visibleTop > 0.5, geometry.contentSize.height - visibleBottom > 0.5]
            } action: { _, edges in
                showsTopFade = edges[0]
                showsBottomFade = edges[1]
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { recordViewport(geometry.size.height) }
                        .onChange(of: geometry.size.height) { _, newHeight in recordViewport(newHeight) }
                }
            )
            .task(id: [contentHeight, unbandedViewportHeight] + scrollFrames.textBlocks.flatMap { [$0.minY, $0.maxY] }) {
                // Settles once the entrance rise stops moving the blocks.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                let band = NoctisScrollEdges.restingBand(
                    textBlocks: scrollFrames.textBlocks,
                    viewportHeight: unbandedViewportHeight,
                    contentBottom: contentHeight
                )
                if abs(band - restBand) > 0.5 {
                    withAnimation(.easeOut(duration: 0.2)) { restBand = band }
                }
            }
        }
        // Welcome has no title bar: once content scrolls up, paper backs
        // the status bar and a 24pt fade softens the edge below it, so
        // nothing ever scrolls visibly under the status bar text.
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background(NoctisPaper.bg.ignoresSafeArea(edges: .top))
                LinearGradient(colors: [NoctisPaper.bg, NoctisPaper.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: NoctisScrollEdges.fadeHeight)
            }
            .opacity(showsTopFade ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: showsTopFade)
            .allowsHitTesting(false)
        }
        // Zero spacing: the scroll viewport must end exactly at the bottom
        // stack's top, where its fade is drawn — the default 8pt gap left
        // content visible below the viewport every fade calculation used.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NoctisCTA("Begin", action: beginTapped)
                .padding(.horizontal, NoctisSpacing.xl)
                .padding(.top, NoctisSpacing.lg + restBand)
                .padding(.bottom, NoctisSpacing.sm)
                .background(bottomFade(showsGradient: showsBottomFade))
        }
        .onAppear { runEntranceIfNeeded() }
    }

    /// 1 part of the leftover space (viewport minus content) above the
    /// content block, 2 parts below — optical centering, replacing the old
    /// two-equal-`Spacer` dead-centered split. Zero once content already
    /// fills (or exceeds) the viewport, so scrolling screens are untouched.
    private var topLeftoverShare: CGFloat {
        max(viewportHeight - contentHeight, 0) / 3
    }

    private func recordViewport(_ height: CGFloat) {
        viewportHeight = height
        unbandedViewportHeight = height + restBand
    }

    // MARK: - Hero (R6: the one hero visual, ~45% of height)

    private var heroConstellation: some View {
        ZStack {
            spokeLines
            ForEach(Array(constellationSpokes.enumerated()), id: \.offset) { index, spoke in
                spokeTile(spoke, index: index)
            }
            centerTile
        }
        .frame(width: Self.constellationSize, height: Self.constellationSize)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var spokeLines: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for (index, spoke) in constellationSpokes.enumerated() {
                let progress = lineProgress[index]
                guard progress > 0 else { continue }
                let radians = spoke.angleDegrees * .pi / 180
                let target = CGPoint(
                    x: center.x + cos(radians) * Self.spokeDistance,
                    y: center.y + sin(radians) * Self.spokeDistance
                )
                let currentEnd = CGPoint(
                    x: center.x + (target.x - center.x) * progress,
                    y: center.y + (target.y - center.y) * progress
                )
                var path = Path()
                path.move(to: center)
                path.addLine(to: currentEnd)
                context.stroke(path, with: .color(NoctisPaper.hairline), style: StrokeStyle(lineWidth: 1))
            }
        }
        .frame(width: Self.constellationSize, height: Self.constellationSize)
        .allowsHitTesting(false)
    }

    private var centerTile: some View {
        ZStack {
            Circle()
                .fill(NoctisPaper.lavender)
                .frame(width: Self.centerDiameter, height: Self.centerDiameter)
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 88, weight: .semibold))
                .foregroundStyle(NoctisPaper.bg)
                .symbolEffect(.bounce, value: bounceCenter)
        }
        .scaleEffect(centerScale)
        .opacity(centerOpacity)
    }

    private func spokeTile(_ spoke: ConstellationSpoke, index: Int) -> some View {
        let radians = spoke.angleDegrees * .pi / 180
        let dx = cos(radians) * Self.spokeDistance
        let dy = sin(radians) * Self.spokeDistance
        return ZStack {
            Circle()
                .fill(spoke.fill)
                .frame(width: Self.spokeDiameter, height: Self.spokeDiameter)
            Image(systemName: spoke.glyph)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(NoctisPaper.bg)
                .symbolEffect(.bounce, value: spokeBounce[index])
        }
        .scaleEffect(spokeScale[index])
        .opacity(spokeOpacity[index])
        .offset(x: dx, y: dy)
    }

    // MARK: - Title + tagline

    private var titleTaglineBlock: some View {
        VStack(spacing: NoctisSpacing.xs) {
            Text("NOCTIS")
                .noctisFont(38, .bold, relativeTo: .largeTitle)
                .tracking(-0.6)
                .foregroundStyle(NoctisPaper.ink)
                .opacity(textRisen ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (textRisen ? 0 : 12))
                .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: textRisen)
            Text("Better nights. A brighter you.")
                .noctisFont(17, relativeTo: .body)
                .foregroundStyle(NoctisPaper.ink2)
                .opacity(textRisen ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (textRisen ? 0 : 12))
                .animation(
                    NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)
                        .delay(reduceMotion ? 0 : 0.06),
                    value: textRisen
                )
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("NOCTIS. Better nights. A brighter you.")
    }

    // MARK: - Info card

    private var infoCard: some View {
        NoctisPaperCard(padding: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: NoctisScrollEdges.accessibleBlockGap / 2) {
                        ForEach(Array(welcomeInfoColumns.enumerated()), id: \.offset) { index, column in
                            infoColumn(column)
                                .noctisTextBlock()
                            if index < welcomeInfoColumns.count - 1 {
                                Rectangle().fill(NoctisPaper.hairline).frame(height: 1)
                            }
                        }
                    }
                } else {
                    // `.fixedSize(vertical:)` is the fix, not the dividers
                    // themselves: a bare `Rectangle().frame(width: 1)` has
                    // no height of its own, so it was happily expanding to
                    // fill whatever height this HStack got proposed —
                    // which, chained up through `infoCard` into Welcome's
                    // own `.frame(minHeight: viewportHeight)` ScrollView
                    // content, could be the *entire remaining screen
                    // height*. That's what actually made this card read as
                    // 3x taller than its content, not the padding amount.
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(welcomeInfoColumns.enumerated()), id: \.offset) { index, column in
                            infoColumn(column)
                                .noctisTextBlock()
                                .frame(maxWidth: .infinity)
                            if index < welcomeInfoColumns.count - 1 {
                                Rectangle().fill(NoctisPaper.hairline).frame(width: 1)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, NoctisSpacing.lg)
            .padding(.vertical, NoctisSpacing.md)
        }
        .opacity(cardRisen ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (cardRisen ? 0 : 12))
        .animation(
            NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)
                .delay(reduceMotion ? 0 : 0.12),
            value: cardRisen
        )
    }

    private func infoColumn(_ column: WelcomeInfoColumn) -> some View {
        VStack(spacing: 6) {
            Image(systemName: column.icon)
                .noctisIcon(20, relativeTo: .footnote)
                .foregroundStyle(NoctisPaper.ink)
                .accessibilityHidden(true)
            Text(column.label)
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(NoctisPaper.ink2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Entrance (R9: one hero animation, <= 1.2s)

    private func runEntranceIfNeeded() {
        guard !hasAppeared else { return }
        hasAppeared = true

        guard !reduceMotion else {
            centerScale = 1
            centerOpacity = 1
            for index in spokeScale.indices {
                spokeScale[index] = 1
                spokeOpacity[index] = 1
                lineProgress[index] = 1
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                textRisen = true
                cardRisen = true
            }
            return
        }

        centerOpacity = 1
        withAnimation(NoctisMotion.settle) {
            centerScale = 1
        }
        bounceCenter = true

        for index in constellationSpokes.indices {
            let delay = 0.15 + Double(index) * 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                spokeOpacity[index] = 1
                withAnimation(NoctisMotion.settle) {
                    spokeScale[index] = 1
                }
                spokeBounce[index].toggle()
                withAnimation(.easeOut(duration: 0.25)) {
                    lineProgress[index] = 1
                }
            }
        }

        let contentDelay = 0.15 + Double(constellationSpokes.count) * 0.08 + 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + contentDelay) {
            textRisen = true
            cardRisen = true
        }
    }

    private func beginTapped() {
        NoctisHaptics.medium()
        onBegin()
    }

    private func bottomFade(showsGradient: Bool) -> some View {
        ZStack {
            NoctisPaper.bg.ignoresSafeArea(edges: .bottom)
            LinearGradient(colors: [NoctisPaper.bg.opacity(0), NoctisPaper.bg], startPoint: .top, endPoint: .bottom)
                .frame(height: NoctisSpacing.xl)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: -NoctisSpacing.xl)
                .opacity(showsGradient ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: showsGradient)
        }
        .allowsHitTesting(false)
    }
}
