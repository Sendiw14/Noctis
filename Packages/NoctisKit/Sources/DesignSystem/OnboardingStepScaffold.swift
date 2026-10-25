import SwiftUI

// The shared frame of the onboarding steps in the band style (APP_RULES.md R6, R69): a full-bleed colour band with a curved bottom (radius 48,
// continuous), a back button and six progress segments, the title at the band's bottom-left, an optional subtitle, the step's content, and the actions
// pinned at the bottom. The band's colour is a parameter: the tab colours (apricot Home, sage Sleep, lavender Recovery, butter Insights, rose Coach).
// The steps: Goal apricot (home), Rhythm sage (sleep), Sample lavender (recovery), Health rose (coach), Notifications butter (insights); light and dark.

/// The scale the layout was drawn at (402 x 874 = 1): the step's content may size its tiles with it.
private struct OnboardingScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// min(width / 402, height / 874), set by `OnboardingStepScaffold`.
    public var onboardingScale: CGFloat {
        get { self[OnboardingScaleKey.self] }
        set { self[OnboardingScaleKey.self] = newValue }
    }
}

public struct OnboardingStepScaffold<Content: View, Actions: View>: View {
    private let section: NoctisSection
    private let step: Int?
    private let totalSteps: Int
    private let title: [String]
    private let subtitle: String?
    private let bandHeight: CGFloat
    private let bandSymbol: String?
    private let bandBadge: String?
    private let bandAccessory: AnyView?
    private let topTrailingSymbol: String?
    private let topTrailingAccessory: AnyView?
    private let titleSize: CGFloat
    private let titleLeading: CGFloat
    private let onBack: (() -> Void)?
    private let content: Content
    private let actions: Actions

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `step` is 0-based (nil: no progress, no segments); `title` is one string per line.
    public init(
        section: NoctisSection, step: Int?, totalSteps: Int = 6, title: [String], subtitle: String? = nil, bandHeight: CGFloat = 262, bandSymbol: String? = nil, bandBadge: String? = nil, bandAccessory: AnyView? = nil, topTrailingSymbol: String? = nil, topTrailingAccessory: AnyView? = nil, titleSize: CGFloat = 38, titleLeading: CGFloat = 0, onBack: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions
    ) {
        self.section = section
        self.step = step
        self.totalSteps = totalSteps
        self.title = title
        self.subtitle = subtitle
        self.bandHeight = bandHeight
        self.bandSymbol = bandSymbol
        self.bandBadge = bandBadge
        self.bandAccessory = bandAccessory
        self.topTrailingSymbol = topTrailingSymbol
        self.topTrailingAccessory = topTrailingAccessory
        self.titleSize = titleSize
        self.titleLeading = titleLeading
        self.onBack = onBack
        self.content = content()
        self.actions = actions()
    }

    /// Ivory below the band in Light, cocoa in Dark.
    public static func ground(_ scheme: ColorScheme) -> Color { scheme == .dark ? NoctisPaper.ink : NoctisPaper.bg }

    private var ground: Color { Self.ground(colorScheme) }

    public var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let total = geometry.size.height + safeTop + safeBottom
            let scale = min(geometry.size.width / 402, total / 874)
            VStack(spacing: 0) {
                band(safeTop: safeTop, scale: scale)
                ScrollView {
                    content
                        .padding(.horizontal, 20)
                        .padding(.top, scale < 0.85 ? 12 : 20)
                        .padding(.bottom, scale < 0.85 ? 8 : 16)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Its own height, whatever the text size: the scroll view above gives way, never the buttons.
                actions
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, max(safeBottom, 12) + (scale < 0.85 ? 2 : 8))
            }
            .environment(\.onboardingScale, scale)
            .frame(width: geometry.size.width, height: total, alignment: .top)
        }
        .background(ground.ignoresSafeArea())
        .ignoresSafeArea()
    }

    private func band(safeTop: CGFloat, scale: CGFloat) -> some View {
        let clamped = min(max(scale, 0.72), 1)
        let rowTop = max(70 * clamped, safeTop + 16)
        return ZStack(alignment: .topLeading) {
            // The title sits at the band's bottom-left; the band is as tall as the design says, and taller only when the words need it.
            HStack(alignment: bandAccessory != nil ? .bottom : (bandBadge == nil ? .center : .top), spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                // `titleLeading` pulls the lines together (negative) for the 42 pt titles, which are set tight.
                VStack(alignment: .leading, spacing: titleLeading * clamped) {
                    ForEach(Array(title.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .noctisFont(titleSize * clamped, .heavy, relativeTo: .largeTitle, maxScale: 1.3)
                            .tracking(-1.2)
                            .foregroundStyle(NoctisPaper.ink)
                            // One line each up to the larger sizes (a line shrinks a little rather than wrap); wraps from there.
                            .lineLimit(dynamicTypeSize > .large ? 2 : 1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .noctisFont(14, relativeTo: .footnote)
                        .foregroundStyle(NoctisPaper.ink.opacity(0.75))
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let bandAccessory {
                Spacer(minLength: 0)
                // A small drawing beside the title's last line; hidden from VoiceOver by the caller.
                bandAccessory
            }
            if let bandBadge {
                Spacer(minLength: 0)
                // A small tag at the top of the title block, level with its first line ("SAMPLE").
                Text(bandBadge)
                    .noctisFont(13, .heavy, relativeTo: .footnote, maxScale: 1.2)
                    .tracking(0.8)
                    .foregroundStyle(NoctisPaper.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(NoctisPaper.butter))
                    .fixedSize()
                    .padding(.top, 6)
            }
            if let bandSymbol {
                Spacer(minLength: 0)
                Image(systemName: bandSymbol)
                    .font(.system(size: 24 * clamped, weight: .semibold))
                    .foregroundStyle(NoctisPaper.ink)
                    .frame(width: 58 * clamped, height: 58 * clamped)
                    .background(Circle().fill(NoctisPaper.ivory))
                    .accessibilityHidden(true)
            }
            }
            .padding(.horizontal, 24)
            .padding(.top, rowTop + 44 + 12)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, minHeight: bandHeight * clamped, alignment: .bottomLeading)
            topRow
                .padding(.horizontal, 24)
                .padding(.top, rowTop)
            if let topTrailingAccessory {
                // A small drawing at the band's top right, below the progress row (the caller hides it from VoiceOver).
                topTrailingAccessory
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 30)
                    .padding(.top, rowTop + 58 * clamped)
            }
            if let topTrailingSymbol {
                // A glyph in an ivory circle at the band's top right, just under the progress row (level with the title's first line).
                Image(systemName: topTrailingSymbol)
                    .font(.system(size: 24 * clamped, weight: .semibold))
                    .foregroundStyle(NoctisPaper.ink)
                    .frame(width: 58 * clamped, height: 58 * clamped)
                    .background(Circle().fill(NoctisPaper.ivory))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 28)
                    .padding(.top, rowTop + 33 * clamped)
                    .accessibilityHidden(true)
            }
        }
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 48, bottomTrailingRadius: 48, style: .continuous)
                .fill(section.fill)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NoctisPaper.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(NoctisPaper.ivory))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            if let step {
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? NoctisPaper.ink : NoctisPaper.ink.opacity(0.18))
                            .frame(height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(totalSteps)")
            }
        }
        .frame(height: 44)
    }
}

// MARK: - The actions

/// The step's main action: a 60pt capsule, cocoa with ivory text in Light, ivory with cocoa text in Dark; 40% when it cannot be used yet.
public struct OnboardingPrimaryButton: View {
    private let title: String
    private let isEnabled: Bool
    private let identifier: String
    private let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.onboardingScale) private var scale

    public init(_ title: String, isEnabled: Bool = true, identifier: String = "onboarding.primary", action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button {
            NoctisHaptics.softImpact()
            action()
        } label: {
            // One Text with the arrow inline: at the largest text sizes the words wrap and the capsule grows with them (an HStack of a Text and an
            // Image was measured at fewer lines than it drew, and the last line spilled out of the capsule).
            Text("\(title)  \(Text(Image(systemName: "arrow.forward")).fontWeight(.bold))")
                .noctisFont(18, .semibold, relativeTo: .body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .foregroundStyle(colorScheme == .dark ? NoctisPaper.cocoa : NoctisPaper.ivory)
            .frame(maxWidth: .infinity, minHeight: scale < 0.85 ? 52 : 60)
            .background(Capsule().fill(colorScheme == .dark ? NoctisPaper.ivory : NoctisPaper.cocoa))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.15), value: isEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

/// The quiet second action ("Skip for now", "Not now").
public struct OnboardingSecondaryButton: View {
    private let title: String
    private let identifier: String
    private let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(_ title: String, identifier: String = "onboarding.secondary", action: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .noctisFont(16, .semibold, relativeTo: .body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(colorScheme == .dark ? NoctisPaper.ivory.opacity(0.7) : NoctisPaper.cocoa.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
