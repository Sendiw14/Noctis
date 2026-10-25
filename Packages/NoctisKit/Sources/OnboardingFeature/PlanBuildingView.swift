import DesignSystem
import NoctisCore
import SwiftUI

/// The three things the build does, in order. The words are the ones the checklist has always had; the first changes to "Starting fresh..." when there are
/// no nights yet (`PlanScreen`).
enum PlanBuildLine: Int, CaseIterable, Identifiable {
    case nights
    case bedtime
    case profile

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .nights: "Reading your recent nights"
        case .bedtime: "Finding your typical bedtime"
        case .profile: "Setting your sleep need"
        }
    }

    /// The colour of the row's check, and of the ring it brings in (butter first, then orange, then lavender: the rings are the day coming up).
    var color: Color {
        switch self {
        case .nights: NoctisPaper.sage
        case .bedtime: NoctisPaper.orange
        case .profile: NoctisPaper.lavender
        }
    }
}

/// The numbers and sentences of the "Building your plan" screen, apart from the view, so they are unit tests.
enum PlanBuildFacts {
    static let startingFresh = "Starting fresh. We'll learn your pattern as you sleep."
    /// A step is shown at least this long before the next one completes (the work itself decides when it is later).
    static let minimumGap = 0.7
    /// After the last step: the moon, one pulse, and this hold before the plan.
    static let holdSeconds = 0.6
    /// Lavender, orange, butter and the core (the sun), in the design's 402 x 874.
    static let radii: [CGFloat] = [430, 340, 250, 160]
    /// How far below the screen's bottom the rings' centre sits.
    static let centreBelow: CGFloat = 56
    /// The spring grows a ring to about this much past its size before it settles.
    static let overshoot: CGFloat = 1.08
    static let moonRadius: CGFloat = 34

    /// The rings' scale: with the width (402 = 1), and smaller when the rows leave less room, so the top of the biggest ring (at its overshoot) stays
    /// `gap` below the last row. Never below 0.3: at the accessibility sizes the screen scrolls instead.
    static func ringScale(width: CGFloat, totalHeight: CGFloat, contentHeight: CGFloat, gap: CGFloat = 12) -> CGFloat {
        let byWidth = width / 402
        let byRoom = (totalHeight - contentHeight - gap) / (radii[0] * overshoot - centreBelow)
        return max(0.3, min(byWidth, byRoom))
    }

    /// The top edge of the biggest ring at rest, from the screen's top.
    static func ringTop(totalHeight: CGFloat, scale: CGFloat) -> CGFloat { totalHeight + (centreBelow - radii[0]) * scale }

    /// What VoiceOver says as a step finishes: "Starting fresh step done".
    static func announcement(done text: String) -> String {
        let head = text.components(separatedBy: ". ").first ?? text
        return "\(head.hasSuffix(".") ? String(head.dropLast()) : head) step done"
    }

    /// About 24 tiny stars across the top 230 pt of the dark screen, kept clear of the words: (x, y, diameter, opacity) in the design's 402 x 874.
    static let stars: [(x: CGFloat, y: CGFloat, d: CGFloat, a: Double)] = [
        (332, 18, 1.6, 0.8), (60, 30, 1.2, 0.6), (128, 12, 2.0, 0.7), (214, 44, 1.4, 0.55), (380, 40, 1.8, 0.75), (290, 70, 1.2, 0.5),
        (352, 92, 1.6, 0.7), (18, 70, 1.4, 0.6), (160, 76, 1.2, 0.5), (250, 24, 1.6, 0.65), (306, 12, 1.2, 0.5), (40, 10, 1.6, 0.7),
        (176, 28, 2.0, 0.8), (396, 120, 1.4, 0.6), (372, 150, 1.2, 0.5), (352, 132, 1.8, 0.7), (338, 196, 1.4, 0.6), (262, 186, 1.2, 0.5),
        (392, 208, 1.6, 0.7), (20, 216, 1.2, 0.55), (72, 226, 1.6, 0.65), (150, 214, 1.4, 0.6), (214, 224, 1.2, 0.5), (386, 178, 1.4, 0.55),
    ]
}

struct PlanBuildRow: Identifiable {
    let line: PlanBuildLine
    let text: String
    let isDone: Bool
    var id: Int { line.rawValue }
}

/// "Building your plan": a sunrise of rings at the bottom that grows as each of three steps finishes, and the steps themselves as rows. Flat colour, the
/// band-style palette, Light and Dark (stars in Dark). The work is `PlanScreen`'s; this only shows it. Reduce Motion: no spinning, no growing, no pulse.
struct PlanBuildingView: View {
    let rows: [PlanBuildRow]
    let isFailed: Bool
    let moonShown: Bool
    let pulsing: Bool
    let retry: () -> Void
    let continueAnyway: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 420

    private var dark: Bool { colorScheme == .dark }
    private var ground: Color { OnboardingStepScaffold<EmptyView, EmptyView>.ground(colorScheme) }
    private var ink: Color { dark ? NoctisPaper.ivory : NoctisPaper.ink }
    private var accent: Color { dark ? NoctisPaper.butter : NoctisPaper.orangeText }
    private func isDone(_ line: PlanBuildLine) -> Bool { rows.first { $0.line == line }?.isDone ?? false }

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let width = geometry.size.width
            let total = geometry.size.height + safeTop + safeBottom
            let c = min(max(min(width / 402, total / 874), 0.8), 1)
            let s = PlanBuildFacts.ringScale(width: width, totalHeight: total, contentHeight: contentHeight)
            ZStack(alignment: .top) {
                ground
                if dark { stars(width: width, scale: c) }
                SunriseRings(
                    scale: s, butter: isDone(.nights) && !isFailed, orange: isDone(.bedtime) && !isFailed, lavender: isDone(.profile) && !isFailed,
                    moon: moonShown && !isFailed, pulsing: pulsing, dark: dark, ground: ground, reduceMotion: reduceMotion
                )
                .position(x: width / 2, y: total + PlanBuildFacts.centreBelow * s)
                .accessibilityHidden(true)
                ScrollView {
                    content(c: c, safeTop: safeTop)
                        .padding(.bottom, isFailed ? 140 : max(0, (PlanBuildFacts.radii[0] * PlanBuildFacts.overshoot - PlanBuildFacts.centreBelow) * s + 11))
                }
                .scrollBounceBehavior(.basedOnSize)
                if isFailed {
                    VStack(spacing: 4) {
                        OnboardingPrimaryButton("Try again", identifier: "plan.retry", action: retry)
                        OnboardingSecondaryButton("Continue anyway", identifier: "plan.continueAnyway", action: continueAnyway)
                    }
                    .environment(\.onboardingScale, min(width / 402, total / 874))
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(safeBottom, 12) + 8)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(width: width, height: total, alignment: .top)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private func content(c: CGFloat, safeTop: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8 * c) {
                Text("NOCTIS")
                    .noctisFont(12, .bold, relativeTo: .caption, maxScale: 1.3)
                    .tracking(1.4)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: -7 * c) {
                    Text("Building your").foregroundStyle(ink)
                    Text("plan.").foregroundStyle(accent)
                }
                .noctisFont(42 * c, .heavy, relativeTo: .largeTitle, maxScale: 1.3)
                .tracking(-1.2)
                .lineLimit(dynamicTypeSize > .large ? 2 : 1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 28)
            .padding(.top, max(84 * c, safeTop + 22))
            VStack(spacing: 8) {
                let current = rows.first { !$0.isDone }?.line
                ForEach(rows) { row in
                    BuildRowView(row: row, isCurrent: row.line == current && !isFailed, dark: dark)
                }
                if isFailed {
                    Text("We couldn't read your latest sleep data.")
                        .noctisFont(14, relativeTo: .subheadline)
                        .foregroundStyle(ink.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 44 * c)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }

    private func stars(width: CGFloat, scale: CGFloat) -> some View {
        Canvas { context, _ in
            for star in PlanBuildFacts.stars {
                let d = min(2, star.d * 1.3)
                let rect = CGRect(x: star.x * width / 402, y: star.y * scale, width: d, height: d)
                context.fill(Path(ellipseIn: rect), with: .color(NoctisPaper.ivory.opacity(star.a)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - A row

private struct BuildRowView: View {
    let row: PlanBuildRow
    let isCurrent: Bool
    let dark: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            BuildMark(color: row.line.color, isDone: row.isDone, isSpinning: isCurrent, dark: dark, reduceMotion: reduceMotion)
            Text(row.text)
                .noctisFont(16, .semibold, relativeTo: .callout, maxScale: 1.3)
                .foregroundStyle(dark ? NoctisPaper.ivory : NoctisPaper.ink)
                .padding(.vertical, 2.5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(dark ? NoctisPaper.ivory.opacity(0.09) : NoctisPaper.surface))
        .shadow(color: dark ? .clear : NoctisPaper.ink.opacity(0.09), radius: 9, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.text)
        .accessibilityValue(row.isDone ? "Completed" : "In progress")
        .accessibilityIdentifier("plan.row.\(row.line.rawValue)")
    }
}

/// An empty ring while it waits (turning, if it is the one being done), a coloured disc with an ink check once it is done: the check pops in on a spring.
private struct BuildMark: View {
    let color: Color
    let isDone: Bool
    let isSpinning: Bool
    let dark: Bool
    let reduceMotion: Bool

    @State private var angle: Double = 0

    private var track: Color { dark ? NoctisPaper.ivory.opacity(0.3) : NoctisPaper.ink.opacity(0.22) }
    private var arc: Color { dark ? NoctisPaper.ivory : NoctisPaper.ink }

    var body: some View {
        ZStack {
            Circle().strokeBorder(track, lineWidth: 2.5).opacity(isDone ? 0 : 1)
            if isSpinning && !isDone && !reduceMotion {
                Circle()
                    .trim(from: 0, to: 0.26)
                    .stroke(arc, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .padding(1.25)
                    .rotationEffect(.degrees(angle))
                    .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 } }
            }
            Circle().fill(color).scaleEffect(isDone ? 1 : 0.4).opacity(isDone ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(NoctisPaper.ink)
                .scaleEffect(isDone ? 1 : 0.3)
                .opacity(isDone ? 1 : 0)
        }
        .frame(width: 30, height: 30)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.55), value: isDone)
        .accessibilityHidden(true)
    }
}

// MARK: - The sunrise

/// Flat concentric discs centred below the screen: lavender, orange, butter and a core. Each grows from nothing, with a spring that overshoots a little, as
/// its step finishes; the moon fades in once all three are done and the whole stack breathes once (1.0, 1.02, 1.0).
private struct SunriseRings: View {
    let scale: CGFloat
    let butter: Bool
    let orange: Bool
    let lavender: Bool
    let moon: Bool
    let pulsing: Bool
    let dark: Bool
    let ground: Color
    let reduceMotion: Bool

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.6) }

    var body: some View {
        let r = PlanBuildFacts.radii
        ZStack {
            disc(r[0], NoctisPaper.lavender, on: lavender)
            disc(r[1], NoctisPaper.orange, on: orange)
            disc(r[2], NoctisPaper.butter, on: butter)
            // The core: the paper in Light (a hole in the rings), ivory in Dark (a sun). It arrives with the first ring.
            disc(r[3], dark ? NoctisPaper.ivory : ground, on: butter)
            MoonAndSparkle(scale: scale)
                .offset(x: -8 * scale, y: -(r[3] - 42) * scale)
                .opacity(moon ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: moon)
        }
        .frame(width: 2 * r[0] * scale, height: 2 * r[0] * scale)
        .scaleEffect(pulsing ? 1.02 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: pulsing)
    }

    private func disc(_ radius: CGFloat, _ color: Color, on: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 2 * radius * scale, height: 2 * radius * scale)
            .scaleEffect(on ? 1 : 0.001)
            .animation(spring, value: on)
    }
}

/// A cocoa crescent (34 pt radius) with a small orange four-point sparkle to its upper right.
private struct MoonAndSparkle: View {
    let scale: CGFloat

    var body: some View {
        let radius = PlanBuildFacts.moonRadius * scale
        ZStack {
            CrescentShape()
                .fill(NoctisPaper.cocoa)
                .frame(width: 2 * radius, height: 2 * radius)
            SparkleShape()
                .fill(NoctisPaper.orange)
                .frame(width: 18 * scale, height: 18 * scale)
                .offset(x: 43 * scale, y: -7 * scale)
        }
    }
}
