import DesignSystem
import HomeFeature
import NightKit
import NoctisCore
import SoundKit
import SwiftUI

/// What can be opened from the session, over the same night.
enum WindDownActivity: String, Identifiable, CaseIterable {
    case sounds
    case breathing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sounds: "Sounds"
        case .breathing: BreathingCopy.title
        }
    }
}

/// Wind-down: full screen, no scaffold, the one place the app goes dark on purpose (APP_RULES.md
/// R32). Before it begins, the length, an optional sound and "Begin"; while it runs, the sky moves
/// with progress and the controls fall away; at the end, "Sleep well."
public struct WindDownScreen: View {
    let autostart: Bool
    let viewModel: WindDownViewModel
    let sounds: SoundsViewModel
    let breathing: BreathingViewModel
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var activity: WindDownActivity?

    public init(autostart: Bool, viewModel: WindDownViewModel, sounds: SoundsViewModel, breathing: BreathingViewModel) {
        self.autostart = autostart
        self.viewModel = viewModel
        self.sounds = sounds
        self.breathing = breathing
    }

    private var reduceMotion: Bool { viewModel.reducedMotionOverride ?? systemReduceMotion }

    /// Under Reduce Motion the sky shows five checkpoints and nothing between.
    private var displayProgress: Double {
        reduceMotion ? WindDownVisuals.checkpoint(viewModel.progress) : viewModel.progress
    }

    public var body: some View {
        ZStack {
            WindDownScene(progress: displayProgress)
                // Each checkpoint is its own scene: a plain 0.2 s fade, no travel.
                .id(reduceMotion ? displayProgress : -1)
                .transition(.opacity)
            content
        }
        .background(NoctisNight.sky(WindDownVisuals.background(displayProgress)).ignoresSafeArea())
        .animation(reduceMotion ? NoctisMotion.reduced : nil, value: displayProgress)
        .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.45), reduceMotion: reduceMotion), value: viewModel.state)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .task {
            viewModel.prepare(autostart: autostart)
            #if DEBUG
            if let opening = viewModel.debugOpensActivity {
                viewModel.debugOpensActivity = nil
                activity = opening
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.sceneBecameActive() }
        }
        .onChange(of: viewModel.state) { _, state in
            // It is over: whatever was open over it closes.
            if state == .ending || state == .finished { activity = nil }
        }
        .fullScreenCover(item: $activity) { item in
            WindDownActivityHost(progress: displayProgress, reduceMotion: reduceMotion, title: item.title) {
                switch item {
                case .sounds: WindDownSoundsPanel(sounds: sounds)
                case .breathing: BreathingPanel(viewModel: breathing, reduceMotion: reduceMotion)
                }
            }
        }
        .accessibilityIdentifier("windDown.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            WindDownPreStart(viewModel: viewModel, dismiss: { dismiss() })
                .transition(.opacity)
        case .running, .paused:
            WindDownSession(viewModel: viewModel, sounds: sounds, reduceMotion: reduceMotion, open: { activity = $0 })
                .transition(.opacity)
        case .ending:
            Color.clear
        case .finished:
            WindDownFinish(viewModel: viewModel, setAlarm: {
                viewModel.done()
                appModel.open(.alarm)
            }, done: {
                viewModel.done()
                appModel.open(.home)
            })
            .transition(.opacity)
        }
    }
}

// MARK: - The words at the top

private struct WindDownHeader: View {
    let line: String

    var body: some View {
        VStack(spacing: 6) {
            Text(WindDownCopy.title)
                .noctisFont(30, .bold, relativeTo: .largeTitle)
                .foregroundStyle(NoctisNight.ivory)
                .accessibilityAddTraits(.isHeader)
            Text(line)
                .noctisFont(17, relativeTo: .body)
                .foregroundStyle(NoctisNight.ivory2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, NoctisSpacing.xl)
    }
}

// MARK: - Before beginning

private struct WindDownPreStart: View {
    let viewModel: WindDownViewModel
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: NoctisSpacing.lg) {
            WindDownHeader(line: WindDownCopy.preStartLine)
            Spacer(minLength: NoctisSpacing.xl)
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                NightCaption("HOW LONG")
                HStack(spacing: NoctisSpacing.xs) {
                    ForEach(WindDownClock.options, id: \.self) { minutes in
                        NightChip(title: "\(minutes) min", isSelected: viewModel.plannedMinutes == minutes, identifier: "windDown.chip.\(minutes)") {
                            viewModel.choose(minutes: minutes)
                            NoctisHaptics.selection()
                        }
                    }
                }
                NightCaption("SOUND, IF YOU LIKE")
                    .padding(.top, NoctisSpacing.xs)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NoctisSpacing.xs) {
                        NightChip(title: "None", isSelected: viewModel.sound == nil, identifier: "windDown.sound.none") {
                            viewModel.choose(sound: nil)
                            NoctisHaptics.selection()
                        }
                        ForEach(SoundKind.allCases, id: \.self) { kind in
                            NightChip(title: kind.title, isSelected: viewModel.sound == kind, identifier: "windDown.sound.\(kind.rawValue)") {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: NoctisSpacing.lg)
            VStack(spacing: NoctisSpacing.xs) {
                NightPrimaryButton(title: WindDownCopy.begin, symbol: "moon.stars") { viewModel.begin() }
                    .accessibilityIdentifier("windDown.begin")
                NightQuietButton(title: WindDownCopy.notNow, action: dismiss)
                    .accessibilityIdentifier("windDown.notNow")
            }
            .padding(.bottom, NoctisSpacing.md)
        }
        .padding(.horizontal, NoctisSpacing.lg)
    }
}

// MARK: - The session

private struct WindDownSession: View {
    let viewModel: WindDownViewModel
    let sounds: SoundsViewModel
    let reduceMotion: Bool
    let open: (WindDownActivity) -> Void

    private var stage: WindDownStage { viewModel.stage }
    private var soundPlaying: Bool { sounds.state.phase == .playing }

    var body: some View {
        VStack(spacing: 0) {
            WindDownHeader(line: WindDownCopy.line)
            Spacer()
            VStack(spacing: NoctisSpacing.xs) {
                NoctisMetric(viewModel.countdown, size: 64, tone: .nightPanel)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : NoctisMotion.settle, value: viewModel.countdown.plain)
                    .accessibilityLabel("Time left, \(viewModel.countdown.spoken)")
                    .accessibilityIdentifier("windDown.countdown")
                if viewModel.state == .paused {
                    Text("Paused")
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisNight.lavender)
                        .accessibilityIdentifier("windDown.paused")
                }
            }
            Spacer()
            if stage == .full {
                HStack(spacing: NoctisSpacing.lg) {
                    WindDownActionTile(symbol: "speaker.wave.2", title: WindDownActivity.sounds.title, identifier: "windDown.action.sounds") { open(.sounds) }
                    WindDownActionTile(symbol: "wind", title: WindDownActivity.breathing.title, identifier: "windDown.action.breathing") { open(.breathing) }
                }
                .transition(.opacity)
                .padding(.bottom, NoctisSpacing.lg)
            }
            WindDownControls(viewModel: viewModel, stage: stage, soundPlaying: soundPlaying)
                .padding(.bottom, NoctisSpacing.xl)
        }
        .padding(.horizontal, NoctisSpacing.lg)
        .animation(NoctisMotion.adaptive(.easeInOut(duration: WindDownStage.transitionSeconds(for: viewModel.progress)), reduceMotion: reduceMotion), value: stage)
    }
}

/// The control row, simplifying as the session goes: labelled while it is young, icons once it is
/// older, and from 60% only a small End and the sound toggle.
private struct WindDownControls: View {
    let viewModel: WindDownViewModel
    let stage: WindDownStage
    let soundPlaying: Bool

    var body: some View {
        HStack(spacing: NoctisSpacing.sm) {
            if stage == .full {
                NightPill(title: viewModel.state == .paused ? WindDownCopy.resume : WindDownCopy.pause, symbol: viewModel.state == .paused ? "play.fill" : "pause.fill", identifier: "windDown.pause") {
                    viewModel.state == .paused ? viewModel.resume() : viewModel.pause()
                }
            } else if stage == .reduced {
                NightIconButton(symbol: viewModel.state == .paused ? "play.fill" : "pause.fill", label: viewModel.state == .paused ? WindDownCopy.resume : WindDownCopy.pause, identifier: "windDown.pause") {
                    viewModel.state == .paused ? viewModel.resume() : viewModel.pause()
                }
            }
            if stage == .full {
                NightPill(title: soundPlaying ? WindDownCopy.soundOn : WindDownCopy.soundOff, symbol: soundPlaying ? "speaker.wave.2.fill" : "speaker.slash", identifier: "windDown.sound") {
                    viewModel.toggleSound()
                }
            } else {
                NightIconButton(symbol: soundPlaying ? "speaker.wave.2.fill" : "speaker.slash", label: soundPlaying ? "Turn the sound off" : "Turn the sound on", identifier: "windDown.sound") {
                    viewModel.toggleSound()
                }
            }
            if stage == .minimal {
                Button(action: { viewModel.end() }) {
                    Text(WindDownCopy.end)
                        .noctisFont(15, .medium, relativeTo: .subheadline)
                        .foregroundStyle(NoctisNight.ivory2)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, NoctisSpacing.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("windDown.end")
            } else {
                NightPill(title: WindDownCopy.end, symbol: nil, identifier: "windDown.end") { viewModel.end() }
            }
        }
    }
}

// MARK: - The end

private struct WindDownFinish: View {
    let viewModel: WindDownViewModel
    let setAlarm: () -> Void
    let done: () -> Void
    private let format = HomeFormat(calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)

    var body: some View {
        let content = WindDownFinishContent.make(alarm: viewModel.alarm) { format.clock(minutesSinceMidnight: $0) }
        VStack(spacing: NoctisSpacing.lg) {
            Spacer()
            Text(WindDownCopy.finishTitle)
                .noctisFont(44, .bold, relativeTo: .largeTitle)
                .foregroundStyle(NoctisNight.ivory)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("windDown.finish")
            if let line = content.alarmLine {
                Label(line, systemImage: "alarm")
                    .noctisFont(17, relativeTo: .body)
                    .foregroundStyle(NoctisNight.ivory2)
                    .accessibilityIdentifier("windDown.alarmLine")
            } else if content.showsSetAlarm {
                NightPill(title: WindDownCopy.setAlarm, symbol: "alarm", identifier: "windDown.setAlarm", action: setAlarm)
            }
            Spacer()
            NightPrimaryButton(title: WindDownCopy.done, symbol: "checkmark", action: done)
                .accessibilityIdentifier("windDown.done")
                .padding(.bottom, NoctisSpacing.md)
        }
        .padding(.horizontal, NoctisSpacing.lg)
    }
}

// MARK: - Over the same night

/// Something opened from the session: the same sky behind it, a way back, and the clock running on.
struct WindDownActivityHost<Content: View>: View {
    let progress: Double
    let reduceMotion: Bool
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            WindDownScene(progress: progress, backdrop: true)
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        Text(WindDownCopy.title).noctisFont(17, .medium, relativeTo: .body)
                    }
                    .foregroundStyle(NoctisNight.ivory)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to wind down")
                .accessibilityIdentifier("windDown.back")
                Text(title)
                    .noctisFont(30, .bold, relativeTo: .largeTitle)
                    .foregroundStyle(NoctisNight.ivory)
                    .accessibilityAddTraits(.isHeader)
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NoctisSpacing.lg)
            .padding(.top, NoctisSpacing.xs)
        }
        .background(NoctisNight.sky(WindDownVisuals.background(progress)).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// The sounds, in the night: six flat chips and the one playing sound's gain.
struct WindDownSoundsPanel: View {
    let sounds: SoundsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.lg) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: NoctisSpacing.sm), GridItem(.flexible(), spacing: NoctisSpacing.sm)], spacing: NoctisSpacing.sm) {
                ForEach(sounds.tiles) { tile in
                    Button { sounds.tap(tile.kind) } label: {
                        HStack(spacing: NoctisSpacing.sm) {
                            Image(systemName: tile.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text(tile.title)
                                .noctisFont(15, .semibold, relativeTo: .subheadline)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(tile.isPlaying ? NoctisNight.night : NoctisNight.ivory)
                        .padding(.horizontal, NoctisSpacing.md)
                        .frame(minHeight: 56)
                        .background(tile.isPlaying ? NoctisNight.ivory : NoctisNight.ivory.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tile.accessibilityLabel)
                    .accessibilityHint(tile.accessibilityHint)
                    .accessibilityAddTraits(tile.isPlaying ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("windDown.sounds.\(tile.kind.rawValue)")
                }
            }
            if let playing = sounds.nowPlaying {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    NightCaption("\(playing.title.uppercased()) VOLUME")
                    Slider(value: Binding(get: { Double(playing.gain) }, set: { sounds.setGain(Float($0)) }), in: 0...1)
                        .tint(NoctisNight.ivory)
                        .frame(minHeight: 44)
                        .accessibilityLabel("\(playing.title) volume")
                        .accessibilityValue(playing.gainText)
                }
            }
        }
    }
}

/// A 56pt flat tile in the action row.
private struct WindDownActionTile: View {
    let symbol: String
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(NoctisNight.ivory)
                    .frame(width: 56, height: 56)
                    .background(NoctisNight.ivory.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(title)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(NoctisNight.ivory2)
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}
