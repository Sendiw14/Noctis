import DesignSystem
import NoctisCore
import SwiftUI

/// Settings > Apple Watch (APP_RULES.md R29, R50, R52): whether the Watch is connected, when it was last sent a summary, what it shows, and one
/// button that sends the latest summary again. It says what the iPhone can really tell and nothing more, and has no other rows.
struct WatchSettingsView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        let content = viewModel.watchContent
        SettingsPageScaffold(.appleWatch, summary: "NOCTIS on your wrist.") {
            status(content).noctisRise(index: 0)
            if content.canSend { send.noctisRise(index: 1) }
            if viewModel.offersWatch { appears.noctisRise(index: 2) }
        }
        .task { await viewModel.followWatch() }
    }

    private func status(_ content: WatchSettingsContent) -> some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                Text(content.statusTitle)
                    .noctisFont(22, .bold, relativeTo: .title3)
                    .foregroundStyle(NoctisAppColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settings.watch.status")
                Text(content.statusDetail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.watch.detail")
                if let install = content.installInstruction {
                    Text(install)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoctisSpacing.xs)
                        .accessibilityIdentifier("settings.watch.install")
                }
                if let lastSent = content.lastSent {
                    Text(lastSent)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .padding(.top, NoctisSpacing.xs)
                        .accessibilityIdentifier("settings.watch.lastSent")
                }
            }
        }
    }

    private var send: some View {
        VStack(spacing: NoctisSpacing.xs) {
            NoctisCTA(WatchSettingsContent.sendButton, isLoading: viewModel.isSendingToWatch, icon: "applewatch", adaptive: true) {
                Task { await viewModel.sendWatchUpdate() }
            }
            .accessibilityHint(WatchSettingsContent.sendHint)
            .accessibilityIdentifier("settings.watch.send")
            if let message = viewModel.watchSendMessage {
                Text(message)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk2)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("settings.watch.sendResult")
                    // Said aloud when it appears, so a VoiceOver user is not left wondering whether the button did anything.
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var appears: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            SettingsGroup("ON YOUR WATCH") {
                NoctisRowCard {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { NoctisRowDivider() }
                        NoctisRow(systemImage: row.symbol, fill: row.fill, title: row.title)
                            .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("settings.watch.appears")
            }
            SettingsNote(WatchSettingsContent.readsNothing)
            SettingsNote(WatchSettingsContent.deleteNote)
        }
    }

    /// The four things the Watch shows, each with the glyph of its place on the Watch.
    private static let rows: [(symbol: String, fill: Color, title: String)] = [
        ("arrow.triangle.2.circlepath", NoctisAppColor.blockLavender, WatchSettingsContent.appears[0]),
        ("bed.double", NoctisAppColor.blockSage, WatchSettingsContent.appears[1]),
        ("waveform.path.ecg", NoctisAppColor.orange, WatchSettingsContent.appears[2]),
        ("moon.stars", NoctisAppColor.blockButter, WatchSettingsContent.appears[3]),
    ]
}
