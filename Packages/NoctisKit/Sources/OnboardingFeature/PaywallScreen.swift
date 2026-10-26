import DesignSystem
import NoctisCore
import NoctisText
import StoreKit
import SwiftUI
import UserNotifications

private enum PaywallLoadPhase: Equatable {
    case loading
    case unavailable
    case ready
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
        case .week:
            value *= 7
            period = .day
        case .month: period = .month
        case .year: period = .year
        @unknown default: return nil
        }
        adjective = NoctisCount.adjective(value, period)
        phrase = NoctisCount.period(value, period)
    }
}

extension PaywallPlan {
    /// From the product StoreKit returned: its own localized price, its own intro offer, and the year's price over twelve in its own format.
    fileprivate init(product: Product, isYearly: Bool) {
        let trial = isYearly ? TrialLength(product) : nil
        self.init(
            id: product.id,
            isYearly: isYearly,
            displayPrice: product.displayPrice,
            price: product.price,
            perMonthText: isYearly ? "\((product.price / 12).formatted(product.priceFormatStyle)) / month" : nil,
            trialPhrase: trial?.phrase,
            trialAdjective: trial?.adjective
        )
    }
}

/// The paywall, in the band style: a cocoa band with the sleep ring, what Premium adds, two plans side by side and the button that starts one. It is the page
/// onboarding ends with, the sheet a locked thing opens (with the line saying what it unlocks, R58) and the page Settings opens; light and dark.
///
/// Everything fits one screen on an iPhone 17 Pro: `PaywallMetrics` has the design's sizes and tighter ones, and `ViewThatFits` takes the first that fits the
/// height (a sheet, an SE); at the accessibility sizes it scrolls, with the button and the renewal line pinned. Price and period are visible with the
/// plans, and the line under the button always reflects the selected plan (guideline 3.1.2): `PaywallFacts`.
struct PaywallScreen: View {
    let wakeMinutes: Int
    let needMinutes: Int
    let onFinished: () -> Void
    /// Why it was opened: the line above the title says exactly what the tapped thing unlocks (R58). Nil in onboarding.
    var context: PaywallContext?

    @Environment(StoreManager.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var appeared = false
    /// Which density is on show: an index into `densities` (the last scrolls). It starts at the design's and moves down while the page is taller than the screen.
    @State private var density = 0
    #if DEBUG
    /// `-mockPaywallPlans` (DEBUG): the two plans without StoreKit, so the screen can be seen on any simulator (StoreKit's configuration only answers under test).
    @State private var mockPlans = PaywallScreen.debugMockPlans
    #endif

    private var dark: Bool { colorScheme == .dark }
    private var ground: Color { dark ? PaywallStyle.darkGround : NoctisPaper.bg }
    private var ink: Color { dark ? NoctisPaper.ivory : NoctisPaper.ink }

    // MARK: Facts

    private var facts: PaywallFacts {
        #if DEBUG
        if let mock = mockPlans {
            return PaywallFacts(yearly: mock.yearly, monthly: mock.monthly, selectedID: selectedProductID, eligibleForIntroOffer: isEligibleForTrial)
        }
        #endif
        return PaywallFacts(
            yearly: store.yearlyProduct.map { PaywallPlan(product: $0, isYearly: true) },
            monthly: store.monthlyProduct.map { PaywallPlan(product: $0, isYearly: false) },
            selectedID: selectedProductID,
            eligibleForIntroOffer: isEligibleForTrial
        )
    }

    private var selectedProduct: Product? { store.products.first { $0.id == selectedProductID } }
    private var showReminderToggle: Bool { notificationsAuthorized && facts.showsTrial }
    private var isPurchasing: Bool { store.purchaseState == .purchasing }
    private var pinsActions: Bool { dynamicTypeSize.isAccessibilitySize }

    /// The densities in the order they are tried; nil is the scrolling page.
    private static let densities: [PaywallMetrics?] = [.regular, .relaxed, .compact, .tight, .tightMore, nil]

    /// The accessibility sizes go straight to the scrolling page; the rest start with the design's.
    private var startingDensity: Int { dynamicTypeSize.isAccessibilitySize ? Self.densities.count - 1 : 0 }

    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            let topInset = max(geometry.safeAreaInsets.top, 0)
            let bottomInset = geometry.safeAreaInsets.bottom
            let total = geometry.size.height + topInset + bottomInset
            ZStack {
                ground.ignoresSafeArea()
                Group {
                    if let metrics = Self.densities[min(density, Self.densities.count - 1)] {
                        // The page at its own height: if that is more than the screen has, the next denser one is tried (the last scrolls). Measured here, at the
                        // real width and with its text wrapped, rather than by `ViewThatFits`, which judged a page of wrapped rows by its one-line height.
                        column(metrics, top: topInset, bottom: bottomInset)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: geometry.size.width)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.size.height
                            } action: { height in
                                if height > total + 0.5, density < Self.densities.count - 1 { density += 1 }
                            }
                    } else {
                        scrollingColumn(top: topInset, bottom: bottomInset).frame(width: geometry.size.width)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: geometry.size.width, height: total, alignment: .top)
            .ignoresSafeArea()
            .onChange(of: total) { _, _ in density = startingDensity }
        }
        .onChange(of: dynamicTypeSize, initial: true) { _, _ in density = startingDensity }
        .sheet(isPresented: $showCompareSheet) { PremiumComparisonSheet().preferredColorScheme(.light) }
        .alert(restoreAlertTitle, isPresented: restoreAlertBinding) {
            Button("OK") { restoreOutcome = nil }
        }
        .task { await onFirstAppear() }
        .onChange(of: store.purchaseState) { _, newValue in
            if newValue == .success { handlePurchaseSuccess() }
        }
        .onAppear { runEntranceIfNeeded() }
    }

    /// The whole page at one density: band, benefits, the compare link, the plans, the button and the small print.
    private func column(_ metrics: PaywallMetrics, top: CGFloat, bottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            PaywallBand(
                metrics: metrics, topInset: top, context: context, ringProgress: ringProgress, showsClose: true, dark: dark,
                reduceMotion: reduceMotion, close: dismissWithoutSubscribing, restore: restorePurchases
            )
            VStack(spacing: 0) {
                benefitsCard(metrics).padding(.top, metrics.gap)
                compareLink.padding(.top, metrics.gap == 16 ? 0 : -2)
                plansSection(metrics).padding(.top, metrics.gap == 16 ? 0 : 2)
                if showReminderToggle { reminderToggle(metrics).padding(.top, metrics.gap) }
                actions(metrics).padding(.top, metrics.gap + 8)
                smallPrint(metrics).padding(.top, metrics.gap == 16 ? 0 : 2)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .padding(.bottom, max(bottom, 10))
    }

    /// The accessibility sizes: everything scrolls, the button and its renewal line stay put.
    private func scrollingColumn(top: CGFloat, bottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    PaywallBand(
                        metrics: .tight, topInset: top, context: context, ringProgress: ringProgress, showsClose: true, dark: dark,
                        reduceMotion: reduceMotion, close: dismissWithoutSubscribing, restore: restorePurchases
                    )
                    VStack(spacing: 0) {
                        benefitsCard(.tight).padding(.top, 12)
                        compareLink
                        plansSection(.tight)
                        if showReminderToggle { reminderToggle(.tight).padding(.top, 12) }
                        VStack(spacing: 4) {
                            if pinsActions { freePlanLink }
                            links
                            medical(.tight)
                        }
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 6) {
                statusLine
                primaryButton(.tight)
                if let renewal = facts.renewalText { renewalLine(renewal) }
                // A short screen that cannot fit the page keeps the way out in view; at the accessibility sizes the pinned part stays small.
                if !pinsActions { freePlanLink }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, max(bottom, 10))
            .background(ground.shadow(color: .black.opacity(dark ? 0.3 : 0.08), radius: 8, y: -2))
        }
    }

    // MARK: Benefits

    private func benefitsCard(_ metrics: PaywallMetrics) -> some View {
        let rows = Array(PaywallBenefits.all.prefix(metrics.benefitsShown))
        return VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(PaywallBenefits.fill(row.id))
                        // The ivory circle needs an edge on the white card.
                        if row.id == 3 && !dark { Circle().strokeBorder(NoctisPaper.ink.opacity(0.14), lineWidth: 1) }
                        Image(systemName: row.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(NoctisPaper.ink)
                    }
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                    // One line at the default size (as designed); above it the row wraps instead of shrinking away.
                    Text(row.text)
                        .noctisFont(13.5, .semibold, relativeTo: .footnote, maxScale: 1.3)
                        .foregroundStyle(ink)
                        .lineLimit(dynamicTypeSize > .large ? nil : 1)
                        .minimumScaleFactor(dynamicTypeSize > .large ? 1 : 0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .atLeastTall(metrics.benefitRowHeight, alignment: .leading)
                .slideUp(index: row.id, appeared: appeared || reduceMotion, reduceMotion: reduceMotion, stagger: 0.05)
                .accessibilityElement(children: .combine)
            }
            if metrics.benefitsShown < PaywallBenefits.all.count {
                HStack(spacing: 10) {
                    Color.clear.frame(width: 26, height: 26)
                    Text("and more")
                        .noctisFont(13.5, .semibold, relativeTo: .footnote, maxScale: 1.3)
                        .foregroundStyle(ink.opacity(0.65))
                    Spacer(minLength: 0)
                }
                .atLeastTall(metrics.benefitRowHeight, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, metrics.cardPadding)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(dark ? NoctisPaper.ivory.opacity(0.08) : NoctisPaper.surface))
        .shadow(color: dark ? .clear : NoctisPaper.ink.opacity(0.10), radius: 12, x: 0, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.benefits")
    }

    private var compareLink: some View {
        Button {
            showCompareSheet = true
        } label: {
            Text("Compare free and Premium")
                .noctisFont(13.5, .bold, relativeTo: .footnote, maxScale: 1.3)
                .foregroundStyle(dark ? PaywallStyle.darkLink : NoctisPaper.orangeText)
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -4)
        .accessibilityIdentifier("paywall.compare")
    }

    // MARK: Plans

    @ViewBuilder
    private func plansSection(_ metrics: PaywallMetrics) -> some View {
        switch phase {
        case .loading:
            HStack(spacing: 8) {
                PlanTileSkeleton(height: metrics.tileHeight, dark: dark)
                PlanTileSkeleton(height: metrics.tileHeight, dark: dark)
            }
        case .unavailable:
            unavailableNotice
        case .ready:
            let facts = facts
            HStack(spacing: 8) {
                ForEach(Array(facts.plans.enumerated()), id: \.element.id) { index, plan in
                    PlanTile(
                        plan: plan, facts: facts, isSelected: selectedProductID == plan.id, height: metrics.tileHeight, dark: dark,
                        reduceMotion: reduceMotion, select: { select(plan) }
                    )
                    .slideUp(index: 5 + index, appeared: appeared || reduceMotion, reduceMotion: reduceMotion, stagger: 0.05)
                }
            }
            // The badges hang a little below the yearly tile.
            .padding(.bottom, 8)
        }
    }

    private func select(_ plan: PaywallPlan) {
        guard selectedProductID != plan.id else { return }
        NoctisHaptics.softImpact()
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.62)) { selectedProductID = plan.id }
        NoctisAnalytics.log(.planSelected, parameters: ["product_id": plan.id])
    }

    private var unavailableNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .noctisIcon(22, relativeTo: .subheadline)
                .foregroundStyle(ink.opacity(0.65))
                .accessibilityHidden(true)
            Text("We couldn't load plans.")
                .noctisFont(15, .medium, relativeTo: .subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(ink.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(.vertical, 6)
    }

    private func reminderToggle(_ metrics: PaywallMetrics) -> some View {
        Toggle(isOn: $remindBeforeTrialEnds) {
            Text("Remind me 2 days before my trial ends")
                .noctisFont(metrics.oneLineTitle ? 13 : 14, relativeTo: .subheadline, maxScale: 1.3)
                .foregroundStyle(ink)
        }
        .tint(PaywallStyle.butter)
        .padding(.horizontal, 16)
        .padding(.vertical, metrics.oneLineTitle ? 2 : 8)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(dark ? NoctisPaper.ivory.opacity(0.08) : NoctisPaper.surface))
    }

    // MARK: Actions

    /// The button, its status and renewal line, the way out, the links and the medical line (pinned or not depending on the density).
    private func actions(_ metrics: PaywallMetrics) -> some View {
        VStack(spacing: 0) {
            statusLine
            primaryButton(metrics)
            if let renewal = facts.renewalText, phase == .ready {
                renewalLine(renewal).padding(.top, 8)
            }
            ctaFootnotes.frame(height: 0)
            freePlanLink.padding(.top, metrics.gap == 16 ? 2 : 0)
        }
    }

    /// Nothing in the screen beyond the renewal line for these: kept as a hook for the pinned layout.
    private var ctaFootnotes: some View { EmptyView() }

    @ViewBuilder
    private var statusLine: some View {
        if store.purchaseState == .pending {
            Text("Waiting for approval — this can take a moment.")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(ink.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        }
        if case .failed(let message) = store.purchaseState {
            Text(message)
                .noctisFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(dark ? PaywallStyle.darkLink : NoctisPaper.orangeText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
                .accessibilityIdentifier("paywall.error")
        }
    }

    private func renewalLine(_ text: String) -> some View {
        Text(text)
            .noctisFont(12, relativeTo: .caption, maxScale: 1.3)
            .foregroundStyle(ink.opacity(0.65))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("paywall.renewal")
    }

    @ViewBuilder
    private func primaryButton(_ metrics: PaywallMetrics) -> some View {
        switch phase {
        case .loading:
            PaywallButton(title: "Loading plans", spoken: "Loading plans", height: metrics.buttonHeight, state: .loading, action: {})
                .disabled(true)
        case .unavailable:
            PaywallButton(title: "Try again", spoken: "Try again", height: metrics.buttonHeight, state: .idle, icon: "arrow.clockwise") {
                Task { await loadStore() }
            }
        case .ready:
            let facts = facts
            PaywallButton(
                title: facts.buttonTitle, spoken: facts.buttonSpoken, height: metrics.buttonHeight,
                state: showCheckmark ? .done : (isPurchasing ? .loading : .idle), action: startPurchase
            )
            .disabled(facts.selected == nil || isPurchasing || store.purchaseState == .pending)
        }
    }

    private var freePlanLink: some View {
        Button(action: dismissWithoutSubscribing) {
            Text("Continue with the free plan")
                .noctisFont(16, .bold, relativeTo: .body, maxScale: 1.3)
                .foregroundStyle(ink.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .atLeastTall(44, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall.free")
    }

    /// A 12.5pt footer link whose frame is a full 44pt tall, so the tap target and the accessibility frame (Switch Control, the audit) agree. The row keeps its
    /// compact height because the container takes the padding back (`links`), not each label.
    private func linkLabel(_ title: String) -> some View {
        Text(title)
            .padding(.vertical, Self.linkPadding.height)
            .padding(.horizontal, Self.linkPadding.width)
            .contentShape(Rectangle())
    }

    private static let linkPadding = CGSize(width: 8, height: 15)

    @ViewBuilder
    private var linkItems: some View {
        Button(action: restorePurchases) { linkLabel("Restore Purchases") }.accessibilityIdentifier("paywall.restore")
        Link(destination: StoreLegalLinks.terms) { linkLabel("Terms") }
        Link(destination: StoreLegalLinks.privacy) { linkLabel("Privacy") }
    }

    /// One row of links; stacked when large text can't fit them across.
    private var links: some View {
        let inset = Self.linkPadding
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 24 - 2 * inset.width) { linkItems }
            VStack(spacing: 4 - 2 * inset.height) { linkItems }
        }
        .padding(.vertical, -inset.height)
        .padding(.horizontal, -inset.width)
        .noctisFont(12.5, relativeTo: .caption, maxScale: 1.3)
        .foregroundStyle(ink.opacity(0.65))
        .frame(maxWidth: .infinity)
    }

    private func medical(_ metrics: PaywallMetrics) -> some View {
        Text(NoctisMedicalNotice.statement)
            .noctisFont(10.5, relativeTo: .caption2, maxScale: 1.3)
            .foregroundStyle(ink.opacity(0.65))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
    }

    /// Below the button at one density: the links and the medical line.
    private func smallPrint(_ metrics: PaywallMetrics) -> some View {
        VStack(spacing: 0) {
            links
            medical(metrics).padding(.top, 2)
        }
    }

    // MARK: Behaviour

    private func runEntranceIfNeeded() {
        guard !appeared else { return }
        if reduceMotion {
            appeared = true
            ringProgress = 1
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { appeared = true }
            withAnimation(NoctisMotion.drawIn) { ringProgress = 1 }
        }
    }

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
        #if DEBUG
        // `-mockNotificationsAuthorized yes|no`: the trial reminder's switch on or off, whatever this simulator was told.
        let launch = ProcessInfo.processInfo.arguments
        if let flag = launch.firstIndex(of: "-mockNotificationsAuthorized"), launch.indices.contains(flag + 1) {
            notificationsAuthorized = launch[flag + 1] == "yes"
        }
        #endif
        isEligibleForTrial = await eligible
        #if DEBUG
        applyDebugPurchaseState()
        if mockPlans != nil {
            phase = .ready
            return
        }
        #endif
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
        let wasTrial = facts.showsTrial
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

    private var restoreAlertTitle: String { PaywallFacts.restoreMessage(restoreOutcome) }

    private var restoreAlertBinding: Binding<Bool> {
        Binding(
            get: { restoreOutcome != nil },
            set: { if !$0 { restoreOutcome = nil } }
        )
    }
}

// MARK: - Sizes

private extension View {
    /// At least `height` tall, also when the page is measured at its own height (`fixedSize`): a bare `frame(minHeight:)` only clamps a size that is proposed.
    func atLeastTall(_ height: CGFloat, alignment: Alignment = .topLeading) -> some View {
        ZStack(alignment: alignment) {
            Color.clear.frame(height: height)
            self
        }
    }
}

// MARK: - Palette

enum PaywallStyle {
    /// The background in Dark, under the cocoa band.
    static let darkGround = noctisHexColor("1A110B")
    /// "Compare free and Premium" in Dark (the orange lifted to read on the dark ground).
    static let darkLink = noctisHexColor("F08A4B")
    static let butter = NoctisPaper.butter
    static let band = NoctisPaper.ink
}

// MARK: - The band

/// The cocoa header: Close and Restore, "NOCTIS PREMIUM", the title in two lines, the sleep ring at the bottom right and a few tiny stars.
private struct PaywallBand: View {
    let metrics: PaywallMetrics
    let topInset: CGFloat
    let context: PaywallContext?
    let ringProgress: Double
    let showsClose: Bool
    let dark: Bool
    let reduceMotion: Bool
    let close: () -> Void
    let restore: () -> Void

    var body: some View {
        let contentLine = context.flatMap { $0 == .general ? nil : $0.line }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NoctisPaper.ivory)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(NoctisPaper.ivory.opacity(0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("paywall.close")
                Spacer()
                // Frames and content shapes sit inside the labels: on the Button itself they sized layout but not the tap target.
                Button(action: restore) {
                    Text("Restore")
                        .noctisFont(15, .semibold, relativeTo: .subheadline, maxScale: 1.3)
                        .foregroundStyle(NoctisPaper.ivory.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, max(topInset, 14))
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("NOCTIS PREMIUM")
                    .noctisFont(12, .bold, relativeTo: .caption, maxScale: 1.3)
                    .tracking(1.4)
                    .foregroundStyle(NoctisPaper.butter)
                    .accessibilityHidden(true)
                if let contentLine {
                    Text(contentLine)
                        .noctisFont(15, .semibold, relativeTo: .subheadline, maxScale: 1.3)
                        .foregroundStyle(NoctisPaper.ivory.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("paywall.context")
                }
                Group {
                    if metrics.oneLineTitle {
                        Text("\(Text("Sleep ").foregroundStyle(NoctisPaper.ivory))\(Text("deeper.").foregroundStyle(NoctisPaper.butter))")
                    } else {
                        VStack(alignment: .leading, spacing: -9) {
                            Text("Sleep").foregroundStyle(NoctisPaper.ivory)
                            Text("deeper.").foregroundStyle(NoctisPaper.butter)
                        }
                    }
                }
                .noctisFont(metrics.titleSize, .heavy, relativeTo: .largeTitle, maxScale: 1.3)
                .tracking(-1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .atLeastTall(topInset + metrics.bandContent)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                UnevenRoundedRectangle(bottomLeadingRadius: 48, bottomTrailingRadius: 48, style: .continuous).fill(PaywallStyle.band)
                PaywallStars(reduceMotion: reduceMotion)
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottomTrailing) {
            NoctisStageRing(
                progress: ringProgress, diameter: metrics.ring, lineWidth: metrics.ringLine,
                trackColor: NoctisPaper.ivory.opacity(0.12)
            )
            .padding(.trailing, 28)
            .padding(.bottom, 22)
            .accessibilityHidden(true)
        }
    }
}

/// About 26 tiny ivory stars across the band, off the words; they twinkle slowly (Reduce Motion: still).
private struct PaywallStars: View {
    let reduceMotion: Bool

    static let stars: [(x: CGFloat, y: CGFloat, d: CGFloat, a: Double)] = [
        (332, 22, 2.0, 0.8), (214, 34, 1.4, 0.55), (150, 16, 1.6, 0.6), (382, 64, 1.8, 0.75), (290, 80, 1.2, 0.5), (190, 70, 1.4, 0.6),
        (110, 40, 1.2, 0.5), (24, 28, 1.6, 0.7), (60, 12, 1.2, 0.55), (250, 18, 1.6, 0.65), (310, 52, 1.2, 0.5), (396, 28, 1.4, 0.6),
        (372, 120, 1.6, 0.7), (230, 112, 1.2, 0.5), (396, 150, 1.4, 0.6), (330, 110, 1.2, 0.55), (262, 140, 1.4, 0.6), (210, 168, 1.2, 0.5),
        (396, 196, 1.6, 0.7), (250, 206, 1.2, 0.55), (318, 236, 1.4, 0.6), (200, 240, 1.2, 0.5), (140, 98, 1.4, 0.6), (360, 214, 1.2, 0.5),
        (30, 76, 1.2, 0.5), (278, 200, 1.4, 0.6),
    ]

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: reduceMotion ? nil : 1.0 / 15.0, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    for (index, star) in Self.stars.enumerated() {
                        let twinkle = reduceMotion ? 1 : 0.72 + 0.28 * sin(t * 0.7 + Double(index) * 1.9)
                        let rect = CGRect(x: star.x * size.width / 402, y: star.y, width: star.d, height: star.d)
                        context.fill(Path(ellipseIn: rect), with: .color(NoctisPaper.ivory.opacity(star.a * twinkle)))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The button

private struct PaywallButton: View {
    enum State { case idle, loading, done }

    let title: String
    let spoken: String
    let height: CGFloat
    let state: State
    var icon: String?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            NoctisHaptics.softImpact()
            action()
        } label: {
            ZStack {
                switch state {
                case .idle:
                    label
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView().tint(NoctisPaper.ink)
                        if title == "Loading plans" { Text(title).noctisFont(18, .bold, relativeTo: .body, maxScale: 1.3) }
                    }
                case .done:
                    PaywallCheckmark().frame(width: 26, height: 26)
                }
            }
            .foregroundStyle(NoctisPaper.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .atLeastTall(height, alignment: .center)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(NoctisPaper.butter))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled || state != .idle ? 1 : 0.55)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: state)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("paywall.cta")
    }

    @ViewBuilder
    private var label: some View {
        if let icon {
            HStack(spacing: 8) {
                Text(title).noctisFont(18, .bold, relativeTo: .body, maxScale: 1.3)
                Image(systemName: icon).noctisIcon(15, .bold, relativeTo: .body)
            }
        } else {
            // One Text with the arrow inline, so a wrapped title grows the capsule instead of spilling out of it.
            Text("\(title)  \(Text(Image(systemName: "arrow.forward")).fontWeight(.bold))")
                .noctisFont(18, .bold, relativeTo: .body, maxScale: 1.3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Purchase-success checkmark

private struct PaywallCheckmark: View {
    @State private var trim: CGFloat = 0

    var body: some View {
        PaywallCheckmarkShape()
            .trim(from: 0, to: trim)
            .stroke(NoctisPaper.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
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

// MARK: - Plan tile

/// One plan: its name, price and period, selected (butter, a heavy outline, a filled radio) or not (paper, a hairline, an empty radio). The yearly tile carries
/// the trial and Save badges hanging over its bottom edge. Renders from `PaywallPlan` and `PaywallFacts` alone, so the DEBUG preview can draw it with no product.
private struct PlanTile: View {
    let plan: PaywallPlan
    let facts: PaywallFacts
    let isSelected: Bool
    let height: CGFloat
    let dark: Bool
    let reduceMotion: Bool
    let select: () -> Void

    private var onButter: Bool { isSelected }
    private var ink: Color { onButter || !dark ? NoctisPaper.ink : NoctisPaper.ivory }
    private var outline: Color { dark ? NoctisPaper.ivory : NoctisPaper.ink }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(plan.name)
                        .noctisFont(19, .heavy, relativeTo: .title3, maxScale: 1.3)
                        .foregroundStyle(ink)
                    Spacer(minLength: 4)
                    radio
                }
                Spacer(minLength: 4)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(plan.displayPrice)
                        .noctisFont(24, .heavy, relativeTo: .title2, maxScale: 1.3)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("/ \(plan.periodWord)")
                        .noctisFont(13, .semibold, relativeTo: .footnote, maxScale: 1.3)
                        .foregroundStyle(ink.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                }
                if let perMonth = plan.perMonthText {
                    Text(perMonth)
                        .noctisFont(12.5, relativeTo: .caption, maxScale: 1.3)
                        .foregroundStyle(ink.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .atLeastTall(height)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(fill))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(isSelected ? outline : (dark ? NoctisPaper.ivory.opacity(0.18) : NoctisPaper.hairline), lineWidth: isSelected ? 4 : 1.5)
            }
            .shadow(color: dark ? .clear : NoctisPaper.ink.opacity(isSelected ? 0.16 : 0.08), radius: 10, x: 0, y: 4)
            .overlay(alignment: .bottom) {
                if plan.isYearly { badges.offset(y: 10) }
            }
            .scaleEffect(isSelected ? 1 : 0.985)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.62), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(facts.spoken(plan))
        .accessibilityHint(isSelected ? "" : "Double tap to choose this plan")
        .accessibilityIdentifier("paywall.plan.\(plan.isYearly ? "yearly" : "monthly")")
    }

    private var fill: Color {
        if isSelected { return NoctisPaper.butter }
        return dark ? NoctisPaper.ivory.opacity(0.08) : NoctisPaper.surface
    }

    private var radio: some View {
        ZStack {
            if isSelected {
                Circle().fill(NoctisPaper.ink)
                Circle().fill(NoctisPaper.butter).frame(width: 8, height: 8)
            } else {
                Circle().strokeBorder(dark ? NoctisPaper.ivory.opacity(0.45) : NoctisPaper.ink.opacity(0.28), lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if let trial = facts.trialBadge {
                badge(trial.uppercased(), fill: NoctisPaper.cocoa, text: NoctisPaper.ivory)
            }
            if let percent = facts.savingsPercent {
                badge("SAVE \(percent)%", fill: NoctisPaper.orange, text: NoctisPaper.ink)
            }
        }
    }

    private func badge(_ text: String, fill: Color, text color: Color) -> some View {
        Text(text)
            .noctisFont(10, .heavy, relativeTo: .caption2, maxScale: 1.2)
            .tracking(0.5)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule(style: .continuous).fill(fill))
            .overlay { if dark { Capsule(style: .continuous).strokeBorder(NoctisPaper.ivory.opacity(0.16), lineWidth: 0.5) } }
            .fixedSize()
    }
}

private struct PlanTileSkeleton: View {
    let height: CGFloat
    let dark: Bool

    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(dark ? NoctisPaper.ivory.opacity(0.08) : NoctisPaper.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(
                    dark ? NoctisPaper.ivory.opacity(0.18) : NoctisPaper.hairline, lineWidth: 1.5)
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(NoctisPaper.track.opacity(dark ? 0.2 : 1)).frame(width: 70, height: 16)
                    RoundedRectangle(cornerRadius: 4).fill(NoctisPaper.track.opacity(dark ? 0.2 : 1)).frame(width: 110, height: 22)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .atLeastTall(height)
            .opacity(pulse ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Preview and QA (DEBUG only: StoreKit `Product` can't be constructed
// by hand, so these draw the same `PlanTile` and screen from two hardcoded
// `PaywallPlan`s instead of a real product load.)

#if DEBUG
extension PaywallScreen {
    /// `-mockPaywallPlans`: sample plans, so the paywall shows on a simulator without StoreKit's test configuration.
    fileprivate static var debugMockPlans: (yearly: PaywallPlan, monthly: PaywallPlan)? {
        guard ProcessInfo.processInfo.arguments.contains("-mockPaywallPlans") else { return nil }
        return (PaywallPlanSamples.yearly, PaywallPlanSamples.monthly)
    }

    /// `-mockPurchase purchasing|pending|failed|success`: the state after a tap on the button, for a still of each.
    fileprivate func applyDebugPurchaseState() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-mockPurchase"), arguments.indices.contains(flag + 1) else { return }
        switch arguments[flag + 1] {
        case "purchasing": store.purchaseState = .purchasing
        case "pending": store.purchaseState = .pending
        case "failed": store.purchaseState = .failed("We couldn't complete the purchase. You haven't been charged.")
        case "success": showCheckmark = true
        default: break
        }
    }
}

enum PaywallPlanSamples {
    static let yearly = PaywallPlan(
        id: StoreProductID.yearly, isYearly: true, displayPrice: "$39.99", price: 39.99, perMonthText: "$3.33 / month", trialPhrase: "7 days",
        trialAdjective: "7-day")
    static let monthly = PaywallPlan(
        id: StoreProductID.monthly, isYearly: false, displayPrice: "$6.99", price: 6.99, perMonthText: nil, trialPhrase: nil, trialAdjective: nil)
}

#Preview("Paywall plans — yearly selected") {
    PlanCardPreviewHarness(selectedID: PlanCardPreviewHarness.yearlyID)
}

#Preview("Paywall plans — monthly selected") {
    PlanCardPreviewHarness(selectedID: PlanCardPreviewHarness.monthlyID)
}

/// Internal (DEBUG only) so the QA suite can also render it to images.
struct PlanCardPreviewHarness: View {
    static let yearlyID = StoreProductID.yearly
    static let monthlyID = StoreProductID.monthly

    @State var selectedID: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let facts = PaywallFacts(yearly: PaywallPlanSamples.yearly, monthly: PaywallPlanSamples.monthly, selectedID: selectedID, eligibleForIntroOffer: true)
        ZStack {
            (colorScheme == .dark ? PaywallStyle.darkGround : NoctisPaper.bg).ignoresSafeArea()
            HStack(spacing: 8) {
                ForEach(facts.plans) { plan in
                    PlanTile(plan: plan, facts: facts, isSelected: selectedID == plan.id, height: 118, dark: colorScheme == .dark, reduceMotion: false) {
                        selectedID = plan.id
                    }
                }
            }
            .padding(20)
        }
    }
}
#endif
