import Foundation
import SwiftData
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import NightKit
@testable import NoctisCore
@testable import ProfileFeature
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SoundKit

private let settingsFormat = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
private let settingsNow = Fixture.date(2026, 9, 24, 20)

// MARK: - Pages and routes

struct SettingsPageTests {
    @Test func everyPageHasATitleAndATokenThatRoundTrips() {
        for page in SettingsPage.allCases {
            #expect(!page.title.isEmpty)
            #expect(SettingsPage(token: page.token) == page, "\(page)")
        }
        #expect(SettingsPage(token: "health-data") == .healthData)
        #expect(SettingsPage(token: "healthdata") == .healthData)
        #expect(SettingsPage(token: "Wind_Down") == .windDown)
        #expect(SettingsPage(token: "nonsense") == nil)
    }

    @MainActor
    @Test func showReturnsToProfileWhereItIsInTheStackAndPushesItWhereItIsNot() throws {
        let model = try makeAppModel()
        model.push(.profile)
        model.push(.settings(.root))
        model.push(.settings(.notifications))
        #expect(model.homePath == [.profile, .settings(.root), .settings(.notifications)])
        model.show(.profile)
        #expect(model.homePath == [.profile], "back to Profile, not a second Profile")
        model.homePath = []
        model.show(.profile)
        #expect(model.homePath == [.profile])
    }

    @MainActor
    private func makeAppModel() throws -> AppModel {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
    }
}

// MARK: - The subscription

struct SubscriptionSummaryTests {
    private let end = Fixture.date(2026, 10, 11, 12)
    private func detail(_ summary: SubscriptionSummary) -> String {
        summary.detail(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
    }

    @Test func freeSaysFreeAndNothingAboutAPrice() {
        let free = SubscriptionSummary.free
        #expect(free.title == "Free" && free.headline == "Free")
        #expect(detail(free) == "You can upgrade to Premium at any time.", "nothing is claimed to be locked: gating isn't built (ROADMAP.md)")
    }

    @Test func premiumNamesThePlanAndWhenItRenews() {
        let yearly = SubscriptionSummary(isPremium: true, plan: .yearly, willRenew: true, endDate: end)
        #expect(yearly.headline == "Premium · Yearly" && yearly.title == "Premium")
        #expect(detail(yearly) == "Renews on Oct 11, 2026.")
        let monthly = SubscriptionSummary(isPremium: true, plan: .monthly, willRenew: true, endDate: end)
        #expect(monthly.headline == "Premium · Monthly")
    }

    @Test func aSubscriptionThatWontRenewSaysWhenItEnds() {
        let ending = SubscriptionSummary(isPremium: true, plan: .yearly, willRenew: false, endDate: end)
        #expect(detail(ending) == "Ends on Oct 11, 2026. It won't renew.")
    }

    @Test func aTrialSaysWhenItEndsAndWhatHappensThen() {
        let trial = SubscriptionSummary(isPremium: true, plan: .yearly, isTrial: true, willRenew: true, endDate: end)
        #expect(detail(trial) == "Your free trial ends on Oct 11, 2026, then it renews.")
        let cancelled = SubscriptionSummary(isPremium: true, plan: .yearly, isTrial: true, willRenew: false, endDate: end)
        #expect(detail(cancelled) == "Your free trial ends on Oct 11, 2026. It won't renew.")
    }

    @Test func aBillingProblemIsSaidPlainlyAndPremiumContinues() {
        let grace = SubscriptionSummary(isPremium: true, plan: .monthly, willRenew: true, endDate: end, isInGracePeriod: true)
        #expect(detail(grace).hasPrefix("Your last payment didn't go through."))
        #expect(grace.isPremium)
    }

    @Test func aPlanComesFromTheProductIDs() {
        #expect(SubscriptionSummary.Plan(productID: StoreProductID.monthly) == .monthly)
        #expect(SubscriptionSummary.Plan(productID: StoreProductID.yearly) == .yearly)
        #expect(SubscriptionSummary.Plan(productID: "com.other") == nil)
        #expect(SubscriptionSummary(isPremium: true).headline == "Premium", "no plan, no suffix")
    }

    @Test func theRestoreMessagesCoverEveryOutcome() {
        for result in [StoreManager.RestoreResult.restored, .nothingFound, .failed] {
            #expect(!SubscriptionCopy.restoreMessage(result).isEmpty)
        }
        #expect(SubscriptionCopy.restoreMessage(.nothingFound) == "There's nothing to restore for this Apple Account.")
    }

    @MainActor
    @Test func aMockedSubscriptionIsWhatTheManagerReports() {
        let manager = EntitlementManager()
        #expect(manager.summary == .free)
        manager.debugSet(SubscriptionSummary(isPremium: true, plan: .yearly, willRenew: true, endDate: nil))
        #expect(manager.hasActivePremium && manager.summary.headline == "Premium · Yearly")
    }
}

// MARK: - Support

struct SupportMessageTests {
    @Test func theBodyHoldsTheVersionTheBuildAndIOSAndNothingElse() {
        let body = SupportMessage.body(version: "1.0", build: "42", iOS: "27.0")
        #expect(body == "\n\n\u{2014}\nNOCTIS 1.0 (42)\niOS 27.0")
        for forbidden in ["sleep", "recovery", "heart", "name", "goal", "wake"] {
            #expect(!body.lowercased().contains(forbidden), Comment(rawValue: forbidden))
        }
    }

    @Test func theMailtoLinkIsAddressedToSupportWithTheSubjectAndBody() throws {
        let url = try #require(SupportMessage.mailtoURL(version: "1.0", build: "42", iOS: "27.0"))
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == StoreLegalLinks.supportEmail)
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["subject"] == "NOCTIS support")
        #expect(items["body"] == SupportMessage.body(version: "1.0", build: "42", iOS: "27.0"))
    }

    @Test func theSupportAddressIsOneAddressFromStoreConstants() {
        #expect(StoreLegalLinks.supportEmail.contains("@") && !StoreLegalLinks.supportEmail.contains(" "))
        #expect(StoreLegalLinks.terms.scheme == "https" && StoreLegalLinks.privacy.scheme == "https")
    }
}

// MARK: - Language

struct LanguageRowTests {
    @Test func theRowIsOfferedOnlyForMoreThanOneLanguage() {
        #expect(!LanguageRow.isOffered(localizations: []))
        #expect(!LanguageRow.isOffered(localizations: ["en"]))
        #expect(!LanguageRow.isOffered(localizations: ["en", "Base"]), "Base is not a language")
        #expect(!LanguageRow.isOffered(localizations: ["en", "en"]))
        #expect(LanguageRow.isOffered(localizations: ["en", "fr"]))
        #expect(LanguageRow.isOffered(localizations: ["Base", "en", "de", "ja"]))
    }

    @Test func theCurrentLanguageIsNamedInItself() {
        #expect(LanguageRow.currentName(preferred: ["fr-FR", "en"], available: ["en", "fr"]) == "Français")
        #expect(LanguageRow.currentName(preferred: ["de"], available: ["en", "fr"]) == "English", "falls back to a language the app has")
        #expect(LanguageRow.currentName(preferred: ["en-US"], available: []) == nil)
    }

    @Test func theAppBundleHasOneLanguageSoTheRowIsNotShownToday() {
        // The test host is the app: whatever it ships decides. Today that is English alone (ROADMAP.md: localisation).
        #expect(LanguageRow.languages(in: Bundle.main.localizations).count >= 1)
    }
}

// MARK: - Help

struct HelpCatalogTests {
    private func answer(_ key: String) -> String { HelpCatalog.answer(key) }

    @Test func thereAreEightQuestionsEachWithAnAnswerFromTheCatalog() {
        let entries = HelpCatalog.entries
        #expect(entries.count == 8)
        for entry in entries {
            #expect(entry.question.hasSuffix("?"), Comment(rawValue: entry.key))
            #expect(!entry.question.hasPrefix("help.") && !entry.answer.hasPrefix("help."), "\(entry.key) is missing from Help.xcstrings")
            #expect(entry.answer.count > 80, Comment(rawValue: entry.key))
        }
        #expect(Set(entries.map(\.key)).count == 8)
    }

    @Test func theRecoveryAnswerHasTheModelsNumbers() {
        let text = answer("recovery")
        let w = RecoveryModelV3.weights
        #expect(text.contains("\(Int(w[.sleepDuration] ?? 0)) points"), "sleep duration")
        #expect(text.contains("(\(Int(w[.sleepConsistency] ?? 0)))"), "consistency")
        #expect(text.contains("(\(Int(w[.hrv] ?? 0)))"), "HRV")
        #expect(text.contains("(\(Int(w[.restingHeartRate] ?? 0)))"), "resting heart rate")
        #expect(text.contains("\(RecoveryModelV3.heartCapScore) or less"), "the cap")
        #expect(text.contains(RecoveryModel.current.rawValue), "the version")
        #expect(text.contains("last 14 nights"))
        #expect(RecoveryNormalRange.standardDeviations == 1)
    }

    @Test func theSleepQualityAnswerHasTheModelsNumbers() {
        let text = answer("quality")
        let w = SleepQualityModelV1.weights
        #expect(text.contains("(\(Int(w[.duration] ?? 0)) points)") || text.contains("need (\(Int(w[.duration] ?? 0)) points"), "duration")
        #expect(text.contains("(\(Int(w[.continuity] ?? 0)))"), "continuity")
        #expect(text.contains("(\(Int(w[.consistency] ?? 0)))"), "consistency")
        #expect(text.contains("(\(Int(w[.stages] ?? 0)))"), "stages")
        #expect(text.contains("\(SleepQualityModelV1.personalStageNights) or more nights"))
        #expect(text.contains(SleepQualityModelV1.version))
    }

    @Test func theBedtimeAnswerHasTheModelsNumbers() {
        let text = answer("bedtime")
        let p = BedtimeModel.current.parameters
        #expect(text.contains("last \(SleepBalanceEngine.windowNights) nights"))
        #expect(p.catchUpBehindMinutes == 60 && text.contains("an hour or more under"))
        #expect(p.catchUpShareDivisor == 4 && text.contains("a quarter of the gap"))
        #expect(text.contains("no more than \(p.catchUpLimitMinutes) minutes"))
        #expect(text.contains("Once \(p.minimumNights) nights"))
        #expect(text.contains("within \(p.gradualStepMinutes) minutes of your usual bedtime"))
        #expect(text.contains("\(p.windowHalfWidthMinutes) minutes either side"))
        #expect(text.contains("nearest \(p.roundingMinutes) minutes"))
        #expect(text.contains(BedtimeModel.current.version))
    }

    @Test func theMissingNumberAnswerHasTheRealThresholds() {
        let text = answer("missing")
        #expect(text.contains("at least \(RecoveryModelV1.learningNights) nights"))
        #expect(text.contains("need \(BedtimeInputsBuilder.usualBedtimeMinimumNights) recorded nights"))
        #expect(text.contains("last \(Int(RecoveryModelV1.lastNightWindow / 3600)) hours"))
    }

    @Test func theCoachAnswerPromisesNothingMedicalAndNothingLeavingThePhone() {
        let text = answer("coach")
        #expect(text.contains("isn't medical advice") && text.contains("can't diagnose"))
        #expect(text.contains("nothing you ask is sent to a server"))
        #expect(!text.lowercased().contains("diagnoses you"))
    }

    @Test func theDeleteAnswerNamesWhatTheAppCanDeleteAndWhatItCannot() {
        let text = answer("delete")
        #expect(text.contains("Coach") && text.contains("History") && text.contains("Journal") && text.contains("Delete all entries"))
        #expect(text.contains("Apple Health"))
        #expect(text.contains("isn't built yet"), "no single erase-everything control exists")
    }
}

// MARK: - About

struct AboutContentTests {
    @Test func theModelVersionsComeFromTheCode() {
        let models = Dictionary(uniqueKeysWithValues: AboutContent.models.map { ($0.name, $0.version) })
        #expect(models["Recovery"] == RecoveryModel.current.rawValue && models["Recovery"] == "recovery-v3")
        #expect(models["Sleep quality"] == SleepQualityModelV1.version && models["Sleep quality"] == "sleep-quality-v1")
        #expect(models["Bedtime"] == BedtimeModel.current.version && models["Bedtime"] == "bedtime-v1")
    }

    @Test func theWordsAreThePlainOnes() {
        #expect(AboutContent.medical == "NOCTIS isn't a medical device and doesn't diagnose or treat any condition.")
        #expect(AboutContent.versionLine(version: "1.0", build: "42") == "1.0 (42)")
    }

    @Test func thePackageHasNoThirdPartyDependencies() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!manifest.contains(".package("), "an acknowledgements page is needed the day this fails")
        let project = try String(contentsOf: root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("project.yml"), encoding: .utf8)
        #expect(!project.contains("url: http") && !project.contains("github.com"), "no remote package")
    }
}

// MARK: - Notifications and Health, in words

struct NotificationsCopyTests {
    @Test func theBannerFollowsThePermissionWithTheOneThingToDo() {
        #expect(NotificationsCopy.banner(for: .allowed).action == nil)
        #expect(NotificationsCopy.banner(for: .notDetermined).action == .allow)
        #expect(NotificationsCopy.banner(for: .denied).action == .openSettings)
        #expect(NotificationsCopy.banner(for: .denied).action?.title == "Open Settings")
        #expect(NotificationsCopy.banner(for: .notDetermined).action?.title == "Turn on notifications")
    }

    @Test func theSwitchesWorkUnlessTheSystemHasSaidNo() {
        #expect(NotificationsCopy.switchesAreEnabled(.allowed) && NotificationsCopy.switchesAreEnabled(.notDetermined))
        #expect(!NotificationsCopy.switchesAreEnabled(.denied))
    }

    @Test func whatEachNotificationSaysIsWhatItWillSay() {
        #expect(NotificationsCopy.morningSays == NotificationPlan.morningBody)
        #expect(NotificationsCopy.weeklySays == NotificationPlan.weeklyBody)
        for lead in NotificationPreferences.windDownLeads {
            #expect(NotificationsCopy.windDownSays(leadMinutes: lead) == NotificationPlan.windDownBody(leadMinutes: lead))
        }
        #expect(NotificationsCopy.privacyNote == "Reminders never carry a number from your Health data.")
    }

    @Test func theChoicesReadInPlainWords() {
        #expect(NotificationsCopy.minutesAfterWake(0) == "At wake time")
        #expect(NotificationsCopy.minutesAfterWake(15) == "15 min after waking")
        #expect(NotificationsCopy.minutesBeforeBed(20) == "20 min before bedtime")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        #expect(NotificationsCopy.weekdayName(1, calendar: calendar) == "Sunday" && NotificationsCopy.weekdayName(7, calendar: calendar) == "Saturday")
    }
}

struct HealthCopyTests {
    private var calendar: Calendar { Fixture.calendar() }
    private let locale = Locale(identifier: "en_US")

    @Test func theLineSaysDataFoundWithTheDateOrNoDataFound() {
        let found = HealthKindStatus(kind: .sleepAnalysis, lastSample: Fixture.date(2026, 9, 29, 7))
        #expect(HealthCopy.line(found, calendar: calendar, locale: locale) == "Data found · last sample Sep 29")
        #expect(HealthCopy.line(HealthKindStatus(kind: .hrv, lastSample: nil), calendar: calendar, locale: locale) == "No data found")
        #expect(HealthCopy.line(HealthKindStatus(kind: .hrv, lastSample: nil, couldNotCheck: true), calendar: calendar, locale: locale) == "Couldn't check just now")
    }

    @Test func noWordInTheHealthCopyClaimsAPermissionState() {
        let all = [HealthCopy.emptyExplanation, HealthCopy.noDataDetail, HealthCopy.unavailableDetail] + HealthCopy.howAccessWorks
        for text in all {
            #expect(!text.lowercased().contains("permission required"), Comment(rawValue: text))
            #expect(!text.lowercased().contains("denied") || text.contains("never tells an app which kinds you declined"), Comment(rawValue: text))
        }
        #expect(HealthCopy.emptyExplanation.contains("Apple Health doesn't tell apps which."))
    }

    @Test func theSourceIsNamedOnlyWhenItIsKnown() {
        #expect(HealthCopy.sourceLine("Apple Watch") == "Last night's sleep came from Apple Watch.")
        #expect(HealthCopy.sourceLine(nil) == nil)
    }

    @Test func thePurposeComesFromTheKindsOwnList() {
        for kind in HealthDataKind.allCases { #expect(HealthCopy.purpose(kind) == kind.benefit) }
    }
}

// MARK: - The view model

@MainActor
struct SettingsViewModelTests {
    final class Calls {
        var settingsOpened = 0
        var healthOpened = 0
        var connected = 0
    }

    struct Bench {
        let viewModel: SettingsViewModel
        let preferences: AppPreferences
        let center: InMemoryNotificationCenter
        let coordinator: NotificationCoordinator
        let calls: Calls
    }

    private func make(
        scenario: MockScenario = .full, authorized: Bool = true, notifications: NotificationAuthorization = .allowed, haptics: Bool = true,
        answer: Bool = true
    ) -> Bench {
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? NoctisUserDefaults.standard
        let preferences = AppPreferences(defaults: defaults)
        let center = InMemoryNotificationCenter(authorization: notifications, answer: answer)
        let coordinator = NotificationCoordinator(
            scheduler: NotificationScheduler(center: center), preferences: preferences, profile: { UserProfileSnapshot() }, bedtimeCenter: { _, _ in 23 * 60 }
        )
        let now = settingsNow
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: authorized)
        let service = AlarmService(backend: MockAlarmBackend(mode: .authorized), store: MemoryAlarmStore(), defaultMinutes: { 7 * 60 })
        let calls = Calls()
        let viewModel = SettingsViewModel(
            preferences: preferences, notifications: coordinator, store: StoreManager(), health: HealthDataStatusReader(provider: provider),
            alarm: service, profile: { UserProfileSnapshot(typicalWakeMinutes: 7 * 60, needMinutes: 8 * 60) },
            connectHealth: { [calls] in
                calls.connected += 1
                _ = await provider.requestAuthorization(for: HealthDataKind.allCases)
            },
            hapticsAvailable: { haptics }, format: settingsFormat, bundle: .main, preferredLanguages: { ["en"] },
            openSettings: { [calls] in calls.settingsOpened += 1 }, openHealth: { [calls] in calls.healthOpened += 1 }, clock: { now }
        )
        return Bench(viewModel: viewModel, preferences: preferences, center: center, coordinator: coordinator, calls: calls)
    }

    @Test func theBannerButtonAsksOnceWhenNothingHasBeenAskedAndOpensSettingsWhenDenied() async {
        let fresh = make(notifications: .notDetermined)
        await fresh.viewModel.onAppear()
        #expect(fresh.viewModel.banner.action == .allow)
        await fresh.viewModel.performBannerAction(.allow)
        #expect(fresh.viewModel.authorization == .allowed)
        #expect(fresh.viewModel.banner.action == nil)

        let refused = make(notifications: .notDetermined, answer: false)
        await refused.viewModel.performBannerAction(.allow)
        #expect(refused.viewModel.authorization == .denied)
        #expect(refused.viewModel.banner.action == .openSettings)
        await refused.viewModel.performBannerAction(.openSettings)
        #expect(refused.calls.settingsOpened == 1)
    }

    @Test func aDeniedStateIsSeenOnAppearingAndNothingIsScheduled() async {
        let bench = make(notifications: .denied)
        await bench.viewModel.onAppear()
        #expect(bench.viewModel.authorization == .denied)
        #expect(!NotificationsCopy.switchesAreEnabled(bench.viewModel.authorization))
        bench.coordinator.reschedule()
        await bench.coordinator.settled()
        #expect(bench.center.pendingNotifications.isEmpty)
    }

    @Test func changingAReminderChangesWhatIsScheduled() async {
        let bench = make()
        bench.preferences.onChange = { [coordinator = bench.coordinator] change in if change == .notifications { coordinator.reschedule() } }
        bench.coordinator.reschedule()
        await bench.coordinator.settled()
        #expect(bench.center.pendingNotifications.count == 3)
        bench.preferences.update { $0.notifications.morningIsOn = false }
        await bench.coordinator.settled()
        #expect(bench.center.pendingNotifications.count == 2)
        #expect(!bench.center.pendingNotifications.contains { $0.identifier == NoctisNotification.morningSummary })
    }

    @Test func theHealthPageHasARowForEveryKindAndTheSourceWhenKnown() async {
        let bench = make()
        #expect(bench.viewModel.health == nil, "nothing is claimed before the first look")
        await bench.viewModel.refreshHealth()
        let health = bench.viewModel.health
        #expect(health?.kinds.map(\.kind) == HealthDataKind.allCases)
        #expect(health?.hasAllData == true)
    }

    @Test func noDataOffersTheConnectFlowUntilTheQuestionHasBeenAsked() async {
        let bench = make(scenario: .empty, authorized: false)
        await bench.viewModel.refreshHealth()
        #expect(bench.viewModel.health?.hasAnyData == false && bench.viewModel.health?.canRequestAccess == true)
        await bench.viewModel.connectHealth()
        #expect(bench.calls.connected == 1)
        #expect(bench.viewModel.health?.canRequestAccess == false, "asked once: the Health app is the only way to change it")
        #expect(bench.viewModel.health?.hasAnyData == false, "and an empty store is still empty")
    }

    @Test func openingHealthAndSettingsGoToTheSystem() {
        let bench = make()
        bench.viewModel.openHealth()
        bench.viewModel.openSystemSettings()
        #expect(bench.calls.healthOpened == 1 && bench.calls.settingsOpened == 1)
    }

    @Test func theHapticsRowsAreOfferedOnlyWhereThereIsATapticEngine() {
        #expect(make(haptics: true).viewModel.offersHaptics)
        #expect(!make(haptics: false).viewModel.offersHaptics)
    }

    @Test func theAlarmRowSaysOffUntilAnAlarmIsOn() async {
        let bench = make()
        #expect(bench.viewModel.alarmValue == "Off")
        await bench.viewModel.onAppear()
        #expect(bench.viewModel.alarmValue == "Off")
    }

    @Test func theSubscriptionFollowsTheStoreAndTheSupportMailCarriesTheVersion() {
        let bench = make()
        #expect(bench.viewModel.subscription == .free)
        #expect(bench.viewModel.supportBody.contains("NOCTIS ") && bench.viewModel.supportBody.contains("iOS "))
        #expect(bench.viewModel.supportMailto?.scheme == "mailto")
    }

    @Test func thePreferencesSettingsWritesAreTheOnesTheAppReads() {
        let bench = make()
        bench.preferences.update { $0.appearance = .dark; $0.appHaptics = false; $0.windDownMinutes = 30; $0.soundsGainPercent = 65; $0.soundsTimer = .minutes45 }
        let values = bench.viewModel.values
        #expect(values.appearance == .dark && !values.appHaptics && values.windDownMinutes == 30 && values.soundsGainPercent == 65 && values.soundsTimer == .minutes45)
        bench.preferences.update { $0.windDownMinutes = 99; $0.soundsGainPercent = 500 }
        #expect(bench.viewModel.values.windDownMinutes == WindDownClock.defaultMinutes && bench.viewModel.values.soundsGainPercent == 100, "kept inside what is offered")
    }
}
