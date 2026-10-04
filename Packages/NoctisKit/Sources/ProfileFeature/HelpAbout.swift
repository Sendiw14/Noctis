import DesignSystem
import NoctisCore
import SwiftUI

// MARK: - Help

/// Eight questions, each opening to its answer. The words are in `Resources/Help.xcstrings` and a test holds the
/// numbers in them to the code that uses them.
struct HelpView: View {
    @State private var openKey: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPageScaffold(.help, summary: "How NOCTIS works, in plain words.") {
            NoctisRowCard {
                ForEach(Array(HelpCatalog.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Rectangle().fill(NoctisAppColor.hairline).frame(height: 1).accessibilityHidden(true) }
                    HelpRow(entry: entry, isOpen: openKey == entry.key) {
                        NoctisHaptics.selection()
                        withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
                            openKey = openKey == entry.key ? nil : entry.key
                        }
                    }
                }
            }
            .noctisRise(index: 0)
        }
    }
}

struct HelpRow: View {
    let entry: HelpEntry
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                    Text(entry.question)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: NoctisSpacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.noctisInk3)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, NoctisSpacing.sm)
                .frame(minHeight: 56, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.question)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("help.question.\(entry.key)")
            if isOpen {
                Text(entry.answer)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, NoctisSpacing.sm)
                    .transition(.opacity)
                    .accessibilityIdentifier("help.answer.\(entry.key)")
            }
        }
    }
}

// MARK: - About

struct AboutView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        SettingsPageScaffold(.about, summary: "Version, models and a few plain facts.") {
            NoctisRowCard {
                NoctisInfoRow(
                    systemImage: "info.circle", fill: NoctisAppColor.fieldSand, title: "Version",
                    value: AboutContent.versionLine(version: viewModel.version, build: viewModel.build), identifier: "about.version"
                )
            }
            .noctisRise(index: 0)
            SettingsGroup("MODELS") {
                NoctisRowCard {
                    ForEach(Array(AboutContent.models.enumerated()), id: \.element.name) { index, model in
                        if index > 0 { NoctisRowDivider() }
                        NoctisInfoRow(
                            systemImage: "function", fill: NoctisAppColor.blockLavender, title: model.name, value: model.version,
                            identifier: "about.model.\(index)"
                        )
                    }
                }
            }
            .noctisRise(index: 1)
            SettingsNote("Each number NOCTIS shows says which model it came from. A model never changes under a version name.")
                .noctisRise(index: 2)
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    Text(AboutContent.medical)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("about.medical")
                    Text(AboutContent.acknowledgements)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("about.acknowledgements")
                }
            }
            .noctisRise(index: 3)
        }
    }
}
