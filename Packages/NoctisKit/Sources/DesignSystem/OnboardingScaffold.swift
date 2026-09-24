import SwiftUI

/// The shared frame every paper onboarding step sits inside (R1/R3/R6/R7/
/// R10/R14): full-bleed `PaperBackground`, an optional top bar (back
/// button + R7's six-segment progress — pass `step: nil` to hide it on
/// Welcome, the Plan build phase and Paywall), an `NoctisTitle`, content
/// starting exactly 24pt below the title and top-aligned (R6 — leftover
/// space collects above the bottom stack), and a bottom action stack pinned
/// via `safeAreaInset`. The content region is *always* a single
/// `ScrollView` (R10) — callers must not nest a second one.
///
/// R14: both edge fades are driven by `onScrollGeometryChange` and render
/// only when content is actually hidden past that edge — when content
/// fits, there are none. Content padding sits inside the viewport floor, so
/// fitting content never becomes scrollable by the padding alone.
///
/// Callers mark cards with `.noctisScrollRow()` and text-bearing content
/// with `.noctisTextBlock()`; both keep the fades off text at rest:
/// - At rest, when content overflows, the bottom stack's solid paper band
///   grows (`restBand`) just enough that the 24pt bottom fade lands in a
///   gap between text blocks instead of across a line of text. Content
///   itself never moves, so R6's 24pt title gap holds.
/// - At the scrolled end, just enough runway is added that no text block
///   straddles the top fade and no card is left as a sliver (a card either
///   clears the fade entirely, shadow included, starts at or below its top
///   edge, or shows at least 40pt below it).
/// Deliberately NOT `.scrollClipDisabled()`: that disables the vertical
/// clip too, letting scrolled-past content bleed up over the fixed title.
public struct OnboardingScaffold<Hero: View, Bottom: View>: View {
    private let step: Int?
    private let totalSteps: Int
    private let title: String
    private let titleEmphasis: String?
    private let caption: String?
    private let onBack: (() -> Void)?
    private let hero: Hero
    private let bottom: Bottom

    @State private var scrollViewportHeight: CGFloat = 400
    /// Content height including its own top/bottom padding but excluding
    /// the end runway — the runway is derived from it, so it can't feed
    /// back into it.
    @State private var naturalContentHeight: CGFloat = 0
    @State private var scrollFrames = NoctisScrollFrames()
    @State private var fades = EdgeFades(top: false, bottom: false)
    /// Extra solid paper above the bottom stack at rest (see type docs).
    @State private var restBand: CGFloat = 0
    /// The scroll viewport's height as it would be with no `restBand`,
    /// recorded together with the band it was measured under so the band
    /// can never feed back into its own calculation.
    @State private var unbandedViewportHeight: CGFloat = 0

    private static var contentTopPadding: CGFloat { NoctisSpacing.xl }
    private static var contentBottomPadding: CGFloat { NoctisSpacing.md }
    private static var fadeHeight: CGFloat { NoctisSpacing.xl }

    public init(
        step: Int?,
        totalSteps: Int = 6,
        title: String,
        emphasis: String? = nil,
        caption: String? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder bottomStack: () -> Bottom
    ) {
        self.step = step
        self.totalSteps = totalSteps
        self.title = title
        self.titleEmphasis = emphasis
        self.caption = caption
        self.onBack = onBack
        self.hero = hero()
        self.bottom = bottomStack()
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                PaperBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    if let step {
                        topBar(step: step)
                            .padding(.horizontal, NoctisSpacing.xl)
                            .padding(.top, NoctisSpacing.sm)
                    }

                    NoctisTitle(title, emphasis: titleEmphasis)
                        .padding(.horizontal, NoctisSpacing.xl)
                        .padding(.top, NoctisSpacing.md)

                    ScrollView {
                        VStack(spacing: NoctisSpacing.md) {
                            hero
                            captionView
                        }
                        .padding(.horizontal, NoctisSpacing.xl)
                        .padding(.top, Self.contentTopPadding)
                        .padding(.bottom, Self.contentBottomPadding)
                        .background(
                            GeometryReader { contentGeometry in
                                Color.clear
                                    .onAppear { naturalContentHeight = contentGeometry.size.height }
                                    .onChange(of: contentGeometry.size.height) { _, newHeight in naturalContentHeight = newHeight }
                            }
                        )
                        .padding(.bottom, endRunway)
                        .frame(minHeight: scrollViewportHeight, alignment: .top)
                        .noctisScrollFrames(scrollFrames)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onScrollGeometryChange(for: EdgeFades.self) { geometry in
                        // `visibleRect` spans the scroll view's full bounds,
                        // including the regions under the CTA stack and any
                        // top bar; minus the insets it's what's unobscured.
                        let visibleTop = geometry.visibleRect.minY + geometry.contentInsets.top
                        let visibleBottom = geometry.visibleRect.maxY - geometry.contentInsets.bottom
                        let lastContentY = geometry.contentSize.height - Self.contentBottomPadding - endRunway
                        return EdgeFades(top: visibleTop > 0.5, bottom: lastContentY - visibleBottom > 0.5)
                    } action: { _, newFades in
                        fades = newFades
                    }
                    .overlay(alignment: .top) {
                        topScrollFade
                            .opacity(fades.top ? 1 : 0)
                            .animation(.easeOut(duration: 0.15), value: fades.top)
                    }
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear
                                .onAppear { recordViewport(scrollGeometry.size.height) }
                                .onChange(of: scrollGeometry.size.height) { _, newHeight in recordViewport(newHeight) }
                        }
                    )
                    // Settles once the entrance rise stops moving the blocks.
                    .task(id: RestBandInputs(content: naturalContentHeight, viewport: unbandedViewportHeight, blocks: scrollFrames.textBlocks)) {
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled else { return }
                        let band = restingBand
                        if abs(band - restBand) > 0.5 {
                            withAnimation(.easeOut(duration: 0.2)) { restBand = band }
                        }
                    }
                }
                // Explicit rather than relying on the VStack's own implicit
                // safe-area avoidance: on at least one iPhone SE (3rd
                // generation)/iOS 26.5 simulator, an unadorned VStack
                // sibling of `PaperBackground().ignoresSafeArea()` was
                // observed starting at the screen's absolute top edge,
                // under the status bar, despite carrying no
                // `ignoresSafeArea` of its own (confirmed with a debug
                // background fill during R11 verification). Reading and
                // applying the inset directly is robust to that regardless
                // of root cause. `max(_, 20)` floors it to the standard
                // status bar height in the event the reported inset is
                // itself zero on such a device.
                .padding(.top, max(geometry.safeAreaInsets.top, 20))
            }
            .ignoresSafeArea(edges: .top)
        }
        // Zero spacing: the scroll viewport must end exactly at the bottom
        // stack's top, where its fade is drawn — the default 8pt gap left
        // content visible below the viewport every fade calculation used.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottom
                .padding(.horizontal, NoctisSpacing.xl)
                .padding(.top, NoctisSpacing.lg + restBand)
                .padding(.bottom, NoctisSpacing.sm)
                .background(bottomFade(showsGradient: fades.bottom))
        }
    }

    private func recordViewport(_ height: CGFloat) {
        scrollViewportHeight = height
        unbandedViewportHeight = height + restBand
    }

    /// The rest band: the smallest extra paper height above the bottom
    /// stack that puts the bottom fade's 24pt zone in a gap between text
    /// blocks — each block either ends above the zone or starts no more
    /// than 4pt above its opaque bottom edge. Zero when content fits, when
    /// the natural cut is already clean, or when no clean cut exists within
    /// the lower 45% of the viewport.
    private var rowFrames: [CGRect] { scrollFrames.rows }
    private var textBlocks: [CGRect] { scrollFrames.textBlocks }

    private var restingBand: CGFloat {
        NoctisScrollEdges.restingBand(
            textBlocks: textBlocks,
            viewportHeight: unbandedViewportHeight,
            contentBottom: naturalContentHeight - Self.contentBottomPadding
        )
    }

    /// Extra space after the last block so the scrolled-to-the-end position
    /// is clean for the top fade (see the type docs). Zero whenever content
    /// fits, nothing is marked, or no clean end exists within half a
    /// viewport of runway.
    private var endRunway: CGFloat {
        let overflow = naturalContentHeight - scrollViewportHeight
        guard overflow > 0, !(rowFrames.isEmpty && textBlocks.isEmpty) else { return 0 }
        let fade = Self.fadeHeight
        func textIsClean(_ offset: CGFloat) -> Bool {
            textBlocks.allSatisfy { $0.maxY <= offset - NoctisScrollEdges.hiddenMargin || $0.minY >= offset + fade }
        }
        func isClean(_ offset: CGFloat) -> Bool {
            textIsClean(offset)
                && rowFrames.allSatisfy { $0.maxY <= offset - 4 || $0.minY >= offset || $0.maxY - (offset + fade) >= 40 }
        }
        var candidates: [CGFloat] = [overflow]
        for row in rowFrames {
            candidates += [row.minY, row.maxY + 4, row.maxY - fade - 40]
        }
        for block in textBlocks {
            candidates += [block.maxY + NoctisScrollEdges.hiddenMargin, block.minY - fade]
        }
        let sorted = candidates.filter { $0 >= overflow }.sorted()
        let inReach = sorted.filter { $0 <= overflow + scrollViewportHeight / 2 }
        // Text always wins (R14: text never rests half-faded):
        // 1. text and card edges both clear, within half a viewport of runway;
        // 2. text clear, a text-free card edge allowed in the fade;
        // 3. text clear with up to a full viewport of runway, as long as some
        //    text stays on screen — when rows sit closer together than the
        //    fade is tall (Health's signal rows at AX3 on iPhone SE) the only
        //    clean end is past them, so the end is sparse but never faded.
        let lastTextTop = textBlocks.map(\.minY).max() ?? overflow
        let wide = sorted.filter { $0 <= overflow + scrollViewportHeight && $0 <= lastTextTop }
        let target = inReach.first(where: isClean)
            ?? inReach.first(where: textIsClean)
            ?? wide.first(where: textIsClean)
            ?? overflow
        return target - overflow
    }

    @ViewBuilder
    private var captionView: some View {
        if let caption {
            Text(caption)
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(NoctisPaper.ink3)
                .multilineTextAlignment(.center)
                .padding(.top, NoctisSpacing.sm)
                .frame(maxWidth: .infinity)
        }
    }

    /// R14(b): a 24pt paper-to-clear fade at the scroll region's top edge,
    /// shown only once content has scrolled up under it.
    private var topScrollFade: some View {
        LinearGradient(colors: [NoctisPaper.bg, NoctisPaper.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
            .frame(height: Self.fadeHeight)
            .allowsHitTesting(false)
    }

    /// The bottom stack's solid paper fill (explicitly ignoring the bottom
    /// safe area — `.background()` otherwise stops at the stack's own
    /// bounds, which at some Dynamic Type sizes falls short of the screen
    /// edge) plus, only while content extends below the visible area, the
    /// 24pt paper fade above it (R14).
    private func bottomFade(showsGradient: Bool) -> some View {
        ZStack {
            NoctisPaper.bg.ignoresSafeArea(edges: .bottom)
            LinearGradient(colors: [NoctisPaper.bg.opacity(0), NoctisPaper.bg], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fadeHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: -Self.fadeHeight)
                .opacity(showsGradient ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: showsGradient)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func topBar(step: Int) -> some View {
        HStack(spacing: NoctisSpacing.md) {
            backButton
            NoctisSegmentedProgress(step: step, totalSteps: totalSteps)
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoctisPaper.ink)
                    .frame(width: 44, height: 44)
                    .noctisPaperGlass()
                    // The whole 44pt circle, for touch and for VoiceOver
                    // (whose frame otherwise shrank to the chevron glyph).
                    .contentShape([.interaction, .accessibility], Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

/// R2/R8: Liquid Glass on the back button only.
private extension View {
    func noctisPaperGlass() -> some View {
        glassEffect(.regular.tint(NoctisPaper.surface.opacity(0.6)).interactive(), in: .circle)
    }
}

private struct EdgeFades: Equatable {
    let top: Bool
    let bottom: Bool
}

private struct RestBandInputs: Equatable {
    let content: CGFloat
    let viewport: CGFloat
    let blocks: [CGRect]
}

/// Where `.noctisScrollRow()` and `.noctisTextBlock()` markers report their
/// frames, in the scroll content's own coordinate space (`coordinateSpace`).
/// Frames arrive through `onGeometryChange`, not a preference: a preference
/// observer was measured to stop firing after the first layout while the
/// entrance rise (an animated `.offset`) was still in flight, leaving every
/// frame 12pt low for good.
@Observable
public final class NoctisScrollFrames {
    nonisolated public static let coordinateSpace = "noctisScrollContent"

    enum Kind { case row, textBlock }

    private var rowsByID: [UUID: CGRect] = [:]
    private var blocksByID: [UUID: CGRect] = [:]

    public init() {}

    public var rows: [CGRect] { rowsByID.values.sorted { $0.minY < $1.minY } }
    public var textBlocks: [CGRect] { blocksByID.values.sorted { $0.minY < $1.minY } }

    func set(_ kind: Kind, _ id: UUID, _ frame: CGRect?) {
        switch kind {
        case .row: rowsByID[id] = frame
        case .textBlock: blocksByID[id] = frame
        }
    }
}

extension EnvironmentValues {
    @Entry public var noctisScrollFrames: NoctisScrollFrames?
}

private struct ScrollFrameMarker: ViewModifier {
    let kind: NoctisScrollFrames.Kind
    @Environment(\.noctisScrollFrames) private var store
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(NoctisScrollFrames.coordinateSpace))
            } action: { frame in
                store?.set(kind, id, frame)
            }
            .onDisappear { store?.set(kind, id, nil) }
    }
}

extension View {
    /// Marks a row (typically a card) inside `OnboardingScaffold`'s hero so
    /// the scaffold can keep it from coming to rest as a sliver under the
    /// top fade at full scroll (R14).
    public func noctisScrollRow() -> some View {
        modifier(ScrollFrameMarker(kind: .row))
    }

    /// Marks text-bearing content inside `OnboardingScaffold`'s hero (or
    /// Welcome's) so both edge fades stay off it at rest (R14). Mark the
    /// smallest groups a fade may fall between (a card's content, a row, a
    /// caption), not whole screens.
    public func noctisTextBlock() -> some View {
        modifier(ScrollFrameMarker(kind: .textBlock))
    }

    /// Collects the markers inside this scroll content into `frames`.
    public func noctisScrollFrames(_ frames: NoctisScrollFrames) -> some View {
        environment(\.noctisScrollFrames, frames)
            .coordinateSpace(name: NoctisScrollFrames.coordinateSpace)
    }
}

/// R14's resting cut, shared by `OnboardingScaffold` and Welcome.
public enum NoctisScrollEdges {
    public static let fadeHeight = NoctisSpacing.xl

    /// At accessibility sizes, the least space between two stacked text
    /// blocks: more than a fade is tall, so a resting fade (top or bottom)
    /// can always fall in a gap instead of across a line of text.
    public static let accessibleBlockGap: CGFloat = fadeHeight + 4

    /// `base` at standard sizes; at least `accessibleBlockGap` at
    /// accessibility sizes.
    public static func blockGap(_ base: CGFloat, _ size: DynamicTypeSize) -> CGFloat {
        size.isAccessibilitySize ? max(base, accessibleBlockGap) : base
    }
    /// How far past a fade's opaque edge hidden text must sit, so pixel
    /// rounding and glyph antialiasing never leave a ghost of its top.
    public static let hiddenMargin: CGFloat = 2

    /// The smallest extra paper height above a bottom stack that puts the
    /// 24pt bottom fade's zone in a gap between text blocks — each block
    /// either ends above the zone or starts at or below its opaque bottom
    /// edge (even the gradient's last few points let dark text ghost
    /// through). Zero when content ends inside the viewport, when
    /// the natural cut is already clean, or when no clean cut exists within
    /// the lower 45% of the viewport.
    public static func restingBand(textBlocks: [CGRect], viewportHeight: CGFloat, contentBottom: CGFloat) -> CGFloat {
        guard viewportHeight > 0, !textBlocks.isEmpty, contentBottom > viewportHeight + 0.5 else { return 0 }
        func isClean(_ band: CGFloat) -> Bool {
            let zoneBottom = viewportHeight - band
            let zoneTop = zoneBottom - fadeHeight
            return textBlocks.allSatisfy { $0.maxY <= zoneTop || $0.minY >= zoneBottom + hiddenMargin }
        }
        var candidates: [CGFloat] = [0]
        for block in textBlocks {
            candidates.append(viewportHeight - fadeHeight - block.maxY)
            candidates.append(viewportHeight - block.minY + hiddenMargin)
        }
        let limit = viewportHeight * 0.45
        return candidates.filter { $0 >= 0 && $0 <= limit }.sorted().first(where: isClean) ?? 0
    }
}
