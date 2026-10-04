import CoreTransferable
import DesignSystem
import NoctisCore
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

/// The export, as something the share sheet can take: the file is made when the person picks where it goes.
struct DataExportItem: Transferable {
    let manager: DataManager

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            SentTransferredFile(try await item.manager.exportFile())
        }
    }
}

// MARK: - Data management

/// Delete what NOCTIS keeps, one kind at a time or all of it, or take a copy. Reads `DataManager` (APP_RULES.md R41, R42).
struct DataManagementView: View {
    let viewModel: SettingsViewModel
    @State private var pending: DeletableGroup?
    @State private var showsDeleteAll = false
    @State private var status: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var manager: DataManager { viewModel.data }

    var body: some View {
        SettingsPageScaffold(.dataManagement, summary: "Delete what NOCTIS keeps, or take a copy.") {
            SettingsGroup("DELETE ONE KIND AT A TIME") {
                NoctisRowCard {
                    ForEach(Array(viewModel.inventory.groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { NoctisRowDivider() }
                        row(group)
                    }
                }
                if let status {
                    SettingsNote(status).accessibilityIdentifier("data.status")
                }
            }
            .noctisRise(index: 0)
            SettingsGroup("TAKE A COPY") {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        ShareLink(item: DataExportItem(manager: manager), preview: SharePreview("NOCTIS export")) {
                            HStack(spacing: NoctisSpacing.xs) {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold))
                                Text(DataManagementCopy.exportTitle).noctisFont(17, .semibold, relativeTo: .body)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(NoctisAppColor.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("data.export")
                        .accessibilityHint("Makes a file of everything NOCTIS stores and opens the share sheet.")
                        Text(DataManagementCopy.exportNote(viewModel.inventory))
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(.noctisInk3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .noctisRise(index: 1)
            SettingsGroup("DELETE EVERYTHING") {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        Text(DataManagementCopy.deleteAllCardText)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(.noctisInk2)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(role: .destructive) {
                            NoctisHaptics.selection()
                            manager.resetDeleteAll()
                            showsDeleteAll = true
                        } label: {
                            Text(DataManagementCopy.deleteAllButton)
                                .noctisFont(17, .semibold, relativeTo: .body)
                                .foregroundStyle(NoctisAppColor.destructive)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(NoctisAppColor.destructive, lineWidth: 2))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("data.deleteAll")
                        .accessibilityHint("Asks you to confirm before deleting anything.")
                    }
                }
            }
            .noctisRise(index: 2)
            if let account = viewModel.privacy.noAccount {
                SettingsNote(account).accessibilityIdentifier("data.noAccount")
            }
        }
        .task { viewModel.refreshPrivacy() }
        .onDisappear { manager.discardExport() }
        .confirmationDialog(
            pending?.question ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending
        ) { group in
            Button(group.confirm, role: .destructive) { Task { await delete(group) } }
            Button(DataManagementCopy.cancel, role: .cancel) {}
        } message: { group in
            Text(DataManagementCopy.message(for: group))
        }
        .sheet(isPresented: $showsDeleteAll) { DeleteAllSheet(viewModel: viewModel) }
    }

    private func row(_ group: DeletableGroup) -> some View {
        let first = group.categories[0]
        return NoctisRow(systemImage: first.symbol, fill: first.fill, title: group.title, detail: manager.sizeText(for: group)) {
            Button(group.verb.rawValue) {
                NoctisHaptics.selection()
                pending = group
            }
            .buttonStyle(.plain)
            .noctisFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(NoctisAppColor.destructive)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("\(group.verb.rawValue) \(group.title)")
            .accessibilityHint("Asks you to confirm.")
            .accessibilityIdentifier("data.delete.\(group.id)")
        }
        .accessibilityIdentifier("data.row.\(group.id)")
    }

    private func delete(_ group: DeletableGroup) async {
        let report = await manager.delete(group)
        NoctisHaptics.soft()
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
            status = DataManagementCopy.result(report, group: group)
        }
        viewModel.refreshPrivacy()
    }
}

// MARK: - Delete everything

/// The one confirmation for "Delete all NOCTIS data": what goes, what does not, then the steps as they run, then "Done", which starts
/// the app over at onboarding.
struct DeleteAllSheet: View {
    let viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.restartApp) private var restart
    @State private var started = false
    @State private var showsManage = false

    private var manager: DataManager { viewModel.data }
    private var finished: Bool { manager.deleteAllReport != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    if started { progress } else { confirmation }
                }
                .padding(NoctisSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PaperBackground(adaptive: true).ignoresSafeArea())
            .navigationTitle(finished ? "Deleted" : "Delete all")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !started {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(DataManagementCopy.cancel) { dismiss() }.accessibilityIdentifier("data.deleteAll.cancel")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottom }
        }
        .interactiveDismissDisabled(started)
        .presentationDetents([.large])
        .manageSubscriptionsSheet(isPresented: $showsManage)
        .accessibilityIdentifier("data.deleteAll.sheet")
    }

    // Before: what goes, what does not.
    private var confirmation: some View {
        let removes = DataManagementCopy.deleteAllRemoves(viewModel.inventory)
        return VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            Text(DataManagementCopy.deleteAllTitle)
                .noctisFont(28, .bold, relativeTo: .title)
                .foregroundStyle(NoctisAppColor.ink)
                .accessibilityAddTraits(.isHeader)
            SettingsGroup("WHAT IS DELETED") {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        Text(removes.lead)
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                        ForEach(removes.items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.sm) {
                                Circle().fill(NoctisAppColor.ink3).frame(width: 5, height: 5).accessibilityHidden(true)
                                Text(item).noctisFont(15, relativeTo: .subheadline).foregroundStyle(NoctisAppColor.ink)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("data.deleteAll.removes")
            }
            SettingsGroup("WHAT IS NOT") {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        ForEach(DataManagementCopy.deleteAllKeeps, id: \.self) { line in
                            Text(line).noctisFont(15, relativeTo: .subheadline).foregroundStyle(NoctisAppColor.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        Button(DataManagementCopy.manageSubscription) { showsManage = true }
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.orangeText)
                            .frame(minHeight: 44, alignment: .leading)
                            .accessibilityIdentifier("data.deleteAll.manage")
                            .accessibilityHint("Opens your subscription in the App Store.")
                    }
                }
                .accessibilityIdentifier("data.deleteAll.keeps")
            }
        }
    }

    // While and after: the steps.
    private var progress: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            Text(finished ? (manager.deleteAllReport?.succeeded == true ? DataManagementCopy.deleteAllDone : DataManagementCopy.deleteAllPartial) : "Deleting")
                .noctisFont(22, .bold, relativeTo: .title3)
                .foregroundStyle(NoctisAppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("data.deleteAll.headline")
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    ForEach(Array(manager.steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.sm) {
                            symbol(step.state)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).noctisFont(15, relativeTo: .subheadline).foregroundStyle(NoctisAppColor.ink)
                                if case .failed(let message) = step.state {
                                    Text(message).noctisFont(13, relativeTo: .footnote).foregroundStyle(NoctisAppColor.destructive).fixedSize(horizontal: false, vertical: true)
                                } else if let note = manager.stepNotes[step.id] {
                                    Text(note).noctisFont(13, relativeTo: .footnote).foregroundStyle(NoctisAppColor.ink2).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .accessibilityIdentifier("data.deleteAll.steps")
        }
    }

    @ViewBuilder
    private func symbol(_ state: DataManager.StepState) -> some View {
        switch state {
        case .waiting: Image(systemName: "circle").foregroundStyle(NoctisAppColor.ink3)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(NoctisAppColor.sectionSage)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NoctisAppColor.destructive)
        }
    }

    private var bottom: some View {
        VStack(spacing: NoctisSpacing.xs) {
            if finished {
                NoctisCTA(DataManagementCopy.done, icon: "arrow.right", adaptive: true) {
                    dismiss()
                    restart()
                }
                .accessibilityIdentifier("data.deleteAll.done")
            } else if !started {
                Text(DataManagementCopy.deleteAllClosing)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("data.deleteAll.closing")
                Button(role: .destructive) {
                    started = true
                    NoctisHaptics.soft()
                    Task { _ = await manager.deleteEverything() }
                } label: {
                    Text(DataManagementCopy.deleteAllConfirm)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.destructiveLabel)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(NoctisAppColor.destructive, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("data.deleteAll.confirm")
            }
        }
        .padding(.horizontal, NoctisSpacing.md)
        .padding(.vertical, NoctisSpacing.sm)
        .background(NoctisAppColor.bg)
    }
}
