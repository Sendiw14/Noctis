import AppIntents
import Foundation
import SwiftData
import Testing

@testable import AppRoot
@testable import HealthProviding
@testable import InsightsKit
@testable import NightFeature
@testable import NightKit
@testable import NoctisCore
@testable import NoctisIntentKit
@testable import NoctisWidgetKit
@testable import SoundKit

// Siri, Shortcuts and the intents (APP_RULES.md R47): what is said for each data state, what each intent asks the app to do, the flags that
// keep Health numbers behind an unlock, the entities, the phrases, and the real host against real objects.

private let calendar = Fixture.calendar()
private let morning = Fixture.date(2026, 9, 24, 10)

private func snapshot(_ state: WidgetDataState, day: Int = 24) -> WidgetSnapshot {
    var value = WidgetSamples.snapshot(state, now: morning, calendar: calendar)
    value.forDay = WidgetDay(year: 2026, month: 9, day: day)
    return value
}

private let format = WidgetFormat(calendar: calendar, locale: Locale(identifier: "en_US"))

/// The clock writes a narrow no-break space before AM and PM.
private func sp(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }

@MainActor
private final class FakeIntentHost: IntentHost {
    var calls: [String] = []
    var alarmOutcome: AlarmIntentOutcome = .set(minutes: 0)
    var played: SoundKind?
    var lastSleepSound: SoundKind?
    /// The app's own guard refuses the sound.
    var refusesSounds = false
    var coachLimited = false

    func open(_ destination: IntentDestination) { calls.append("open \(destination)") }
    func startWindDown(minutes: Int?) { calls.append("windDown \(minutes.map(String.init) ?? "nil")") }
    func playSleepSounds(_ kind: SoundKind) -> Bool {
        calls.append("play \(kind.rawValue)")
        guard !refusesSounds else { return false }
        played = kind
        lastSleepSound = kind
        return true
    }
    func stopSleepSounds() { calls.append("stop") }
    func endWindDown() { calls.append("end wind-down") }
    func setTonightAlarm(minutes: Int) async -> AlarmIntentOutcome {
        calls.append("alarm \(minutes)")
        if case .set = alarmOutcome { return .set(minutes: minutes) }
        return alarmOutcome
    }
    func askCoach(_ text: String) -> AskCoachOutcome {
        calls.append(coachLimited ? "coach limit" : "coach \(text)")
        return coachLimited ? .limitReached : .asked
    }
}

@MainActor
private func runtime(_ value: WidgetSnapshot?, host: FakeIntentHost? = nil, wait: Double = 0.05) -> IntentRuntime {
    let (now, calendar, format) = (morning, calendar, format)
    let runtime = IntentRuntime(environment: IntentEnvironment(snapshot: { value }, now: { now }, calendar: { calendar }, format: { format }), host: host)
    runtime.hostWaitSeconds = wait
    return runtime
}

// MARK: - What is said

struct IntentAnswerTests {
    private func recovery(_ value: WidgetSnapshot?) -> String { WidgetSpoken.recovery(value, now: morning, calendar: calendar, format: format) }
    private func sleep(_ value: WidgetSnapshot?) -> String { WidgetSpoken.sleep(value, now: morning, calendar: calendar, format: format) }

    @Test func fullDataSaysTheRecoveryAndTheSleep() {
        #expect(recovery(snapshot(.full)) == "Your recovery is 70. Sleep was 6 hours 42 minutes.")
        #expect(recovery(snapshot(.sleepOnly)) == "Your recovery is 68. Sleep was 6 hours 42 minutes.")
        #expect(sleep(snapshot(.full)) == "You slept 6 hours 42 minutes. Sleep quality was 81.")
        var noQuality = snapshot(.full)
        noQuality.lastNight?.quality = nil
        #expect(sleep(noQuality) == "You slept 6 hours 42 minutes.")
    }

    @Test func learningEmptyAndGapSayWhatIsMissingAndNoNumber() {
        for words in [recovery(snapshot(.learning(nightsSoFar: 3))), sleep(snapshot(.learning(nightsSoFar: 3)))] {
            #expect(words == "NOCTIS is still learning your baseline: 3 of 5 nights so far.")
        }
        for state in [WidgetDataState.empty, .noPermission] {
            #expect(recovery(snapshot(state)) == "Open NOCTIS to connect Apple Health." && sleep(snapshot(state)) == "Open NOCTIS to connect Apple Health.")
        }
        #expect(recovery(snapshot(.gap)) == "No sleep was recorded last night." && sleep(snapshot(.gap)) == "No sleep was recorded last night.")
        #expect(recovery(nil) == "Open NOCTIS to get started." && sleep(nil) == "Open NOCTIS to get started.")
    }

    @Test func staleNumbersAreSaidToBeOldNeverAsToday() {
        let stale = snapshot(.stale(hours: 14))
        #expect(recovery(stale) == "The latest numbers are 14 hours old. Your recovery was 70. Sleep was 6 hours 42 minutes.")
        #expect(sleep(stale) == "The latest numbers are 14 hours old. The last recorded sleep was 6 hours 42 minutes. Sleep quality was 81.")
        // Older as time goes on, and in days.
        #expect(WidgetSpoken.recovery(stale, now: morning.addingTimeInterval(3 * 3600), calendar: calendar, format: format).hasPrefix("The latest numbers are 17 hours old."))
        var old = snapshot(.stale(hours: 60))
        old.generatedAt = morning
        #expect(recovery(old).hasPrefix("The latest numbers are 2 days old."))
        // Stale and no score: only the sleep is known.
        var noScore = snapshot(.stale(hours: 30))
        noScore.recovery = nil
        #expect(recovery(noScore) == "The latest numbers are 30 hours old. The last recorded sleep was 6 hours 42 minutes. Sleep quality was 81.")
    }

    @Test func aSnapshotForYesterdayIsWaitingAndNeverYesterdaysNumbers() {
        let yesterday = snapshot(.full, day: 23)
        #expect(recovery(yesterday) == "NOCTIS is waiting for last night's sleep." && sleep(yesterday) == "NOCTIS is waiting for last night's sleep.")
        // Until 4 AM the evening before is still its day: the same rule as the widgets'.
        #expect(WidgetSpoken.recovery(yesterday, now: Fixture.date(2026, 9, 24, 3, 59), calendar: calendar, format: format).hasPrefix("Your recovery"))
        #expect(WidgetSpoken.recovery(yesterday, now: Fixture.date(2026, 9, 24, 4, 0), calendar: calendar, format: format).hasPrefix("NOCTIS is waiting"))
    }

    @Test func theBedtimeIsTheBedtimeOnlyAndIsTheSameInEveryHealthState() {
        for state in [WidgetDataState.full, .learning(nightsSoFar: 1), .empty, .stale(hours: 40), .gap] {
            // The free plan hears the one bedtime and Premium the window around it (R62); neither holds a Health value, in any state.
            #expect(sp(WidgetSpoken.bedtime(snapshot(state).with(tier: .free), format: format)) == "Your bedtime tonight is 11:00 PM.")
            #expect(sp(WidgetSpoken.bedtime(snapshot(state).with(tier: .premium), format: format)) == "Your bedtime window tonight is 10:45 to 11:15 PM.")
        }
        #expect(WidgetSpoken.bedtime(nil, format: format) == "Open NOCTIS to get started.")
        #expect(sp(WidgetSpoken.alarmSet(minutes: 6 * 60 + 30, format: format)) == "Alarm set for 6:30 AM.")
    }

    @Test func everySentenceIsFreeOfTheBannedLanguage() {
        var strings: [String] = []
        let states: [WidgetSnapshot?] = [
            snapshot(.full), snapshot(.sleepOnly), snapshot(.learning(nightsSoFar: 3)), snapshot(.empty), snapshot(.noPermission), snapshot(.stale(hours: 14)),
            snapshot(.stale(hours: 90)), snapshot(.gap), snapshot(.full, day: 23), nil,
        ]
        for value in states {
            strings += [recovery(value), sleep(value), WidgetSpoken.bedtime(value, format: format)]
        }
        strings += [WidgetSpoken.alarmSet(minutes: 390, format: format)]
        strings += [StartWindDownIntent.dialog(length: nil), StartWindDownIntent.withoutApp, PlaySleepSoundsIntent.withoutApp, SetTonightAlarmIntent.withoutApp]
        strings += WindDownLength.allCases.map { StartWindDownIntent.dialog(length: $0) }
        strings += SoundKind.allCases.map { PlaySleepSoundsIntent.dialog(kind: $0) }
        strings += [AlarmIntentOutcome.set(minutes: 450), .couldNotSet, .needsAuthorization].map { SetTonightAlarmIntent.dialog($0, format: format) }
        strings += [AskCoachIntent.noQuestion, AskCoachIntent.opening, AskCoachIntent.withoutApp]
        strings += [IntentGate.startWindDownLocked, IntentGate.coachLimitReached] + SoundKind.allCases.map { IntentGate.premiumSoundDialog($0) }
        strings += [WidgetSpoken.bedtime(snapshot(.full).with(tier: .free), format: format), WidgetSpoken.bedtime(snapshot(.full).with(tier: .premium), format: format)]
        #expect(strings.count > 40)
        for text in strings {
            #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: "\"\(text)\" has \(BannedLanguage.hits(in: text, of: BannedLanguage.coach))"))
        }
    }
}

// MARK: - What each intent does

@MainActor
struct IntentPerformTests {
    private func run<I: AppIntent>(_ intent: I, under runtime: IntentRuntime) async throws {
        _ = try await IntentRuntime.$override.withValue(runtime) { try await intent.perform() }
    }

    @Test func eachOpeningIntentSendsThePersonToItsScreenThroughTheHost() async throws {
        let host = FakeIntentHost()
        let under = runtime(snapshot(.full), host: host)
        try await run(ShowMyRecoveryIntent(), under: under)
        try await run(ShowMySleepIntent(), under: under)
        try await run(ShowRecommendedBedtimeIntent(), under: under)
        #expect(host.calls == ["open recovery", "open sleep", "open bedtime"])
        #expect(ShowMyRecoveryIntent.answer(under) == "Your recovery is 70. Sleep was 6 hours 42 minutes.")
    }

    @Test func theActionIntentsAskTheHostForExactlyWhatWasSaid() async throws {
        let host = FakeIntentHost()
        let under = runtime(snapshot(.full), host: host)
        try await run(StartWindDownIntent(length: .thirtyMinutes), under: under)
        try await run(StartWindDownIntent(), under: under)
        try await run(PlaySleepSoundsIntent(sound: SoundEntity(.ocean)), under: under)
        try await run(PlaySleepSoundsIntent(), under: under)
        try await run(AskCoachIntent(question: "  Why was my sleep short?  "), under: under)
        #expect(host.calls == ["windDown 30", "windDown nil", "play ocean", "play ocean", "coach Why was my sleep short?"], "no sound named: the last one played, here Ocean")
    }

    @Test func theAlarmIsSetOnlyWithAccessAndOtherwiseTheSheetOpens() async throws {
        let host = FakeIntentHost()
        let under = runtime(nil, host: host)
        try await run(SetTonightAlarmIntent(time: DateComponents(hour: 6, minute: 30)), under: under)
        host.alarmOutcome = .needsAuthorization
        try await run(SetTonightAlarmIntent(time: DateComponents(hour: 5, minute: 15)), under: under)
        host.alarmOutcome = .couldNotSet
        try await run(SetTonightAlarmIntent(time: DateComponents(hour: 7)), under: under)
        #expect(host.calls == ["alarm 390", "alarm 315", "open alarm", "alarm 420"], "the sheet opens only when access is missing")
        #expect(SetTonightAlarmIntent(time: DateComponents(hour: 25, minute: 70)).minutes == (25 * 60 + 70) % 1440)
    }

    @Test func aQuestionIsTrimmedBoundedAndNeverKeptByTheIntent() async throws {
        let host = FakeIntentHost()
        let under = runtime(nil, host: host)
        let long = String(repeating: "a", count: 500)
        #expect(AskCoachIntent(question: long).cleaned.count == AskCoachIntent.maximumLength)
        try await run(AskCoachIntent(question: "   "), under: under)
        #expect(host.calls.isEmpty, "nothing to ask: Coach is not opened")
        try await run(AskCoachIntent(question: long), under: under)
        #expect(host.calls.count == 1)
        // The intent holds nothing: no storage, no log, no donation.
        let source = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisIntentKit/ActionIntents.swift"), encoding: .utf8)
        let ask = try #require(source.range(of: "public struct AskCoachIntent"))
        let code = RawDefaultsTests.code(String(source[ask.lowerBound...]))
        for token in ["UserDefaults", "Logger", "os_log", "print(", ".donate(", "FileManager", "NoctisAnalytics", "write(to"] {
            #expect(!code.contains(token), Comment(rawValue: "AskCoachIntent uses \(token)"))
        }
        #expect(code.contains("host.askCoach(cleaned)"), "the one thing it does is hand the text to Coach")
    }

    @Test func withoutTheAppAnIntentSaysToOpenItAndDoesNothing() async throws {
        let under = runtime(snapshot(.full), host: nil, wait: 0.05)
        // These return their "open NOCTIS" sentence; nothing throws and nothing is called.
        try await run(ShowMyRecoveryIntent(), under: under)
        try await run(StartWindDownIntent(), under: under)
        try await run(PlaySleepSoundsIntent(), under: under)
        try await run(SetTonightAlarmIntent(time: DateComponents(hour: 6)), under: under)
        try await run(AskCoachIntent(question: "Hello"), under: under)
        let found = await under.host(waiting: 0.01)
        #expect(found == nil)
    }

    @Test func aHostThatArrivesWhileAnIntentWaitsIsUsed() async throws {
        let host = FakeIntentHost()
        let under = runtime(snapshot(.full), host: nil, wait: 5)
        async let running: Void = run(StartWindDownIntent(length: .tenMinutes), under: under)
        try await Task.sleep(for: .milliseconds(100))
        under.install(host)
        try await running
        #expect(host.calls == ["windDown 10"], "a background launch finished starting: the intent found the app")
    }

    // MARK: Flags

    @Test func onlyTheIntentsThatSpeakHealthNumbersAskForTheDeviceToBeUnlocked() {
        #expect(ShowMyRecoveryIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(ShowMySleepIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(ShowRecommendedBedtimeIntent.authenticationPolicy == .alwaysAllowed, "the bedtime is the plan, not Health")
        #expect(StartWindDownIntent.authenticationPolicy == .alwaysAllowed && SetTonightAlarmIntent.authenticationPolicy == .alwaysAllowed)
        #expect(PlaySleepSoundsIntent.authenticationPolicy == .alwaysAllowed && AskCoachIntent.authenticationPolicy == .alwaysAllowed)
    }

    @Test func eachIntentOpensTheAppOrNotAsItsLabelSays() {
        #expect(ShowMyRecoveryIntent.supportedModes == .foreground(.immediate) && ShowMySleepIntent.supportedModes == .foreground(.immediate))
        #expect(ShowRecommendedBedtimeIntent.supportedModes == .foreground(.immediate) && StartWindDownIntent.supportedModes == .foreground(.immediate))
        #expect(AskCoachIntent.supportedModes == .foreground(.immediate))
        // The alarm works in the background, and goes to the foreground only to ask for access.
        #expect(SetTonightAlarmIntent.supportedModes.contains(.background) && SetTonightAlarmIntent.supportedModes.contains(.foreground(.dynamic)))
        // Sleep sounds start without a visible launch: an audio playback intent, which iOS runs in the app's own process.
        let audio: [any AppIntent.Type] = [PlaySleepSoundsIntent.self]
        let others: [any AppIntent.Type] = [ShowMyRecoveryIntent.self, StartWindDownIntent.self, SetTonightAlarmIntent.self, AskCoachIntent.self]
        #expect(audio.allSatisfy { $0 is any AudioPlaybackIntent.Type })
        #expect(others.allSatisfy { !($0 is any AudioPlaybackIntent.Type) })
    }
}

// MARK: - Entities

struct IntentEntityTests {
    @Test func theSoundEntitiesAreTheShippedSoundsAndNothingElse() async throws {
        let query = SoundEntityQuery()
        let all = try await query.suggestedEntities()
        #expect(all.map(\.id) == SoundKind.allCases.map(\.rawValue) && all.count == 6)
        #expect(all.compactMap(\.kind) == SoundKind.allCases)
        let found = try await query.entities(for: ["rain", "forest", "wind"])
        #expect(found.map(\.id) == ["rain", "wind"], "a sound NOCTIS does not ship is no entity")
        #expect(SoundEntity(id: "gone").kind == nil)
    }

    @Test func aSoundCanBeFoundByWhatItIsCalled() async throws {
        let query = SoundEntityQuery()
        let rain = try await query.entities(matching: "rain")
        let brown = try await query.entities(matching: "Brown noise")
        let ocean = try await query.entities(matching: "ocean sounds")
        let everything = try await query.entities(matching: "  ")
        let nothing = try await query.entities(matching: "zzz")
        #expect(rain.map(\.id) == ["rain"] && brown.map(\.id) == ["brown"] && ocean.map(\.id) == ["ocean"])
        #expect(everything.count == 6 && nothing.isEmpty)
    }

    @Test func theSoundListIsNotWrittenOutAgain() throws {
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources/NoctisIntentKit"]) {
            let code = RawDefaultsTests.code(file.text).lowercased()
            for kind in SoundKind.allCases { #expect(!code.contains("\"\(kind.rawValue)\""), Comment(rawValue: "\(file.path) names \(kind.rawValue) itself")) }
        }
    }

    @Test func theLengthsAreTheWindDownsOwn() {
        #expect(WindDownLength.allCases.map(\.minutes) == WindDownClock.options)
        #expect(Set(WindDownLength.caseDisplayRepresentations.keys) == Set(WindDownLength.allCases))
    }
}

// MARK: - The phrases

struct AppShortcutsTests {
    private let phrases = [
        "Show my recovery in NOCTIS", "Show my sleep in NOCTIS", "Start my wind-down in NOCTIS", "What time should I sleep in NOCTIS",
        "Start my sleep sounds in NOCTIS", "Ask Coach in NOCTIS",
    ]

    @Test func theProviderHasTheSixPhrasesEachSayingTheAppsNameWithATitleASymbolAndADescription() throws {
        let source = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/NoctisShortcuts.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(source)
        let found = code.matches(of: /phrases: \["([^"]+)"\]/).map { String($0.1) }
        #expect(found.count == 6)
        #expect(found.map { $0.replacingOccurrences(of: "\\(.applicationName)", with: "NOCTIS") } == phrases)
        #expect(found.allSatisfy { $0.contains("\\(.applicationName)") }, "every phrase says the app's name")
        #expect(code.matches(of: /shortTitle: "[^"]+", systemImageName: "[a-z0-9.]+"/).count == 6)
        // The intents name a description each (the Shortcuts gallery shows it).
        let intents = RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources/NoctisIntentKit"]).map(\.text).joined()
        for name in ["ShowMyRecoveryIntent", "ShowMySleepIntent", "StartWindDownIntent", "ShowRecommendedBedtimeIntent", "PlaySleepSoundsIntent", "AskCoachIntent"] {
            #expect(code.contains("\(name)()"), Comment(rawValue: "\(name) has no shortcut"))
            #expect(intents.contains("struct \(name)"))
        }
        #expect(intents.components(separatedBy: "public static let description = IntentDescription(").count - 1 >= 7)
    }

    @Test func theStringCatalogHasEveryPhraseSoItCanBeTranslated() throws {
        let data = try Data(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/AppShortcuts.xcstrings"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(Set(strings.keys) == Set(phrases.map { $0.replacingOccurrences(of: "NOCTIS", with: "${applicationName}") }))
        #expect(catalog["sourceLanguage"] as? String == "en")
    }

    @Test func thePhrasesAreFreeOfTheBannedLanguageExceptTheQuestionTheyAnswer() {
        // "What time should I sleep" is what a person says; the app never says it back.
        for phrase in phrases where phrase != "What time should I sleep in NOCTIS" {
            #expect(BannedLanguage.hits(in: phrase, of: BannedLanguage.coach).isEmpty, Comment(rawValue: phrase))
        }
    }

    @Test func theAppAndTheWidgetExtensionBothReachTheIntents() throws {
        let app = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/NoctisShortcuts.swift"), encoding: .utf8)
        #expect(app.contains("NoctisIntentKitPackage.self"))
        let kit = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Package.swift"), encoding: .utf8)
        #expect(kit.contains(#"name: "NoctisIntentKit", dependencies: ["NoctisWidgetKit", "SoundCatalog"]"#), "the intents depend on the snapshot and the sound names, never on Health, SwiftData, Coach or the player")
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources/NoctisIntentKit"]) {
            let code = RawDefaultsTests.code(file.text)
            for token in ["import HealthKit", "import HealthProviding", "import SoundKit", "import SwiftData", "import CoachKit", "import JournalKit", "import NoctisCore", "import SleepKit", "import RecoveryKit", "import AppRoot"] {
                #expect(!code.contains(token), Comment(rawValue: "\(file.path) has \(token)"))
            }
        }
    }
}

// MARK: - The app's side

@MainActor
struct IntentHostTests {
    private struct Bench {
        let host: AppIntentHost
        let model: AppModel
        let preferences: AppPreferences
        let player: PlayerBench
        let sounds: SoundsViewModel
        let backend: MockAlarmBackend
        let alarm: AlarmService

        init(alarm mode: MockAlarmBackend.Mode = .authorized) throws {
            let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
            let preferences = AppPreferences(defaults: UserDefaults(suiteName: "noctis.intent.\(UUID().uuidString)") ?? .standard)
            let player = PlayerBench.make()
            let sounds = SoundsViewModel(player: player.player, haptic: {}, defaultTimer: { preferences.values.soundsTimer })
            let backend = MockAlarmBackend(mode: mode)
            let alarm = AlarmService(backend: backend, store: MemoryAlarmStore(), defaultMinutes: { 7 * 60 })
            self.model = model
            self.preferences = preferences
            self.player = player
            self.sounds = sounds
            self.backend = backend
            self.alarm = alarm
            host = AppIntentHost(model: model, preferences: preferences, player: player.player, sounds: sounds, alarm: alarm)
        }
    }

    @Test func everyDestinationIsOpenedByTheAppsOwnRoutePath() {
        #expect(IntentRouting.route(for: .recovery) == WidgetURLRouter.route(for: .recovery), "the strict router the widgets use")
        #expect(IntentRouting.route(for: .sleep) == WidgetURLRouter.route(for: .sleep))
        #expect(IntentRouting.route(for: .bedtime) == WidgetURLRouter.route(for: .bedtime) && IntentRouting.route(for: .bedtime) == .tonight)
        #expect(IntentRouting.route(for: .windDown(autostart: true)) == .windDown(autostart: true))
        #expect(IntentRouting.route(for: .alarm) == .alarm && IntentRouting.route(for: .coach) == .coach())
    }

    @Test func openingGoesThroughTheModelsOneOpen() throws {
        let bench = try Bench()
        bench.host.open(.recovery)
        #expect(bench.model.selectedTab == .recovery)
        bench.host.open(.sleep)
        #expect(bench.model.selectedTab == .sleep)
        bench.host.open(.bedtime)
        #expect(bench.model.homePath == [.tonight])
        bench.host.open(.alarm)
        #expect(bench.model.takeAlarmDestination() != nil)
    }

    @Test func aWindDownFromSiriSetsTheLengthThenOpensTheScreenToBeginIt() throws {
        let bench = try Bench()
        bench.host.startWindDown(minutes: 20)
        #expect(bench.preferences.values.windDownMinutes == 20)
        #expect(bench.model.homePath == [.tonight, .windDown(autostart: true)])
        bench.host.startWindDown(minutes: 25)
        #expect(bench.preferences.values.windDownMinutes == 20, "a length the wind-down does not have changes nothing")
        bench.host.startWindDown(minutes: nil)
        #expect(bench.preferences.values.windDownMinutes == 20, "no length: the last one")
    }

    @Test func sleepSoundsStartThroughThePlayerAndRespectWhatIsPlaying() throws {
        let bench = try Bench()
        // Nothing played before: the host has no last sound (the intent turns that into Rain).
        #expect(bench.host.lastSleepSound == nil)
        #expect(bench.host.playSleepSounds(.rain) && bench.player.player.state.kind == .rain && bench.player.player.state.phase == .playing)
        // Saying "play" again does not pause it.
        _ = bench.host.playSleepSounds(.rain)
        #expect(bench.player.player.state.phase == .playing)
        // Another sound crosses over; the last one played is remembered.
        #expect(bench.host.playSleepSounds(.ocean) && bench.player.player.lastKind == .ocean && bench.host.lastSleepSound == .ocean)
        // Paused by the person: play resumes it.
        bench.player.player.pause()
        _ = bench.host.playSleepSounds(.ocean)
        #expect(bench.player.player.state.phase == .playing)
    }

    @Test func aSoundThatBeginsFromSilenceTakesTheDefaultTimer() throws {
        let bench = try Bench()
        bench.preferences.update { $0.soundsTimer = .minutes30 }
        _ = bench.host.playSleepSounds(.wind)
        #expect(bench.player.player.state.timer != nil)
    }

    @Test func theAlarmIsSetOnlyWhenAlarmsAreAlreadyAllowed() async throws {
        let allowed = try Bench(alarm: .authorized)
        let first = await allowed.host.setTonightAlarm(minutes: 6 * 60 + 30)
        #expect(first == .set(minutes: 6 * 60 + 30))
        #expect(allowed.backend.scheduleCalls == 1 && allowed.backend.promptCount == 0)
        let stored = await allowed.alarm.status().settings.minutesSinceMidnight
        #expect(stored == 6 * 60 + 30)
        // Again, a new time: the same alarm moves.
        let moved = await allowed.host.setTonightAlarm(minutes: 5 * 60)
        #expect(moved == .set(minutes: 5 * 60))

        // Not asked yet: nothing is scheduled and the system's question is not put to the person from a spoken request.
        let fresh = try Bench(alarm: .notDetermined)
        let unasked = await fresh.host.setTonightAlarm(minutes: 6 * 60)
        #expect(unasked == .needsAuthorization)
        #expect(fresh.backend.scheduleCalls == 0 && fresh.backend.promptCount == 0)
        let denied = try Bench(alarm: .denied)
        let refused = await denied.host.setTonightAlarm(minutes: 6 * 60)
        #expect(refused == .needsAuthorization)
        #expect(denied.backend.scheduleCalls == 0 && denied.backend.promptCount == 0)
    }

    @Test func theLastSoundIsKeptForOneKeyAndForgottenWithTheSavedVolumes() throws {
        let bench = try Bench()
        #expect(bench.player.player.lastKind == nil)
        _ = bench.host.playSleepSounds(.wind)
        #expect(bench.player.defaults.string(forKey: SoundPlayer.lastKindKey) == "wind" && bench.player.player.lastKind == .wind)
        bench.player.player.forgetSavedGains()
        #expect(bench.player.player.lastKind == nil && bench.player.defaults.string(forKey: SoundPlayer.lastKindKey) == nil)
    }

    @Test func coachIsOpenedOnTheTextAndTheTabTakesItOnce() throws {
        let bench = try Bench()
        #expect(bench.host.askCoach("Why was my sleep short?") == .asked)
        #expect(bench.model.selectedTab == .coach)
        let destination = try #require(bench.model.takeCoachDestination())
        #expect(destination.text == "Why was my sleep short?" && destination.question == nil)
        #expect(bench.model.takeCoachDestination() == nil, "held in memory until taken, then gone")
    }
}
