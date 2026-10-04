import DesignSystem
import NightKit
import SoundKit
import SwiftUI

/// Meditation, opened over the wind-down's night (APP_RULES.md R34). Before it begins, a kind, a length and
/// two optional extras (the lines read aloud, a quiet sound underneath); while it runs, a slow ring that
/// fills once over the session, the time left in it, and one calm line at a time that fades into the
/// next. Quiet mind has no lines at all. Leaving it ends it.
struct MeditationPanel: View {
    let viewModel: MeditationViewModel
    let reduceMotion: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch viewModel.state {
            case .setup:
                MeditationSetup(viewModel: viewModel)
                    .transition(.opacity)
            case .running, .paused:
                MeditationSession(viewModel: viewModel, reduceMotion: reduceMotion)
                    .transition(.opacity)
            case .finished:
                MeditationFinished(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.3), reduceMotion: reduceMotion), value: viewModel.state)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.sceneBecameActive() }
        }
        .onDisappear { viewModel.leave() }
        .accessibilityIdentifier("meditation.panel")
    }
}

// MARK: - Before beginning

private struct MeditationSetup: View {
    let viewModel: MeditationViewModel

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.lg) {
                    Text(MeditationCopy.line)
                        .noctisFont(17, relativeTo: .body)
                        .foregroundStyle(NoctisNight.ivory2)
                        .accessibilityIdentifier("meditation.line")
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        NightCaption(MeditationCopy.categoryCaption)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: NoctisSpacing.xs), GridItem(.flexible(), spacing: NoctisSpacing.xs)], spacing: NoctisSpacing.xs) {
                            ForEach(MeditationCategory.allCases) { category in
                                MeditationCategoryTile(category: category, isSelected: viewModel.categoryID == category) {
                                    viewModel.choose(category: category)
                                    NoctisHaptics.selection()
                                }
                            }
                        }
                        Text(MeditationCopy.summary(viewModel.categoryID))
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(NoctisNight.ivory2)
                            .accessibilityIdentifier("meditation.summary")
                    }
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        NightCaption(MeditationCopy.durationCaption)
                        HStack(spacing: NoctisSpacing.xs) {
                            ForEach(MeditationSchedule.durations, id: \.self) { minutes in
                                NightChip(title: "\(minutes) min", isSelected: viewModel.minutes == minutes, identifier: "meditation.minutes.\(minutes)") {
                                    viewModel.choose(minutes: minutes)
                                    NoctisHaptics.selection()
                                }
                            }
                        }
                    }
                    if viewModel.canSpeak {
                        Toggle(isOn: Binding(get: { viewModel.spokenOn }, set: { viewModel.setSpoken($0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MeditationCopy.spokenTitle)
                                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                                    .foregroundStyle(NoctisNight.ivory)
                                Text(MeditationCopy.spokenNote)
                                    .noctisFont(13, relativeTo: .footnote)
                                    .foregroundStyle(NoctisNight.ivory2)
                            }
                        }
                        .tint(NoctisNight.lavender)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("meditation.spoken")
                    }
                    if viewModel.offersSound {
                        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                            NightCaption(MeditationCopy.soundCaption)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: NoctisSpacing.xs) {
                                    NightChip(title: MeditationCopy.noSound, isSelected: viewModel.sound == nil, identifier: "meditation.sound.none") {
                                        viewModel.choose(sound: nil)
                                        NoctisHaptics.selection()
                                    }
                                    ForEach(SoundKind.allCases, id: \.self) { kind in
                                        NightChip(title: kind.title, isSelected: viewModel.sound == kind, identifier: "meditation.sound.\(kind.rawValue)") {
                                            viewModel.choose(sound: kind)
                                            NoctisHaptics.selection()
                                        }
                                    }
                                }
                                .padding(.horizontal, NoctisSpacing.lg)
                            }
                            .scrollClipDisabled()
                            .padding(.horizontal, -NoctisSpacing.lg)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NoctisSpacing.lg)
                .padding(.bottom, NoctisSpacing.md)
            }
            // The scroll view reaches the screen's edges (its content keeps the margins), so nothing at
            // the content's edge, like a switch, is cut off by the scroll view's own bounds.
            .padding(.horizontal, -NoctisSpacing.lg)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            NightPrimaryButton(title: MeditationCopy.begin, symbol: "figure.mind.and.body") { viewModel.begin() }
                .accessibilityIdentifier("meditation.begin")
                .padding(.bottom, NoctisSpacing.md)
        }
    }
}

/// A kind of meditation: a symbol and its name. 56pt, flat.
private struct MeditationCategoryTile: View {
    let category: MeditationCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NoctisSpacing.sm) {
                Image(systemName: MeditationCopy.symbol(category))
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(MeditationCopy.title(category))
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? NoctisNight.night : NoctisNight.ivory)
            .padding(.horizontal, NoctisSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isSelected ? NoctisNight.ivory : NoctisNight.ivory.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MeditationCopy.title(category))
        .accessibilityHint(MeditationCopy.summary(category))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("meditation.category.\(category.rawValue)")
    }
}

// MARK: - While it runs

private struct MeditationSession: View {
    let viewModel: MeditationViewModel
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: NoctisSpacing.lg) {
            // The line, or for Quiet mind its name: always the same room, so the ring never moves.
            ZStack {
                if viewModel.categoryID.hasLines {
                    if let line = viewModel.line, let key = viewModel.lineKey {
                        Text(line)
                            .noctisFont(24, .semibold, relativeTo: .title2)
                            .foregroundStyle(NoctisNight.ivory)
                            .multilineTextAlignment(.center)
                            .id(key)
                            .transition(.opacity)
                            .accessibilityIdentifier("meditation.guidance")
                    }
                } else {
                    Text(MeditationCopy.title(viewModel.categoryID))
                        .noctisFont(17, .medium, relativeTo: .body)
                        .foregroundStyle(NoctisNight.ivory2)
                        .accessibilityIdentifier("meditation.quiet")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .animation(reduceMotion ? NoctisMotion.reduced : .easeInOut(duration: 0.9), value: viewModel.lineKey)
            Spacer(minLength: 0)
            ZStack {
                Circle().inset(by: 4).stroke(NoctisNight.ivory.opacity(0.15), lineWidth: 6)
                if viewModel.progress > 0 {
                    MeditationArc(progress: viewModel.progress)
                        .stroke(NoctisNight.ivory, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
                VStack(spacing: 2) {
                    NoctisMetric(WindDownCountdown.metric(remaining: viewModel.remaining), size: 44, tone: .nightPanel)
                        .contentTransition(.numericText(countsDown: true))
                    if viewModel.state == .paused {
                        Text("Paused")
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisNight.lavender)
                    }
                }
            }
            .frame(maxWidth: 260)
            .aspectRatio(1, contentMode: .fit)
            // One second of ring at a time: a straight line from one second to the next, no timer drawing it.
            .animation(reduceMotion ? nil : .linear(duration: 1), value: viewModel.progress)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.state == .paused ? "Paused" : MeditationCopy.title)
            .accessibilityValue(WindDownCountdown.metric(remaining: viewModel.remaining).spoken)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("meditation.ring")
            Spacer(minLength: 0)
            HStack(spacing: NoctisSpacing.sm) {
                NightPill(
                    title: viewModel.state == .paused ? MeditationCopy.resume : MeditationCopy.pause,
                    symbol: viewModel.state == .paused ? "play.fill" : "pause.fill", identifier: "meditation.pause"
                ) {
                    viewModel.state == .paused ? viewModel.resume() : viewModel.pause()
                }
                NightPill(title: MeditationCopy.end, symbol: nil, identifier: "meditation.end") { viewModel.end() }
            }
            .padding(.bottom, NoctisSpacing.md)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The ring's arc: from the top, clockwise, as far as `progress` (0...1).
nonisolated struct MeditationArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2 - 4
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * min(max(progress, 0), 1)), clockwise: false
        )
        return path
    }
}

// MARK: - The end

private struct MeditationFinished: View {
    let viewModel: MeditationViewModel

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            Spacer()
            Text(MeditationCopy.finishedTitle)
                .noctisFont(34, .bold, relativeTo: .largeTitle)
                .foregroundStyle(NoctisNight.ivory)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("meditation.finished")
            if let category = viewModel.finishedCategory {
                Text(MeditationCopy.finishedLine(category: category, minutes: viewModel.finishedMinutes))
                    .noctisFont(17, relativeTo: .body)
                    .foregroundStyle(NoctisNight.ivory2)
            }
            Spacer()
            NightPrimaryButton(title: MeditationCopy.again, symbol: "arrow.clockwise") { viewModel.begin() }
                .accessibilityIdentifier("meditation.again")
                .padding(.bottom, NoctisSpacing.md)
        }
        .frame(maxWidth: .infinity)
    }
}
