import AppIntents
import Foundation
import SwiftData
import Testing

@testable import AppRoot
@testable import HealthProviding
@testable import NightFeature
@testable import NightKit
@testable import NoctisCore
@testable import NoctisIntentKit
@testable import NoctisWidgetKit
@testable import SoundKit

// The Sleep sounds control and the Wind down control (APP_RULES.md R48): the record the toggle reads, the publisher that keeps it true to the
// one sound player, what the control's intent asks of the app, and what the extension may and may not hold.

private let now = Fixture.date(2026, 9, 24, 23)

private func tempStore() throws -> (SleepSoundsStore, URL) {
    let directory = try WidgetFixture.directory()
    return (SleepSoundsStore(directory: directory), directory)
}

private func playing(_ plan: SleepTimerPlan? = nil, gain: Float? = nil) -> SoundPlayerState {
    var state = SoundPlayerState(kind: .rain, phase: .playing, timer: plan)
    if let gain { state.gains[.rain] = gain }
    return state
}

// MARK: - The record

struct SleepSoundsStateTests {
    @Test func itSaysOnlyThatASoundPlaysAndWhenItsTimerEnds() throws {
        let state = SleepSoundsState(endsAt: now.addingTimeInterval(1800))
        let data = try state.encoded()
        #expect(SleepSoundsState.decode(data) == state)
        #expect(data.count < SleepSoundsState.maximumBytes / 2, "a few dozen bytes")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["version", "endsAt"], "no sound name, no start time, nothing about what was played")
        #expect(Set(try #require(try JSONSerialization.jsonObject(with: SleepSoundsState().encoded()) as? [String: Any]).keys) == ["version"])
    }

    @Test func aRecordIsPlayingUntilItsTimerEndsAndNeverForAnotherVersion() {
        #expect(SleepSoundsState().isPlaying(at: now), "no timer: until the app says otherwise")
        #expect(SleepSoundsState(endsAt: now.addingTimeInterval(60)).isPlaying(at: now))
        #expect(!SleepSoundsState(endsAt: now).isPlaying(at: now), "the moment the timer ends it is over")
        #expect(!SleepSoundsState(endsAt: now.addingTimeInterval(-1)).isPlaying(at: now), "a record the app could not take back is wrong once its timer has ended")
        #expect(!SleepSoundsState(version: 2).isPlaying(at: now))
    }

    @Test func aRecordThatIsAnotherVersionsOrTooBigOrDamagedIsNothingPlaying() throws {
        let other = try SleepSoundsState(version: 2).encoded()
        #expect(SleepSoundsState.decode(other) == nil)
        #expect(SleepSoundsState.decode(Data("not json".utf8)) == nil)
        #expect(SleepSoundsState.decode(Data(count: SleepSoundsState.maximumBytes + 1)) == nil)
    }
}

struct SleepSoundsStoreTests {
    @Test func itIsWrittenReadAndDeletedInTheGroupFolder() throws {
        let (store, directory) = try tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.fileURL.lastPathComponent == "SleepSoundsState.json" && store.fileURL.deletingLastPathComponent().path == directory.path)
        #expect(store.load() == nil && !store.exists && !store.isPlaying(at: now), "no file: nothing plays")
        let record = SleepSoundsState(endsAt: now.addingTimeInterval(900))
        #expect(store.save(record) && store.exists && store.load() == record)
        #expect(store.isPlaying(at: now) && !store.isPlaying(at: now.addingTimeInterval(901)))
        store.delete()
        #expect(!store.exists && !store.isPlaying(at: now))
        store.delete()
        #expect(!store.exists, "nothing to delete is not an error")
    }

    @Test func itIsKeptOutOfBackups() throws {
        let (store, directory) = try tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.save(SleepSoundsState()))
        let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func aFileNothingCanReadIsNeverPlaying() throws {
        let (store, directory) = try tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("garbage".utf8).write(to: store.fileURL)
        #expect(store.exists && store.load() == nil && !store.isPlaying(at: now))
    }

    @Test func itReusesTheWidgetsContainerAndNeverNamesTheGroupItself() throws {
        let source = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWidgetKit/SleepSoundsState.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(source)
        #expect(code.contains("WidgetSnapshotStore.containerURL"))
        #expect(!code.contains("group.com.noctis") && !code.contains("forSecurityApplicationGroupIdentifier"))
        #expect(!code.contains("UserDefaults"), "no defaults suite is shared")
        #expect(ControlKind.windDown != ControlKind.sleepSounds && ControlKind.sleepSounds.hasPrefix("com.noctis.app.control."))
    }
}

// MARK: - What a control draws

struct SleepSoundsPublisherTests {
    @Test func onlyAPlayingSoundIsARecordAndPausedOrInterruptedIsNot() {
        let plan = SleepTimerPlan(start: now, choice: .minutes30)
        #expect(SleepSoundsPublisher.record(for: SoundPlayerState()) == nil)
        #expect(SleepSoundsPublisher.record(for: playing()) == SleepSoundsState(endsAt: nil))
        #expect(SleepSoundsPublisher.record(for: playing(plan)) == SleepSoundsState(endsAt: plan.end))
        for phase in [SoundPlaybackPhase.paused, .interrupted, .stopped] {
            #expect(SleepSoundsPublisher.record(for: SoundPlayerState(kind: .rain, phase: phase, timer: plan)) == nil, "not audible: the control must not say it is")
        }
    }

    @MainActor
    final class ReloadBox { var count = 0 }

    @MainActor
    private final class Bench {
        let store: SleepSoundsStore
        let directory: URL
        let box: ReloadBox
        let publisher: SleepSoundsPublisher

        init(existing: SleepSoundsState? = nil, damaged: Bool = false) throws {
            let (store, directory) = try tempStore()
            if let existing { store.save(existing) }
            if damaged { try Data("garbage".utf8).write(to: store.fileURL) }
            let box = ReloadBox()
            self.store = store
            self.directory = directory
            self.box = box
            publisher = SleepSoundsPublisher(store: store, reload: { box.count += 1 })
        }

        var reloadsSoFar: Int { box.count }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @Test @MainActor func aSoundStartingWritesOnceAndStoppingDeletesAndEachRedrawsTheControl() throws {
        let bench = try Bench()
        bench.publisher.apply(SoundPlayerState())
        #expect(!bench.store.exists && bench.reloadsSoFar == 0, "launched with nothing playing and nothing written: nothing to redraw")
        bench.publisher.apply(playing())
        #expect(bench.store.load() == SleepSoundsState() && bench.reloadsSoFar == 1)
        bench.publisher.apply(playing(gain: 0.7))
        bench.publisher.apply(playing(gain: 0.2))
        #expect(bench.reloadsSoFar == 1, "a volume change is not something the control draws")
        bench.publisher.apply(SoundPlayerState(kind: .rain, phase: .paused))
        #expect(!bench.store.exists && bench.reloadsSoFar == 2)
        bench.publisher.apply(SoundPlayerState(kind: .rain, phase: .stopped))
        #expect(bench.reloadsSoFar == 2, "already deleted: no second redraw")
    }

    @Test @MainActor func theSleepTimerIsTheOnlyThingKeptBesidesThat() throws {
        let bench = try Bench()
        let plan = SleepTimerPlan(start: now, choice: .minutes45)
        bench.publisher.apply(playing())
        bench.publisher.apply(playing(plan))
        #expect(bench.store.load() == SleepSoundsState(endsAt: plan.end) && bench.reloadsSoFar == 2)
        bench.publisher.apply(playing())
        #expect(bench.store.load() == SleepSoundsState(endsAt: nil) && bench.reloadsSoFar == 3, "the timer turned off")
    }

    @Test @MainActor func aRecordLeftByAProcessTheSystemEndedIsRemovedByTheFirstStateSeen() throws {
        let bench = try Bench(existing: SleepSoundsState())
        #expect(bench.store.exists, "the control would still say Playing")
        bench.publisher.apply(SoundPlayerState())
        #expect(!bench.store.exists && bench.reloadsSoFar == 1)
        // A record a sound is really playing for stays, and is not rewritten.
        let again = try Bench(existing: SleepSoundsState())
        again.publisher.apply(playing())
        #expect(again.store.exists && again.reloadsSoFar == 0)
    }

    @Test @MainActor func aFileNothingCanReadIsRemovedWhenThePublisherStarts() throws {
        let bench = try Bench(damaged: true)
        #expect(!bench.store.exists)
    }

    @Test @MainActor func aStopWithNothingPlayingAsksForNothingAndAPlayEndsTheFadeWindow() async throws {
        let (store, directory) = try tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let time = ManualTime()
        let box = ReloadBox()
        let publisher = SleepSoundsPublisher(store: store, reload: { box.count += 1 }, sleeper: { seconds in await time.sleep(seconds) })
        publisher.apply(SoundPlayerState())
        publisher.stopping()
        #expect(box.count == 0 && !store.exists, "nothing to fade: the control's own intent redraws it")
        publisher.apply(playing())
        publisher.stopping()
        #expect(!store.exists && box.count == 2)
        // Played again at once, inside the fade: it is shown as playing at once, not after the window.
        publisher.started()
        #expect(store.exists && box.count == 3)
        await time.advance(2)
        #expect(store.exists && box.count == 3, "the window that was running does nothing now")
    }

    @Test @MainActor func forgetDeletesAndRedrawsAndSuspendStopsAllWriting() throws {
        let bench = try Bench()
        bench.publisher.apply(playing())
        bench.publisher.forget()
        #expect(!bench.store.exists && bench.reloadsSoFar == 2)
        bench.publisher.suspend()
        bench.publisher.apply(playing())
        bench.publisher.started()
        bench.publisher.stopping()
        #expect(!bench.store.exists && bench.reloadsSoFar == 2, "while everything is deleted, the fading sound writes nothing")
    }

    @Test @MainActor func withoutAppGroupItDoesNothing() {
        let publisher = SleepSoundsPublisher(store: nil)
        publisher.apply(playing())
        publisher.started()
        publisher.stopping()
        publisher.forget()
        publisher.suspend()
    }

    @Test @MainActor func itFollowsTheRealPlayerThroughPlayPauseInterruptionAndTheTimer() async throws {
        let (store, directory) = try tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bench = PlayerBench.make()
        let box = ReloadBox()
        let publisher = SleepSoundsPublisher(store: store, reload: { box.count += 1 })
        bench.player.observe { publisher.apply($0) }
        publisher.apply(bench.player.state)
        #expect(!store.exists)

        bench.player.play(.rain)
        #expect(store.isPlaying(at: bench.time.now), "playing")
        bench.player.pause()
        #expect(!store.exists, "paused by the person")
        bench.player.resume()
        #expect(store.exists)
        bench.session.emit(.interruptionBegan)
        #expect(bench.player.state.phase == .interrupted && !store.exists, "a call has the audio: not playing")
        bench.session.emit(.interruptionEnded(shouldResume: true))
        #expect(bench.player.state.phase == .playing && store.exists, "and playing again when it gives it back")

        bench.player.setTimer(.minutes15)
        let end = SleepTimerPlan(start: bench.time.now, choice: .minutes15).end
        #expect(store.load() == SleepSoundsState(endsAt: end))
        await bench.time.advance(15 * 60 + 1)
        #expect(bench.player.state.phase == .stopped && !store.exists, "the timer ran out and the sound faded: nothing plays")
        #expect(box.count >= 6)
    }
}

// MARK: - What the control asks of the app

@MainActor
struct ControlIntentTests {
    @MainActor
    private final class Host: IntentHost {
        var calls: [String] = []
        func open(_ destination: IntentDestination) { calls.append("open \(destination)") }
        func startWindDown(minutes: Int?) { calls.append("windDown \(minutes.map(String.init) ?? "nil")") }
        func playSleepSounds(_ kind: SoundKind?) -> SoundKind { calls.append("play \(kind?.rawValue ?? "nil")"); return kind ?? .rain }
        func stopSleepSounds() { calls.append("stop") }
        func endWindDown() { calls.append("end wind-down") }
        func setTonightAlarm(minutes: Int) async -> AlarmIntentOutcome { .couldNotSet }
        func askCoach(_ text: String) { calls.append("coach") }
    }

    private func run<I: AppIntent>(_ intent: I, under runtime: IntentRuntime) async throws {
        _ = try await IntentRuntime.$override.withValue(runtime) { try await intent.perform() }
    }

    private nonisolated final class Reloads: @unchecked Sendable {
        private let lock = NSLock()
        private var kinds: [String] = []
        func add(_ kind: String) { lock.withLock { kinds.append(kind) } }
        var all: [String] { lock.withLock { kinds } }
    }

    @Test func theToggleTurnsTheLastSoundOnAndStopsItOffAndAlwaysAsksTheControlToReadTheTruth() async throws {
        let host = Host()
        let reloads = Reloads()
        let runtime = IntentRuntime(environment: IntentEnvironment(snapshot: { nil }, reloadControl: { reloads.add($0) }), host: host)
        try await run(SleepSoundsToggleIntent(value: true), under: runtime)
        try await run(SleepSoundsToggleIntent(value: false), under: runtime)
        #expect(host.calls == ["play nil", "stop"], "on plays the last sound (the host knows which); off stops what plays")
        #expect(reloads.all == [ControlKind.sleepSounds, ControlKind.sleepSounds])
    }

    @Test func withoutTheAppTheToggleDoesNothingButTheControlIsStillToldToReadAgain() async throws {
        let reloads = Reloads()
        let runtime = IntentRuntime(environment: IntentEnvironment(snapshot: { nil }, reloadControl: { reloads.add($0) }), host: nil)
        runtime.hostWaitSeconds = 0.05
        try await run(SleepSoundsToggleIntent(value: true), under: runtime)
        #expect(reloads.all == [ControlKind.sleepSounds], "the system flipped the control; nothing came true; it must not stay flipped")
    }

    @Test func theToggleIsAnAudioPlaybackIntentAndAValueIntentAndNotInTheShortcutsGallery() {
        let types: [any AppIntent.Type] = [SleepSoundsToggleIntent.self]
        #expect(types.allSatisfy { $0 is any AudioPlaybackIntent.Type }, "iOS runs it in the app, which holds the audio")
        #expect(types.allSatisfy { $0 is any SetValueIntent.Type })
        #expect(!SleepSoundsToggleIntent.isDiscoverable)
        #expect(SleepSoundsToggleIntent(value: true).value && !SleepSoundsToggleIntent(value: false).value)
    }

    @Test func theWindDownButtonRunsTheOneWindDownIntentWhichOpensTheApp() {
        #expect(StartWindDownIntent.supportedModes == .foreground(.immediate), "the wind-down is a screen: the control opens NOCTIS")
        #expect(StartWindDownIntent().length == nil, "the person's last length")
    }

    @Test func theRealHostStartsAndStopsThroughThePlayerAndRedrawsTheControl() async throws {
        let (store, directory) = try tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let box = SleepSoundsPublisherTests.ReloadBox()
        let bench = PlayerBench.make()
        let time = bench.time
        let publisher = SleepSoundsPublisher(store: store, reload: { box.count += 1 }, sleeper: { seconds in await time.sleep(seconds) })
        bench.player.observe { publisher.apply($0) }
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "noctis.control.\(UUID().uuidString)") ?? .standard)
        let sounds = SoundsViewModel(player: bench.player, haptic: {}, sleeper: { seconds in await time.sleep(seconds) })
        let backend = MockAlarmBackend(mode: .authorized)
        let alarm = AlarmService(backend: backend, store: MemoryAlarmStore(), defaultMinutes: { 7 * 60 })
        let host = AppIntentHost(model: model, preferences: preferences, player: bench.player, sounds: sounds, alarm: alarm, controls: publisher)

        _ = host.playSleepSounds(nil)
        #expect(bench.player.state.phase == .playing && store.exists)
        let afterPlay = box.count
        host.stopSleepSounds()
        // The sound fades for a second: the control was flipped off, so it is off now and does not flicker on while the fade runs.
        #expect(bench.player.state.phase == .playing && !store.exists && box.count > afterPlay)
        let afterStop = box.count
        await bench.time.advance(1.2)
        #expect(bench.player.state.phase == .stopped && !store.exists, "the sound has stopped and the record is still gone")
        #expect(box.count == afterStop, "nothing more to draw")
        // Asked to stop again with nothing playing: nothing to write and nothing to fade.
        host.stopSleepSounds()
        #expect(box.count == afterStop && !store.exists)
    }

    @Test func aSoundStartedAgainDuringTheFadeIsShownAsPlayingWhenTheFadeIsOver() async throws {
        let (store, directory) = try tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bench = PlayerBench.make()
        let time = bench.time
        let publisher = SleepSoundsPublisher(store: store, sleeper: { seconds in await time.sleep(seconds) })
        bench.player.observe { publisher.apply($0) }
        bench.player.play(.rain)
        publisher.stopping()
        #expect(!store.exists)
        // The Sounds screen plays another sound while the control's stop is still fading: a gain or kind change is a state change too.
        bench.player.setGain(0.9, for: .rain)
        #expect(!store.exists, "during the fade the record is not written back")
        await bench.time.advance(1.6)
        #expect(bench.player.state.phase == .stopped || store.exists, "after the window the player's own state decides: stopped, or playing and shown as playing")
        #expect(store.exists == (bench.player.state.phase == .playing))
    }
}

// MARK: - The extension and what it links

struct ControlExtensionTests {
    private let controls = RawDefaultsTests.root.appendingPathComponent("NoctisWidgets/NoctisControls.swift")

    @Test func theBundleHoldsTheWidgetsAndBothControls() throws {
        let bundle = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("NoctisWidgets/NoctisWidgets.swift"), encoding: .utf8)
        let body = RawDefaultsTests.code(bundle)
        for name in ["NoctisTodayWidget()", "NoctisLockWidget()", "NoctisWindDownControl()", "NoctisSleepSoundsControl()"] { #expect(body.contains(name), Comment(rawValue: name)) }
    }

    @Test func eachControlHasItsKindItsIntentAndAnAccessibleLabel() throws {
        let code = RawDefaultsTests.code(try String(contentsOf: controls, encoding: .utf8))
        #expect(code.contains("kind: ControlKind.windDown") && code.contains("kind: ControlKind.sleepSounds"))
        #expect(code.contains("ControlWidgetButton(action: StartWindDownIntent())"))
        #expect(code.contains("ControlWidgetToggle(isOn: isPlaying, action: SleepSoundsToggleIntent())"))
        #expect(code.contains("Label(\"Wind down\", systemImage:") && code.contains("Label(\"Sleep sounds\", systemImage:"), "a title and a symbol: VoiceOver reads the title")
        #expect(code.contains(".tint(ControlStyle.tint)") && !code.contains("Color("), "the app's tint, not a color of its own")
        #expect(code.contains("NoctisIntentKitPackage.self"), "the extension names the package so the system finds the intents")
        #expect(code.contains("SleepSoundsStore()?.isPlaying()"), "the toggle reads the one record")
    }

    @Test func theExtensionHoldsNothingThatPlaysReadsHealthOrStores() throws {
        for file in RawDefaultsTests.swiftFiles(under: ["NoctisWidgets"]) {
            let code = RawDefaultsTests.code(file.text)
            for token in ["import HealthKit", "import SwiftData", "import AVFoundation", "import SoundKit", "import CoachKit", "import JournalKit", "import NoctisCore", "import NightKit", "import AppRoot", "AVAudioEngine", "UserDefaults"] {
                #expect(!code.contains(token), Comment(rawValue: "\(file.path) has \(token)"))
            }
        }
    }

    @Test func theModulesTheExtensionLinksUseNoRequiredReasonAPI() throws {
        // The extension's manifest declares none (R43), and now it also links the intents and the sound names: none of that may use one.
        let modules = ["NoctisWidgets", "Packages/NoctisKit/Sources/NoctisWidgetKit", "Packages/NoctisKit/Sources/NoctisIntentKit", "Packages/NoctisKit/Sources/SoundCatalog", "Packages/NoctisKit/Sources/DesignSystem"]
        let tokens = ["UserDefaults", "@AppStorage", "creationDate", "modificationDate", "contentModificationDate", "systemUptime", "mach_absolute_time", "volumeAvailableCapacity", "systemFreeSize", "activeInputModes", "fstat(", "lstat("]
        let files = RawDefaultsTests.swiftFiles(under: modules)
        #expect(files.count > 15)
        for file in files {
            let code = RawDefaultsTests.code(file.text)
            for token in tokens { #expect(!code.contains(token), Comment(rawValue: "\(file.path) uses \(token); the extension's manifest would have to say so")) }
        }
    }

    @Test func theSoundNamesAreTheirOwnModuleWithNoAudioInIt() throws {
        let files = RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources/SoundCatalog"])
        #expect(files.map(\.path) == ["Packages/NoctisKit/Sources/SoundCatalog/SoundKind.swift"])
        let code = RawDefaultsTests.code(files[0].text)
        for token in ["import AVFoundation", "import AudioToolbox", "import MediaPlayer", "UserDefaults"] { #expect(!code.contains(token)) }
        // SoundKit does not declare the names a second time: it re-exports them.
        let kit = RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources/SoundKit"])
        #expect(!kit.contains { RawDefaultsTests.code($0.text).contains("enum SoundKind") })
        #expect(kit.contains { $0.text.contains("@_exported import SoundCatalog") })
    }

    @Test func theContainerIsMadeWhenTheProcessStartsSoAHeadlessLaunchHasAHost() throws {
        let code = RawDefaultsTests.code(try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/NoctisApp.swift"), encoding: .utf8))
        #expect(code.contains("_container = State(initialValue: AppContainer())"), "an intent that starts the app with no screen still needs its host (R47, R48)")
        #expect(!code.contains("@State private var container = AppContainer()"), "that form is made only when a screen is drawn")
    }

    @Test func theProjectLinksTheIntentsIntoTheExtensionAndItsEntitlementsStayTheOneGroup() throws {
        let project = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("project.yml"), encoding: .utf8)
        let section = try #require(project.range(of: "  NoctisWidgets:\n"))
        let tail = String(project[section.upperBound...])
        let block = String(tail[..<(tail.range(of: "\n  [A-Za-z]+:\n", options: .regularExpression)?.lowerBound ?? tail.endIndex)])
        #expect(block.contains("product: NoctisWidgetKit") && block.contains("product: NoctisIntentKit"))
        // (comment lines belong to the next target)
        let lines = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
        #expect(!lines.contains("product: SoundKit") && !lines.contains("HealthKit"))
        let entitlements = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("NoctisWidgets/NoctisWidgets.entitlements"), encoding: .utf8)
        #expect(entitlements.components(separatedBy: "<string>").count - 1 == 1, "the App Group and nothing else")
    }
}
