import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

/// Profile, pushed over Home from the avatar: the name, what NOCTIS knows about the person's sleep (and the
/// two things they can set: need and wake time), their goals, and the state of Health, notifications and the
/// subscription, each of which opens its page in Settings. A gear in the field opens Settings itself. It reads
/// only `ProfileViewModel` (APP_RULES.md R20, R36).
public struct ProfileScreen: View {
    let viewModel: ProfileViewModel
    @Environment(AppModel.self) private var model
    @State private var scrollPosition = ScrollPosition(edge: .top)

    public init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var viewModel = viewModel
        let content = viewModel.content
        TabScreenScaffold(
            .profile,
            presentation: .pushed,
            header: TabScreenHeader(
                dateCaption: content.dateCaption,
                title: "Profile",
                showsTitle: false,
                summary: AnyView(Text(content.summary).accessibilityIdentifier("profile.summary")),
                trailing: AnyView(SettingsGearButton { model.push(.settings(.root)) })
            ),
            contentTop: .overlapsField,
            scrollPosition: $scrollPosition
        ) {
            ProfileSections(content: content, viewModel: viewModel) { page in model.push(.settings(page)) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .sheet(item: $viewModel.sheet) { sheet in
            ProfileEditorSheet(sheet: sheet, viewModel: viewModel)
        }
        .accessibilityIdentifier("profile.screen")
    }
}

/// The 36pt gear at the field's trailing edge, in a 44pt target (the avatar's twin on Home).
struct SettingsGearButton: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Circle()
                .fill(NoctisAppColor.blockInk.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NoctisAppColor.blockInk)
                )
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens Settings.")
        .accessibilityIdentifier("profile.settings")
    }
}

/// The page's cards, in order: the name, the sleep profile, and the status rows.
private struct ProfileSections: View {
    let content: ProfileContent
    let viewModel: ProfileViewModel
    let openSettings: (SettingsPage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            NoctisRowCard {
                NoctisLinkRow(
                    systemImage: "person", fill: NoctisAppColor.fieldSand, title: "Name", value: content.nameValue,
                    hint: "Opens the name editor.", identifier: "profile.name"
                ) { viewModel.open(.name) }
            }
            .noctisRise(index: 0)
            ProfileSleepCard(content: content, viewModel: viewModel)
                .noctisRise(index: 1)
            NoctisRowCard {
                ForEach(Array(content.status.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { NoctisRowDivider() }
                    NoctisLinkRow(
                        systemImage: row.systemImage, fill: fill(for: row.page), title: row.title, value: row.value,
                        hint: "Opens \(row.title) in Settings.", identifier: "profile.status.\(row.page.rawValue)"
                    ) { openSettings(row.page) }
                }
            }
            .noctisRise(index: 2)
            Text("Your name stays on this device. NOCTIS never sends it anywhere.")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, NoctisSpacing.xs)
                .noctisRise(index: 3)
        }
    }

    private func fill(for page: SettingsPage) -> Color {
        switch page {
        case .healthData: NoctisAppColor.blockSage
        case .notifications: NoctisAppColor.blockButter
        default: NoctisAppColor.blockLavender
        }
    }
}

// MARK: - Your sleep profile

/// Tonight's bedtime, then what NOCTIS knows and what the person set. The bedtime follows an edit at once.
private struct ProfileSleepCard: View {
    let content: ProfileContent
    let viewModel: ProfileViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                Text("Your sleep profile")
                    .noctisFont(22, .bold, relativeTo: .title3)
                    .foregroundStyle(NoctisAppColor.ink)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    NoctisCaption(content.bedtime.heroCaption, style: .noctisInk3)
                    NoctisMetric(content.bedtime.hero, size: 34)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: content.bedtime.hero.spoken)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tonight's \(content.bedtime.heroCaption.lowercased()), \(content.bedtime.hero.spoken)")
                .accessibilityIdentifier("profile.bedtime")
                Rectangle().fill(NoctisAppColor.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: 0) {
                    NoctisLinkRow(
                        systemImage: "moon.zzz", fill: NoctisAppColor.blockLavender, title: "Sleep need", value: content.needValue,
                        hint: "Opens the sleep need editor.", identifier: "profile.need"
                    ) { viewModel.open(.need) }
                    NoctisRowDivider()
                    NoctisLinkRow(
                        systemImage: "sunrise", fill: NoctisAppColor.blockButter, title: "Wake time", value: content.wakeValue,
                        hint: "Opens the wake time editor.", identifier: "profile.wake"
                    ) { viewModel.open(.wake) }
                    NoctisRowDivider()
                    NoctisInfoRow(
                        systemImage: "bed.double", fill: NoctisAppColor.blockLavender, title: "Typical bedtime", value: content.typicalBedtime,
                        identifier: "profile.typicalBedtime"
                    )
                    NoctisRowDivider()
                    NoctisInfoRow(
                        systemImage: "alarm", fill: NoctisAppColor.blockButter, title: "Typical wake", value: content.typicalWake,
                        identifier: "profile.typicalWake"
                    )
                    NoctisRowDivider()
                    NoctisLinkRow(
                        systemImage: "target", fill: NoctisAppColor.blockSage, title: "Goals", value: content.goalsValue,
                        hint: "Opens the goals editor.", identifier: "profile.goals"
                    ) { viewModel.open(.goals) }
                }
                if let note = content.learningNote {
                    Text(note)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.learning")
                }
                if let alarm = content.alarmLine {
                    Text(alarm)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.alarmLine")
                }
            }
        }
        .accessibilityIdentifier("profile.sleepCard")
    }
}
