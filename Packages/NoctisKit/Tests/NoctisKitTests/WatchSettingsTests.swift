import Foundation
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import NightKit
@testable import NoctisCore
@testable import NoctisWidgetKit
@testable import ProfileFeature
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SoundKit

// Settings > Apple Watch (APP_RULES.md R29, R50, R52): the row exists only while a Watch is paired, the page says what the iPhone can really tell,
// and "Send update now" says what happened. Pure content, so every sentence is a unit test.

private nonisolated let ny: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    return calendar
}()

/// 2026-09-24 10:00 in New York.
private nonisolated let settingsClock = Date(timeIntervalSince1970: 1_790_258_400)

private nonisolated func status(
    supported: Bool = true, paired: Bool = true, installed: Bool = true, activation: WatchActivation = .activated, reachable: Bool = true, lastSent: Date? = nil
) -> WatchConnectionStatus {
    WatchConnectionStatus(
        isSupported: supported, isPaired: paired, isWatchAppInstalled: installed, activation: activation, isReachable: reachable, lastSentAt: lastSent)
}

private func content(_ value: WatchConnectionStatus) -> WatchSettingsContent {
    WatchSettingsContent.make(value, now: settingsClock, calendar: ny, locale: Locale(identifier: "en_US"))
}

struct WatchSettingsContentTests {
    @Test func eachStateOfTheLinkHasItsOwnWordsAndOnlyAnInstalledWatchCanBeSent() {
        let cases: [(WatchConnectionStatus, String, String, Bool)] = [
            (status(supported: false), "Not available", "Not available", false),
            (status(paired: false), "No Apple Watch paired", "None paired", false),
            (status(activation: .notActivated), "Connecting", "Connecting", false),
            (status(installed: false), "Watch app not installed", "Not installed", false),
            (status(reachable: true), "Connected", "Connected", true),
            (status(reachable: false), "Not reachable", "Not reachable", true),
        ]
        for (value, title, row, canSend) in cases {
            let made = content(value)
            #expect(made.statusTitle == title && made.rowValue == row && made.canSend == canSend, Comment(rawValue: "\(value.connection)"))
            #expect(!made.statusDetail.isEmpty && made.canSend == value.canSend, Comment(rawValue: "\(value.connection)"))
        }
    }

    @Test func theInstallInstructionIsShownOnlyWhileTheWatchAppIsNotThere() {
        #expect(content(status(installed: false)).installInstruction == WatchSettingsContent.installSteps)
        #expect(WatchSettingsContent.installSteps.contains("Watch app") && WatchSettingsContent.installSteps.contains("Install"))
        for value in [status(), status(reachable: false), status(paired: false), status(supported: false), status(activation: .notActivated)] {
            #expect(content(value).installInstruction == nil, Comment(rawValue: "\(value.connection)"))
        }
    }

    @Test func theSettingsRowExistsOnlyForAPairedWatchOnASupportingPhone() {
        #expect(status().showsSettingsRow)
        #expect(status(installed: false).showsSettingsRow, "a Watch without the app is the case the page explains")
        #expect(!status(paired: false).showsSettingsRow)
        #expect(!status(supported: false, paired: true).showsSettingsRow)
        #expect(!WatchConnectionStatus.unsupported.showsSettingsRow)
    }

    @Test func theLastSentTimeIsTheLocalesAndSaysTodayYesterdayOrTheDay() {
        let locale = Locale(identifier: "en_US")
        func line(_ date: Date?) -> String { WatchSettingsContent.lastSentLine(date, now: settingsClock, calendar: ny, locale: locale) }
        func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }
        let sevenAM = settingsClock.addingTimeInterval(-3 * 3600)
        #expect(plain(line(sevenAM)) == "Last sent today at 7:00 AM")
        #expect(plain(line(settingsClock.addingTimeInterval(-11 * 3600))) == "Last sent yesterday at 11:00 PM")
        #expect(plain(line(settingsClock.addingTimeInterval(-34 * 3600))).hasPrefix("Last sent yesterday at"))
        #expect(plain(line(settingsClock.addingTimeInterval(-5 * 86_400))) == "Last sent Sep 19 at 10:00 AM")
        #expect(line(nil) == "Nothing sent yet")
        // A 24-hour locale has no period.
        let german = WatchSettingsContent.lastSentLine(sevenAM, now: settingsClock, calendar: ny, locale: Locale(identifier: "de_DE"))
        #expect(!german.contains("AM") && !german.contains("PM"))
    }

    @Test func theLastSentLineIsShownOnlyWhereAnUpdateCanBeSent() {
        let sent = settingsClock.addingTimeInterval(-3600)
        #expect(content(status(lastSent: sent)).lastSent?.hasPrefix("Last sent today") == true)
        #expect(content(status(reachable: false, lastSent: sent)).lastSent?.hasPrefix("Last sent today") == true)
        #expect(content(status(lastSent: nil)).lastSent == "Nothing sent yet")
        #expect(content(status(installed: false, lastSent: sent)).lastSent == nil)
        #expect(content(status(paired: false)).lastSent == nil)
    }

    @Test func whatSendUpdateNowDidIsSaidInWords() {
        #expect(WatchSettingsContent.sendResult(.sent(settingsClock), reachable: true) == "Update sent to your Watch.")
        #expect(WatchSettingsContent.sendResult(.sent(settingsClock), reachable: false).hasPrefix("Update queued."))
        #expect(WatchSettingsContent.sendResult(.nothingToSend, reachable: true).hasPrefix("There's nothing to send yet."))
        #expect(WatchSettingsContent.sendResult(.appNotInstalled, reachable: false) == "NOCTIS isn't installed on your Watch yet.")
        #expect(WatchSettingsContent.sendResult(.noWatchPaired, reachable: false) == WatchSettingsContent.sendResult(.notSupported, reachable: false))
        #expect(WatchSettingsContent.sendResult(.notActivated, reachable: false).contains("Try again"))
        #expect(
            WatchSettingsContent.sendResult(.failed("The system would not queue the update."), reachable: true)
                == "Couldn't send the update. The system would not queue the update.")
    }

    @Test func everySentenceIsFreeOfTheBannedLanguageAndMakesNoHealthClaim() {
        var strings =
            WatchSettingsContent.appears + [
                WatchSettingsContent.readsNothing, WatchSettingsContent.deleteNote, WatchSettingsContent.sendButton, WatchSettingsContent.sendHint,
                WatchSettingsContent.installSteps,
            ]
        for value in [
            status(supported: false), status(paired: false), status(activation: .notActivated), status(installed: false), status(), status(reachable: false),
            status(lastSent: settingsClock.addingTimeInterval(-60)),
        ] {
            let made = content(value)
            strings += [made.statusTitle, made.statusDetail, made.rowValue] + [made.lastSent, made.installInstruction].compactMap { $0 }
        }
        for outcome in [
            WatchSendOutcome.sent(settingsClock), .nothingToSend, .appNotInstalled, .noWatchPaired, .notSupported, .notActivated,
            .failed("The summary could not be prepared."),
        ] {
            strings += [WatchSettingsContent.sendResult(outcome, reachable: true), WatchSettingsContent.sendResult(outcome, reachable: false)]
        }
        for text in strings {
            #expect(
                BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty,
                Comment(rawValue: "\"\(text)\" has \(BannedLanguage.hits(in: text, of: BannedLanguage.coach))"))
        }
    }

    @Test func thePageListsWhatTheWatchShowsAndTheWatchPagesShowExactlyThat() {
        #expect(WatchSettingsContent.appears.count == 4)
        // One line for each of the Watch's four pages of numbers: Recovery, Sleep, Heart, Tonight.
        #expect(WatchSettingsContent.appears[0].contains("recovery") && WatchSettingsContent.appears[1].contains("sleep"))
        #expect(WatchSettingsContent.appears[2].contains("Heart rate variability") && WatchSettingsContent.appears[3].contains("alarm"))
        #expect(WatchSettingsContent.readsNothing.contains("reads nothing from Apple Health"))
    }

    @Test func theAppleWatchPageIsReachableByItsTokenAndALink() {
        #expect(SettingsPage(token: "apple-watch") == .appleWatch && SettingsPage(token: "applewatch") == .appleWatch)
        #expect(SettingsPage.appleWatch.title == "Apple Watch")
        #expect(AppRoute(url: AppRoute.settings(section: .appleWatch).url) == .settings(section: .appleWatch))
    }
}

// MARK: - The view model

struct WatchSettingsViewModelTests {
    private func make(watch: WatchSyncService?) -> SettingsViewModel {
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? NoctisUserDefaults.standard
        let preferences = AppPreferences(defaults: defaults)
        let center = InMemoryNotificationCenter(authorization: .allowed)
        let coordinator = NotificationCoordinator(
            scheduler: NotificationScheduler(center: center), preferences: preferences, profile: { UserProfileSnapshot() }, bedtimeCenter: { _, _ in 23 * 60 }
        )
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: settingsClock, calendar: ny, startAuthorized: true)
        return SettingsViewModel(
            preferences: preferences, notifications: coordinator, store: StoreManager(), health: HealthDataStatusReader(provider: provider),
            alarm: AlarmService(backend: MockAlarmBackend(mode: .authorized), store: MemoryAlarmStore(), defaultMinutes: { 7 * 60 }),
            profile: { UserProfileSnapshot(typicalWakeMinutes: 7 * 60, needMinutes: 8 * 60) }, connectHealth: {}, hapticsAvailable: { true },
            format: HomeFormat(calendar: ny, locale: Locale(identifier: "en_US")), bundle: .main, preferredLanguages: { ["en"] }, clock: { settingsClock },
            data: DataManager(erasers: [:], providers: [:], deleteAllSteps: []), watch: watch
        )
    }

    private func service(_ session: FakeWatchSession, stored: @escaping @Sendable () -> WidgetSnapshot? = { nil }) -> WatchSyncService {
        let defaults = WatchSyncDefaults(defaults: UserDefaults(suiteName: "noctis.watch.\(UUID().uuidString)") ?? .standard)
        return WatchSyncService(session: session, defaults: defaults, clock: { settingsClock }, signpost: { _ in }, stored: stored)
    }

    @Test func withoutALinkThereIsNoRowAndNothingToSend() async {
        let viewModel = make(watch: nil)
        #expect(!viewModel.offersWatch && viewModel.watchStatus == .unsupported)
        await viewModel.sendWatchUpdate()
        #expect(viewModel.watchSendMessage == nil)
    }

    @Test func theRowAppearsForAPairedWatchTheMomentTheViewModelIsMade() {
        let paired = FakeWatchSession()
        #expect(make(watch: service(paired)).offersWatch)
        let none = FakeWatchSession()
        none.isPaired = false
        #expect(!make(watch: service(none)).offersWatch)
        let unsupported = FakeWatchSession()
        unsupported.isSupported = false
        #expect(!make(watch: service(unsupported)).offersWatch)
    }

    @Test func sendingQueuesTheLatestSummaryAndSaysSo() async throws {
        let session = FakeWatchSession()
        let watch = service(session)
        let viewModel = make(watch: watch)
        // Nothing has been written yet, so there is nothing to send, and it says so.
        await viewModel.sendWatchUpdate()
        #expect(viewModel.watchSendMessage?.hasPrefix("There's nothing to send yet.") == true && session.contexts.isEmpty)
        // After the summary exists, the button queues it.
        await watch.publish(WidgetSamples.snapshot(.full, now: settingsClock, calendar: ny))
        let before = session.contexts.count
        await viewModel.sendWatchUpdate()
        #expect(session.contexts.count == before + 1)
        #expect(viewModel.watchSendMessage == "Update sent to your Watch." && !viewModel.isSendingToWatch)
        #expect(viewModel.watchStatus.lastSentAt == settingsClock)
    }

    @Test func aSummaryTheWidgetsSavedIsSentEvenBeforeAnythingWasWrittenInThisLaunch() async {
        let session = FakeWatchSession()
        let saved = WidgetSamples.snapshot(.full, now: settingsClock, calendar: ny)
        let viewModel = make(watch: service(session, stored: { saved }))
        await viewModel.sendWatchUpdate()
        #expect(session.contexts.count == 1 && viewModel.watchSendMessage == "Update sent to your Watch.")
    }

    @Test func anUnreachableWatchIsToldItWillGetTheUpdateWhenItConnects() async {
        let session = FakeWatchSession()
        session.isReachable = false
        let watch = service(session)
        let viewModel = make(watch: watch)
        await watch.publish(WidgetSamples.snapshot(.full, now: settingsClock, calendar: ny))
        await viewModel.sendWatchUpdate()
        #expect(viewModel.watchSendMessage?.hasPrefix("Update queued.") == true)
        #expect(viewModel.watchContent.statusTitle == "Not reachable")
    }

    @Test func aWatchWithoutTheAppIsToldToInstallItAndNothingIsQueued() async {
        let session = FakeWatchSession()
        session.isWatchAppInstalled = false
        let watch = service(session)
        let viewModel = make(watch: watch)
        await watch.publish(WidgetSamples.snapshot(.full, now: settingsClock, calendar: ny))
        await viewModel.sendWatchUpdate()
        #expect(session.contexts.isEmpty && viewModel.watchSendMessage == "NOCTIS isn't installed on your Watch yet.")
        #expect(viewModel.watchContent.installInstruction == WatchSettingsContent.installSteps && !viewModel.watchContent.canSend)
    }

    @Test func aFailureSaysWhyAndTheButtonIsFreeAgain() async {
        let session = FakeWatchSession()
        session.failUpdates = true
        let watch = service(session)
        let viewModel = make(watch: watch)
        await watch.publish(WidgetSamples.snapshot(.full, now: settingsClock, calendar: ny))
        await viewModel.sendWatchUpdate()
        #expect(viewModel.watchSendMessage?.hasPrefix("Couldn't send the update.") == true && !viewModel.isSendingToWatch)
    }

    /// Waits for `condition` by the clock (the whole suite shares the main actor, so a count of turns is not a time).
    private func eventually(_ condition: @MainActor () -> Bool) async {
        _ = await waitFor { condition() }
    }

    @Test func theStatusFollowsTheLinkWhileThePageIsOpen() async {
        let session = FakeWatchSession()
        let watch = service(session)
        // The app activates the link once, at launch; that is what makes the session tell the service about changes.
        await watch.activate()
        let viewModel = make(watch: watch)
        let following = Task { await viewModel.followWatch() }
        defer { following.cancel() }
        #expect(viewModel.watchStatus.connection == .connected)
        session.isReachable = false
        // Said again each turn: the page may not be listening yet when the first change comes.
        await eventually {
            session.linkChanged()
            return viewModel.watchStatus.connection == .notReachable
        }
        #expect(viewModel.watchStatus.connection == .notReachable)
        session.isPaired = false
        await eventually {
            session.linkChanged()
            return !viewModel.offersWatch
        }
        #expect(!viewModel.offersWatch, "unpairing the Watch takes the row away")
    }
}
