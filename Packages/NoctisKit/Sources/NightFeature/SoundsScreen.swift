import DesignSystem
import HomeFeature
import NoctisCore
import SoundKit
import SwiftUI

/// Sleep sounds, pushed over Tonight: six sounds made on the phone, a Now Playing card pinned
/// above the tab bar while one plays, and a sleep timer. It reads only `SoundsViewModel`
/// (APP_RULES.md R20, R31).
public struct SoundsScreen: View {
    let viewModel: SoundsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// Whether anything is scrolled under the pinned card: its paper fade shows only then (R14).
    @State private var contentBelow = false

    public init(viewModel: SoundsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var viewModel = viewModel
        TabScreenScaffold(
            .sleep,
            presentation: .pushed,
            header: TabScreenHeader(
                dateCaption: SoundsCopy.caption,
                title: "Sleep sounds",
                showsTitle: false,
                summary: AnyView(Text(SoundsCopy.summary).accessibilityIdentifier("sounds.summary"))
            ),
            contentTop: .overlapsField,
            scrollPosition: $scrollPosition,
            configureScroll: { scroll in
                AnyView(scroll.onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height + geometry.contentInsets.bottom - 1
                } action: { _, below in
                    contentBelow = below
                })
            }
        ) {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                SoundGrid(viewModel: viewModel)
                if viewModel.showsSleepWell {
                    Text(SoundsCopy.sleepWell)
                        .noctisFont(22, .semibold, relativeTo: .title3)
                        .foregroundStyle(NoctisAppColor.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.top, NoctisSpacing.sm)
                        .transition(.opacity)
                        .accessibilityIdentifier("sounds.sleepWell")
                }
            }
            .animation(NoctisMotion.fade, value: viewModel.showsSleepWell)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Sleep sounds")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let playing = viewModel.nowPlaying {
                NowPlayingBar(content: playing, viewModel: viewModel, showsFade: contentBelow)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(NoctisMotion.flow, value: viewModel.nowPlaying != nil)
        .sheet(isPresented: $viewModel.isTimerSheetPresented) {
            SoundTimerSheet(viewModel: viewModel)
        }
        .onAppear { viewModel.appear() }
        .onDisappear { viewModel.disappear() }
        .onChange(of: scenePhase) { _, phase in
            // Behind the lock screen nothing is looked at: the meter stops; the sound plays on.
            if phase == .active { viewModel.appear() } else { viewModel.disappear() }
        }
        .accessibilityIdentifier("sounds.screen")
    }
}

// MARK: - The grid

private struct SoundGrid: View {
    let viewModel: SoundsViewModel
    @Environment(AppModel.self) private var model

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: NoctisSpacing.md), GridItem(.flexible(), spacing: NoctisSpacing.md)], spacing: NoctisSpacing.md) {
            ForEach(Array(viewModel.tiles.enumerated()), id: \.element.id) { index, tile in
                SoundTileView(tile: tile, level: viewModel.level) {
                    // A Premium sound on the free plan opens the paywall (R58); the others play.
                    if tile.isLocked {
                        NoctisHaptics.selection()
                        model.presentPaywall(.sounds)
                    } else {
                        viewModel.tap(tile.kind)
                    }
                }
                    .noctisRise(index: index)
            }
        }
    }
}

/// A sound: a flat tile in its color and its name. The one that is playing has a 2pt cocoa border
/// and a small level indicator.
struct SoundTileView: View {
    let tile: SoundTileContent
    let level: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    HStack(alignment: .top) {
                        SoundTile(symbol: tile.symbol, tone: tile.tone, size: 56)
                        Spacer(minLength: 0)
                        if tile.isPlaying { SoundLevelGlyph(level: level) }
                        if tile.isLocked { LockGlyph(size: 14).foregroundStyle(.noctisInk3) }
                    }
                    Spacer(minLength: NoctisSpacing.xs)
                    Text(tile.title)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                        .multilineTextAlignment(.leading)
                    Text(tile.stateText ?? " ")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .opacity(tile.stateText == nil ? 0 : 1)
                }
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            }
            .overlay {
                if tile.isPlaying {
                    RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                        .strokeBorder(NoctisAppColor.cocoa, lineWidth: 2)
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
        .accessibilityHint(tile.accessibilityHint)
        .accessibilityAddTraits(tile.isPlaying ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("sounds.tile.\(tile.kind.rawValue)")
    }
}

/// A sound's icon tile: its block color, flat.
struct SoundTile: View {
    let symbol: String
    let tone: SoundTone
    let size: CGFloat

    var body: some View {
        NoctisIconTile(systemImage: symbol, fill: Self.fill(tone), foreground: Self.ink(tone), size: size)
    }

    static func fill(_ tone: SoundTone) -> Color {
        switch tone {
        case .cocoa: NoctisAppColor.blockCocoa
        case .lavender: NoctisAppColor.blockLavender
        case .sage: NoctisAppColor.blockSage
        case .butter: NoctisAppColor.blockButter
        case .orange: NoctisAppColor.coreTint
        case .apricot: NoctisAppColor.fieldApricot
        }
    }

    /// Ivory on the cocoa tile, block ink on the others (R26).
    static func ink(_ tone: SoundTone) -> Color {
        tone == .cocoa ? NoctisAppColor.nightInk : NoctisAppColor.blockInk
    }
}

/// Three small bars that follow the playing sound's level. Under Reduce Motion they stand still.
struct SoundLevelGlyph: View {
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(NoctisAppColor.cocoa)
                    .frame(width: 4, height: height(index))
            }
        }
        .frame(width: 20, height: 20, alignment: .bottom)
        .animation(reduceMotion ? nil : NoctisMotion.select, value: level)
        .accessibilityHidden(true)
    }

    private func height(_ index: Int) -> CGFloat {
        // Under Reduce Motion: a fixed, quiet glyph that says "playing". Otherwise the three bars
        // lean on the level at different amounts, so they don't move as one.
        if reduceMotion { return [8, 14, 10][index] }
        let weights: [Float] = [0.75, 1, 0.55]
        return 5 + 15 * CGFloat(min(max(level * weights[index], 0), 1))
    }
}

// MARK: - Now Playing

/// Pinned above the tab bar while a sound is loaded: its name and tile, a waveform of the real
/// level, play and pause, its gain, and the sleep timer.
struct NowPlayingBar: View {
    let content: NowPlayingContent
    let viewModel: SoundsViewModel
    let showsFade: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(spacing: NoctisSpacing.sm) {
                    SoundTile(symbol: content.symbol, tone: content.tone, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.title)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                        Text(content.stateText)
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(.noctisInk3)
                            .accessibilityIdentifier("sounds.state")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    SoundTimerButton(content: content) { viewModel.presentTimer() }
                    PlayPauseButton(content: content) { viewModel.togglePlayPause() }
                }
                SoundWaveform(bars: viewModel.bars)
                    .frame(height: 36)
                HStack(spacing: NoctisSpacing.xs) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.noctisInk3)
                        .accessibilityHidden(true)
                    Slider(
                        value: Binding(get: { Double(content.gain) }, set: { viewModel.setGain(Float($0)) }),
                        in: 0...1
                    )
                    .tint(NoctisAppColor.cocoa)
                    .frame(minHeight: 44)
                    .accessibilityLabel("\(content.title) volume")
                    .accessibilityValue(content.gainText)
                    .accessibilityIdentifier("sounds.gain")
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.noctisInk3)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, NoctisSpacing.lg)
        .padding(.top, NoctisSpacing.xs)
        .padding(.bottom, NoctisSpacing.xs)
        .background(alignment: .bottom) {
            NoctisAppColor.bg
                .overlay(alignment: .top) {
                    LinearGradient(colors: [NoctisAppColor.bg.opacity(0), NoctisAppColor.bg], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                        .offset(y: -24)
                        .opacity(showsFade ? 1 : 0)
                }
        }
        .accessibilityIdentifier("sounds.nowPlaying")
    }
}

private struct PlayPauseButton: View {
    let content: NowPlayingContent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: content.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NoctisAppColor.ctaLabel)
                .frame(width: 44, height: 44)
                .background(NoctisAppColor.ctaFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(content.playPauseLabel)
        .accessibilityIdentifier("sounds.playPause")
    }
}

private struct SoundTimerButton: View {
    let content: NowPlayingContent
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text(content.timerText)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : NoctisMotion.settle, value: content.timerText)
            }
            .foregroundStyle(NoctisAppColor.ink)
            .padding(.horizontal, NoctisSpacing.sm)
            .frame(minWidth: 44, minHeight: 44)
            .background(NoctisAppColor.ringTrack.opacity(content.timerIsRunning ? 1 : 0.6), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(content.timerLabel)
        .accessibilityHint("Opens the sleep timer.")
        .accessibilityIdentifier("sounds.timer")
    }
}

/// 24 flat cocoa bars drawn from the real RMS meter, newest on the right; no glow. Under Reduce
/// Motion, one static bar that fills to the current level.
struct SoundWaveform: View {
    let bars: [Float]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // A single level bar: the track, and the fill to where the sound is now.
                NoctisSpanLayout(to: 1) { Capsule().fill(NoctisAppColor.ringTrack).frame(height: 8) }
                    .overlay {
                        NoctisSpanLayout(to: Double(bars.last ?? 0), minimumWidth: 8) { Capsule().fill(NoctisAppColor.cocoa).frame(height: 8) }
                    }
            } else {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                        Capsule()
                            .fill(NoctisAppColor.cocoa)
                            .frame(maxWidth: .infinity)
                            .frame(height: 4 + 32 * CGFloat(value))
                    }
                }
                .animation(NoctisMotion.select, value: bars)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - The timer sheet

struct SoundTimerSheet: View {
    let viewModel: SoundsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    if let remaining = viewModel.remaining {
                        VStack(alignment: .leading, spacing: 4) {
                            NoctisCaption("TIME LEFT", style: .noctisInk3)
                            Text(SleepTimerPlan.clock(remaining))
                                .noctisFont(44, .heavy, relativeTo: .largeTitle)
                                .monospacedDigit()
                                .foregroundStyle(NoctisAppColor.ink)
                                .contentTransition(.numericText(countsDown: true))
                                .animation(reduceMotion ? nil : NoctisMotion.settle, value: SleepTimerPlan.clock(remaining))
                                .accessibilityLabel("\(SoundsBuilder.spokenRemaining(remaining)) left")
                                .accessibilityIdentifier("sounds.timer.remaining")
                        }
                        .padding(.horizontal, NoctisSpacing.xs)
                    }
                    NoctisAppCard {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.timerChoices.enumerated()), id: \.element.choice.id) { index, item in
                                if index > 0 { Rectangle().fill(NoctisAppColor.hairline).frame(height: 1) }
                                Button { viewModel.selectTimer(item.choice) } label: {
                                    HStack {
                                        Text(item.choice.title)
                                            .noctisFont(17, relativeTo: .body)
                                            .foregroundStyle(NoctisAppColor.ink)
                                        Spacer(minLength: 0)
                                        if item.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(NoctisAppColor.cocoa)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .frame(minHeight: 52)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(item.isSelected ? [.isButton, .isSelected] : .isButton)
                                .accessibilityIdentifier("sounds.timer.\(item.choice.minutes)")
                            }
                        }
                    }
                    Text(SoundsCopy.timerNote)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, NoctisSpacing.xs)
                }
                .padding(.horizontal, NoctisSpacing.lg)
                .padding(.top, NoctisSpacing.xs)
                .padding(.bottom, NoctisSpacing.xl)
            }
            .background(PaperBackground(adaptive: true).ignoresSafeArea())
            .navigationTitle(SoundsCopy.timerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("sounds.timer.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("sounds.timerSheet")
    }
}
