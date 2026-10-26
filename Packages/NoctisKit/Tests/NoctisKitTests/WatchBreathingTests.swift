import BreathingKit
import Foundation
import Testing

@testable import InsightsKit
@testable import NoctisWatchKit
@testable import NoctisWidgetKit

// Breathing on the Apple Watch (APP_RULES.md R55): what the wrist feels and when, what the session does when the system's extended runtime session starts,
// is about to expire or ends, what one frame says, and the one preference. The system's session and haptics are replaced by fakes, so every rule is a test.

private nonisolated let start = Date(timeIntervalSince1970: 1_790_258_400)
private nonisolated func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

private nonisolated func schedule(_ id: BreathingPattern.ID = .calm, minutes: Int = 2) -> BreathingSchedule {
    BreathingSchedule(pattern: BreathingPattern.pattern(id), minutes: minutes)
}

nonisolated final class FakeRuntime: ExtendedRuntimeClient, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (ExtendedRuntimeEvent) -> Void)?
    private var starts = 0, invalidations = 0

    var onEvent: (@Sendable (ExtendedRuntimeEvent) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    var startCount: Int { lock.withLock { starts } }
    var invalidateCount: Int { lock.withLock { invalidations } }

    func start() { lock.withLock { starts += 1 } }
    func invalidate() { lock.withLock { invalidations += 1 } }
    func send(_ event: ExtendedRuntimeEvent) { onEvent?(event) }
}

nonisolated final class FakeHaptics: BreathHapticPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var played: [BreathHaptic] = []

    var all: [BreathHaptic] { lock.withLock { played } }
    func play(_ haptic: BreathHaptic) { lock.withLock { played.append(haptic) } }
}

// MARK: - What the wrist feels

struct BreathHapticPlannerTests {
    @Test func calmTwoMinutesIsOneHapticAtEachChangeOfPhaseAndOneAtTheEnd() {
        let events = BreathHapticPlanner.events(for: schedule(.calm, minutes: 2))
        // 4-2-6 is twelve seconds: ten breaths of three phases fill two minutes.
        #expect(events.count == 31)
        #expect(Array(events.prefix(7)) == [
            BreathHapticEvent(time: 0, haptic: .inhale), BreathHapticEvent(time: 4, haptic: .hold), BreathHapticEvent(time: 6, haptic: .exhale),
            BreathHapticEvent(time: 12, haptic: .inhale), BreathHapticEvent(time: 16, haptic: .hold), BreathHapticEvent(time: 18, haptic: .exhale),
            BreathHapticEvent(time: 24, haptic: .inhale),
        ])
        #expect(events.last == BreathHapticEvent(time: 120, haptic: .done))
    }

    @Test func boxHasTwoHoldsAndRelaxOneLongOne() {
        let box = BreathHapticPlanner.events(for: schedule(.box, minutes: 2))
        // 4-4-4-4 is sixteen seconds: eight breaths, 128 seconds, four phases each, and the end.
        #expect(box.count == 8 * 4 + 1 && box.last == BreathHapticEvent(time: 128, haptic: .done))
        #expect(box.prefix(5).map(\.haptic) == [.inhale, .hold, .exhale, .hold, .inhale])
        #expect(box.prefix(5).map(\.time) == [0, 4, 8, 12, 16])
        let relax = BreathHapticPlanner.events(for: schedule(.relax, minutes: 2))
        // 4-7-8 is nineteen seconds: seven breaths, 133 seconds.
        #expect(relax.count == 7 * 3 + 1 && relax.last == BreathHapticEvent(time: 133, haptic: .done))
        #expect(relax.prefix(4).map(\.time) == [0, 4, 11, 19])
    }

    @Test func thereIsNeverAHapticInTheMiddleOfAPhaseOrTwoAtOnce() {
        for id in BreathingPattern.ID.allCases {
            for minutes in BreathingSchedule.durations {
                let plan = schedule(id, minutes: minutes)
                let events = BreathHapticPlanner.events(for: plan)
                #expect(events.map(\.time) == events.map(\.time).sorted() && Set(events.map(\.time)).count == events.count, Comment(rawValue: "\(id) \(minutes)"))
                #expect(events.count == plan.cycles * plan.phasesPerCycle + 1 && events.first?.time == 0 && events.last?.time == Double(plan.totalSeconds))
                #expect(events.filter { $0.haptic == .done }.count == 1)
                // Each event falls exactly where a phase begins.
                for event in events.dropLast() {
                    let moment = plan.moment(at: event.time)
                    #expect(moment.secondsIntoPhase == 0 && BreathHapticPlanner.haptic(for: moment.kind) == event.haptic, Comment(rawValue: "\(id) \(event.time)"))
                }
            }
        }
    }

    @Test func theExerciseIsWholeBreathsSoItEndsAtTheEndOfOne() {
        #expect(schedule(.calm, minutes: 10).totalSeconds == 600)
        #expect(schedule(.box, minutes: 10).totalSeconds == 608 && schedule(.relax, minutes: 10).totalSeconds == 608)
        for id in BreathingPattern.ID.allCases { #expect(schedule(id, minutes: 5).totalSeconds >= 300) }
    }
}

// MARK: - The session's rules

struct BreathSessionModelTests {
    private func make(isActive: Bool = true) -> BreathSessionModel { BreathSessionModel(schedule: schedule(), now: at(0), isActive: isActive) }

    @Test func aRunStartsRunningAndAsksForTheRuntimeSessionOnce() {
        var model = make()
        #expect(model.status == .running && model.runtime == .notStarted)
        let first = model.begin()
        #expect(first == [.startRuntime] && model.runtime == .starting)
        let second = model.begin()
        #expect(second == [], "never a second session")
        _ = model.apply(.runtime(.started), at: at(0.5))
        #expect(model.runtime == .running)
    }

    @Test func theElapsedTimeIsTheClockAndNeverMoreThanTheEnd() {
        let model = make()
        #expect(model.elapsed(at: at(0)) == 0 && model.elapsed(at: at(37.5)) == 37.5 && model.elapsed(at: at(5000)) == 120)
        #expect(model.elapsed(at: at(-5)) == 0)
    }

    @Test func withTheRuntimeRunningTheWristCanGoDownAndTheExerciseGoesOn() {
        var model = make()
        _ = model.begin()
        _ = model.apply(.runtime(.started), at: at(1))
        _ = model.apply(.becameInactive, at: at(10))
        #expect(model.status == .running && model.pauseMessage == nil && model.elapsed(at: at(30)) == 30)
    }

    @Test func withNoRuntimeTheWristGoingDownPausesAndSaysToRaiseIt() {
        var model = make()
        _ = model.begin()
        _ = model.apply(.runtime(.invalidated(.suppressedBySystem)), at: at(1))
        #expect(model.runtime == .ended && model.status == .running, "the screen is on: it goes on without the session")
        _ = model.apply(.becameInactive, at: at(10))
        #expect(model.status == .paused && model.pauseMessage == "Raise your wrist to continue")
        #expect(model.elapsed(at: at(10)) == 10 && model.elapsed(at: at(500)) == 10, "frozen while paused")
        _ = model.apply(.becameActive, at: at(60))
        #expect(model.status == .running && model.pauseMessage == nil && model.elapsed(at: at(70)) == 20, "it picks up where it was")
    }

    @Test func theRuntimeSessionEndingWhileTheWristIsDownPausesTheExercise() {
        var model = make()
        _ = model.begin()
        _ = model.apply(.runtime(.started), at: at(0))
        _ = model.apply(.becameInactive, at: at(20))
        #expect(model.status == .running)
        _ = model.apply(.runtime(.willExpire), at: at(25))
        #expect(model.isExpiring && model.status == .running, "a warning changes nothing by itself")
        _ = model.apply(.runtime(.invalidated(.expired)), at: at(30))
        #expect(model.status == .paused && model.elapsed(at: at(999)) == 30)
    }

    @Test func theRuntimeSessionEndingWithTheScreenOnChangesNothingYouCanSee() {
        var model = make()
        _ = model.begin()
        _ = model.apply(.runtime(.started), at: at(0))
        _ = model.apply(.runtime(.invalidated(.resignedFrontmost)), at: at(15))
        #expect(model.status == .running && model.elapsed(at: at(40)) == 40)
    }

    @Test func aSessionThatComesUpAfterTheWristWentDownResumesAPausedExercise() {
        var model = make()
        _ = model.begin()
        _ = model.apply(.becameInactive, at: at(2))
        #expect(model.status == .paused)
        _ = model.apply(.runtime(.started), at: at(3))
        #expect(model.status == .running, "the session keeps it running with the wrist down")
    }

    @Test func theExerciseFinishesWhenTheLastBreathEndsAndEndsTheSession() {
        var model = make()
        _ = model.begin()
        _ = model.apply(.runtime(.started), at: at(0))
        let early = model.apply(.tick, at: at(119.9))
        #expect(early == [] && model.status == .running)
        let end = model.apply(.tick, at: at(120))
        #expect(end == [.invalidateRuntime] && model.status == .finished(completed: true) && model.isFinished)
        let after = model.apply(.becameInactive, at: at(130))
        #expect(after == [] && model.status == .finished(completed: true), "nothing happens after the end")
    }

    @Test func endingEarlyIsNotCompletedAndAlsoEndsTheSession() {
        var model = make()
        _ = model.begin()
        _ = model.apply(.runtime(.started), at: at(0))
        let ended = model.apply(.cancel, at: at(33))
        #expect(ended == [.invalidateRuntime] && model.status == .finished(completed: false) && model.elapsed(at: at(100)) == 33)
        var never = make()
        let none = never.apply(.cancel, at: at(1))
        #expect(none == [], "no session was asked for, so none is ended")
    }

    @Test func aPausedExerciseDoesNotFinishWhileItWaits() {
        var model = make()
        _ = model.begin()
        _ = model.apply(.runtime(.invalidated(.error)), at: at(1))
        _ = model.apply(.becameInactive, at: at(100))
        let effects = model.apply(.tick, at: at(5000))
        #expect(effects == [] && model.status == .paused)
    }
}

// MARK: - The driver, with the system's session and haptics replaced

@MainActor
struct BreathSessionDriverTests {
    private func make(
        _ plan: BreathingSchedule = schedule(), haptics on: Bool = true, active: Bool = true
    ) -> (BreathSessionDriver, FakeRuntime, FakeHaptics) {
        let runtime = FakeRuntime(), haptics = FakeHaptics()
        let driver = BreathSessionDriver(schedule: plan, now: at(0), isActive: active, hapticsEnabled: on, runtime: runtime, haptics: haptics, clock: { at(0) })
        return (driver, runtime, haptics)
    }

    @Test func beginningAsksForOneSessionAndGivesTheFirstBreathItsHaptic() {
        let (driver, runtime, haptics) = make()
        driver.begin(at: at(0))
        #expect(runtime.startCount == 1 && haptics.all == [.inhale])
    }

    @Test func theWristOnlyFeelsTheChangesOfPhaseAndTheEnd() {
        let (driver, runtime, haptics) = make()
        driver.begin(at: at(0))
        // The timer ticks every tenth of a second all the way through.
        var time = 0.0
        while time < 121 {
            driver.tick(at: at(time))
            time += 0.1
        }
        let planned = BreathHapticPlanner.events(for: schedule()).map(\.haptic)
        #expect(haptics.all == planned && haptics.all.last == .done && haptics.all.filter { $0 == .done }.count == 1)
        #expect(runtime.invalidateCount == 1 && driver.model.status == .finished(completed: true))
    }

    @Test func theHapticAtEachBoundaryComesAtThatBoundary() {
        let (driver, _, haptics) = make()
        driver.begin(at: at(0))
        driver.tick(at: at(3.9))
        #expect(haptics.all == [.inhale], "nothing during the inhale")
        driver.tick(at: at(4))
        #expect(haptics.all == [.inhale, .hold])
        driver.tick(at: at(5.9))
        driver.tick(at: at(6))
        #expect(haptics.all == [.inhale, .hold, .exhale])
    }

    @Test func aLateTimerPlaysOnlyTheNewestChangeNotABurst() {
        let (driver, _, haptics) = make()
        driver.begin(at: at(0))
        // The app was busy: it is 13 seconds in, three changes of phase later (hold, exhale and the next inhale).
        driver.tick(at: at(13))
        #expect(haptics.all == [.inhale, .inhale])
        driver.tick(at: at(13.5))
        #expect(haptics.all.count == 2, "and none again")
    }

    @Test func withHapticsOffTheWristFeelsNothingButTheExerciseRuns() {
        let (driver, runtime, haptics) = make(haptics: false)
        driver.begin(at: at(0))
        driver.tick(at: at(50))
        driver.tick(at: at(120))
        #expect(haptics.all.isEmpty && runtime.startCount == 1 && driver.model.status == .finished(completed: true))
    }

    @Test func endingEarlyPlaysNoSuccessHapticAndEndsTheSession() {
        let (driver, runtime, haptics) = make()
        driver.begin(at: at(0))
        driver.tick(at: at(5))
        driver.cancel(at: at(6))
        driver.tick(at: at(200))
        #expect(!haptics.all.contains(.done) && haptics.all == [.inhale, .hold])
        #expect(runtime.invalidateCount == 1 && driver.model.status == .finished(completed: false))
    }

    @Test func nothingIsPlayedWhilePaused() {
        let (driver, runtime, haptics) = make()
        driver.begin(at: at(0))
        driver.runtimeEvent(.invalidated(.suppressedBySystem), at: at(1))
        driver.sceneBecameInactive(at: at(2))
        #expect(driver.model.status == .paused)
        driver.tick(at: at(50))
        #expect(haptics.all == [.inhale])
        driver.sceneBecameActive(at: at(60))
        driver.tick(at: at(62))
        #expect(driver.model.status == .running && haptics.all == [.inhale, .hold], "elapsed 4s after the resume")
        #expect(runtime.startCount == 1, "resuming never asks for another session")
    }

    @Test func theSystemsEventsReachTheDriverThroughTheClient() async {
        let (driver, runtime, _) = make()
        driver.begin(at: at(0))
        runtime.send(.started)
        for _ in 0..<50 where driver.model.runtime != .running { await Task.yield() }
        #expect(driver.model.runtime == .running)
        runtime.send(.invalidated(.expired))
        for _ in 0..<50 where driver.model.runtime != .ended { await Task.yield() }
        #expect(driver.model.runtime == .ended)
    }
}

// MARK: - What the screen says

struct WatchBreathFrameTests {
    @Test func theCircleGrowsOnTheInhaleHoldsFullShrinksOnTheExhaleAndNeverVanishes() {
        let plan = schedule()
        func frame(_ seconds: Double) -> WatchBreathFrame { WatchBreathFrame(moment: plan.moment(at: seconds)) }
        #expect(frame(0).phase == "Breathe in" && frame(0).seconds == 4 && frame(0).level == 0 && abs(frame(0).circleScale - 0.4) < 1e-9)
        #expect(frame(2).level == 0.5 && abs(frame(2).circleScale - 0.7) < 1e-9, "the middle of an inhale is half full")
        #expect(frame(4).phase == "Hold" && frame(4).seconds == 2 && frame(4).level == 1 && abs(frame(4).circleScale - 1) < 1e-9, "the boundary belongs to the phase that begins")
        #expect(frame(3.999).phase == "Breathe in" && frame(3.999).seconds == 1)
        #expect(frame(6).phase == "Breathe out" && frame(6).seconds == 6 && frame(6).level == 1)
        #expect(frame(9).level == 0.5 && frame(11.99).seconds == 1 && frame(11.99).level < 0.01)
        #expect(frame(12).phase == "Breathe in" && frame(12).level == 0, "the next breath")
        for step in stride(from: 0.0, through: 120, by: 0.25) { #expect(frame(step).circleScale >= 0.4 && frame(step).circleScale <= 1) }
    }

    @Test func theCountdownCountsDownThroughEveryPhaseAndSaysWhatItIs() {
        let plan = schedule(.box)
        #expect((0..<4).map { WatchBreathFrame(moment: plan.moment(at: Double($0))).seconds } == [4, 3, 2, 1])
        #expect(WatchBreathFrame(moment: plan.moment(at: 1)).accessibilityLabel == "Breathe in, 3")
        let phases = [0.0, 4, 8, 12].map { WatchBreathFrame(moment: plan.moment(at: $0)).phase }
        #expect(phases == ["Breathe in", "Hold", "Breathe out", "Hold"])
    }

    @Test func theChoicesStartAtTheiPhonesDefaults() {
        var choice = WatchBreathChoice()
        #expect(choice.pattern == .calm && choice.minutes == 5 && choice.schedule.totalSeconds == 300)
        choice.pattern = .relax
        choice.minutes = 10
        #expect(choice.schedule.pattern.rhythm == "4-7-8" && choice.schedule.minutes == 10)
        #expect(BreathingPattern.all.map(\.rhythm) == ["4-2-6", "4-4-4-4", "4-7-8"] && BreathingSchedule.durations == [2, 5, 10])
    }

    @Test func theWordsMakeNoHealthClaim() {
        let words = [
            WatchBreathCopy.tagline, WatchBreathCopy.button, WatchBreathCopy.raiseWrist, WatchBreathCopy.done, WatchBreathCopy.again, WatchBreathCopy.close, WatchBreathCopy.start,
            WatchBreathCopy.end, WatchBreathCopy.hapticsToggle, WatchBreathCopy.inhale, WatchBreathCopy.hold, WatchBreathCopy.exhale, WatchBreathCopy.minutes(5),
        ]
        #expect(WatchBreathCopy.tagline == "A slow breathing exercise.")
        for text in words {
            #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: text))
            for claim in ["stress", "anxi", "heal", "cure", "treat", "medical", "reduce", "lower", "improve", "health", "mindful"] {
                #expect(!text.lowercased().contains(claim), Comment(rawValue: "\"\(text)\" claims \(claim)"))
            }
        }
    }
}

// MARK: - The one preference, and what the Watch does not do

struct WatchBreathPreferenceTests {
    private func preferences() -> WatchPreferences {
        WatchPreferences(defaults: UserDefaults(suiteName: "noctis.watchbreath.\(UUID().uuidString)") ?? .standard)
    }

    @Test func hapticsAreOnUntilSwitchedOffAndResetGoesBackToOn() {
        let value = preferences()
        #expect(value.breathHaptics)
        value.breathHaptics = false
        #expect(!value.breathHaptics)
        value.reset()
        #expect(value.breathHaptics, "what delete-all does to the Watch")
    }

    @Test func theKeyIsTheOneTheInventoryListsAndItIsNotTheEpochsKey() {
        #expect(WatchPreferenceKeys.breathHaptics == "noctis.watch.breathHaptics")
        #expect(WatchPreferenceKeys.breathHaptics.hasPrefix("noctis."), "so a delete-all on the iPhone's own keys would clear it too")
    }

    @Test func breathingWritesNothingToHealthAndTheWatchHasTheBackgroundModeItNeeds() throws {
        let files = RawDefaultsTests.swiftFiles(under: ["Watch/App", "Packages/NoctisKit/Sources/NoctisWatchKit", "Packages/NoctisKit/Sources/BreathingKit"])
        for file in files {
            let code = RawDefaultsTests.code(file.text)
            for token in ["HealthKit", "HKHealthStore", "mindfulSession", "HKCategoryType", "HKWorkout", "requestAuthorization"] {
                #expect(!code.contains(token), Comment(rawValue: "\(file.path) has \(token)"))
            }
        }
        let project = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("project.yml"), encoding: .utf8)
        let watch = try #require(project.range(of: "\n  NOCTISWatch:\n"))
        let tail = String(project[watch.upperBound...])
        let block = String(tail[..<(tail.range(of: "\n  NOCTISWatchWidgets:\n")?.lowerBound ?? tail.endIndex)])
        #expect(block.contains("WKBackgroundModes") && block.contains("- mindfulness"), "the mindfulness extended runtime session needs its background mode")
        #expect(!block.contains("healthkit") && !block.contains("HealthKit"))
    }

    @Test func breathingKitDependsOnNothingSoTheWatchCanLinkIt() throws {
        let package = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Package.swift"), encoding: .utf8)
        let row = try #require(package.components(separatedBy: "\n").first { $0.contains(".target(name: \"BreathingKit\"") })
        #expect(!row.contains("dependencies"), Comment(rawValue: row))
        let sources = RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources/BreathingKit"])
        #expect(!sources.isEmpty)
        for file in sources {
            let imports = file.text.split(separator: "\n").filter { $0.hasPrefix("import ") }.map(String.init)
            #expect(Set(imports).isSubset(of: ["import Foundation"]), Comment(rawValue: "\(file.path): \(imports)"))
        }
    }
}
