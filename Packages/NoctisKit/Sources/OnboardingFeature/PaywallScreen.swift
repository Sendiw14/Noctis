import DesignSystem
import NoctisCore
import StoreKit
import SwiftUI
import UserNotifications
import NoctisText

private enum PaywallLoadPhase: Equatable {
    case loading
    case unavailable
    case ready
}

/// What Paywall's edge fades need from its scroll view (R14): whether any
/// content sits hidden above or below the visible area.
private struct PaywallScrollMetrics: Equatable {
    var visibleTop: CGFloat = 0
    var visibleHeight: CGFloat = 0
    var contentHeight: CGFloat = 0
    var bottomPadding: CGFloat = 0

    func topFadeOpacity(over distance: CGFloat) -> Double {
        Double(min(max(visibleTop / distance, 0), 1))
    }
    var showsBottomFade: Bool { contentHeight - bottomPadding - (visibleTop + visibleHeight) > 0.5 }
}

/// Frames of Paywall's text-bearing blocks in its scroll content's own
/// coordinate space, for the resting-cut solver.
private struct PaywallBlockFramesKey: PreferenceKey {
    static let coordinateSpace = "paywallContent"
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

/// Benefit rows' laid-out heights by index (see `cardRowFrames`).
private struct PaywallCardRowHeightsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func paywallCardRow(_ index: Int) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(key: PaywallCardRowHeightsKey.self, value: [index: geometry.size.height])
            }
        )
    }

    func paywallBlock() -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PaywallBlockFramesKey.self,
                    value: [geometry.frame(in: .named(PaywallBlockFramesKey.coordinateSpace))]
                )
            }
        )
    }
}

private struct BenefitRow: Identifiable {
    let id: Int
    let icon: String
    let fill: Color
    let text: String
}

/// A plan card's own display data, mapped once from a real StoreKit
/// `Product` (see `planOption(for:isYearly:)`) so the rendering code in
/// `planCard(_:)` never touches `Product` itself — and can be driven by a
/// hardcoded value in a DEBUG `#Preview` for a StoreKit-less environment.
private struct PlanOption: Identifiable {
    let id: String
    let isYearly: Bool
    let displayPrice: String
    let perMonthText: String?
    /// e.g. "7 days free", from the product's real intro offer; nil when
    /// there's no free trial to offer.
    let trialBadge: String?
    let savingsPercent: Int?
}

/// A free trial's real length, read from StoreKit so the copy can never
/// promise a different trial than the one the store will grant (R13).
private struct TrialLength {
    /// "7-day"
    let adjective: String
    /// "7 days"
    let phrase: String

    init?(_ product: Product?) {
        guard let offer = product?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        var value = offer.period.value * max(offer.periodCount, 1)
        let period: NoctisCount.Period
        switch offer.period.unit {
        case .day: period = .day
        case .week: value *= 7; period = .day
        case .month: period = .month
        case .year: period = .year
        @unknown default: return nil
        }
        adjective = NoctisCount.adjective(value, period)
        phrase = NoctisCount.period(value, period)
    }
}

/// What Premium adds (R58): depth, each line true of the app as it is (the full list, made from `FeatureTable`, is "Compare free and Premium").
private let benefitRows: [BenefitRow] = [
    BenefitRow(id: 0, icon: "heart.fill", fill: NoctisPaper.orange, text: "Recovery over 30 and 90 days"),
    BenefitRow(id: 1, icon: "moon.zzz.fill", fill: NoctisPaper.sage, text: "A month of sleep, and what went into it"),
    BenefitRow(id: 2, icon: "chart.line.uptrend.xyaxis", fill: NoctisPaper.lavender, text: "Every insight, your records and history"),
    BenefitRow(id: 3, icon: "sparkles", fill: NoctisPaper.cocoa, text: "Unlimited Coach questions"),
    BenefitRow(id: 4, icon: "speaker.wave.2.fill", fill: NoctisPaper.butter, text: "Wind-down, meditation and all six sounds"),
]

/// Step after Plan — no progress bar (R7 exception), top bar hidden. Built
/// custom rather than on `OnboardingScaffold` since the top row (close +
/// Restore) and the richer hero don't fit that scaffold's back+progress
/// shape; the paper background, safe-area handling and bottom fade below
/// still follow the same R1/R10 rules the scaffold itself encodes.
struct PaywallScreen: View {
    let wakeMinutes: Int
    let needMinutes: Int
    let onFinished: () -> Void
    /// Why it was opened: the line above the title says exactly what the tapped thing unlocks (R58). Nil in onboarding.
    var context: PaywallContext?

    @Environment(StoreManager.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var phase: PaywallLoadPhase = .loading
    @State private var selectedProductID = StoreProductID.yearly
    @State private var isEligibleForTrial = false
    @State private var notificationsAuthorized = false
    @State private var remindBeforeTrialEnds = false
    @State private var ringProgress: Double = 0
    @State private var showCheckmark = false
    @State private var showCompareSheet = false
    @State private var restoreOutcome: StoreManager.RestoreResult?
    @State private var hasCheckedEntitlement = false
    @State private var scrollMetrics = PaywallScrollMetrics()
    @State private var blockFrames: [CGRect] = []
    @State private var cardRowHeights: [Int: CGFloat] = [:]
    /// The benefits card's resting frame (measured outside its entrance
    /// rise), for placing its rows and for the end runway's sliver check.
    @State private var cardFrame: CGRect = .zero
    @State private var userHasScrolled = false
    /// The resting cut (see `settleRestingCut`): how far content is raised
    /// by layout into the empty band beside Close/Restore, or else how much
    /// extra paper sits above the bottom stack.
    @State private var restShift: CGFloat = 0
    @State private var restBand: CGFloat = 0
    /// The visible height as it would be with no `restBand`.
    @State private var unbandedVisibleHeight: CGFloat = 0
    /// Extra space after the last block so the fully scrolled end is clean
    /// under the header fade too (see `settleRestingCut`).
    @State private var endRunway: CGFloat = 0
    @State private var headerBandEnd: CGFloat = 0

    /// Sample's segmented ring scaled to 140pt, its 26pt stroke scaled with
    /// it (26 / 242, Sample's ring on iPhone 17 Pro).
    private static let ringDiameter: CGFloat = 140
    private static let ringLineWidth: CGFloat = 15
    private static let contentBottomPadding = NoctisSpacing.md
    private static let fadeHeight = NoctisSpacing.xl
    private static let benefitsCardPadding = NoctisSpacing.lg

    /// The plan choice's actions are pinned under the content, except at accessibility sizes: there the button, the legal line, the free-plan
    /// link and three footer links are most of the screen (about 75% of an SE at AX5) and leave the plans a strip of blank page. They are the
    /// end of the page instead, and everything scrolls (QA part 3, QA-084).
    private var pinsBottomStack: Bool { !dynamicTypeSize.isAccessibilitySize }

    private var bedtimeMinutes: Int { noctisBedtimeMinutes(wakeMinutes: wakeMinutes, needMinutes: needMinutes) }
    private var selectedProduct: Product? { store.products.first { $0.id == selectedProductID } }
    private var yearlyProduct: Product? { store.yearlyProduct }
    private var monthlyProduct: Product? { store.monthlyProduct }
    private var showTrialCTA: Bool { isEligibleForTrial && TrialLength(selectedProduct) != nil }
    private var showReminderToggle: Bool { notificationsAuthorized && showTrialCTA }

    /// Close/Restore's own reserved height (padding above the buttons +
    /// the 44pt row + the 24pt fade band below it) — `content`'s top
    /// padding matches this exactly so the first item sits right where
    /// the fade finishes, and GeometryReader stays outermost with
    /// `.safeAreaInset` chained onto its result (matching
    /// OnboardingScaffold's structure — swapping that order silently
    /// breaks a ScrollView's bottom content inset, see git history).
    private var topRowClearance: CGFloat { NoctisSpacing.sm + 44 + NoctisSpacing.xl }

    /// The furthest the solver may raise content by layout: the ring (140pt,
    /// centered) never meets Close or Restore horizontally, so it may rise
    /// into their row — but never above the row's vertical center.
    private var maxRestShift: CGFloat { topRowClearance - NoctisSpacing.sm - 22 }

    var body: some View {
        GeometryReader { geometry in
            let topInset = max(geometry.safeAreaInsets.top, 20)
            ZStack(alignment: .top) {
                Color.clear.onChange(of: topInset + topRowClearance, initial: true) { _, newValue in headerBandEnd = newValue }
                PaperBackground().ignoresSafeArea()
                content(topInset: topInset)
                topRow
                    .padding(.horizontal, NoctisSpacing.xl)
                    .padding(.top, topInset + NoctisSpacing.sm)
                    .padding(.bottom, NoctisSpacing.xl)
                    // Fades in with the first 24pt of scroll rather than
                    // popping, since at rest the hero may sit inside this band.
                    .background(topFade.opacity(scrollMetrics.topFadeOpacity(over: Self.fadeHeight)))
                    // Layered over the content, but read first: Close and
                    // Restore must be reachable without swiping through the
                    // whole paywall.
                    .accessibilitySortPriority(1)
            }
            .accessibilityElement(children: .contain)
            .ignoresSafeArea(edges: .top)
        }
        // Zero spacing: the scroll viewport must end exactly at the bottom
        // stack's top, where its fade is drawn — the default 8pt gap left
        // content visible below the viewport every fade calculation used.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pinsBottomStack {
                bottomStack
                    .padding(.horizontal, NoctisSpacing.xl)
                    .padding(.top, NoctisSpacing.lg + restBand)
                    .padding(.bottom, NoctisSpacing.sm)
                    .background(bottomFade(showsGradient: scrollMetrics.showsBottomFade))
            }
        }
        .sheet(isPresented: $showCompareSheet) { PremiumComparisonSheet() }
        .alert(restoreAlertTitle, isPresented: restoreAlertBinding) {
            Button("OK") { restoreOutcome = nil }
        }
        .task { await onFirstAppear() }
        .task(id: restingCutInputs) {
            // Coalesce a burst of layout changes into one solve.
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            settleRestingCut()
        }
        .onChange(of: store.purchaseState) { _, newValue in
            if newValue == .success { handlePurchaseSuccess() }
        }
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack {
            Button(action: dismissWithoutSubscribing) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoctisPaper.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(NoctisPaper.surface))
                    .overlay(Circle().stroke(NoctisPaper.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()

            // Frames and content shapes sit inside the labels below: on the
            // Button itself they sized layout but not the tap target.
            Button(action: restorePurchases) {
                Text("Restore")
                    .noctisFont(15, .medium, relativeTo: .subheadline)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(NoctisPaper.ink2)
        }
    }

    // MARK: - Scroll content

    private func content(topInset: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: NoctisSpacing.lg) {
                hero
                benefitsCard
                compareLink.paywallBlock()
                plansSection
                if !pinsBottomStack {
                    bottomStack.padding(.top, NoctisSpacing.sm)
                }
            }
            .padding(.horizontal, NoctisSpacing.xl)
            .padding(.top, topInset + topRowClearance - restShift)
            // R14: clears the CTA stack by 16pt when fully scrolled.
            .padding(.bottom, Self.contentBottomPadding)
            .padding(.bottom, endRunway)
            .coordinateSpace(name: PaywallBlockFramesKey.coordinateSpace)
            .onPreferenceChange(PaywallBlockFramesKey.self) { blockFrames = $0 }
        }
        .onScrollGeometryChange(for: PaywallScrollMetrics.self) { geometry in
            PaywallScrollMetrics(
                visibleTop: geometry.visibleRect.minY + geometry.contentInsets.top,
                visibleHeight: geometry.visibleRect.height - geometry.contentInsets.top - geometry.contentInsets.bottom,
                contentHeight: geometry.contentSize.height,
                // Runway is empty space: nothing below it warrants a fade.
                bottomPadding: Self.contentBottomPadding + endRunway
            )
        } action: { _, metrics in
            scrollMetrics = metrics
            unbandedVisibleHeight = metrics.visibleHeight + restBand
        }
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .interacting { userHasScrolled = true }
        }
    }

    /// Everything the resting-cut solver reads, so it reruns whenever any
    /// of it changes (phase swaps, CTA stack height, Dynamic Type).
    private var restingCutInputs: [CGFloat] {
        [unbandedVisibleHeight, scrollMetrics.contentHeight, cardFrame.minY, cardFrame.height, restShift, restBand, endRunway, headerBandEnd]
            + (blockFrames + cardRowFrames).flatMap { [$0.minY, $0.maxY] }
    }

    /// Benefit rows' frames in content coordinates, rebuilt from their
    /// measured heights and the card's structure (padding, rows, 1pt
    /// hairlines) on top of the card's resting origin. Row *positions*
    /// read through a GeometryReader report the card's in-flight entrance
    /// offset; sizes never do, so the solver sees final layout from the
    /// first pass instead of chasing the rise.
    private var cardRowFrames: [CGRect] {
        guard cardRowHeights.count == benefitRows.count else { return [] }
        var y = cardFrame.minY + Self.benefitsCardPadding
        var frames: [CGRect] = []
        for index in benefitRows.indices {
            let height = cardRowHeights[index] ?? 0
            frames.append(CGRect(x: 0, y: y, width: 1, height: height))
            y += height + 1
        }
        return frames
    }

    /// Text-bearing blocks in content coordinates as laid out with no rest
    /// shift applied.
    private var unshiftedBlockFrames: [CGRect] {
        (blockFrames + cardRowFrames).map { $0.offsetBy(dx: 0, dy: restShift) }
    }

    /// R14 at rest: when content extends below the fold the bottom fade is
    /// on, and it must never land across a line of text. The fix never
    /// scrolls (that would slide the hero under the header): first the
    /// content may rise by layout, up to `maxRestShift`, into the empty
    /// band beside Close/Restore — enough to fit entirely, or to put the
    /// fade's 24pt zone in a gap between blocks (each block ending above
    /// the zone or starting at or below its opaque edge). If no
    /// such cut is in reach, the bottom stack's paper band grows instead,
    /// moving the fade up to the nearest clean gap. Never adjusts after the
    /// user has scrolled.
    private func settleRestingCut() {
        guard pinsBottomStack else {
            // Nothing is pinned, so there is no fade to keep off a line of text: the page just scrolls.
            if restShift != 0 { restShift = 0 }
            if restBand != 0 { restBand = 0 }
            if endRunway != 0 { endRunway = 0 }
            return
        }
        guard scrollMetrics.visibleHeight > 0 else { return }
        settleEndRunway()
        guard !userHasScrolled else { return }
        let frames = unshiftedBlockFrames
        guard !frames.isEmpty else { return }
        let viewport = unbandedVisibleHeight
        let contentBottom = scrollMetrics.contentHeight - endRunway + restShift - Self.contentBottomPadding
        var shift: CGFloat = 0
        var band: CGFloat = 0
        if contentBottom > viewport + 0.5 {
            func isClean(_ zoneBottom: CGFloat) -> Bool {
                frames.allSatisfy { $0.maxY <= zoneBottom - Self.fadeHeight || $0.minY >= zoneBottom + NoctisScrollEdges.hiddenMargin }
            }
            var cuts: [CGFloat] = [viewport]
            for frame in frames {
                cuts.append(frame.maxY + Self.fadeHeight)
                cuts.append(frame.minY - NoctisScrollEdges.hiddenMargin)
            }
            let clean = cuts.filter(isClean)
            var upward = clean.filter { $0 >= viewport && $0 <= viewport + maxRestShift }
            if contentBottom - viewport <= maxRestShift { upward.append(contentBottom) }
            if let cut = upward.min() {
                shift = cut - viewport
            } else if let cut = clean.filter({ $0 < viewport && $0 >= viewport * 0.55 }).max() {
                band = viewport - cut
            }
        }
        if abs(shift - restShift) > 0.5 { restShift = shift }
        if abs(band - restBand) > 0.5 { restBand = band }
    }

    /// The scrolled end's counterpart to the resting cut: adds just enough
    /// runway after the last block that at full scroll no block straddles
    /// the header's 24pt fade — each is either fully hidden under the
    /// header's solid band (descenders included) or starts below the
    /// gradient — and the benefits card is never left as a sliver (it is
    /// hidden with its shadow, starts at or below the fade, or shows at
    /// least 40pt below it). Zero when the natural end is clean.
    private func settleEndRunway() {
        let frames = blockFrames + cardRowFrames
        let naturalMaxOffset = scrollMetrics.contentHeight - endRunway - scrollMetrics.visibleHeight
        guard naturalMaxOffset > 0, !frames.isEmpty, headerBandEnd > 0 else {
            if endRunway != 0 { endRunway = 0 }
            return
        }
        let bandEnd = headerBandEnd
        let fade = Self.fadeHeight
        let card = cardFrame
        func isClean(_ offset: CGFloat) -> Bool {
            let textClean = frames.allSatisfy { $0.maxY - offset <= bandEnd - NoctisScrollEdges.hiddenMargin || $0.minY - offset >= bandEnd + fade }
            let cardClean = card.height == 0
                || card.maxY - offset <= bandEnd - 4
                || card.minY - offset >= bandEnd
                || card.maxY - offset - (bandEnd + fade) >= 40
            return textClean && cardClean
        }
        var candidates: [CGFloat] = [naturalMaxOffset]
        for frame in frames {
            candidates.append(frame.maxY - bandEnd + NoctisScrollEdges.hiddenMargin)
            candidates.append(frame.minY - bandEnd - fade)
        }
        if card.height > 0 {
            candidates += [card.maxY - bandEnd + 4, card.minY - bandEnd, card.maxY - bandEnd - fade - 40]
        }
        // Never more than half a viewport of runway, so the scrolled end can
        // never come to rest showing nothing at all.
        let limit = naturalMaxOffset + scrollMetrics.visibleHeight / 2
        candidates = candidates.filter { $0 >= naturalMaxOffset && $0 <= limit }.sorted()
        let runway = (candidates.first(where: isClean) ?? naturalMaxOffset) - naturalMaxOffset
        if abs(runway - endRunway) > 0.5 { endRunway = runway }
    }

    /// R14(b): the pinned Close/Restore row's paper backing and 24pt fade,
    /// shown only once content has scrolled up underneath it.
    private var topFade: some View {
        ZStack {
            NoctisPaper.bg.ignoresSafeArea(edges: .top)
            LinearGradient(colors: [NoctisPaper.bg, NoctisPaper.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: NoctisSpacing.xl)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: NoctisSpacing.xl)
        }
        .allowsHitTesting(false)
    }

    private var hero: some View {
        VStack(spacing: NoctisScrollEdges.blockGap(NoctisSpacing.sm, dynamicTypeSize)) {
            ZStack {
                // The same segmented ring Sample draws (R2: solid arcs with
                // real gaps, no blended joints), center number hidden.
                NoctisStageRing(progress: ringProgress, diameter: Self.ringDiameter, lineWidth: Self.ringLineWidth)
                if showCheckmark {
                    PaywallCheckmark()
                        .frame(width: 40, height: 40)
                }
            }
            .frame(height: Self.ringDiameter)
            .frame(maxWidth: .infinity)
            .paywallBlock()

            if let context, context != .general {
                Text(context.line)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoctisPaper.orangeText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("paywall.context")
                    .paywallBlock()
            }
            NoctisTitle("Sleep", emphasis: "deeper.")
                .paywallBlock()
            Text("Understand yourself.")
                .noctisFont(17, .medium, relativeTo: .body)
                .foregroundStyle(NoctisPaper.ink2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paywallBlock()
            Text(personalizedLine)
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(NoctisPaper.ink3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paywallBlock()
        }
        .frame(maxWidth: .infinity)
        .onAppear { runHeroEntranceIfNeeded() }
    }

    private var personalizedLine: String {
        "Built around your \(formattedNeed(needMinutes)) plan, bed by \(noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes))."
    }

    private func runHeroEntranceIfNeeded() {
        guard ringProgress == 0 else { return }
        if reduceMotion {
            ringProgress = 1
        } else {
            withAnimation(NoctisMotion.drawIn) { ringProgress = 1 }
        }
    }

    // MARK: - Benefits

    private var benefitsCard: some View {
        NoctisPaperCard(padding: Self.benefitsCardPadding) {
            VStack(spacing: 0) {
                ForEach(Array(benefitRows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: NoctisSpacing.sm) {
                        NoctisIconTile(systemImage: row.icon, fill: row.fill, size: 28)
                        // One line at the default size (as designed); above
                        // it the row wraps instead of shrinking away.
                        Text(row.text)
                            .noctisFont(13, .medium, relativeTo: .footnote)
                            .foregroundStyle(NoctisPaper.ink)
                            .lineLimit(dynamicTypeSize > .large ? nil : 1)
                            .minimumScaleFactor(dynamicTypeSize > .large ? 1 : 0.85)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, NoctisScrollEdges.blockGap(12, dynamicTypeSize) / 2)
                    .paywallCardRow(index)
                    if index < benefitRows.count - 1 {
                        Rectangle().fill(NoctisPaper.hairline).frame(height: 1)
                    }
                }
            }
            .onPreferenceChange(PaywallCardRowHeightsKey.self) { cardRowHeights = $0 }
        }
        .noctisRise()
        // Measured outside the rise's offset: the card's resting position.
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { cardFrame = geometry.frame(in: .named(PaywallBlockFramesKey.coordinateSpace)) }
                    .onChange(of: geometry.frame(in: .named(PaywallBlockFramesKey.coordinateSpace))) { _, newValue in cardFrame = newValue }
            }
        )
    }

    private var compareLink: some View {
        Button {
            showCompareSheet = true
        } label: {
            Text("Compare free and Premium")
                .noctisFont(14, .medium, relativeTo: .subheadline)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(NoctisPaper.orangeText)
    }

    // MARK: - Plans

    @ViewBuilder
    private var plansSection: some View {
        switch phase {
        case .loading:
            VStack(spacing: NoctisSpacing.sm) {
                PlanCardSkeleton().paywallBlock()
                PlanCardSkeleton().paywallBlock()
            }
        case .unavailable:
            unavailableNotice
        case .ready:
            VStack(spacing: NoctisSpacing.sm) {
                if let yearly = yearlyProduct {
                    planCard(planOption(for: yearly, isYearly: true)).paywallBlock()
                }
                if let monthly = monthlyProduct {
                    planCard(planOption(for: monthly, isYearly: false)).paywallBlock()
                }
                if showReminderToggle {
                    reminderToggle.paywallBlock()
                }
            }
        }
    }

    private var unavailableNotice: some View {
        VStack(spacing: NoctisSpacing.xs) {
            Image(systemName: "wifi.slash")
                .noctisIcon(22, relativeTo: .subheadline)
                .foregroundStyle(NoctisPaper.ink3)
                .accessibilityHidden(true)
            Text("We couldn't load plans.")
                .noctisFont(15, .medium, relativeTo: .subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(NoctisPaper.ink2)
        }
        // The icon and text, not the padded frame, are what a fade must avoid.
        .paywallBlock()
        .frame(maxWidth: .infinity)
        .padding(.vertical, NoctisSpacing.lg)
    }

    /// Plan cards render from `PlanOption` alone — never touching `Product`
    /// directly — so the same rendering code can be exercised from a
    /// DEBUG-only `#Preview` with two hardcoded options, without needing a
    /// live StoreKit product load (see the bottom of this file).
    private func planOption(for product: Product, isYearly: Bool) -> PlanOption {
        PlanOption(
            id: product.id,
            isYearly: isYearly,
            displayPrice: product.displayPrice,
            perMonthText: isYearly ? "\(perMonthEquivalent(product)) / mo" : nil,
            trialBadge: isYearly && isEligibleForTrial ? TrialLength(product).map { "\($0.phrase) free" } : nil,
            savingsPercent: isYearly ? savingsPercent : nil
        )
    }

    private func planCard(_ option: PlanOption) -> some View {
        let isSelected = selectedProductID == option.id
        return PlanCardView(option: option, isSelected: isSelected, reduceMotion: reduceMotion) {
            NoctisHaptics.selectionTick()
            withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
                selectedProductID = option.id
            }
            NoctisAnalytics.log(.planSelected, parameters: ["product_id": option.id])
        }
    }

    private func perMonthEquivalent(_ product: Product) -> String {
        (product.price / 12).formatted(product.priceFormatStyle)
    }

    private var savingsPercent: Int? {
        guard let yearly = yearlyProduct, let monthly = monthlyProduct else { return nil }
        let yearlyCostIfMonthly = monthly.price * 12
        guard yearlyCostIfMonthly > 0 else { return nil }
        let savings = 1 - (yearly.price / yearlyCostIfMonthly)
        let percent = Int((Double(truncating: savings as NSDecimalNumber) * 100).rounded())
        return percent > 0 ? percent : nil
    }

    private var reminderToggle: some View {
        Toggle(isOn: $remindBeforeTrialEnds) {
            Text("Remind me 2 days before my trial ends")
                .noctisFont(14, relativeTo: .subheadline)
                .foregroundStyle(NoctisPaper.ink)
        }
        .tint(NoctisPaper.cocoa)
        .padding(NoctisSpacing.md)
        .background(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous).fill(NoctisPaper.surface))
    }

    private func formattedNeed(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
    }

    // MARK: - Bottom stack

    @ViewBuilder
    private var bottomStack: some View {
        switch phase {
        case .loading:
            VStack(spacing: NoctisSpacing.sm) {
                NoctisCTA("Loading plans", isLoading: true) {}
                    .disabled(true)
                NoctisTextButton("Continue with the free plan", action: dismissWithoutSubscribing)
            }
        case .unavailable:
            VStack(spacing: NoctisSpacing.sm) {
                NoctisCTA("Try again", icon: "arrow.clockwise") { Task { await loadStore() } }
                NoctisTextButton("Continue with the free plan", action: dismissWithoutSubscribing)
            }
        case .ready:
            VStack(spacing: NoctisSpacing.xs) {
                if store.purchaseState == .pending {
                    Text("Waiting for approval — this can take a moment.")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(NoctisPaper.ink2)
                        .multilineTextAlignment(.center)
                }
                if case .failed(let message) = store.purchaseState {
                    Text(message)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(NoctisPaper.orangeText)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: NoctisSpacing.sm) {
                    NoctisCTA(ctaTitle, isLoading: store.purchaseState == .purchasing, action: startPurchase)
                        .disabled(selectedProduct == nil || store.purchaseState == .purchasing || store.purchaseState == .pending)
                    if let legal = legalLine {
                        Text(legal)
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(NoctisPaper.ink3)
                            .multilineTextAlignment(.center)
                    }
                    NoctisTextButton("Continue with the free plan", action: dismissWithoutSubscribing)
                    footer
                }
            }
        }
    }

    private var ctaTitle: String {
        guard showTrialCTA, let trial = TrialLength(selectedProduct) else { return "Subscribe" }
        return "Start \(trial.adjective) free trial"
    }

    private var legalLine: String? {
        guard let product = selectedProduct else { return nil }
        let period = selectedProductID == StoreProductID.yearly ? "year" : "month"
        if showTrialCTA, let trial = TrialLength(product) {
            return "\(trial.phrase) free, then \(product.displayPrice) per \(period). Cancel anytime in Settings."
        }
        return "\(product.displayPrice) per \(period). Cancel anytime in Settings."
    }

    /// A 12pt footer link whose frame is a full 44pt tall, so the tap target and the accessibility frame (Switch Control, the audit) agree. The row
    /// keeps its compact height because the container takes the padding back (`footer`), not each label: a label that gave the padding back itself
    /// would report a 14pt frame.
    private func footerLabel(_ title: String) -> some View {
        Text(title)
            .padding(.vertical, Self.footerLinkPadding.height)
            .padding(.horizontal, Self.footerLinkPadding.width)
            .contentShape(Rectangle())
    }

    private static let footerLinkPadding = CGSize(width: 8, height: 15)

    /// One row of links; stacked when large text can't fit them across.
    @ViewBuilder
    private var footerLinks: some View {
        Button(action: restorePurchases) { footerLabel("Restore Purchases") }
        Link(destination: StoreLegalLinks.terms) { footerLabel("Terms") }
        Link(destination: StoreLegalLinks.privacy) { footerLabel("Privacy") }
    }

    private var footer: some View {
        let inset = Self.footerLinkPadding
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: NoctisSpacing.lg - 2 * inset.width) { footerLinks }
            VStack(spacing: NoctisSpacing.xs - 2 * inset.height) { footerLinks }
        }
        .padding(.vertical, -inset.height)
        .padding(.horizontal, -inset.width)
        .noctisFont(12, relativeTo: .caption)
        .foregroundStyle(NoctisPaper.ink3)
        .padding(.top, NoctisSpacing.xs)
    }

    /// Solid paper behind the CTA stack, plus the 24pt fade above it only
    /// while content actually extends below the visible area (R14).
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

    // MARK: - Actions

    private func onFirstAppear() async {
        guard !hasCheckedEntitlement else { return }
        hasCheckedEntitlement = true
        await store.entitlementManager.refresh()
        if store.entitlementManager.hasAccess {
            onFinished()
            return
        }
        NoctisAnalytics.log(.paywallViewed)
        async let notifSettings = UNUserNotificationCenter.current().notificationSettings()
        async let eligible = store.isEligibleForIntroOffer()
        notificationsAuthorized = await notifSettings.authorizationStatus == .authorized
        isEligibleForTrial = await eligible
        await loadStore()
    }

    private func loadStore() async {
        phase = .loading
        await store.loadProducts()
        phase = store.loadState == .loaded ? .ready : .unavailable
    }

    private func startPurchase() {
        guard let product = selectedProduct else { return }
        Task { await store.purchase(product) }
    }

    private func handlePurchaseSuccess() {
        let wasTrial = showTrialCTA
        if wasTrial {
            NoctisAnalytics.log(.trialStarted, parameters: ["product_id": selectedProductID])
        }
        NoctisAnalytics.log(.purchaseCompleted, parameters: ["product_id": selectedProductID, "trial": wasTrial ? "true" : "false"])
        if wasTrial, remindBeforeTrialEnds {
            scheduleTrialEndingReminder()
        }
        NoctisHaptics.success()
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
            ringProgress = 1
            showCheckmark = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.4 : 1.0)) {
            onFinished()
        }
    }

    private func scheduleTrialEndingReminder() {
        let content = UNMutableNotificationContent()
        content.title = "NOCTIS"
        content.body = "Your free trial ends in 2 days."
        content.sound = .default
        var trigger = DateComponents()
        let fireDate = Date.now.addingTimeInterval(5 * 24 * 3600)
        trigger = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let calendarTrigger = UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false)
        let request = UNNotificationRequest(identifier: "noctis.notification.trialEnding", content: content, trigger: calendarTrigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func restorePurchases() {
        Task {
            let result = await store.restore()
            restoreOutcome = result
        }
    }

    private func dismissWithoutSubscribing() {
        NoctisAnalytics.log(.paywallDismissed)
        onFinished()
    }

    private var restoreAlertTitle: String {
        switch restoreOutcome {
        case .restored: "Purchases restored."
        case .nothingFound: "No purchases found to restore."
        case .failed: "Restore failed. Please try again."
        case nil: ""
        }
    }

    private var restoreAlertBinding: Binding<Bool> {
        Binding(
            get: { restoreOutcome != nil },
            set: { if !$0 { restoreOutcome = nil } }
        )
    }
}

// MARK: - Purchase-success checkmark

private struct PaywallCheckmark: View {
    @State private var trim: CGFloat = 0

    var body: some View {
        Circle()
            .fill(NoctisPaper.cocoa)
            .overlay(
                PaywallCheckmarkShape()
                    .trim(from: 0, to: trim)
                    .stroke(NoctisPaper.ivory, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .padding(16)
            )
            .onAppear { withAnimation(.easeOut(duration: 0.35)) { trim = 1 } }
    }
}

private struct PaywallCheckmarkShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Plan card

/// Renders purely from `PlanOption` — no `Product`, no `StoreManager` — so
/// it's usable both from the live screen (`PaywallScreen.planCard(_:)`)
/// and from the DEBUG preview harness at the bottom of this file.
private struct PlanCardView: View {
    let option: PlanOption
    let isSelected: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void

    /// R4: the radio mark grows with the plan text beside it.
    @NoctisScaledLength(relativeTo: .callout) private var radioDiameter: CGFloat = 22

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: NoctisSpacing.md) {
                Circle()
                    .strokeBorder(isSelected ? NoctisPaper.cocoa : NoctisPaper.hairline, lineWidth: isSelected ? 6 : 1.5)
                    .frame(width: radioDiameter, height: radioDiameter)

                VStack(alignment: .leading, spacing: 3) {
                    // Name and badges on one line; badges drop below the
                    // name when large text can't fit them beside it.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            planName
                            badges
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            planName
                            HStack(spacing: 6) { badges }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            planName
                            badges
                        }
                    }
                    Text(option.isYearly ? "\(option.displayPrice) / year" : "\(option.displayPrice) / month")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(NoctisPaper.ink2)
                    if let perMonthText = option.perMonthText {
                        Text(perMonthText)
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(NoctisPaper.ink3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(NoctisSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                    .fill(NoctisPaper.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                            .stroke(isSelected ? NoctisPaper.cocoa : NoctisPaper.hairline, lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: isSelected ? NoctisPaper.cocoa.opacity(0.12) : .clear, radius: 12, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(option.isYearly ? "Yearly" : "Monthly") plan, \(option.displayPrice) per \(option.isYearly ? "year" : "month")")
    }

    private var planName: some View {
        Text(option.isYearly ? "Yearly" : "Monthly")
            .noctisFont(16, .semibold, relativeTo: .callout)
            .foregroundStyle(NoctisPaper.ink)
            .fixedSize()
    }

    @ViewBuilder
    private var badges: some View {
        if let trialBadge = option.trialBadge {
            PlanBadge(text: trialBadge, fill: NoctisPaper.cocoa)
        }
        if let savings = option.savingsPercent {
            PlanBadge(text: "Save \(savings)%", fill: NoctisPaper.orange)
        }
    }
}

private struct PlanBadge: View {
    let text: String
    let fill: Color

    var body: some View {
        Text(text)
            .noctisFont(11, .bold, relativeTo: .caption2)
            .tracking(0.3)
            .foregroundStyle(NoctisPaper.bg)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(fill))
            .fixedSize()
    }
}

// MARK: - Skeleton

private struct PlanCardSkeleton: View {
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
            .fill(NoctisPaper.surface)
            .overlay(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous).stroke(NoctisPaper.hairline, lineWidth: 1))
            .overlay(
                HStack(spacing: NoctisSpacing.md) {
                    Circle().fill(NoctisPaper.track).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(NoctisPaper.track).frame(width: 90, height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(NoctisPaper.track).frame(width: 140, height: 11)
                    }
                    Spacer(minLength: 0)
                }
                .padding(NoctisSpacing.md)
            )
            .frame(height: 68)
            .opacity(pulse ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

// MARK: - Preview (DEBUG only — StoreKit `Product` can't be constructed
// by hand, so this drives the exact same `PlanCardView` the live screen
// uses from two hardcoded `PlanOption`s instead of a real product load.)

#if DEBUG
#Preview("Paywall plans — yearly selected") {
    PlanCardPreviewHarness(selectedID: PlanCardPreviewHarness.yearly.id)
}

#Preview("Paywall plans — monthly selected") {
    PlanCardPreviewHarness(selectedID: PlanCardPreviewHarness.monthly.id)
}

/// Internal (DEBUG only) so the QA suite can also render it to images.
struct PlanCardPreviewHarness: View {
    static let yearlyID = "yearly"
    static let monthlyID = "monthly"

    fileprivate static let yearly = PlanOption(
        id: "yearly",
        isYearly: true,
        displayPrice: "$39.99",
        perMonthText: "$3.33 / mo",
        trialBadge: "7 days free",
        savingsPercent: 33
    )
    fileprivate static let monthly = PlanOption(
        id: "monthly",
        isYearly: false,
        displayPrice: "$4.99",
        perMonthText: nil,
        trialBadge: nil,
        savingsPercent: nil
    )

    @State var selectedID: String

    var body: some View {
        ZStack {
            PaperBackground().ignoresSafeArea()
            VStack(spacing: NoctisSpacing.sm) {
                PlanCardView(option: Self.yearly, isSelected: selectedID == Self.yearly.id, reduceMotion: false) {
                    selectedID = Self.yearly.id
                }
                PlanCardView(option: Self.monthly, isSelected: selectedID == Self.monthly.id, reduceMotion: false) {
                    selectedID = Self.monthly.id
                }
            }
            .padding(NoctisSpacing.xl)
        }
    }
}
#endif
