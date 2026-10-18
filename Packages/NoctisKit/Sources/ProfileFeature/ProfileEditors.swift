import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

/// The editor a row opens, as a sheet: Cancel and Save, nothing applied until Save.
struct ProfileEditorSheet: View {
    let sheet: ProfileViewModel.Sheet
    let viewModel: ProfileViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    private var editor: some View {
        switch sheet {
        case .name: NameEditor(viewModel: viewModel)
        case .need: RhythmEditor(kind: .need, viewModel: viewModel)
        case .wake: RhythmEditor(kind: .wake, viewModel: viewModel)
        case .goals: GoalsEditor(viewModel: viewModel)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                // At accessibility sizes the editor is taller than the sheet: it scrolls. Without that the five goal rows were squeezed to
                // their minimum height and their wrapped names overprinted each other ("Better sleep" over "More energy").
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView { editor }
                        .scrollBounceBehavior(.basedOnSize)
                } else {
                    editor
                }
            }
            .background(PaperBackground(adaptive: true).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancel() }
                        .accessibilityIdentifier("profile.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { viewModel.save() }
                        .disabled(!viewModel.hasChanges)
                        .accessibilityIdentifier("profile.editor.save")
                }
            }
        }
        .presentationDetents(sheet == .goals ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("profile.editor.\(sheet.rawValue)")
    }

    private var title: String {
        switch sheet {
        case .name: "Name"
        case .need: "Sleep need"
        case .wake: "Wake time"
        case .goals: "Goals"
        }
    }
}

// MARK: - Name

private struct NameEditor: View {
    let viewModel: ProfileViewModel
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    NoctisCaption("YOUR NAME", style: .noctisInk3)
                    TextField("Add your name", text: $viewModel.nameDraft)
                        .noctisFont(22, .semibold, relativeTo: .title3)
                        .foregroundStyle(NoctisAppColor.ink)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focused)
                        .frame(minHeight: 44)
                        .onChange(of: viewModel.nameDraft) { _, text in
                            if text.count > ProfileEdit.nameLimit { viewModel.nameDraft = String(text.prefix(ProfileEdit.nameLimit)) }
                        }
                        .onSubmit { if viewModel.hasChanges { viewModel.save() } else { viewModel.cancel() } }
                        .accessibilityIdentifier("profile.editor.nameField")
                }
            }
            Text("Optional. \(PrivacyStatements.nameStays(.shared) ?? "") It appears only on this page. To remove it, clear the field and Save.")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, NoctisSpacing.xs)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NoctisSpacing.md)
        .padding(.top, NoctisSpacing.md)
        .onAppear { focused = true }
    }
}

// MARK: - Sleep need and wake time

/// The onboarding ruler, on a card, with the bedtime it gives under it: it changes as the ruler moves.
private struct RhythmEditor: View {
    enum Kind { case need, wake }

    let kind: Kind
    let viewModel: ProfileViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var viewModel = viewModel
        let preview = viewModel.previewBedtime
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    NoctisCaption(kind == .need ? "I FEEL BEST WITH" : "I USUALLY WAKE AT", style: .noctisInk3)
                    Text(valueText)
                        .noctisNumeral(48)
                        .foregroundStyle(NoctisAppColor.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.15), reduceMotion: reduceMotion), value: kind == .need ? viewModel.needDraft : viewModel.wakeDraft)
                        .accessibilityIdentifier("profile.editor.value")
                    ruler
                        .padding(.top, NoctisSpacing.xs)
                }
            }
            VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                NoctisCaption(preview.heroCaption, style: .noctisInk3)
                NoctisMetric(preview.hero, size: 34)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.2), reduceMotion: reduceMotion), value: preview.hero.spoken)
            }
            .padding(.horizontal, NoctisSpacing.xs)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tonight's \(preview.heroCaption.lowercased()), \(preview.hero.spoken)")
            .accessibilityIdentifier("profile.editor.bedtime")
            Text("Saving moves your reminders to match. An alarm you have already set keeps its own time.")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, NoctisSpacing.xs)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NoctisSpacing.md)
        .padding(.top, NoctisSpacing.md)
    }

    private var valueText: String {
        switch kind {
        case .need: HomeFormat.compactDuration(viewModel.needDraft)
        case .wake: viewModel.clockFormat.clock(minutesSinceMidnight: viewModel.wakeDraft)
        }
    }

    @ViewBuilder
    private var ruler: some View {
        @Bindable var viewModel = viewModel
        switch kind {
        case .need:
            NoctisRulerDial(
                range: 300...600, step: 15, value: $viewModel.needDraft, hourLabel: { "\($0 / 60)h" },
                accessibilityName: "Sleep need",
                accessibilityValue: { minutes in
                    let hours = minutes / 60, rest = minutes % 60
                    return rest == 0 ? "\(hours) hours" : "\(hours) hours \(rest) minutes"
                },
                tone: .app
            )
            .accessibilityIdentifier("profile.editor.ruler")
        case .wake:
            NoctisRulerDial(
                range: 180...720, step: 5, value: $viewModel.wakeDraft,
                hourLabel: { viewModel.clockFormat.hour(minutesSinceMidnight: $0) },
                accessibilityName: "Wake time",
                accessibilityValue: { viewModel.clockFormat.clock(minutesSinceMidnight: $0) },
                minorTickMinutes: 15, pxPerMinute: 1.7, tone: .app
            )
            .accessibilityIdentifier("profile.editor.ruler")
        }
    }
}

// MARK: - Goals

private struct GoalsEditor: View {
    let viewModel: ProfileViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            Text("Choose up to two. A third replaces the first you chose.")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
                .padding(.horizontal, NoctisSpacing.xs)
            NoctisRowCard {
                ForEach(Array(PrimaryGoal.allCases.enumerated()), id: \.element) { index, goal in
                    if index > 0 { NoctisRowDivider() }
                    goalRow(goal)
                }
            }
            Text("\(viewModel.goalsDraft.count) of \(ProfileEdit.goalLimit) chosen")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
                .padding(.horizontal, NoctisSpacing.xs)
                .contentTransition(.numericText())
                .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: viewModel.goalsDraft.count)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NoctisSpacing.md)
        .padding(.top, NoctisSpacing.md)
    }

    private func goalRow(_ goal: PrimaryGoal) -> some View {
        let isSelected = viewModel.goalsDraft.contains(goal)
        return Button {
            NoctisHaptics.selection()
            withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) { viewModel.toggle(goal: goal) }
        } label: {
            NoctisRow(systemImage: goal.systemImage, fill: NoctisAppColor.blockSage, title: goal.displayName) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? NoctisAppColor.ink : NoctisAppColor.ink3)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("profile.editor.goal.\(goal.rawValue)")
    }
}
