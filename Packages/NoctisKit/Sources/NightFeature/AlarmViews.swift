import DesignSystem
import HomeFeature
import NightKit
import SwiftUI

// The wake alarm on Tonight: a card with the time, a toggle, the repeat days and a state chip,
// and the sheet it opens. "Alarm" is the word: it rings at the time that was set, and the
// copy claims nothing more (APP_RULES.md R30).

/// The card. Its toggle turns the alarm on or off; the rest of it opens the sheet. When alarms
/// are unavailable the card gives way to a note.
struct AlarmCardView: View {
    let viewModel: TonightViewModel

    var body: some View {
        if let card = viewModel.alarmCard {
            switch card.kind {
            case .unavailable:
                AlarmNoteCard(message: card.message ?? AlarmBuilder.unavailableMessage)
            case .normal, .permissionDenied, .error:
                AlarmCard(card: card, viewModel: viewModel)
            }
        }
    }
}

private struct AlarmCard: View {
    let card: AlarmCardContent
    let viewModel: TonightViewModel

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack {
                    NoctisCaption("ALARM", style: .noctisInk3)
                    Spacer(minLength: 0)
                    AlarmChipView(chip: card.chip)
                }
                HStack(alignment: .center, spacing: NoctisSpacing.sm) {
                    Button {
                        viewModel.openSheet()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            NoctisMetric(card.time, size: 44)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(card.repeatSummary)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(.noctisInk2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(card.accessibilityLabel)
                    .accessibilityHint("Opens the alarm.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("tonight.alarmCard")
                    Toggle(
                        "Alarm",
                        isOn: Binding(
                            get: { card.isOn },
                            set: { on in Task { await viewModel.setAlarm(on: on) } }
                        )
                    )
                    .labelsHidden()
                    .frame(minWidth: 52, minHeight: 44)
                    .disabled(viewModel.isWorking)
                    .accessibilityLabel("Alarm")
                    .accessibilityIdentifier("tonight.alarmToggle")
                }
                if let message = card.message {
                    AlarmMessage(card: card, message: message, viewModel: viewModel)
                }
            }
        }
    }
}

/// The calm sentence for permission and errors, with the one thing that helps.
struct AlarmMessage: View {
    let card: AlarmCardContent
    let message: String
    let viewModel: TonightViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            Text(message)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(.noctisInk2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("alarm.message")
            switch card.kind {
            case .permissionDenied:
                NoctisCTA("Open Settings", icon: "arrow.up.forward", adaptive: true) { viewModel.openSettings() }
                    .accessibilityIdentifier("alarm.openSettings")
            case .error:
                NoctisCTA("Try again", icon: "arrow.clockwise", adaptive: true) { Task { await viewModel.retry() } }
                    .accessibilityIdentifier("alarm.retry")
            case .normal, .unavailable:
                EmptyView()
            }
        }
    }
}

struct AlarmChipView: View {
    let chip: AlarmChip

    var body: some View {
        Text(chip.text)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .foregroundStyle(ink)
            .padding(.horizontal, NoctisSpacing.sm)
            .padding(.vertical, 6)
            .background(fill, in: Capsule())
            .accessibilityHidden(true)
            .accessibilityIdentifier("tonight.alarmChip")
    }

    private var ink: Color {
        switch chip.tone {
        case .on: NoctisAppColor.blockInk
        case .off: NoctisAppColor.ink2
        case .attention: NoctisAppColor.blockInk
        }
    }

    private var fill: Color {
        switch chip.tone {
        case .on: NoctisAppColor.blockLavender
        case .off: NoctisAppColor.ringTrack
        case .attention: NoctisAppColor.blockButter
        }
    }
}

/// Where the card would be on a system that can't schedule alarms.
struct AlarmNoteCard: View {
    let message: String

    var body: some View {
        NoctisAppCard {
            HStack(spacing: NoctisSpacing.sm) {
                NoctisIconTile(systemImage: "alarm", fill: NoctisAppColor.ringTrack, foreground: NoctisAppColor.ink2, size: 40)
                Text(message)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tonight.alarmUnavailable")
    }
}

// MARK: - The sheet

/// The alarm's sheet: a wheel for the time, the days, a snooze, and the one honest line.
/// Permission is explained here before the system asks, once.
struct AlarmSheet: View {
    @Bindable var viewModel: TonightViewModel
    @Environment(\.dismiss) private var dismiss
    /// Whether anything is scrolled under the bottom stack: the paper fade shows only then (R14).
    @State private var contentBelow = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    if let card = viewModel.alarmCard, card.kind == .permissionDenied || card.kind == .unavailable, let message = card.message {
                        // Nothing can be set: say why, and the one thing that helps, and stop there.
                        NoctisAppCard { AlarmMessage(card: card, message: message, viewModel: viewModel) }
                    } else {
                        if let card = viewModel.alarmCard, card.kind == .error, let message = card.message {
                            NoctisAppCard { AlarmMessage(card: card, message: message, viewModel: viewModel) }
                        } else if viewModel.explainsPermission {
                            NoctisAppCard {
                                Text(AlarmBuilder.permissionExplanation)
                                    .noctisFont(15, relativeTo: .subheadline)
                                    .foregroundStyle(.noctisInk2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityIdentifier("alarm.explanation")
                        }
                        NoctisAppCard {
                            DatePicker("Alarm time", selection: $viewModel.draftTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("alarm.picker")
                        }
                        NoctisAppCard { AlarmRepeatRow(viewModel: viewModel) }
                        NoctisAppCard { AlarmSnoozeRow(viewModel: viewModel) }
                    }
                }
                .padding(.horizontal, NoctisSpacing.lg)
                .padding(.top, NoctisSpacing.xs)
                .padding(.bottom, NoctisSpacing.xl)
            }
            .scrollClipDisabled()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height + geometry.contentInsets.bottom - 1
            } action: { _, below in
                contentBelow = below
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground(adaptive: true).ignoresSafeArea())
            .navigationTitle("Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("alarm.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) { AlarmSheetActions(viewModel: viewModel, showsFade: contentBelow) }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("alarm.sheet")
    }
}

/// The days it repeats: seven 44pt circles, Monday first, and a line saying what they add up to.
private struct AlarmRepeatRow: View {
    @Bindable var viewModel: TonightViewModel
    let format = HomeFormat(calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            HStack {
                NoctisCaption("REPEAT", style: .noctisInk3)
                Spacer(minLength: 0)
                Text(AlarmBuilder.repeatSummary(viewModel.draft.repeatDays, format: format))
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
                    .accessibilityIdentifier("alarm.repeatSummary")
            }
            HStack(spacing: NoctisSpacing.xxs) {
                ForEach(AlarmWeekday.mondayFirst, id: \.self) { day in
                    AlarmDayButton(
                        day: day, isOn: viewModel.draft.repeatDays.contains(day), initial: AlarmBuilder.dayName(day, width: .narrow, format: format),
                        name: AlarmBuilder.dayName(day, width: .wide, format: format)
                    ) {
                        if viewModel.draft.repeatDays.contains(day) {
                            viewModel.draft.repeatDays.remove(day)
                        } else {
                            viewModel.draft.repeatDays.insert(day)
                        }
                        NoctisHaptics.selection()
                    }
                }
            }
        }
    }
}

private struct AlarmDayButton: View {
    let day: AlarmWeekday
    let isOn: Bool
    let initial: String
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(initial)
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(isOn ? NoctisAppColor.ctaLabel : NoctisAppColor.ink)
                .frame(minWidth: 40, maxWidth: .infinity, minHeight: 44)
                .background(isOn ? NoctisAppColor.ctaFill : NoctisAppColor.ringTrack.opacity(0.6), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("alarm.day.\(day.rawValue)")
    }
}

/// Snooze: off unless chosen, and then 5, 9 or 10 minutes.
private struct AlarmSnoozeRow: View {
    @Bindable var viewModel: TonightViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            Toggle(isOn: $viewModel.draft.snoozeEnabled) {
                Text("Snooze")
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("alarm.snoozeToggle")
            if viewModel.draft.snoozeEnabled {
                Picker("Snooze length", selection: $viewModel.draft.snoozeMinutes) {
                    ForEach(AlarmSettings.snoozeChoices, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("alarm.snoozeMinutes")
                .transition(.opacity)
            }
        }
        .animation(NoctisMotion.flow, value: viewModel.draft.snoozeEnabled)
    }
}

/// What the sheet offers at its foot, pinned over a paper fade (R10, R14): the one honest line,
/// then turn the alarm on, or save it and turn it off.
private struct AlarmSheetActions: View {
    let viewModel: TonightViewModel
    let showsFade: Bool

    var body: some View {
        VStack(spacing: NoctisSpacing.xs) {
            // The claim is made only where it can be kept: not when nothing can be scheduled.
            if viewModel.alarmCard.map({ $0.kind == .normal }) ?? true {
                Text(AlarmBuilder.honestyLine)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("alarm.honesty")
            }
            switch viewModel.alarmCard?.kind {
            case .unavailable, .permissionDenied:
                EmptyView()
            default:
                if viewModel.alarm?.isOn == true {
                    NoctisCTA("Save changes", isLoading: viewModel.isWorking, icon: "checkmark", adaptive: true) {
                        Task { await viewModel.save() }
                    }
                    .disabled(!viewModel.hasChanges)
                    .opacity(viewModel.hasChanges ? 1 : 0.5)
                    .accessibilityIdentifier("alarm.save")
                    NoctisTextButton("Turn off alarm", adaptive: true) { Task { await viewModel.turnOff() } }
                        .accessibilityIdentifier("alarm.turnOff")
                } else {
                    NoctisCTA(viewModel.explainsPermission ? "Continue" : "Turn on alarm", isLoading: viewModel.isWorking, icon: "alarm", adaptive: true) {
                        Task { await viewModel.turnOn() }
                    }
                    .accessibilityIdentifier("alarm.turnOn")
                }
            }
        }
        .padding(.horizontal, NoctisSpacing.lg)
        .padding(.top, NoctisSpacing.xs)
        .padding(.bottom, NoctisSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            NoctisAppColor.bg
                .overlay(alignment: .top) {
                    LinearGradient(colors: [NoctisAppColor.bg.opacity(0), NoctisAppColor.bg], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                        .offset(y: -24)
                        .opacity(showsFade ? 1 : 0)
                }
        }
    }
}
