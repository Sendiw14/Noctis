import DesignSystem
import NightKit
import SwiftUI

/// Breathing, opened over the wind-down's night (APP_RULES.md R33). Before it begins, a pattern, a
/// length and "Begin"; while it runs, one flat circle that grows through each inhale and shrinks
/// through each exhale, with the phase and its seconds counting down; under Reduce Motion the circle is
/// a level bar that steps once a second. Leaving it ends it.
struct BreathingPanel: View {
    let viewModel: BreathingViewModel
    let reduceMotion: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch viewModel.state {
            case .setup:
                BreathingSetup(viewModel: viewModel)
                    .transition(.opacity)
            case .running, .paused:
                BreathingSession(viewModel: viewModel, reduceMotion: reduceMotion)
                    .transition(.opacity)
            case .finished:
                BreathingFinished(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.3), reduceMotion: reduceMotion), value: viewModel.state)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.sceneBecameActive() }
        }
        .onAppear { viewModel.refreshFromPreferences() }
        .onDisappear { viewModel.leave() }
        .accessibilityIdentifier("breathing.panel")
    }
}

// MARK: - Before beginning

private struct BreathingSetup: View {
    let viewModel: BreathingViewModel

    var body: some View {
        // The options scroll and "Begin" stays under them: at accessibility sizes three patterns, three lengths and the line did not fit above it.
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            ScrollView {
                options
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            NightPrimaryButton(title: BreathingCopy.begin, symbol: "wind") { viewModel.begin() }
                .accessibilityIdentifier("breathing.begin")
                .padding(.bottom, NoctisSpacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.lg) {
            Text(BreathingCopy.line)
                .noctisFont(17, relativeTo: .body)
                .foregroundStyle(NoctisNight.ivory2)
                .accessibilityIdentifier("breathing.line")
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                NightCaption(BreathingCopy.patternCaption)
                // Side by side when they fit; one under the other when large text cannot have three in a row ("4-4-…", "2…" at AX5).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NoctisSpacing.xs) { patternChips }
                    VStack(spacing: NoctisSpacing.xs) { patternChips }
                }
                Text(BreathingCopy.summary(viewModel.pattern))
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisNight.ivory2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(BreathingCopy.spokenSummary(viewModel.pattern))
                    .accessibilityIdentifier("breathing.summary")
            }
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                NightCaption(BreathingCopy.durationCaption)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NoctisSpacing.xs) { durationChips }
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) { durationChips }
                }
            }
            if viewModel.hapticsAvailable {
                Toggle(isOn: Binding(get: { viewModel.hapticsOn }, set: { viewModel.setHaptics($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BreathingCopy.hapticsTitle)
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisNight.ivory)
                        Text(BreathingCopy.hapticsNote)
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(NoctisNight.ivory2)
                    }
                }
                .tint(NoctisNight.lavender)
                .frame(minHeight: 44)
                .accessibilityIdentifier("breathing.haptics")
            }
        }
    }

    @ViewBuilder
    private var patternChips: some View {
        ForEach(BreathingPattern.all) { pattern in
            BreathingPatternChip(pattern: pattern, isSelected: viewModel.patternID == pattern.id) {
                viewModel.choose(pattern: pattern.id)
                NoctisHaptics.selection()
            }
        }
    }

    @ViewBuilder
    private var durationChips: some View {
        ForEach(BreathingSchedule.durations, id: \.self) { minutes in
            NightChip(title: "\(minutes) min", isSelected: viewModel.minutes == minutes, identifier: "breathing.minutes.\(minutes)") {
                viewModel.choose(minutes: minutes)
                NoctisHaptics.selection()
            }
        }
    }
}

/// A pattern: its name and its numbers. 56pt, flat.
private struct BreathingPatternChip: View {
    let pattern: BreathingPattern
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(pattern.title)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                // One line: "4-4-4-4" broke into "4-4-4- / 4" in a third of an SE at AX3. With it unbreakable, three chips in a row no longer
                // fit there, so the row falls back to the column (ViewThatFits) instead of wrapping a number.
                Text(pattern.rhythm)
                    .noctisFont(12, .medium, relativeTo: .caption)
                    .foregroundStyle(isSelected ? NoctisNight.night.opacity(0.7) : NoctisNight.ivory2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? NoctisNight.night : NoctisNight.ivory)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isSelected ? NoctisNight.ivory : NoctisNight.ivory.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pattern.title)
        .accessibilityValue(BreathingCopy.spokenSummary(pattern))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("breathing.pattern.\(pattern.id.rawValue)")
    }
}

// MARK: - While it runs

private struct BreathingSession: View {
    let viewModel: BreathingViewModel
    let reduceMotion: Bool
    /// How full the circle is drawn: animated by the view from phase to phase, never by a timer.
    @State private var shown = 0.0

    var body: some View {
        VStack(spacing: NoctisSpacing.lg) {
            Spacer(minLength: 0)
            if reduceMotion {
                VStack(spacing: NoctisSpacing.lg) {
                    BreathingLabel(viewModel: viewModel, reduceMotion: true)
                    BreathingLevelBar(level: viewModel.level)
                }
            } else {
                ZStack {
                    BreathingDisc(level: shown).fill(NoctisNight.ivory.opacity(0.15))
                    BreathingDisc(level: shown).stroke(NoctisNight.ivory, lineWidth: 2)
                    BreathingLabel(viewModel: viewModel, reduceMotion: false)
                }
                .frame(maxWidth: 300)
                .aspectRatio(1, contentMode: .fit)
            }
            Spacer(minLength: 0)
            Text(BreathingCopy.remaining(viewModel.remaining))
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(NoctisNight.ivory2)
                .accessibilityLabel(BreathingCopy.remainingSpoken(viewModel.remaining))
                .accessibilityIdentifier("breathing.remaining")
            HStack(spacing: NoctisSpacing.sm) {
                NightPill(
                    title: viewModel.state == .paused ? BreathingCopy.resume : BreathingCopy.pause,
                    symbol: viewModel.state == .paused ? "play.fill" : "pause.fill", identifier: "breathing.pause"
                ) {
                    viewModel.state == .paused ? viewModel.resume() : viewModel.pause()
                }
                NightPill(title: BreathingCopy.end, symbol: nil, identifier: "breathing.end") { viewModel.end() }
            }
            .padding(.bottom, NoctisSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .onAppear { apply(viewModel.ring) }
        .onChange(of: viewModel.ring) { _, ring in apply(ring) }
    }

    /// A phase begins: grow or shrink to its end over exactly the time it has left. The curve is the
    /// scheduler's own (a smoothstep), so a circle caught up mid-phase and the numbers agree.
    private func apply(_ ring: BreathingRing) {
        let curve = Animation.timingCurve(1.0 / 3.0, 0, 2.0 / 3.0, 1, duration: max(ring.duration, 0.01))
        if ring.jumped || ring.duration <= 0 {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { shown = ring.level }
            guard ring.duration > 0, ring.target != ring.level else { return }
            // One turn later, so the circle is drawn where it is before it starts to move.
            Task { @MainActor in
                withAnimation(curve) { shown = ring.target }
            }
        } else {
            withAnimation(curve) { shown = ring.target }
        }
    }
}

/// "Inhale" and the seconds of the phase counting down.
private struct BreathingLabel: View {
    let viewModel: BreathingViewModel
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(viewModel.phaseName ?? "")
                .noctisFont(26, .semibold, relativeTo: .title2)
                .foregroundStyle(NoctisNight.ivory)
            NoctisMetric(NoctisMetricValue(parts: [.number("\(viewModel.countdown)")], spoken: "\(viewModel.countdown)"), size: 44, tone: .nightPanel)
                .contentTransition(.numericText(countsDown: true))
                .animation(reduceMotion ? nil : NoctisMotion.settle, value: viewModel.countdown)
        }
        // The words sit inside a circle that shrinks to a fixed size at the end of an exhale: they stop growing at xxxLarge (QA-148, SE AX3), and
        // VoiceOver reads the phase and the count whatever the size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.state == .paused ? "Paused" : BreathingCopy.title)
        .accessibilityValue("\(viewModel.phaseName ?? ""), \(viewModel.countdown)")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("breathing.phase")
    }
}

/// Reduce Motion's circle: how full the lungs are, as a bar that steps once a second.
private struct BreathingLevelBar: View {
    let level: Double

    var body: some View {
        Capsule()
            .fill(NoctisNight.ivory.opacity(0.15))
            .frame(height: 20)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(NoctisNight.ivory)
                    .scaleEffect(x: max(level, 0.001), y: 1, anchor: .leading)
            }
            .clipShape(Capsule())
            .overlay(Capsule().stroke(NoctisNight.ivory, lineWidth: 2))
            .frame(maxWidth: 300)
            .animation(nil, value: level)
            .accessibilityHidden(true)
            .accessibilityIdentifier("breathing.bar")
    }
}

/// The breathing circle: a disc whose radius follows `level` (0 the smallest, 1 the largest).
nonisolated struct BreathingDisc: Shape {
    var level: Double
    static let smallest = 0.5

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let radius = side / 2 * (Self.smallest + (1 - Self.smallest) * min(max(level, 0), 1))
        return Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
    }
}

// MARK: - The end

private struct BreathingFinished: View {
    let viewModel: BreathingViewModel

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            Spacer()
            Text(BreathingCopy.finishedTitle)
                .noctisFont(34, .bold, relativeTo: .largeTitle)
                .foregroundStyle(NoctisNight.ivory)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("breathing.finished")
            if let pattern = viewModel.finishedPattern {
                Text(BreathingCopy.finishedLine(pattern: pattern, minutes: viewModel.finishedMinutes))
                    .noctisFont(17, relativeTo: .body)
                    .foregroundStyle(NoctisNight.ivory2)
            }
            Spacer()
            NightPrimaryButton(title: BreathingCopy.again, symbol: "arrow.clockwise") { viewModel.begin() }
                .accessibilityIdentifier("breathing.again")
                .padding(.bottom, NoctisSpacing.md)
        }
        .frame(maxWidth: .infinity)
    }
}
