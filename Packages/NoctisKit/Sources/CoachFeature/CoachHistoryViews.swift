import CoachKit
import DesignSystem
import NoctisCore
import SwiftUI

/// History at the field's trailing edge: a 36pt circle in a 44pt target.
struct CoachHistoryButton: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Circle()
                .fill(NoctisAppColor.blockInk.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NoctisAppColor.blockInk)
                )
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("History")
        .accessibilityHint("Shows the conversations Coach has kept.")
        .accessibilityIdentifier("coach.history")
    }
}

/// Every stored conversation, by day, with the first question as its title.
/// Swipe to delete one; "Delete all conversations" removes them all, once
/// confirmed. It reads only what is stored (APP_RULES.md R20).
struct CoachHistoryScreen: View {
    let viewModel: CoachViewModel
    let open: (UUID) -> Void
    @State private var confirmingDeleteAll = false

    var body: some View {
        Group {
            if let history = viewModel.history {
                if history.isEmpty { empty } else { list(history) }
            } else {
                CoachSkeletonView()
                    .padding(.horizontal, NoctisSpacing.lg)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadHistory() }
        .confirmationDialog(CoachHistoryContent.deleteAllTitle + "?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { Task { await viewModel.deleteAllConversations() } }
                .accessibilityIdentifier("coach.history.confirmDeleteAll")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(CoachHistoryContent.deleteAllMessage)
        }
        .accessibilityIdentifier("coach.history.screen")
    }

    private var empty: some View {
        VStack(spacing: NoctisSpacing.md) {
            NoctisIconTile(systemImage: "clock.arrow.circlepath", fill: NoctisAppColor.fieldRose, foreground: NoctisAppColor.blockInk, size: 72)
            Text(CoachHistoryContent.emptyTitle)
                .noctisFont(22, .semibold, relativeTo: .title3)
                .foregroundStyle(NoctisAppColor.ink)
                .multilineTextAlignment(.center)
            Text(CoachHistoryContent.emptyMessage)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(.noctisInk2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, NoctisSpacing.xl)
        .padding(.top, NoctisSpacing.xxxl)
        .frame(maxWidth: 480, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.history.empty")
    }

    private func list(_ history: CoachHistoryContent) -> some View {
        List {
            ForEach(history.days) { day in
                Section {
                    ForEach(day.rows) { row in
                        CoachHistoryRowView(row: row) { open(row.id) }
                            .listRowInsets(EdgeInsets(top: 6, leading: NoctisSpacing.lg, bottom: 6, trailing: NoctisSpacing.lg))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteConversation(row.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityIdentifier("coach.history.delete")
                            }
                    }
                } header: {
                    NoctisCaption(day.title.uppercased(), style: .noctisInk3)
                        .padding(.horizontal, NoctisSpacing.lg)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
                .listRowInsets(EdgeInsets())
            }
            Section {
                Button(role: .destructive) { confirmingDeleteAll = true } label: {
                    HStack(spacing: NoctisSpacing.xs) {
                        Image(systemName: "trash").noctisIcon(15, .semibold, relativeTo: .subheadline)
                        Text(CoachHistoryContent.deleteAllTitle).noctisFont(15, .semibold, relativeTo: .subheadline)
                    }
                    .foregroundStyle(NoctisAppColor.orangeText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("coach.history.deleteAll")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }
}

/// A stored conversation: its first question, and when.
struct CoachHistoryRowView: View {
    let row: CoachHistoryRow
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            NoctisAppCard {
                HStack(spacing: NoctisSpacing.sm) {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                        Text(row.title)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.detail)
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(.noctisInk3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .noctisIcon(14, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk3)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(row.detail)")
        .accessibilityHint("Opens the conversation.")
        .accessibilityIdentifier("coach.history.row")
    }
}
