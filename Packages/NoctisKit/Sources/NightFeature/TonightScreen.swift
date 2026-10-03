import DesignSystem
import HomeFeature
import NightKit
import NoctisCore
import SwiftUI

/// Tonight, pushed over Home: when to go to bed, why that time, and the wake alarm. It reads
/// only `TonightViewModel` (APP_RULES.md R20, R30).
public struct TonightScreen: View {
    let viewModel: TonightViewModel
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(edge: .top)

    public init(viewModel: TonightViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var viewModel = viewModel
        TabScreenScaffold(
            .recovery,
            presentation: .pushed,
            header: TabScreenHeader(
                dateCaption: viewModel.content?.dateCaption ?? "",
                title: "Tonight",
                showsTitle: false,
                summary: AnyView(
                    Text(viewModel.content?.summary ?? " ")
                        .accessibilityIdentifier("tonight.summary")
                )
            ),
            contentTop: .overlapsField,
            scrollPosition: $scrollPosition
        ) {
            if let content = viewModel.content {
                TonightSections(content: content, viewModel: viewModel)
            } else {
                TonightSkeleton()
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Tonight")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // `noctis://alarm`: Tonight with the alarm's sheet open.
            if model.takeAlarmDestination() != nil { viewModel.openSheet() }
            await viewModel.onAppear()
        }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: model.alarmDestination) { _, destination in
            if destination != nil, model.takeAlarmDestination() != nil { viewModel.openSheet() }
        }
        .sheet(isPresented: $viewModel.isSheetPresented) {
            AlarmSheet(viewModel: viewModel)
        }
        .accessibilityIdentifier("tonight.screen")
    }
}

/// The page's cards, in order: the bedtime, why, the button, the alarm, the sounds.
private struct TonightSections: View {
    let content: TonightContent
    let viewModel: TonightViewModel
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            TonightHeroCard(content: content)
                .noctisRise(index: 0)
            TonightWhyCard(content: content)
                .noctisRise(index: 1)
            NoctisCTA("Start wind-down", icon: "arrow.right", adaptive: true) {
                model.open(.windDown(autostart: true))
            }
            .accessibilityIdentifier("tonight.windDown")
            .accessibilityHint("Opens Wind-down.")
            .noctisRise(index: 2)
            AlarmCardView(viewModel: viewModel)
                .noctisRise(index: 3)
            SleepSoundsRow { model.open(.sounds) }
                .noctisRise(index: 4)
        }
    }
}

// MARK: - The bedtime

/// The window (or the one bedtime) at 44pt, the wake line and the evening strip.
struct TonightHeroCard: View {
    let content: TonightContent

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption(content.heroCaption, style: .noctisInk3)
                NoctisMetric(content.hero, size: 44)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(content.wakeLine)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                if let note = content.note {
                    Text(note)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TonightStripView(strip: content.strip)
                    .padding(.vertical, NoctisSpacing.xs)
                if let confidence = content.confidence {
                    Text(confidence)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let change = content.clockChange {
                    Text(change)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tonight.clockChange")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityIdentifier("tonight.hero")
    }
}

/// 6 PM to 10 AM: a lavender span for the window, a fainter one from there to waking, and the
/// wake marker in cocoa. Drawn once; nothing here moves.
struct TonightStripView: View {
    let strip: TonightStrip

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                NoctisSpanLayout(to: 1) { Capsule().fill(NoctisAppColor.ringTrack).frame(height: 10) }
                NoctisSpanLayout(from: strip.windowEnd, to: max(strip.wake, strip.windowEnd), minimumWidth: 0) {
                    Capsule().fill(NoctisAppColor.lavender.opacity(0.3)).frame(height: 10)
                }
                NoctisSpanLayout(from: strip.windowStart, to: strip.windowEnd, minimumWidth: 10) {
                    Capsule().fill(NoctisAppColor.lavender).frame(height: 10)
                }
                NoctisFractionLayout {
                    Capsule().fill(NoctisAppColor.cocoa).frame(width: 4, height: 22)
                        .noctisFraction(strip.wake)
                }
            }
            .frame(height: 22)
            NoctisFractionLayout {
                ForEach(strip.labels, id: \.position) { label in
                    Text(label.text)
                        .noctisFont(12, .medium, relativeTo: .caption2)
                        .foregroundStyle(.noctisInk3)
                        .noctisFraction(label.position)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strip.accessibilityLabel)
        .accessibilityHidden(true)
    }
}

// MARK: - Why this time

struct TonightWhyCard: View {
    let content: TonightContent
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                Text("Why this time")
                    .noctisFont(22, .bold, relativeTo: .title3)
                    .foregroundStyle(NoctisAppColor.ink)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: NoctisSpacing.sm) {
                    ForEach(Array(content.reasons.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Rectangle().fill(NoctisAppColor.hairline).frame(height: 1) }
                        TonightReasonRowView(row: row)
                    }
                }
                Rectangle().fill(NoctisAppColor.hairline).frame(height: 1)
                Button {
                    withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) { isExpanded.toggle() }
                    NoctisHaptics.selection()
                } label: {
                    HStack {
                        Text("How this is calculated")
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.noctisInk3)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("tonight.method")
                if isExpanded {
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        ForEach(content.method, id: \.self) { paragraph in
                            Text(paragraph)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(.noctisInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .accessibilityIdentifier("tonight.why")
    }
}

struct TonightReasonRowView: View {
    let row: TonightReasonRow
    private static let tile: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
            HStack(spacing: NoctisSpacing.sm) {
                NoctisIconTile(systemImage: row.systemImage, fill: fill, foreground: NoctisAppColor.blockInk, size: Self.tile)
                Text(row.label)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NoctisMetric(row.value, size: 22, relativeTo: .title3, maxScale: 1.4, tone: .paper)
                    .multilineTextAlignment(.trailing)
                    .layoutPriority(1)
            }
            // What the fact did to the time, under the row, in the label's column.
            if let detail = row.detail {
                Text(detail)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Self.tile + NoctisSpacing.sm)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var fill: Color {
        switch row.tone {
        case .sage: NoctisAppColor.blockSage
        case .lavender: NoctisAppColor.blockLavender
        case .orange: NoctisAppColor.coreTint
        case .butter: NoctisAppColor.blockButter
        }
    }
}

// MARK: - The rest

struct SleepSoundsRow: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            NoctisAppCard {
                HStack(spacing: NoctisSpacing.sm) {
                    NoctisIconTile(systemImage: "speaker.wave.2", fill: NoctisAppColor.blockLavender, foreground: NoctisAppColor.blockInk, size: 40)
                    Text("Sleep sounds")
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.noctisInk3)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityHint("Opens Sleep sounds.")
        .accessibilityIdentifier("tonight.sounds")
    }
}

/// While tonight's bedtime is being worked out (a moment): the shapes of the two cards, quiet.
struct TonightSkeleton: View {
    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            ForEach([240.0, 300.0], id: \.self) { height in
                RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                    .fill(NoctisAppColor.ringTrack.opacity(0.5))
                    .frame(height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working out tonight's bedtime")
    }
}
