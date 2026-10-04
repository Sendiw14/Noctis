import DesignSystem
import JournalKit
import SwiftUI

/// Reflect, opened over the wind-down's night (APP_RULES.md R35): three optional five-step scales (Energy,
/// Mood, Focus, each from Low to High), an optional note, "Skip" always in view and costing nothing, and a way
/// into the Journal. No streak, no count, no score, and nothing here is related to how the night went.
struct ReflectPanel: View {
    let viewModel: JournalViewModel
    let reduceMotion: Bool

    var body: some View {
        Group {
            if viewModel.showsJournal {
                JournalListView(viewModel: viewModel, back: { viewModel.closeJournal() }, backTitle: ReflectCopy.newEntry)
                    .transition(.opacity)
            } else {
                ReflectForm(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.3), reduceMotion: reduceMotion), value: viewModel.showsJournal)
        // Whatever was typed or read is forgotten when the screen is left, saved or not.
        .onDisappear { viewModel.leave() }
        .accessibilityIdentifier("reflect.panel")
    }
}

// MARK: - Reflecting

private struct ReflectForm: View {
    @Bindable var viewModel: JournalViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.lg) {
                    Text(ReflectCopy.line)
                        .noctisFont(17, relativeTo: .body)
                        .foregroundStyle(NoctisNight.ivory2)
                        .accessibilityIdentifier("reflect.line")
                    ForEach(JournalMeasure.allCases) { measure in
                        ReflectScale(
                            measure: measure, value: viewModel.draft.value(measure),
                            choose: { viewModel.choose($0, for: measure) },
                            step: { viewModel.step(measure, by: $0) },
                            clear: { viewModel.clear(measure) }
                        )
                    }
                    TextField(
                        ReflectCopy.notePrompt, text: $viewModel.draft.text,
                        prompt: Text(ReflectCopy.notePrompt).foregroundStyle(NoctisNight.ivory2), axis: .vertical
                    )
                    .lineLimit(3...6)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisNight.ivory)
                    .tint(NoctisNight.lavender)
                    .padding(NoctisSpacing.md)
                    .frame(minHeight: 96, alignment: .topLeading)
                    .background(NoctisNight.ivory.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onChange(of: viewModel.draft.text) { _, _ in viewModel.limitText() }
                    .accessibilityIdentifier("reflect.note")
                    if viewModel.availability == .unavailable {
                        Text(ReflectCopy.unavailable)
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(NoctisNight.ivory2)
                            .accessibilityIdentifier("reflect.unavailable")
                    }
                    NightPill(title: ReflectCopy.journal, symbol: "book.closed", identifier: "reflect.journal") { viewModel.openJournal() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NoctisSpacing.lg)
                .padding(.bottom, NoctisSpacing.md)
            }
            // The scroll view reaches the screen's edges, its content keeps the margins.
            .padding(.horizontal, -NoctisSpacing.lg)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            HStack(spacing: NoctisSpacing.sm) {
                // Always there, and it costs nothing.
                NightPill(title: ReflectCopy.skip, symbol: nil, identifier: "reflect.skip") { dismiss() }
                NightPrimaryButton(title: ReflectCopy.save, symbol: "checkmark") {
                    if viewModel.save() { dismiss() }
                }
                .disabled(!viewModel.canSave)
                .opacity(viewModel.canSave ? 1 : 0.4)
                .accessibilityIdentifier("reflect.save")
            }
            .padding(.bottom, NoctisSpacing.md)
        }
    }
}

/// One measure: five steps in a row, filled up to the one chosen, from Low to High. Each step is 44pt tall
/// and a fifth of the width; a tap on the step already chosen clears it. For VoiceOver it is one adjustable
/// element ("Energy, 3 of 5") with a Clear action.
private struct ReflectScale: View {
    let measure: JournalMeasure
    let value: Int?
    let choose: (Int) -> Void
    let step: (Int) -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(measure.title)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoctisNight.ivory)
                Spacer()
                Text(ReflectCopy.scaleValue(value))
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(NoctisNight.ivory2)
            }
            HStack(spacing: 6) {
                ForEach(JournalDraft.valueRange, id: \.self) { index in
                    Button {
                        choose(index)
                        NoctisHaptics.selection()
                    } label: {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(NoctisNight.ivory.opacity(isFilled(index) ? 1 : 0.12))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("reflect.\(measure.rawValue).\(index)")
                }
            }
            HStack {
                Text(ReflectCopy.low)
                Spacer()
                Text(ReflectCopy.high)
            }
            .noctisFont(12, relativeTo: .caption)
            .foregroundStyle(NoctisNight.ivory2)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(measure.title)
        .accessibilityValue(ReflectCopy.scaleValue(value))
        .accessibilityHint(ReflectCopy.scaleHint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: ReflectCopy.clear) { clear() }
        .accessibilityIdentifier("reflect.\(measure.rawValue)")
    }

    private func isFilled(_ index: Int) -> Bool {
        guard let value else { return false }
        return index <= value
    }
}

// MARK: - The journal

/// The journal: entries by date, newest first; a swipe reveals Delete (a second tap, so one slip never
/// deletes), and "Delete all entries" asks first and says what goes and what stays. Reusable: the Profile's
/// privacy section opens this same view.
public struct JournalListView: View {
    let viewModel: JournalViewModel
    let back: (() -> Void)?
    let backTitle: String
    @State private var confirmingDeleteAll = false

    public init(viewModel: JournalViewModel, back: (() -> Void)? = nil, backTitle: String = ReflectCopy.title) {
        self.viewModel = viewModel
        self.back = back
        self.backTitle = backTitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            if let back {
                Button(action: back) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        Text(backTitle).noctisFont(17, .medium, relativeTo: .body)
                    }
                    .foregroundStyle(NoctisNight.ivory)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journal.back")
            }
            Text(ReflectCopy.journal)
                .noctisFont(24, .semibold, relativeTo: .title2)
                .foregroundStyle(NoctisNight.ivory)
                .accessibilityAddTraits(.isHeader)
            Text(ReflectCopy.privacyLine)
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(NoctisNight.ivory2)
                .accessibilityIdentifier("journal.privacy")
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { viewModel.load() }
        .accessibilityIdentifier("journal.list")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.availability == .unavailable {
            Text(ReflectCopy.unavailable)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(NoctisNight.ivory2)
                .padding(.top, NoctisSpacing.lg)
                .accessibilityIdentifier("journal.unavailable")
            Spacer(minLength: 0)
        } else if viewModel.entries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(ReflectCopy.emptyTitle)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisNight.ivory)
                Text(ReflectCopy.emptyLine)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisNight.ivory2)
            }
            .padding(.top, NoctisSpacing.lg)
            .accessibilityIdentifier("journal.empty")
            Spacer(minLength: 0)
        } else {
            List {
                ForEach(viewModel.entries) { entry in
                    JournalRow(entry: entry)
                        .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(NoctisNight.ivory.opacity(0.08)).padding(.vertical, 3))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.delete(entry.id)
                            } label: {
                                Label(ReflectCopy.delete, systemImage: "trash")
                            }
                            .accessibilityIdentifier("journal.delete")
                        }
                        .accessibilityAction(named: ReflectCopy.delete) { viewModel.delete(entry.id) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            Button { confirmingDeleteAll = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 14, weight: .semibold)).accessibilityHidden(true)
                    Text(ReflectCopy.deleteAll).noctisFont(15, .medium, relativeTo: .subheadline)
                }
                .foregroundStyle(NoctisNight.ivory2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.bottom, NoctisSpacing.md)
            .accessibilityIdentifier("journal.deleteAll")
            // On the button itself, so the dialog is anchored to what asked for it.
            .confirmationDialog(ReflectCopy.deleteAllTitle, isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button(ReflectCopy.deleteAll, role: .destructive) { viewModel.deleteAll() }
                Button(ReflectCopy.cancel, role: .cancel) {}
            } message: {
                Text(ReflectCopy.deleteAllMessage)
            }
        }
    }
}

private struct JournalRow: View {
    let entry: JournalEntrySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(NoctisNight.ivory)
            if let values = ReflectCopy.valuesLine(entry) {
                Text(values)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(NoctisNight.ivory2)
            }
            if !entry.text.isEmpty {
                Text(entry.text)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisNight.ivory)
                    .lineLimit(4)
            }
        }
        .padding(NoctisSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("journal.row")
    }
}
