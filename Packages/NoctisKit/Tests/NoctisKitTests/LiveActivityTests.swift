import ActivityKit
import AppIntents
import Foundation
import Testing

@testable import AppRoot
@testable import InsightsKit
@testable import NightFeature
@testable import NightKit
@testable import NoctisIntentKit
@testable import NoctisWidgetKit
@testable import SoundKit

// The wind-down's Live Activity (APP_RULES.md R49): what it holds and says, what the controller asks of the system and when, what the session
// asks of it, the End button, and what the extension and the project hold.

private typealias State = WindDownActivityAttributes.ContentState
private let start = Fixture.date(2026, 9, 24, 22, 30)

// MARK: - What it holds

struct WindDownActivityStateTests {
    @Test func theAttributesAndTheStateAreSmallAndRoundTrip() throws {
        let attributes = WindDownActivityAttributes(plannedMinutes: 20, startedAt: start)
        let state = WindDownActivityState.make(phase: .running, startedAt: start, pausedTotal: 0, plannedSeconds: 1200)
        let encoder = JSONEncoder()
        let a = try encoder.encode(attributes), s = try encoder.encode(state)
        #expect(try JSONDecoder().decode(WindDownActivityAttributes.self, from: a).plannedMinutes == 20)
        #expect(try JSONDecoder().decode(State.self, from: s) == state)
        #expect(a.count + s.count < 1024, "ActivityKit allows 4 KB and the state is a few dozen bytes")
        let json = try #require(try JSONSerialization.jsonObject(with: s) as? [String: Any])
        #expect(Set(json.keys) == ["phase", "windowStart", "windowEnd"], "no Health value, no sound name, nothing but the clock")
    }

    @Test func theWindowIsTheSessionsClockAndAPauseMovesItOn() {
        var clock = WindDownClock(minutes: 20)
        clock.start(at: start)
        let running = WindDownActivityState.make(phase: .running, startedAt: start, pausedTotal: clock.pausedTotal, plannedSeconds: clock.plannedSeconds)
        #expect(running.windowStart == start && running.windowEnd == start.addingTimeInterval(1200) && running.pausedAt == nil)

        // Paused five minutes in: the countdown stands where it was.
        let pauseAt = start.addingTimeInterval(300)
        clock.pause(at: pauseAt)
        let paused = WindDownActivityState.make(phase: .paused, startedAt: start, pausedTotal: clock.pausedTotal, plannedSeconds: clock.plannedSeconds, pausedAt: clock.pausedAt)
        #expect(paused.pausedAt == pauseAt && paused.isPaused)
        #expect(paused.remaining(at: pauseAt) == 900 && paused.remaining(at: pauseAt.addingTimeInterval(4000)) == 900, "frozen however long it stays paused")
        #expect(paused.progress(at: start.addingTimeInterval(9999)) == 0.25)

        // Resumed three minutes later: the window has moved on by those three minutes, and the same two dates say what is left.
        let resumeAt = pauseAt.addingTimeInterval(180)
        clock.resume(at: resumeAt)
        let resumed = WindDownActivityState.make(phase: .running, startedAt: start, pausedTotal: clock.pausedTotal, plannedSeconds: clock.plannedSeconds, pausedAt: pauseAt)
        #expect(resumed.pausedAt == nil, "a running state has no pause")
        #expect(resumed.windowStart == start.addingTimeInterval(180) && resumed.windowEnd == start.addingTimeInterval(1380))
        #expect(resumed.remaining(at: resumeAt) == 900 && resumed.remaining(at: resumeAt.addingTimeInterval(100)) == 800)
    }

    @Test func itAgreesWithTheSessionsClockAtEveryMomentOfEverySession() {
        for minutes in WindDownClock.options {
            for pauseAfter in stride(from: 0.0, through: Double(minutes) * 60, by: 97) {
                var clock = WindDownClock(minutes: minutes)
                clock.start(at: start)
                let pausedAt = start.addingTimeInterval(pauseAfter)
                clock.pause(at: pausedAt)
                clock.resume(at: pausedAt.addingTimeInterval(61))
                let state = WindDownActivityState.make(phase: .running, startedAt: start, pausedTotal: clock.pausedTotal, plannedSeconds: clock.plannedSeconds)
                for offset in stride(from: 0.0, through: Double(minutes) * 60 + 200, by: 83) {
                    let moment = pausedAt.addingTimeInterval(61 + offset)
                    #expect(abs(state.remaining(at: moment) - clock.remaining(at: moment)) < 0.001, Comment(rawValue: "\(minutes) min, paused at \(pauseAfter), +\(offset)"))
                    #expect(abs(state.progress(at: moment) - clock.progress(at: moment)) < 0.0001)
                }
            }
        }
    }

    @Test func aWindowNeverRunsBackwardsAndProgressStaysInRange() {
        let backwards = State(phase: .running, windowStart: start, windowEnd: start.addingTimeInterval(-60))
        #expect(backwards.windowEnd == backwards.windowStart && backwards.progress(at: start) == 1 && backwards.remaining(at: start) == 0)
        let state = WindDownActivityState.make(phase: .running, startedAt: start, pausedTotal: 0, plannedSeconds: 600)
        #expect(state.progress(at: start.addingTimeInterval(-500)) == 0 && state.progress(at: start.addingTimeInterval(9000)) == 1)
        #expect(state.remaining(at: start.addingTimeInterval(9000)) == 0)
    }

    @Test func onlyARunningSessionGoesStaleAtItsEnd() {
        let running = WindDownActivityState.make(phase: .running, startedAt: start, pausedTotal: 0, plannedSeconds: 600)
        #expect(WindDownActivityState.staleDate(for: running) == running.windowEnd)
        let paused = WindDownActivityState.make(phase: .paused, startedAt: start, pausedTotal: 0, plannedSeconds: 600, pausedAt: start.addingTimeInterval(60))
        #expect(WindDownActivityState.staleDate(for: paused) == nil, "time does not pass while paused")
        let ending = WindDownActivityState.make(phase: .ending, startedAt: start, pausedTotal: 0, plannedSeconds: 600)
        #expect(WindDownActivityState.staleDate(for: ending) == nil)
    }
}

struct WindDownActivityCopyTests {
    private func state(_ phase: State.Phase) -> State {
        WindDownActivityState.make(phase: phase, startedAt: start, pausedTotal: 0, plannedSeconds: 1200, pausedAt: start.addingTimeInterval(300))
    }

    @Test func eachStateSaysWhatItIs() {
        #expect(WindDownActivityCopy.status(state(.running), plannedMinutes: 20, isStale: false) == "20 min")
        #expect(WindDownActivityCopy.status(state(.paused), plannedMinutes: 20, isStale: false) == "Paused")
        #expect(WindDownActivityCopy.status(state(.ending), plannedMinutes: 20, isStale: false) == "Wind-down complete")
        #expect(WindDownActivityCopy.status(state(.running), plannedMinutes: 20, isStale: true) == "Wind-down complete", "the time ran out while the app was away")
        let now = start.addingTimeInterval(300)
        #expect(WindDownActivityCopy.spoken(state(.running), at: now) == "Wind down. 15 minutes left.")
        #expect(WindDownActivityCopy.spoken(state(.paused), at: now.addingTimeInterval(3000)) == "Wind down. Paused. 15 minutes left.")
        #expect(WindDownActivityCopy.spoken(state(.running), at: start.addingTimeInterval(1170)) == "Wind down. 1 minute left.")
        #expect(WindDownActivityCopy.spoken(state(.ending), at: now) == "Wind down. Wind-down complete.")
    }

    @Test func everyWordOnEveryPresentationIsFreeOfTheBannedLanguage() {
        var words = [WindDownActivityCopy.title, WindDownActivityCopy.paused, WindDownActivityCopy.complete, WindDownActivityCopy.end, WindDownActivityCopy.endAccessibility]
        for phase in [State.Phase.running, .paused, .ending] {
            for minutes in WindDownClock.options {
                for stale in [false, true] {
                    words.append(WindDownActivityCopy.status(state(phase), plannedMinutes: minutes, isStale: stale))
                    words.append(WindDownActivityCopy.spoken(state(phase), at: start.addingTimeInterval(100), isStale: stale))
                }
            }
        }
        for word in words { #expect(BannedLanguage.hits(in: word, of: BannedLanguage.coach).isEmpty, Comment(rawValue: word)) }
    }
}

// MARK: - What the controller asks of the system

@MainActor
private final class FakeActivityClient: WindDownActivityClient {
    var isEnabled = true
    var failRequests = false
    var calls: [String] = []
    var contents: [ActivityContent<State>] = []
    var dismissals: [ActivityUIDismissalPolicy] = []
    private var next = 0

    func request(_ attributes: WindDownActivityAttributes, content: ActivityContent<State>) throws -> String {
        if failRequests { throw FakeFailure() }
        next += 1
        calls.append("request \(attributes.plannedMinutes)")
        contents.append(content)
        return "activity-\(next)"
    }

    func update(_ id: String, content: ActivityContent<State>) async {
        calls.append("update \(id) \(content.state.phase.rawValue)")
        contents.append(content)
    }

    func end(_ id: String, content: ActivityContent<State>?, dismissal: ActivityUIDismissalPolicy) async {
        calls.append("end \(id) \(content?.state.phase.rawValue ?? "none")")
        dismissals.append(dismissal)
    }

    func endAll() async { calls.append("endAll") }

    struct FakeFailure: Error {}
}

@MainActor
struct WindDownActivityControllerTests {
    private let attributes = WindDownActivityAttributes(plannedMinutes: 20, startedAt: start)
    private func state(_ phase: State.Phase = .running) -> State {
        WindDownActivityState.make(phase: phase, startedAt: start, pausedTotal: 0, plannedSeconds: 1200, pausedAt: phase == .paused ? start.addingTimeInterval(60) : nil)
    }

    @Test func itClearsWhatWasLeftThenStartsOneAndUpdatesAndEndsItInOrder() async {
        let client = FakeActivityClient()
        let controller = WindDownActivityController(client: client)
        controller.start(attributes, state: state())
        controller.update(state(.paused))
        controller.update(state(.running))
        controller.end(finalState: state(.ending), dismissAfter: 10)
        await controller.settled()
        #expect(client.calls == ["endAll", "request 20", "update activity-1 paused", "update activity-1 running", "end activity-1 ending"])
        #expect(client.contents[0].staleDate == state().windowEnd, "stale when the time runs out")
        #expect(client.contents[1].staleDate == nil, "paused: time does not pass")
        let last = client.dismissals.last
        #expect(last != nil && last != .immediate && last != .default, "the finished card is shown a little while, then goes")
    }

    @Test func endingWithoutAFinalStateRemovesItAtOnce() async {
        let client = FakeActivityClient()
        let controller = WindDownActivityController(client: client)
        controller.start(attributes, state: state())
        controller.end(finalState: nil, dismissAfter: 0)
        await controller.settled()
        #expect(client.calls.last == "end activity-1 none")
        #expect(client.dismissals.last == ActivityUIDismissalPolicy.immediate, "the person ended it: it goes now")
        // Ending again, or updating a finished one, asks the system for nothing.
        controller.end(finalState: nil, dismissAfter: 0)
        controller.update(state())
        await controller.settled()
        #expect(client.calls.count == 3)
    }

    @Test func whereLiveActivitiesAreOffNothingIsAskedAndNothingGoesWrong() async {
        let client = FakeActivityClient()
        client.isEnabled = false
        let controller = WindDownActivityController(client: client)
        controller.start(attributes, state: state())
        controller.update(state(.paused))
        controller.end(finalState: nil, dismissAfter: 0)
        await controller.settled()
        #expect(client.calls.isEmpty, "silent: the wind-down goes on without one")
    }

    @Test func aRefusalFromTheSystemIsSilentToo() async {
        let client = FakeActivityClient()
        client.failRequests = true
        let controller = WindDownActivityController(client: client)
        controller.start(attributes, state: state())
        controller.update(state(.paused))
        controller.end(finalState: state(.ending), dismissAfter: 10)
        await controller.settled()
        #expect(client.calls == ["endAll"], "no update or end for an activity that never was")
        // And the next session can start one.
        client.failRequests = false
        controller.start(attributes, state: state())
        await controller.settled()
        #expect(client.calls.last == "request 20")
    }

    @Test func leftoversFromAnEarlierRunAreEndedInTheSameOrderAsEverythingElse() async {
        let client = FakeActivityClient()
        let controller = WindDownActivityController(client: client)
        controller.endLeftovers()
        controller.start(attributes, state: state())
        await controller.settled()
        #expect(client.calls == ["endAll", "endAll", "request 20"], "the launch clean-up can never end the session that starts right after it")
    }
}

// MARK: - What the session asks

@MainActor
private final class FakeActivityHost: WindDownActivityHosting {
    var calls: [String] = []
    var started: [(WindDownActivityAttributes, State)] = []
    var updates: [State] = []
    var ended: [(State?, TimeInterval)] = []

    func start(_ attributes: WindDownActivityAttributes, state: State) { calls.append("start"); started.append((attributes, state)) }
    func update(_ state: State) { calls.append("update \(state.phase.rawValue)"); updates.append(state) }
    func end(finalState: State?, dismissAfter: TimeInterval) { calls.append("end \(finalState?.phase.rawValue ?? "none")"); ended.append((finalState, dismissAfter)) }
}

@MainActor
struct WindDownSessionActivityTests {
    private func make() -> (WindDownViewModelTests.Bench, FakeActivityHost) {
        let bench = WindDownViewModelTests.make()
        let host = FakeActivityHost()
        bench.model.activity = host
        return (bench, host)
    }

    @Test func beginningStartsOneActivityWithTheLengthAndTheStart() {
        let (bench, host) = make()
        bench.model.choose(minutes: 30)
        bench.model.begin()
        #expect(host.calls == ["start"])
        let (attributes, state) = host.started[0]
        #expect(attributes.plannedMinutes == 30 && attributes.startedAt == bench.time.now)
        #expect(state.phase == .running && state.windowEnd == bench.time.now.addingTimeInterval(1800))
        bench.model.begin()
        #expect(host.calls == ["start"], "a second begin changes nothing")
    }

    @Test func pausingAndResumingUpdateTheSameActivity() async {
        let (bench, host) = make()
        bench.model.begin()
        await bench.time.advance(300)
        bench.model.pause()
        #expect(host.calls == ["start", "update paused"] && host.updates[0].pausedAt == bench.time.now)
        await bench.time.advance(120)
        bench.model.resume()
        #expect(host.calls == ["start", "update paused", "update running"])
        #expect(host.updates[1].windowStart == bench.time.now.addingTimeInterval(-300) && host.updates[1].pausedAt == nil)
        #expect(abs(host.updates[1].remaining(at: bench.time.now) - bench.model.remaining) < 1.01)
    }

    @Test func endingEarlyRemovesTheActivityAtOnce() {
        let (bench, host) = make()
        bench.model.begin()
        bench.model.end()
        #expect(host.calls == ["start", "end none"] && host.ended[0].0 == nil)
    }

    @Test func theTimeRunningOutShowsWindDownCompleteForAMomentThenRemovesIt() async {
        let (bench, host) = make()
        bench.model.choose(minutes: 10)
        bench.model.begin()
        await bench.time.advance(601)
        #expect(bench.model.state == .ending || bench.model.state == .finished)
        #expect(host.calls == ["start", "end ending"])
        #expect(host.ended[0].1 > 0 && host.ended[0].1 <= 30, "shown a few seconds, not for hours")
    }

    @Test func nothingIsAskedWithoutAHostAndAnIdleSessionAsksForNothing() {
        let bench = WindDownViewModelTests.make()
        bench.model.begin()
        bench.model.pause()
        bench.model.end()
        #expect(bench.model.state == .ending, "the session never needed an activity")
        let (idle, host) = make()
        idle.model.pause()
        idle.model.resume()
        idle.model.end()
        #expect(host.calls.isEmpty)
    }

    @Test func resettingASessionStillUnderWayEndsItsActivity() {
        let (bench, host) = make()
        bench.model.begin()
        bench.model.reset()
        #expect(host.calls == ["start", "end none"])
        bench.model.reset()
        #expect(host.calls.count == 2, "nothing left to end")
    }
}

// MARK: - The End button

@MainActor
struct EndWindDownIntentTests {
    @MainActor
    private final class Host: IntentHost {
        var calls: [String] = []
        func open(_ destination: IntentDestination) {}
        func startWindDown(minutes: Int?) {}
        var lastSleepSound: SoundKind?
        func playSleepSounds(_ kind: SoundKind) -> Bool { true }
        func stopSleepSounds() {}
        func endWindDown() { calls.append("end") }
        func setTonightAlarm(minutes: Int) async -> AlarmIntentOutcome { .couldNotSet }
        func askCoach(_ text: String) -> AskCoachOutcome { .asked }
    }

    private nonisolated final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    @Test func itEndsTheSessionThroughTheAppAndThenEveryActivityWhateverTheAppKnew() async throws {
        let host = Host()
        let counter = Counter()
        let environment = IntentEnvironment(snapshot: { nil }, endWindDownActivities: { counter.bump() })
        let runtime = IntentRuntime(environment: environment, host: host)
        _ = try await IntentRuntime.$override.withValue(runtime) { try await EndWindDownIntent().perform() }
        #expect(host.calls == ["end"] && counter.count == 1)
    }

    @Test func withoutTheAppItStillRemovesTheActivity() async throws {
        let counter = Counter()
        let runtime = IntentRuntime(environment: IntentEnvironment(snapshot: { nil }, endWindDownActivities: { counter.bump() }), host: nil)
        runtime.hostWaitSeconds = 0.05
        _ = try await IntentRuntime.$override.withValue(runtime) { try await EndWindDownIntent().perform() }
        #expect(counter.count == 1, "the person pressed End: nothing may be left on their Lock Screen")
    }

    @Test func itIsALiveActivityIntentAndNotInTheShortcutsGallery() {
        let types: [any AppIntent.Type] = [EndWindDownIntent.self]
        #expect(types.allSatisfy { $0 is any LiveActivityIntent.Type }, "iOS runs it in the app, which owns the session")
        #expect(!EndWindDownIntent.isDiscoverable)
    }
}

// MARK: - The extension, the project and delete-all

struct LiveActivityStructureTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RawDefaultsTests.root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theExtensionDrawsTheKitsViewsAndGivesEndItsIntent() throws {
        let code = RawDefaultsTests.code(try read("Widgets/Home/NoctisWindDownActivity.swift"))
        #expect(code.contains("ActivityConfiguration(for: WindDownActivityAttributes.self)"))
        for piece in ["WindDownLockScreenView", "WindDownIslandCompactLeading", "WindDownIslandCompactTrailing", "WindDownIslandMinimal", "WindDownIslandExpandedLeading", "WindDownIslandExpandedTrailing", "WindDownIslandExpandedBottom"] {
            #expect(code.contains(piece), Comment(rawValue: "\(piece) is not used"))
        }
        #expect(code.contains("Button(intent: EndWindDownIntent())"))
        #expect(code.range(of: #"(?<![A-Za-z])Color\("#, options: .regularExpression) == nil && !code.contains(".font("), "the kit draws everything; the extension composes")
        let bundle = RawDefaultsTests.code(try read("Widgets/Home/NoctisWidgets.swift"))
        #expect(bundle.contains("NoctisWindDownLiveActivity()"))
    }

    @Test func theViewsUseTheNightPaletteScaledTypeAndAnEndButtonThatIsBigEnough() throws {
        let code = RawDefaultsTests.code(try read("Packages/NoctisKit/Sources/NoctisWidgetKit/WindDownActivityViews.swift"))
        #expect(code.contains("NoctisNight.") && code.contains(".noctisFont("))
        #expect(code.contains("minHeight: 44"), "a 44pt target")
        #expect(!code.contains(".position(") && !code.contains(".border("))
        // No text smaller than 12pt.
        // (a size can be written `island ? 15 : 17`: every number in the size argument counts)
        let arguments = code.matches(of: /noctisFont\(([^,]+),/).map { String($0.1) }
        let sizes = arguments.flatMap { $0.matches(of: /\d+(?:\.\d+)?/).compactMap { Double(String($0.0)) } }
        #expect(arguments.count >= 6 && sizes.count >= arguments.count && sizes.allSatisfy { $0 >= 12 })
        // The kit cannot name the intent (it is the other way round), so it never imports it.
        #expect(!code.contains("import NoctisIntentKit") && !code.contains("Button(intent"))
    }

    @Test func theAppSupportsLiveActivitiesAndTheDeleteAllStepEndsTheWindDownOnes() throws {
        let project = try read("project.yml")
        #expect(project.contains("INFOPLIST_KEY_NSSupportsLiveActivities: YES"))
        let code = RawDefaultsTests.code(try read("Packages/NoctisKit/Sources/AppRoot/LiveActivities.swift"))
        #expect(code.contains("WindDownActivities.endAll()"))
        // The wind-down is given its host where the app is made, and the leftovers of an earlier run are ended once, in order.
        let container = RawDefaultsTests.code(try read("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"))
        #expect(container.contains("windDown.activity = ") && container.contains(".endLeftovers()"))
    }

    @Test func noLiveActivityExistsForTheMorningSummaryOrTheAlarm() throws {
        // The alarm's snooze countdown is AlarmKit's; the wake window needs Smart Wake (ROADMAP.md). NOCTIS starts exactly one kind of its own.
        var requests = 0
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App", "Widgets/Home", "Widgets/Alarm"]) {
            requests += RawDefaultsTests.code(file.text).components(separatedBy: "Activity.request(").count - 1
        }
        #expect(requests == 1, "one place starts an activity: the wind-down's")
        let rules = try read("Docs/APP_RULES.md")
        #expect(rules.contains("no Live Activity for the morning summary or the alarm"))
    }
}
