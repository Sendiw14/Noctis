import DesignSystem
import HomeFeature
import NightKit
import NoctisCore
import SwiftUI

/// Tonight, pushed over Home: when to go to bed, why that time, and the wake alarm. It reads
/// only `TonightViewModel` (APP_RULES.md R20, R30).
public struct TonightScreen: View {
    let viewModel: TonightViewModel
    /// Breathing and Reflect are free (APP_RULES.md R57), so they open from here as well as from inside a wind-down, which is Premium.
    let breathing: BreathingViewModel
    let journal: JournalViewModel
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.featureGate) private var gate
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var activity: WindDownActivity?

    public init(viewModel: TonightViewModel, breathing: BreathingViewModel, journal: JournalViewModel) {
        self.viewModel = viewModel
        self.breathing = breathing
        self.journal = journal
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
                TonightSections(content: content, viewModel: viewModel, open: { activity = $0 })
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
        .onChange(of: gate.tier) { Task { await viewModel.tierChanged() } }
        .onChange(of: model.alarmDestination) { _, destination in
            if destination != nil, model.takeAlarmDestination() != nil { viewModel.openSheet() }
        }
        .sheet(isPresented: $viewModel.isSheetPresented) {
            AlarmSheet(viewModel: viewModel)
        }
        .fullScreenCover(item: $activity) { item in
            WindDownActivityHost(progress: 0.4, reduceMotion: reduceMotion, title: item.title, backTitle: "Tonight", backLabel: "Back to Tonight") {
                switch item {
                case .breathing: BreathingPanel(viewModel: breathing, reduceMotion: reduceMotion)
                case .reflect: ReflectPanel(viewModel: journal, reduceMotion: reduceMotion)
                case .sounds, .meditation: EmptyView()
                }
            }
        }
        .accessibilityIdentifier("tonight.screen")
    }
}

/// The page's cards, in order: the bedtime, why (Premium; the free plan has one card saying what Premium adds), the button, the alarm, the sounds.
private struct TonightSections: View {
    let content: TonightContent
    let viewModel: TonightViewModel
    let open: (WindDownActivity) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            TonightHeroCard(content: content)
                .noctisRise(index: 0)
            if content.isPersonalized {
                TonightWhyCard(content: content)
                    .noctisRise(index: 1)
            } else if let card = LockedCopy.card(for: .tonightWindow) {
                LockedCard(
                    systemImage: "moon.stars", title: card.title, line: card.line, identifier: "tonight.locked",
                    action: { model.presentPaywall(.tonightWindow) }
                )
                .noctisRise(index: 1)
            }
            let locked = viewModel.windDownLocked
            NoctisCTA("Start wind-down", icon: locked ? "lock.fill" : "arrow.right", adaptive: true) {
                if locked { model.presentPaywall(.windDown) } else { model.push(.windDown(autostart: false)) }
            }
            .accessibilityIdentifier("tonight.windDown")
            .accessibilityHint(locked ? "Premium. Opens what Premium includes." : "Opens Wind-down.")
            .noctisRise(index: 2)
            AlarmCardView(viewModel: viewModel)
                .noctisRise(index: 3)
            TonightLinkRow(
                symbol: "speaker.wave.2", fill: NoctisAppColor.blockLavender, title: "Sleep sounds", hint: "Opens Sleep sounds.", identifier: "tonight.sounds"
            ) { model.open(.sounds) }
                .noctisRise(index: 4)
            TonightLinkRow(
                symbol: "wind", fill: NoctisAppColor.blockSage, title: WindDownActivity.breathing.title, hint: "Opens Breathing.", identifier: "tonight.breathing"
            ) { open(.breathing) }
                .noctisRise(index: 5)
            TonightLinkRow(
                symbol: "square.and.pencil", fill: NoctisAppColor.blockButter, title: WindDownActivity.reflect.title, hint: "Opens Reflect.", identifier: "tonight.reflect"
            ) { open(.reflect) }
                .noctisRise(index: 6)
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

/// A card that is one line: an icon tile, a name and a chevron. Sleep sounds, Breathing and Reflect, all free.
struct TonightLinkRow: View {
    let symbol: String
    let fill: Color
    let title: String
    let hint: String
    let identifier: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            NoctisAppCard {
                HStack(spacing: NoctisSpacing.sm) {
                    NoctisIconTile(systemImage: symbol, fill: fill, foreground: NoctisAppColor.blockInk, size: 40)
                    Text(title)
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
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
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
