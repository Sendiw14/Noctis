import DesignSystem
import NoctisCore
import SwiftUI

private typealias SleepRing = NoctisStageRingLayout

/// Step 3/6, the "this is what you get" moment: a Sleep Ring built from the
/// shared `SampleNight` hypnogram (R13: always labeled "Sample"). The ring
/// itself is a single `Canvas` (R8's absolute-placement exception); every
/// other element is plain system layout.
struct SampleNightScreen: View {
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// R4: the legend's stage dots grow with the legend text.
    @NoctisScaleFactor(relativeTo: .footnote) private var legendScale: CGFloat

    /// Read via a background probe rather than a direct `GeometryReader`
    /// wrap — RhythmScreen hit a real bug where wrapping hero content in a
    /// `GeometryReader` greedily filled the *unbounded* height the scaffold
    /// hands the hero at AX sizes, ballooning descendant hit-areas and
    /// swallowing the AX scroll gesture. The probe avoids that entirely.
    @State private var heroWidth: CGFloat = 400
    /// Drives `compact`, which tightens spacing on short screens (SE) so
    /// the stage columns and caption have room below the large,
    /// width-driven ring.
    @State private var heroHeight: CGFloat = 900

    @State private var selectedStage: SampleSleepStage?
    @State private var isDragging = false
    @State private var dragDegrees: Double = 0
    @State private var lastDragSlotIndex: Int?
    /// Drives which of the badge/pill pair is in the view tree — a boolean
    /// switch rather than a continuous 0-1 opacity blended against its
    /// complement. The dual-opacity version left a faint, persistent
    /// "Sample" ghost showing through the pill even once the pill read as
    /// fully opaque (caught in an R11 mid-scrub screenshot); only one of
    /// the two ever being actually present avoids that entirely.
    @State private var showPill = false

    @State private var entranceProgress: Double = 0
    @State private var entranceStarted = false
    @State private var entranceFinished = false
    @State private var entranceStartDate = Date()

    @State private var a11ySlotIndex: Int = 0

    private var ringDiameter: CGFloat {
        min(max(heroWidth - 64, 180), 300)
    }

    var body: some View {
        OnboardingScaffold(
            step: 2,
            title: "Meet your",
            emphasis: "mornings.",
            onBack: onBack
        ) {
            let compact = heroHeight < 700
            VStack(spacing: 0) {
                ringSection(compact: compact)
                Group {
                    if entranceFinished || reduceMotion {
                        stageColumns(compact: compact)
                            .noctisRise(index: 0)
                            .transition(.identity)
                    } else {
                        // Reserves the columns' height so nothing else
                        // shifts once they appear.
                        stageColumns(compact: compact).hidden()
                    }
                }
                .noctisTextBlock()
                .padding(.top, NoctisScrollEdges.blockGap(NoctisSpacing.lg, dynamicTypeSize))
                Text("Sample data. Your own night appears after your first sleep.")
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(NoctisPaper.ink3)
                    .multilineTextAlignment(.center)
                    .noctisTextBlock()
                    .padding(.top, NoctisScrollEdges.blockGap(NoctisSpacing.md, dynamicTypeSize))
                    .padding(.horizontal, compact ? NoctisSpacing.xs : NoctisSpacing.md)
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            heroWidth = geometry.size.width
                            heroHeight = geometry.size.height
                        }
                        .onChange(of: geometry.size) { _, newSize in
                            heroWidth = newSize.width
                            heroHeight = newSize.height
                        }
                }
            )
        } bottomStack: {
            NoctisCTA("Continue", action: onNext)
        }
        .onAppear { runEntranceIfNeeded() }
    }

    // MARK: - Ring section

    private func ringSection(compact: Bool) -> some View {
        // 12pt fixed (not compact-scaled): the ring's Canvas frame is
        // calibrated so its stroke's outer edge sits exactly at the
        // frame's own top edge (radius = frame/2 - lineWidth/2), so this
        // VStack spacing IS the badge-to-ring-outer-edge gap directly.
        VStack(spacing: 12) {
            // The scrub pill takes over the "Sample" badge's own slot
            // rather than floating as a separate overlay above the ring —
            // an overlay at a fixed offset landed directly on top of the
            // badge (caught live: a mid-drag screenshot showed "REM" and
            // "Sample" overlapping, both unreadable) — and only one of the
            // two is ever actually in the view tree (see `showPill`), so
            // there's no residual ghosting from the other while it fades.
            ZStack {
                if showPill {
                    scrubPill.allowsHitTesting(false).transition(.opacity)
                } else {
                    sampleBadge.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showPill)
            .noctisTextBlock()
            ring
        }
    }

    private var sampleBadge: some View {
        Text("Sample")
            .noctisFont(12, .semibold, relativeTo: .caption)
            .foregroundStyle(NoctisPaper.cocoa)
            .padding(.horizontal, NoctisSpacing.sm)
            .padding(.vertical, 5)
            .background(Capsule().fill(NoctisPaper.butter))
    }

    private var ring: some View {
        ZStack {
            NoctisStageRing(
                progress: entranceFinished || reduceMotion ? 1 : entranceProgress,
                diameter: ringDiameter,
                lineWidth: Self.ringLineWidth,
                highlightedStage: selectedStage
            )
            Canvas { context, size in
                drawRingOverlay(context: context, size: size)
            }
            .frame(width: ringDiameter, height: ringDiameter)
            .allowsHitTesting(false)

            ringCenterContent
                .noctisTextBlock()
        }
        .opacity(reduceMotion && !entranceFinished ? 0 : 1)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: entranceFinished)
        .gesture(ringGesture)
        // VoiceOver sees one adjustable element: swipe up/down steps through
        // the night's segments in order, reading each stage and duration.
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { Double(a11ySlotIndex) },
                    set: { newValue in
                        let index = min(max(Int(newValue.rounded()), 0), SleepRing.slots.count - 1)
                        guard index != a11ySlotIndex else { return }
                        a11ySlotIndex = index
                        NoctisHaptics.selectionTick()
                    }
                ),
                in: 0...Double(SleepRing.slots.count - 1),
                step: 1
            ) {
                Text("Sample night: 8 hours 25 minutes. Deep 1 hour 32, core 4 hours 5, REM 2 hours 8, awake 40 minutes.")
            }
            .accessibilityValue(a11ySlotDescription)
        }
    }

    private var a11ySlotDescription: String {
        let slot = SleepRing.slots[a11ySlotIndex]
        return "\(slot.stage.label), \(noctisFormattedDuration(minutes: slot.minutes))"
    }

    @ViewBuilder
    private var ringCenterContent: some View {
        // Constrained to the ring's inner diameter minus 32pt so "8h 25m"
        // never collides with the ring stroke on either side; 52pt (down
        // from 64) with a .7 floor covers every stage's duration string.
        Group {
            if let selectedStage {
                let minutes = SampleNight.minutes(for: selectedStage)
                VStack(spacing: 4) {
                    Text(noctisFormattedDuration(minutes: minutes))
                        .noctisNumeral(52)
                        .foregroundStyle(NoctisPaper.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(SleepRing.percent(of: minutes))% of the night")
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisPaper.ink2)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.2), reduceMotion: reduceMotion), value: selectedStage)
            } else {
                VStack(spacing: 4) {
                    Text(noctisFormattedDuration(minutes: displayedTotalMinutes))
                        .noctisNumeral(52)
                        .foregroundStyle(NoctisPaper.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("Sleep quality 87%")
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisPaper.ink2)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(width: ringCenterWidth)
        .multilineTextAlignment(.center)
    }

    /// Inside the ring's stroke: 8pt clear of it at standard sizes; at
    /// accessibility sizes narrower still, since the taller text block
    /// reaches where the circle's chord is shorter.
    private var ringCenterWidth: CGFloat {
        let inner = max(ringDiameter - 2 * Self.ringLineWidth, 0)
        return dynamicTypeSize.isAccessibilitySize ? inner * 0.78 : max(inner - 8, 0)
    }

    private var displayedTotalMinutes: Int {
        guard entranceStarted, !entranceFinished, !reduceMotion else { return SampleNight.totalMinutes }
        return Int((entranceProgress * Double(SampleNight.totalMinutes)).rounded())
    }

    private var scrubPill: some View {
        Text(scrubPillText)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .monospacedDigit()
            .foregroundStyle(NoctisPaper.bg)
            .padding(.horizontal, NoctisSpacing.sm)
            .padding(.vertical, 6)
            .background(Capsule().fill(NoctisPaper.ink))
            .fixedSize()
    }

    private var scrubPillText: String {
        let slot = SleepRing.slot(atDegrees: dragDegrees)
        let fraction = ((dragDegrees - slot.startDegrees) / max(slot.endDegrees - slot.startDegrees, 0.001)).clamped(0, 1)
        let minutesIntoSlot = Int((fraction * Double(slot.minutes)).rounded())
        let elapsedMinutes = slot.minutesBeforeInNight + minutesIntoSlot
        let clockMinutes = (Int(SampleNight.startHour * 60) + elapsedMinutes) % 1440
        let clock = noctisFormattedClock(minutesSinceMidnight: clockMinutes)
        return "\(clock)  \(slot.stage.label)  \(minutesIntoSlot) min"
    }

    // MARK: - Drawing

    private static let ringLineWidth: CGFloat = 26

    /// The ring itself is `NoctisStageRing` (shared with Paywall); this
    /// layer only adds Sample's own moving parts on top of it — the moon
    /// riding the entrance sweep's leading tip and the scrub dot.
    private func drawRingOverlay(context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = size.width / 2 - Self.ringLineWidth / 2

        if !entranceFinished && !reduceMotion && entranceStarted {
            let moonPoint = SleepRing.point(at: entranceProgress * 360, center: center, radius: radius)
            let moonBase = Path(ellipseIn: CGRect(x: moonPoint.x - 9, y: moonPoint.y - 9, width: 18, height: 18))
            context.fill(moonBase, with: .color(NoctisPaper.cocoa))
            // A plain crescent painted by hand: a moon body with a
            // same-color "bite" drawn over it reads clearly at 18pt.
            let moonBody = Path(ellipseIn: CGRect(x: moonPoint.x - 5, y: moonPoint.y - 5, width: 10, height: 10))
            context.fill(moonBody, with: .color(NoctisPaper.bg))
            let moonBite = Path(ellipseIn: CGRect(x: moonPoint.x - 1.5, y: moonPoint.y - 6, width: 10, height: 10))
            context.fill(moonBite, with: .color(NoctisPaper.cocoa))
        }

        if isDragging {
            let dotPoint = SleepRing.point(at: dragDegrees, center: center, radius: radius)
            let dotPath = Path(ellipseIn: CGRect(x: dotPoint.x - 7, y: dotPoint.y - 7, width: 14, height: 14))
            context.fill(dotPath, with: .color(NoctisPaper.cocoa))
            context.stroke(dotPath, with: .color(NoctisPaper.bg), style: StrokeStyle(lineWidth: 2))
        }
    }

    // MARK: - Gestures

    private var ringGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if !isDragging {
                    let distance = hypot(drag.translation.width, drag.translation.height)
                    guard distance > 6 else { return }
                    isDragging = true
                    showPill = true
                }
                let center = CGPoint(x: ringDiameter / 2, y: ringDiameter / 2)
                let degrees = SleepRing.degrees(of: drag.location, center: center)
                dragDegrees = degrees
                let slot = SleepRing.slot(atDegrees: degrees)
                if lastDragSlotIndex != slot.index {
                    lastDragSlotIndex = slot.index
                    NoctisHaptics.snapLight()
                }
            }
            .onEnded { drag in
                if isDragging {
                    showPill = false
                    isDragging = false
                    lastDragSlotIndex = nil
                } else {
                    let center = CGPoint(x: ringDiameter / 2, y: ringDiameter / 2)
                    let degrees = SleepRing.degrees(of: drag.location, center: center)
                    let slot = SleepRing.slot(atDegrees: degrees)
                    toggleSelection(slot.stage)
                }
            }
    }

    private func toggleSelection(_ stage: SampleSleepStage) {
        NoctisHaptics.selectionTick()
        withAnimation(NoctisMotion.adaptive(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) {
            selectedStage = (selectedStage == stage) ? nil : stage
        }
    }

    // MARK: - Stage columns

    /// Four columns side by side; at accessibility sizes, one row per
    /// stage (dot, name, duration) stacked vertically.
    @ViewBuilder
    private func stageColumns(compact: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: NoctisSpacing.xs) {
                ForEach(SampleSleepStage.allCases, id: \.self) { stage in
                    stageColumn(stage, compact: compact)
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(SampleSleepStage.allCases, id: \.self) { stage in
                    stageColumn(stage, compact: compact)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func stageColumn(_ stage: SampleSleepStage, compact: Bool) -> some View {
        let minutes = SampleNight.minutes(for: stage)
        let dot = (compact ? 8 : 10) * legendScale
        let name = Text(stage.label)
            .noctisFont(13, relativeTo: .footnote)
            .foregroundStyle(NoctisPaper.ink2)
        let duration = Text(noctisFormattedDuration(minutes: minutes))
            .noctisFont(compact ? 14 : 17, .semibold, relativeTo: .body)
            .foregroundStyle(NoctisPaper.ink)
        return Button {
            toggleSelection(stage)
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: NoctisSpacing.sm) {
                        Circle().fill(stage.color).frame(width: dot, height: dot)
                        name
                        Spacer(minLength: NoctisSpacing.sm)
                        duration
                    }
                    .frame(minHeight: 44)
                } else {
                    VStack(spacing: compact ? 1 : 4) {
                        Circle().fill(stage.color).frame(width: dot, height: dot)
                        name
                        duration
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .contentShape(Rectangle())
            .opacity(selectedStage == nil || selectedStage == stage ? 1 : 0.25)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.label), \(noctisFormattedDuration(minutes: minutes))")
        .accessibilityAddTraits(selectedStage == stage ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Entrance

    /// R9/screen spec: one hero animation, <= 1.4s — arcs sweep clockwise
    /// with a moon riding the leading tip, the center number counts up,
    /// then the stage columns rise. Reduce Motion skips straight to a
    /// 0.2s fade of the finished ring; the columns rise immediately after.
    private func runEntranceIfNeeded() {
        guard !entranceStarted else { return }
        entranceStarted = true
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.2)) {
                entranceFinished = true
            }
            return
        }
        entranceStartDate = Date()
        animateEntranceFrame()
    }

    private func animateEntranceFrame() {
        let duration = 1.1
        let elapsed = Date().timeIntervalSince(entranceStartDate)
        let raw = min(elapsed / duration, 1)
        // Manual ease-out (quadratic) — this drives a value read every
        // frame from a timer rather than an interruptible SwiftUI
        // animation, so the curve has to be computed by hand.
        entranceProgress = 1 - (1 - raw) * (1 - raw)
        if raw >= 1 {
            entranceFinished = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) {
            animateEntranceFrame()
        }
    }
}

private extension Double {
    func clamped(_ lower: Double, _ upper: Double) -> Double {
        min(max(self, lower), upper)
    }
}
