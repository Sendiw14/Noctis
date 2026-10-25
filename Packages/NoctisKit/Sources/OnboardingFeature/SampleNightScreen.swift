import DesignSystem
import NoctisCore
import NoctisText
import SwiftUI

private typealias SleepRing = NoctisStageRingLayout

/// The durations the screen shows, from the shared `SampleNight` (they add up to its total): kept apart from the view so a test can hold them.
enum SampleNightFacts {
    /// Deep, Core, REM, Awake in the ring's order.
    static var stageMinutes: [(stage: SampleSleepStage, minutes: Int)] { SampleSleepStage.allCases.map { ($0, SampleNight.minutes(for: $0)) } }
    static var totalMinutes: Int { SampleNight.totalMinutes }
    static let quality = 87
    static var accessibilitySummary: String {
        "Sample night: \(spoken(totalMinutes)) asleep, sleep quality \(quality) percent"
    }

    /// "1 hour 32 minutes".
    static func spoken(_ minutes: Int) -> String {
        NoctisDurationText.spoken(minutes)
    }
}

/// Step 3/6, in the band style (APP_RULES.md R6, R13, R69): the real stage ring built from the shared `SampleNight` hypnogram, always labelled "Sample"
/// (a tag in the band and the line under the tiles). A tile, or a tap on the ring, highlights its stage and dims the others; a second tap clears it.
struct SampleNightScreen: View {
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedStage: SampleSleepStage?
    @State private var entranceProgress: Double = 0
    @State private var entranceStarted = false
    @State private var entranceFinished = false
    @State private var entranceStartDate = Date()

    var body: some View {
        OnboardingStepScaffold(
            section: .recovery, step: 2, title: ["Meet your", "mornings."], bandHeight: 244, bandBadge: "SAMPLE", onBack: onBack
        ) {
            SampleNightContent(
                selected: $selectedStage, progress: entranceFinished || reduceMotion ? 1 : entranceProgress, shownMinutes: shownMinutes,
                tilesIn: entranceFinished || reduceMotion, dark: colorScheme == .dark, reduceMotion: reduceMotion,
                singleRing: dynamicTypeSize.isAccessibilitySize
            )
        } actions: {
            OnboardingPrimaryButton("Continue", identifier: "sample.continue", action: onNext)
        }
        .onAppear { runEntranceIfNeeded() }
    }

    /// The number in the centre counts up with the ring.
    private var shownMinutes: Int {
        guard entranceStarted, !entranceFinished, !reduceMotion else { return SampleNightFacts.totalMinutes }
        return Int((entranceProgress * Double(SampleNightFacts.totalMinutes)).rounded())
    }

    // MARK: Entrance

    /// One hero animation: the segments draw clockwise in stage order while the number counts up (0.9 s, ease out), then the tiles pop in. Reduce Motion
    /// shows the end at once.
    private func runEntranceIfNeeded() {
        guard !entranceStarted else { return }
        entranceStarted = true
        guard !reduceMotion else { entranceFinished = true; return }
        entranceStartDate = Date()
        animateEntranceFrame()
    }

    private func animateEntranceFrame() {
        let raw = min(Date().timeIntervalSince(entranceStartDate) / 0.9, 1)
        // A hand-made ease-out: the value is read every frame from a timer, so the curve is computed here.
        entranceProgress = 1 - (1 - raw) * (1 - raw)
        if raw >= 1 {
            entranceFinished = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { animateEntranceFrame() }
    }
}

private struct SampleNightContent: View {
    @Binding var selected: SampleSleepStage?
    let progress: Double
    let shownMinutes: Int
    let tilesIn: Bool
    let dark: Bool
    let reduceMotion: Bool
    let singleRing: Bool

    @Environment(\.onboardingScale) private var scale

    private var s: CGFloat { min(max(scale, 0.72), 1) }
    private var ringDiameter: CGFloat { (singleRing ? 220 : 242) * s }
    private var lineWidth: CGFloat { 30 * ringDiameter / 242 }

    var body: some View {
        VStack(spacing: 0) {
            ring.padding(.top, 36 * s)
            tiles.padding(.top, 34 * s)
            Text("Sample data. Your own night appears after your first sleep.")
                .noctisFont(12, relativeTo: .caption)
                .foregroundStyle(dark ? NoctisPaper.ivory.opacity(0.65) : NoctisPaper.ink.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22 * s)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            NoctisStageRing(
                progress: progress, diameter: ringDiameter, lineWidth: lineWidth, highlightedStage: selected,
                trackColor: dark ? NoctisPaper.ivory.opacity(0.1) : NoctisPaper.ink.opacity(0.08),
                deepOutline: dark ? NoctisPaper.ivory.opacity(0.2) : nil
            )
            VStack(spacing: 2) {
                if let selected {
                    let minutes = SampleNight.minutes(for: selected)
                    Text(noctisFormattedDuration(minutes: minutes))
                        .font(.system(size: (singleRing ? 34 : 42) * s, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(NoctisStageRingLayout.percent(of: minutes))% of the night")
                        .noctisFont(14, relativeTo: .footnote, maxScale: 1.0)
                        .opacity(0.7)
                } else {
                    Text(noctisFormattedDuration(minutes: shownMinutes))
                        .font(.system(size: (singleRing ? 34 : 42) * s, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("Sleep quality \(SampleNightFacts.quality)%")
                        .noctisFont(14, relativeTo: .footnote, maxScale: 1.0)
                        .opacity(0.7)
                }
            }
            // The centre is a gauge's label, sized with the ring (art, like the ring): it keeps its size at every Dynamic Type setting.
            .foregroundStyle(dark ? NoctisPaper.ivory : NoctisPaper.ink)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .frame(width: max(ringDiameter - 2 * lineWidth - 12, 0))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .contentShape(Circle())
        .onTapGesture { location in
            // A tap on the ring picks the stage under the finger, like a tile does.
            let center = CGPoint(x: ringDiameter / 2, y: ringDiameter / 2)
            let distance = hypot(location.x - center.x, location.y - center.y)
            guard distance > ringDiameter / 2 - lineWidth - 12, distance < ringDiameter / 2 + 8 else { return }
            toggle(SleepRing.slot(atDegrees: SleepRing.degrees(of: location, center: center)).stage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SampleNightFacts.accessibilitySummary)
        .accessibilityIdentifier("sample.ring")
    }

    // MARK: Tiles

    private var tiles: some View {
        let items = SampleNightFacts.stageMinutes
        return Group {
            if singleRing {
                // At accessibility sizes: two by two.
                VStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 8) {
                            tile(items[row * 2], index: row * 2)
                            tile(items[row * 2 + 1], index: row * 2 + 1)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in tile(item, index: index) }
                }
            }
        }
    }

    private func tile(_ item: (stage: SampleSleepStage, minutes: Int), index: Int) -> some View {
        let isDeep = item.stage == .deep
        let ink: Color = isDeep ? NoctisPaper.ivory : NoctisPaper.ink
        let selectedNow = selected == item.stage
        return Button {
            toggle(item.stage)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.stage.label.uppercased())
                    .noctisFont(11, .heavy, relativeTo: .caption2, maxScale: 1.3)
                    .tracking(0.6)
                    .opacity(0.85)
                Text(noctisFormattedDuration(minutes: item.minutes))
                    .noctisFont(17, .heavy, relativeTo: .headline, maxScale: 1.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 74 * s, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(item.stage.color))
            .overlay {
                if isDeep && dark { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(NoctisPaper.ivory.opacity(0.2), lineWidth: 1) }
            }
            .overlay {
                if selectedNow { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(dark ? NoctisPaper.ivory : NoctisPaper.ink, lineWidth: 3) }
            }
            .opacity(selected == nil || selectedNow ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(tilesIn ? 1 : 0.9)
        .opacity(tilesIn ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.72).delay(Double(index) * 0.05), value: tilesIn)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: selected)
        .accessibilityLabel("\(item.stage.label) sleep, \(SampleNightFacts.spoken(item.minutes))")
        .accessibilityHint("Highlights in the ring")
        .accessibilityAddTraits(selectedNow ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("sample.tile.\(item.stage.label.lowercased())")
    }

    private func toggle(_ stage: SampleSleepStage) {
        NoctisHaptics.softImpact()
        selected = selected == stage ? nil : stage
    }
}
