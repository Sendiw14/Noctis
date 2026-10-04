import DesignSystem
import MessageUI
import NoctisCore
import StoreKit
import SwiftUI

/// Settings, pushed over Profile (and over Home, from another screen's "Open Settings"): the grouped list, and
/// one page for each thing in it with more to say than a row. It reads only `SettingsViewModel` (R20, R36).
public struct SettingsScreen: View {
    let page: SettingsPage
    let viewModel: SettingsViewModel

    public init(page: SettingsPage, viewModel: SettingsViewModel) {
        self.page = page
        self.viewModel = viewModel
    }

    public var body: some View {
        switch page {
        case .root: SettingsRootView(viewModel: viewModel)
        case .notifications: NotificationsSettingsView(viewModel: viewModel)
        case .healthData: HealthDataSettingsView(viewModel: viewModel)
        case .appearance: AppearanceSettingsView(viewModel: viewModel)
        case .subscription: SubscriptionSettingsView(viewModel: viewModel)
        case .windDown: WindDownSettingsView(viewModel: viewModel)
        case .sounds: SoundsSettingsView(viewModel: viewModel)
        case .help: HelpView()
        case .about: AboutView(viewModel: viewModel)
        }
    }
}

// MARK: - The page frame

/// Every Settings page: the sand field with "SETTINGS" and one sentence, the navigation bar's title, and the cards.
struct SettingsPageScaffold<Content: View>: View {
    let page: SettingsPage
    let summary: String
    let content: Content
    @State private var scrollPosition = ScrollPosition(edge: .top)

    init(_ page: SettingsPage, summary: String, @ViewBuilder content: () -> Content) {
        self.page = page
        self.summary = summary
        self.content = content()
    }

    var body: some View {
        TabScreenScaffold(
            .profile,
            presentation: .pushed,
            header: TabScreenHeader(
                dateCaption: "SETTINGS", title: page.title, showsTitle: false,
                summary: AnyView(Text(summary).accessibilityIdentifier("settings.summary"))
            ),
            // Below the field, not over its edge: a group's caption is text on the paper, and over the sand it would not read.
            contentTop: .below(NoctisSpacing.md),
            scrollPosition: $scrollPosition
        ) {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                content
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.\(page.rawValue)")
    }
}

/// A caption over a card: the group's name.
struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            NoctisCaption(title, style: .noctisInk3)
                .padding(.horizontal, NoctisSpacing.xs)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// A line of small print under a card.
struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .noctisFont(13, relativeTo: .footnote)
            .foregroundStyle(.noctisInk3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, NoctisSpacing.xs)
    }
}

// MARK: - The list

struct SettingsRootView: View {
    let viewModel: SettingsViewModel
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showsMailComposer = false

    var body: some View {
        SettingsPageScaffold(.root, summary: "Everything you can change in NOCTIS.") {
            SettingsGroup("SLEEP") {
                NoctisRowCard {
                    NoctisLinkRow(
                        systemImage: "person.crop.circle", fill: NoctisAppColor.fieldSand, title: "Sleep profile", hint: "Opens Profile.",
                        identifier: "settings.row.profile"
                    ) { model.show(.profile) }
                    NoctisRowDivider()
                    NoctisLinkRow(
                        systemImage: "alarm", fill: NoctisAppColor.blockButter, title: "Wake alarm", value: viewModel.alarmValue,
                        hint: "Opens the wake alarm on Tonight.", identifier: "settings.row.alarm"
                    ) { model.open(.alarm) }
                    NoctisRowDivider()
                    NoctisLinkRow(
                        systemImage: "moon.stars", fill: NoctisAppColor.blockLavender, title: "Wind-down defaults",
                        hint: "Opens the wind-down defaults.", identifier: "settings.row.windDown"
                    ) { model.push(.settings(.windDown)) }
                    NoctisRowDivider()
                    NoctisLinkRow(
                        systemImage: "speaker.wave.2", fill: NoctisAppColor.blockSage, title: "Sleep sounds defaults",
                        hint: "Opens the sleep sounds defaults.", identifier: "settings.row.sounds"
                    ) { model.push(.settings(.sounds)) }
                }
            }
            .noctisRise(index: 0)
            SettingsGroup("YOUR DEVICE") {
                NoctisRowCard {
                    NoctisLinkRow(
                        systemImage: "bell", fill: NoctisAppColor.blockButter, title: "Notifications",
                        value: ProfileBuilder.notificationsValue(viewModel.authorization, viewModel.values.notifications),
                        hint: "Opens Notifications.", identifier: "settings.row.notifications"
                    ) { model.push(.settings(.notifications)) }
                    NoctisRowDivider()
                    NoctisLinkRow(
                        systemImage: "heart.text.square", fill: NoctisAppColor.blockSage, title: "Health data",
                        value: viewModel.health.map { ProfileBuilder.healthValue($0) },
                        hint: "Opens Health data.", identifier: "settings.row.healthData"
                    ) { model.push(.settings(.healthData)) }
                    NoctisRowDivider()
                    NoctisLinkRow(
                        systemImage: "circle.lefthalf.filled", fill: NoctisAppColor.blockLavender, title: "Appearance",
                        value: viewModel.values.appearance.title, hint: "Opens Appearance.", identifier: "settings.row.appearance"
                    ) { model.push(.settings(.appearance)) }
                    if viewModel.offersLanguage {
                        NoctisRowDivider()
                        NoctisLinkRow(
                            systemImage: "globe", fill: NoctisAppColor.blockButter, title: "Language",
                            detail: "Choose NOCTIS's language in Settings.", value: viewModel.languageName, hint: "Opens NOCTIS in the Settings app.", identifier: "settings.row.language"
                        ) { viewModel.openSystemSettings() }
                    }
                }
            }
            .noctisRise(index: 1)
            SettingsGroup("SUBSCRIPTION") {
                NoctisRowCard {
                    NoctisLinkRow(
                        systemImage: "star", fill: NoctisAppColor.orange, title: "Subscription", value: viewModel.subscription.title,
                        hint: "Opens Subscription.", identifier: "settings.row.subscription"
                    ) { model.push(.settings(.subscription)) }
                }
            }
            .noctisRise(index: 2)
            SettingsGroup("PRIVACY AND DATA") {
                ComingSoonCard(title: "Privacy Center", detail: "One place to see what NOCTIS keeps, and how it is protected.", identifier: "settings.comingSoon.privacy")
                ComingSoonCard(title: "Data management", detail: "One place to erase what NOCTIS keeps.", identifier: "settings.comingSoon.data")
            }
            .noctisRise(index: 3)
            SettingsGroup("SUPPORT") {
                NoctisRowCard {
                    NoctisLinkRow(
                        systemImage: "questionmark.circle", fill: NoctisAppColor.blockLavender, title: "Help", hint: "Opens Help.",
                        identifier: "settings.row.help"
                    ) { model.push(.settings(.help)) }
                    NoctisRowDivider()
                    NoctisLinkRow(
                        systemImage: "envelope", fill: NoctisAppColor.blockSage, title: "Contact support", detail: StoreLegalLinks.supportEmail,
                        hint: "Starts an email to support.", identifier: "settings.row.contact"
                    ) { contactSupport() }
                    NoctisRowDivider()
                    ExternalLinkRow(systemImage: "doc.text", fill: NoctisAppColor.blockButter, title: "Terms of Use", url: StoreLegalLinks.terms, identifier: "settings.row.terms")
                    NoctisRowDivider()
                    ExternalLinkRow(systemImage: "hand.raised", fill: NoctisAppColor.blockLavender, title: "Privacy Policy", url: StoreLegalLinks.privacy, identifier: "settings.row.privacyPolicy")
                }
            }
            .noctisRise(index: 4)
            SettingsGroup("ABOUT") {
                NoctisRowCard {
                    NoctisLinkRow(
                        systemImage: "info.circle", fill: NoctisAppColor.fieldSand, title: "About NOCTIS",
                        value: AboutContent.versionLine(version: viewModel.version, build: viewModel.build), hint: "Opens About.",
                        identifier: "settings.row.about"
                    ) { model.push(.settings(.about)) }
                }
            }
            .noctisRise(index: 5)
        }
        .task {
            await viewModel.onAppear()
            await viewModel.refreshHealth()
        }
        .sheet(isPresented: $showsMailComposer) {
            SupportMailComposer(address: StoreLegalLinks.supportEmail, subject: SupportMessage.subject, body: viewModel.supportBody)
                .ignoresSafeArea()
        }
    }

    /// The Mail composer where Mail is set up; the `mailto:` link otherwise (which opens whatever mail app the
    /// person uses, or says so if there is none).
    private func contactSupport() {
        if MFMailComposeViewController.canSendMail() {
            showsMailComposer = true
        } else if let url = viewModel.supportMailto {
            openURL(url)
        }
    }
}

/// A row that leaves the app for a web page.
struct ExternalLinkRow: View {
    let systemImage: String
    let fill: Color
    let title: String
    let url: URL
    let identifier: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            NoctisHaptics.selection()
            openURL(url)
        } label: {
            NoctisRow(systemImage: systemImage, fill: fill, title: title) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.noctisInk3)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Opens a web page in your browser.")
        .accessibilityAddTraits(.isLink)
        .accessibilityIdentifier(identifier)
    }
}

/// A feature that isn't built yet (APP_RULES.md R19): its name, what it will be, and "Coming soon". Nothing to tap;
/// it is listed in ROADMAP.md.
struct ComingSoonCard: View {
    let title: String
    let detail: String
    let identifier: String

    var body: some View {
        NoctisAppCard {
            HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                    Text(detail)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: NoctisSpacing.xs)
                Text("Coming soon")
                    .noctisFont(15, .medium, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// The system's Mail composer, with the address, the subject and the body filled in.
struct SupportMailComposer: UIViewControllerRepresentable {
    let address: String
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([address])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?) {
            dismiss()
        }
    }
}
