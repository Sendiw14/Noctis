import DesignSystem
import Foundation
import HealthProviding
import HomeFeature
import NightKit
import NoctisCore
import Observation
import SoundKit
import UIKit

/// Everything Settings reads and changes (APP_RULES.md R20, R36): the preferences, what the system says about
/// notifications, what Health holds, the subscription, the app's version. A row exists only if what it opens
/// works, so each thing here is wired to something real.
@Observable
public final class SettingsViewModel {
    /// The Health data page's state.
    public private(set) var health: HealthDataStatus?
    public private(set) var alarm: AlarmStatus?
    /// The last restore's answer, shown under the button until the next one.
    public private(set) var restoreMessage: String?
    public private(set) var isRestoring = false
    public private(set) var isConnectingHealth = false
    /// The Privacy Center, made from the inventory (R41); made again whenever the page appears, for the sizes.
    public private(set) var privacy: PrivacyCenterContent
    /// The link to the person's Apple Watch, as the iPhone can tell: the Settings row exists only while a Watch is paired (R29).
    public private(set) var watchStatus: WatchConnectionStatus
    /// What "Send update now" last did, shown under the button until the next one.
    public private(set) var watchSendMessage: String?
    public private(set) var isSendingToWatch = false
    /// "Manage subscription" is the system's sheet over the page.
    public var showsManageSubscription = false
    public var showsPaywall = false
    public var showsHowAccessWorks = false

    public let preferences: AppPreferences
    public let notifications: NotificationCoordinator
    public let entitlements: EntitlementManager
    private let store: StoreManager
    private let healthReader: HealthDataStatusReader
    private let alarmService: AlarmService
    private let profile: () -> UserProfileSnapshot
    private let connectHealthAction: () async -> Void
    private let openSettingsAction: @MainActor () -> Void
    private let openHealthAction: @MainActor () -> Void
    private let hapticsAvailable: () -> Bool
    private let format: HomeFormat
    private let bundle: Bundle
    private let preferredLanguages: () -> [String]
    private let clock: () -> Date
    public let inventory: DataInventory
    /// Data management.
    public let data: DataManager
    /// Whether Settings has a Data management page.
    static let hasDataManagement = true
    private let roots: DataRoots
    private let watch: WatchSyncService?

    public init(
        preferences: AppPreferences, notifications: NotificationCoordinator, store: StoreManager, health: HealthDataStatusReader,
        alarm: AlarmService, profile: @escaping () -> UserProfileSnapshot, connectHealth: @escaping () async -> Void,
        hapticsAvailable: @escaping () -> Bool, format: HomeFormat, bundle: Bundle = .main,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
        openSettings: @escaping @MainActor () -> Void = SettingsViewModel.openAppSettings,
        openHealth: @escaping @MainActor () -> Void = SettingsViewModel.openHealthApp, clock: @escaping () -> Date = { Date() },
        inventory: DataInventory = .shared, roots: DataRoots = DataRoots(), data: DataManager, watch: WatchSyncService? = nil
    ) {
        self.data = data
        self.watch = watch
        self.watchStatus = watch?.currentStatus ?? .unsupported
        self.inventory = inventory
        self.roots = roots
        self.privacy = PrivacyCenterBuilder.content(inventory, roots: roots, dataManagement: Self.hasDataManagement)
        self.preferences = preferences
        self.notifications = notifications
        self.entitlements = store.entitlementManager
        self.store = store
        self.healthReader = health
        self.alarmService = alarm
        self.profile = profile
        self.connectHealthAction = connectHealth
        self.hapticsAvailable = hapticsAvailable
        self.format = format
        self.bundle = bundle
        self.preferredLanguages = preferredLanguages
        self.openSettingsAction = openSettings
        self.openHealthAction = openHealth
        self.clock = clock
    }

    public static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// The Health app. The URL scheme is Apple's own and has no documented failure: if it can't open, nothing happens.
    public static func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Reading

    public func onAppear() async {
        async let status = alarmService.status()
        async let authorization: Void = notifications.refreshAuthorization()
        _ = await authorization
        alarm = await status
        await entitlements.refresh()
        if let watch { watchStatus = await watch.status() }
    }

    // MARK: Apple Watch

    /// Keeps the Watch row and page true while they are on screen: the status now, and again whenever the link changes. Ends with the view.
    public func followWatch() async {
        guard let watch else { return }
        for await status in await watch.updates() { watchStatus = status }
    }

    /// What the page says about the link, at this moment.
    public var watchContent: WatchSettingsContent { WatchSettingsContent.make(watchStatus, now: clock()) }

    /// Whether Settings has an Apple Watch row: a Watch is paired with this iPhone (R29, R50).
    public var offersWatch: Bool { watchStatus.showsSettingsRow }

    /// "Send update now": the latest summary queued for the Watch, and what happened, in words.
    public func sendWatchUpdate() async {
        guard let watch, !isSendingToWatch else { return }
        isSendingToWatch = true
        watchSendMessage = nil
        let outcome = await watch.sendNow()
        watchStatus = await watch.status()
        watchSendMessage = WatchSettingsContent.sendResult(outcome, reachable: watchStatus.isReachable)
        isSendingToWatch = false
    }

    /// One look at Health: when the Health data page, or Profile, appears, and again after connecting.
    public func refreshHealth() async {
        health = await healthReader.read(now: clock())
    }

    public var authorization: NotificationAuthorization { notifications.authorization }
    public var banner: NotificationsCopy.Banner { NotificationsCopy.banner(for: notifications.authorization) }
    public var subscription: SubscriptionSummary { entitlements.summary }
    public var values: PreferenceValues { preferences.values }

    /// "6:30 AM" while a wake alarm is on; "Off" otherwise.
    public var alarmValue: String {
        guard let alarm, alarm.isOn else { return "Off" }
        return format.clock(minutesSinceMidnight: alarm.settings.minutesSinceMidnight)
    }

    public var wakeMinutes: Int { profile().typicalWakeMinutes }
    public var needMinutes: Int { profile().needMinutes }

    // MARK: Privacy

    /// Looks at the sizes again.
    public func refreshPrivacy() {
        privacy = PrivacyCenterBuilder.content(inventory, roots: roots, dataManagement: Self.hasDataManagement)
    }

    public func categoryContent(_ id: DataCategoryID) -> PrivacyCategoryContent {
        PrivacyCategoryContent.make(inventory[id], in: inventory, roots: roots)
    }

    // MARK: Rows that exist only sometimes (R36)

    /// The Language row: only for an app with more than one language to choose.
    public var offersLanguage: Bool { LanguageRow.isOffered(localizations: bundle.localizations) }

    public var languageName: String? {
        LanguageRow.currentName(preferred: preferredLanguages(), available: bundle.localizations)
    }

    /// The haptics switches (the app's, and Breathing's): only where the phone has a Taptic Engine to play them on.
    public var offersHaptics: Bool { hapticsAvailable() }

    public func clock(_ minutesSinceMidnight: Int) -> String { format.clock(minutesSinceMidnight: minutesSinceMidnight) }

    // MARK: Notifications

    /// The one button of the banner: asks (once), or opens the app's page in the system's Settings.
    public func performBannerAction(_ action: NotificationsCopy.Banner.Action) async {
        switch action {
        case .allow: await notifications.requestAuthorization()
        case .openSettings: openSettingsAction()
        }
    }

    public func openSystemSettings() {
        openSettingsAction()
    }

    // MARK: Health

    public func connectHealth() async {
        guard !isConnectingHealth else { return }
        isConnectingHealth = true
        await connectHealthAction()
        await refreshHealth()
        isConnectingHealth = false
    }

    public func openHealth() {
        openHealthAction()
    }

    // MARK: Subscription

    public func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        restoreMessage = nil
        restoreMessage = SubscriptionCopy.restoreMessage(await store.restore())
        isRestoring = false
    }

    // MARK: About and support

    public var version: String { bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    public var build: String { bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    public var iOSVersion: String { UIDevice.current.systemVersion }

    public var supportMailto: URL? {
        SupportMessage.mailtoURL(version: version, build: build, iOS: iOSVersion)
    }

    public var supportBody: String { SupportMessage.body(version: version, build: build, iOS: iOSVersion) }
}
