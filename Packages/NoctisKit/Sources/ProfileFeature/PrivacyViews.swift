import DesignSystem
import HealthProviding
import NoctisCore
import SwiftUI

extension DataCategoryID {
    /// The category's glyph on its row.
    var symbol: String {
        switch self {
        case .appleHealth: "heart.text.square"
        case .cachedSummaries: "square.stack"
        case .insightHistory: "lightbulb"
        case .reviews: "calendar"
        case .memorySummaries: "memorychip"
        case .profile: "person"
        case .preferences: "slider.horizontal.3"
        case .soundSettings: "speaker.wave.2"
        case .appState: "flag"
        case .alarm: "alarm"
        case .windDownHistory: "moon.stars"
        case .journal: "book.closed"
        case .coachHistory: "sparkles"
        case .reminders: "bell"
        case .diagnosticLog: "doc.text"
        case .purchases: "star"
        case .systemFiles: "internaldrive"
        case .setAsideFiles: "archivebox"
        case .exportFile: "square.and.arrow.up"
        case .widgetSnapshot: "rectangle.on.rectangle"
        case .watchSync: "applewatch"
        case .sleepSoundsState: "waveform"
        }
    }

    var fill: Color {
        switch self {
        case .appleHealth, .cachedSummaries, .widgetSnapshot, .watchSync, .sleepSoundsState, .memorySummaries, .systemFiles: NoctisAppColor.blockSage
        case .insightHistory, .reviews, .preferences, .soundSettings, .appState, .reminders: NoctisAppColor.blockButter
        case .journal, .coachHistory, .profile, .exportFile, .setAsideFiles: NoctisAppColor.blockLavender
        case .alarm, .windDownHistory, .diagnosticLog, .purchases: NoctisAppColor.fieldSand
        }
    }
}

// MARK: - The Privacy Center

/// What NOCTIS keeps, where, and who can see it. Every sentence on it comes from the inventory (APP_RULES.md R41).
struct PrivacyCenterView: View {
    let viewModel: SettingsViewModel
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let content = viewModel.privacy
        SettingsPageScaffold(.privacyCenter, summary: "What NOCTIS keeps, where, and who can see it.") {
            statements(content).noctisRise(index: 0)
            SettingsGroup("WHAT NOCTIS READS") {
                NoctisRowCard {
                    ForEach(Array(content.reads.enumerated()), id: \.element.id) { index, line in
                        if index > 0 { NoctisRowDivider() }
                        NoctisInfoRow(systemImage: "heart.text.square", fill: NoctisAppColor.blockSage, title: line.title, detail: line.detail, value: "", identifier: "privacy.reads.\(line.id)")
                    }
                }
                if let note = content.readsNote { SettingsNote(note) }
            }
            .noctisRise(index: 1)
            SettingsGroup("WHAT STAYS ON THIS IPHONE") {
                NoctisRowCard {
                    ForEach(Array(content.stays.enumerated()), id: \.element.id) { index, line in
                        if index > 0 { NoctisRowDivider() }
                        if let id = line.category {
                            NoctisLinkRow(
                                systemImage: id.symbol, fill: id.fill, title: line.title, detail: line.detail, hint: "Opens what \(line.title) holds.",
                                identifier: "privacy.stays.\(line.id)"
                            ) { model.push(.dataCategory(id)) }
                        }
                    }
                }
                SettingsNote(content.staysNote)
            }
            .noctisRise(index: 2)
            leaves(content).noctisRise(index: 3)
            coach(content).noctisRise(index: 4)
            SettingsGroup("WHAT SYNCS") {
                NoctisAppCard {
                    Text(content.sync)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("privacy.sync")
                }
            }
            .noctisRise(index: 5)
            SettingsGroup("WHAT'S STORED, AND HOW BIG") {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        Text(content.storedTotal)
                            .noctisFont(28, .bold, relativeTo: .title)
                            .foregroundStyle(NoctisAppColor.ink)
                            .accessibilityIdentifier("privacy.total")
                        Text("in all, on this iPhone")
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(.noctisInk3)
                        Rectangle().fill(NoctisAppColor.hairline).frame(height: 1).padding(.vertical, NoctisSpacing.xxs)
                        ForEach(content.sizes) { line in
                            HStack(alignment: .firstTextBaseline) {
                                Text(line.title)
                                    .noctisFont(15, relativeTo: .subheadline)
                                    .foregroundStyle(NoctisAppColor.ink)
                                Spacer(minLength: NoctisSpacing.xs)
                                Text(line.value ?? "")
                                    .noctisFont(15, relativeTo: .subheadline)
                                    .foregroundStyle(.noctisInk2)
                                    .multilineTextAlignment(.trailing)
                            }
                            .frame(minHeight: 28)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("privacy.size.\(line.id)")
                        }
                    }
                }
            }
            .noctisRise(index: 6)
            SettingsGroup("WHAT YOU CAN DELETE") {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        Text(content.deleteNote)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(.noctisInk2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let noAccount = content.noAccount {
                            Text(noAccount)
                                .noctisFont(15, .semibold, relativeTo: .subheadline)
                                .foregroundStyle(NoctisAppColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("privacy.noAccount")
                        }
                    }
                }
            }
            .noctisRise(index: 7)
            SettingsGroup("LINKS") {
                NoctisRowCard {
                    NoctisLinkRow(
                        systemImage: "heart.text.square", fill: NoctisAppColor.blockSage, title: "Open Health access",
                        detail: "Change what NOCTIS may read in the Health app.", hint: "Opens the Health app.", identifier: "privacy.link.health"
                    ) { viewModel.openHealth() }
                    NoctisRowDivider()
                    ExternalLinkRow(systemImage: "hand.raised", fill: NoctisAppColor.blockLavender, title: "Privacy Policy", url: StoreLegalLinks.privacy, identifier: "privacy.link.policy")
                }
            }
            .noctisRise(index: 8)
        }
        .task { viewModel.refreshPrivacy() }
    }

    private func statements(_ content: PrivacyCenterContent) -> some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                ForEach(content.headline) { statement in
                    HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(NoctisAppColor.sectionSage)
                            .padding(.top, 1)
                            .accessibilityHidden(true)
                        Text(statement.text)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("privacy.statement.\(statement.id)")
                }
            }
        }
        .accessibilityIdentifier("privacy.statements")
    }

    private func leaves(_ content: PrivacyCenterContent) -> some View {
        SettingsGroup("WHAT MAY LEAVE THIS IPHONE") {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    Text(content.leavesNote)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !content.leavesToWatch.isEmpty {
                        NoctisCaption("TO YOUR APPLE WATCH", style: .noctisInk3)
                        ForEach(content.leavesToWatch) { flow($0) }
                    }
                    if !content.leavesIfYouSend.isEmpty {
                        NoctisCaption("ONLY IF YOU SEND IT", style: .noctisInk3)
                        ForEach(content.leavesIfYouSend) { flow($0) }
                    }
                    if !content.leavesThroughApple.isEmpty {
                        NoctisCaption("THROUGH APPLE", style: .noctisInk3)
                        ForEach(content.leavesThroughApple) { flow($0) }
                    }
                }
            }
            .accessibilityIdentifier("privacy.leaves")
        }
    }

    private func flow(_ line: PrivacyCenterContent.Line) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.title)
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(NoctisAppColor.ink)
            Text(line.detail ?? "")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("privacy.flow.\(line.id)")
    }

    private func coach(_ content: PrivacyCenterContent) -> some View {
        SettingsGroup("WHAT COACH CAN SEE") {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    ForEach(content.coachSees, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.sm) {
                            Circle().fill(NoctisSection.coach.ink).frame(width: 6, height: 6).accessibilityHidden(true)
                            Text(line)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(NoctisAppColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(content.coachNeverSees)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoctisSpacing.xxs)
                }
            }
            .accessibilityIdentifier("privacy.coach")
            SettingsNote("The kinds of facts, never the readings themselves.")
        }
    }
}

// MARK: - One kind of data

public struct PrivacyCategoryView: View {
    let id: DataCategoryID
    let viewModel: SettingsViewModel

    public init(id: DataCategoryID, viewModel: SettingsViewModel) {
        self.id = id
        self.viewModel = viewModel
    }

    public var body: some View {
        let content = viewModel.categoryContent(id)
        PrivacyCategoryScaffold(title: content.name, summary: "What it is, where it lives and who can see it.") {
            SettingsGroup("WHAT IT IS") {
                NoctisAppCard {
                    Text(content.summary)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("privacy.category.summary")
            }
            SettingsGroup("WHAT IT HOLDS") {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        ForEach(content.contents, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.sm) {
                                Circle().fill(NoctisAppColor.ink3).frame(width: 5, height: 5).accessibilityHidden(true)
                                Text(line)
                                    .noctisFont(15, relativeTo: .subheadline)
                                    .foregroundStyle(NoctisAppColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("privacy.category.holds")
            }
            .noctisRise(index: 0)
            SettingsGroup("WHERE IT LIVES") {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        ForEach(content.where_, id: \.self) { line in
                            Text(line)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(NoctisAppColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityIdentifier("privacy.category.where")
            }
            .noctisRise(index: 1)
            NoctisAppCard {
                VStack(alignment: .leading, spacing: 0) {
                    fact("Leaves this iPhone", content.leaves, "leaves")
                    divider
                    fact("Syncs", content.syncs, "syncs")
                    divider
                    coachFact(content)
                    divider
                    fact("In backups", content.backups, "backups")
                    divider
                    fact("Protection", content.protection, "protection")
                    divider
                    fact("Size", content.size, "size")
                    divider
                    fact("How to delete it", content.deletion, "deletion")
                }
            }
            .noctisRise(index: 2)
        }
        .accessibilityIdentifier("privacy.category.\(id.rawValue)")
    }

    private var divider: some View {
        Rectangle().fill(NoctisAppColor.hairline).frame(height: 1).padding(.vertical, NoctisSpacing.xs).accessibilityHidden(true)
    }

    private func fact(_ title: String, _ text: String, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NoctisCaption(title.uppercased(), style: .noctisInk3)
            Text(text)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(NoctisAppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("privacy.category.\(key)")
    }

    private func coachFact(_ content: PrivacyCategoryContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NoctisCaption("COACH", style: .noctisInk3)
            Text(content.coachNote)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(NoctisAppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(content.coach, id: \.self) { line in
                Text(line)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("privacy.category.coach")
    }
}

/// A category's page frame: its own title on the sand field.
private struct PrivacyCategoryScaffold<Content: View>: View {
    let title: String
    let summary: String
    let content: Content
    @State private var scrollPosition = ScrollPosition(edge: .top)

    init(title: String, summary: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.content = content()
    }

    var body: some View {
        TabScreenScaffold(
            .profile,
            presentation: .pushed,
            header: TabScreenHeader(dateCaption: "PRIVACY CENTER", title: title, showsTitle: false, summary: AnyView(Text(summary))),
            contentTop: .below(NoctisSpacing.md),
            scrollPosition: $scrollPosition
        ) {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) { content }
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
