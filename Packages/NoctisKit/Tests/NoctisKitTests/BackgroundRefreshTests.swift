import Foundation
import SwiftData
import Testing

@testable import HealthProviding
@testable import NoctisCore

// Background updates (APP_RULES.md R46): Apple Health wakes the app when new sleep data arrives, the refresh keeps the widgets true.
// The guard (coalescing, no-ops, the time budget), the choices made for HealthKit, and what the app says about it.

private nonisolated final class Count: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

private nonisolated final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    func date() -> Date { lock.withLock { now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { now = now.addingTimeInterval(seconds) } }
}

/// Holds a refresh until the test lets it go.
private actor Gate {
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        open = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

struct BackgroundRefresherTests {
    private func refresher(
        onboarded: Bool = true, authorized: Bool = true, clock: Clock = Clock(), refreshes: Count = Count(), asked: Count = Count(),
        minimumInterval: TimeInterval = 60, timeBudget: TimeInterval = 20, hold: Gate? = nil,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = held
    ) -> BackgroundRefresher {
        BackgroundRefresher(
            isOnboarded: { onboarded },
            isAuthorized: {
                asked.bump()
                return authorized
            },
            refresh: {
                refreshes.bump()
                await hold?.wait()
            },
            minimumInterval: minimumInterval, timeBudget: timeBudget, clock: { clock.date() }, sleep: sleep
        )
    }

    @Test func aWakeRefreshesOnce() async {
        let refreshes = Count()
        let outcome = await refresher(refreshes: refreshes).handleWake()
        #expect(outcome == .refreshed && refreshes.count == 1)
    }

    @Test func nothingRunsBeforeSetupIsFinished() async {
        let refreshes = Count()
        let asked = Count()
        let outcome = await refresher(onboarded: false, refreshes: refreshes, asked: asked).handleWake()
        #expect(outcome == .skipped(.notOnboarded) && refreshes.count == 0)
        #expect(asked.count == 0, "Health is not even asked about before setup")
    }

    @Test func nothingRunsWithoutHealthAccess() async {
        let refreshes = Count()
        let outcome = await refresher(authorized: false, refreshes: refreshes).handleWake()
        #expect(outcome == .skipped(.notAuthorized) && refreshes.count == 0)
    }

    @Test func wakesThatArriveTogetherShareOneRefreshAndAllWaitForIt() async {
        let refreshes = Count()
        let gate = Gate()
        let service = refresher(refreshes: refreshes, hold: gate)
        // Sleep, HRV and resting heart rate are delivered as three wakes.
        let first = Task { await service.handleWake() }
        let second = Task { await service.handleWake() }
        let third = Task { await service.handleWake() }
        // The refresh has started and is held, and the other two wakes are waiting for it: none has finished.
        let ready = await waitFor {
            let waiting = await service.waitingWakes
            return refreshes.count == 1 && waiting == 2
        }
        #expect(ready)
        #expect(refreshes.count == 1, "one refresh for three wakes")
        await gate.release()
        let outcomes = await [first.value, second.value, third.value]
        #expect(outcomes.filter { $0 == .refreshed }.count == 1 && outcomes.filter { $0 == .coalesced }.count == 2)
        #expect(refreshes.count == 1)
    }

    @Test func aWakeRightAfterARefreshDoesNothingAndALaterOneRefreshes() async {
        let refreshes = Count()
        let clock = Clock()
        let service = refresher(clock: clock, refreshes: refreshes)
        #expect(await service.handleWake() == .refreshed)
        clock.advance(30)
        #expect(await service.handleWake() == .skipped(.tooSoon) && refreshes.count == 1, "thirty seconds on: no thrash")
        clock.advance(31)
        #expect(await service.handleWake() == .refreshed && refreshes.count == 2)
    }

    @Test func aRefreshThatOutlastsTheBudgetIsLeftAndTheWakeEnds() async {
        let refreshes = Count()
        let clock = Clock()
        let gate = Gate()
        // The sleep returns at once: the budget has run out.
        let service = refresher(clock: clock, refreshes: refreshes, hold: gate, sleep: { _ in })
        let outcome = await service.handleWake()
        #expect(outcome == .timedOut, "the wake ends so HealthKit is let go")
        #expect(await service.handleWake() == .skipped(.tooSoon), "and a timeout does not invite another try at once")
        await gate.release()
    }

    @Test func theCompletionHandlerIsCalledOnEveryPath() async {
        // The glue the app uses: a wake runs the guard, then calls `done`.
        let provider = MockHealthKitProvider(scenario: .full, startAuthorized: true)
        for (onboarded, authorized) in [(true, true), (false, true), (true, false)] {
            let service = refresher(onboarded: onboarded, authorized: authorized, clock: Clock())
            await provider.startBackgroundDelivery { done in
                Task {
                    _ = await service.handleWake()
                    done()
                }
            }
            let done = Count()
            let finished = Gate()
            #expect(
                provider.simulateWake {
                    done.bump()
                    Task { await finished.release() }
                })
            await finished.wait()
            #expect(done.count == 1, "onboarded \(onboarded), authorized \(authorized)")
        }
        #expect(provider.backgroundStarts == 3)
        await provider.stopBackgroundDelivery()
        #expect(provider.backgroundStops == 1 && !provider.simulateWake {}, "stopped: no delivery")
    }
}

struct BackgroundDeliveryChoicesTests {
    @Test func eachKindHasTheLeastFrequentOptionThatServesAMorningWidget() {
        let plan = Dictionary(uniqueKeysWithValues: HealthBackgroundPlan.observed.map { ($0.kind, $0.frequency) })
        #expect(plan[.sleepAnalysis] == .hourly && plan[.hrv] == .daily && plan[.restingHeartRate] == .daily)
        #expect(plan[.heartRate] == nil && plan[.respiratoryRate] == nil, "plain heart rate changes every few minutes; respiratory rate is not watched")
        #expect(HealthBackgroundPlan.observed.map(\.kind) == [.sleepAnalysis, .hrv, .restingHeartRate])
    }

    @Test func backgroundDeliveryIsOnlyAskedForByTheHealthProviderAndTheEntitlementIsThere() throws {
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App", "Widgets/Home", "Widgets/Alarm"])
        where file.text.contains("enableBackgroundDelivery") {
            #expect(file.path.hasSuffix("HealthProviding/HealthKitProvider.swift"), Comment(rawValue: "\(file.path) asks for background delivery"))
        }
        let entitlements = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Config/Noctis.entitlements"), encoding: .utf8)
        #expect(entitlements.contains("com.apple.developer.healthkit.background-delivery"))
        // The widgets' extension cannot read Health, so it has no such entitlement.
        let widgets = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Config/NoctisWidgets.entitlements"), encoding: .utf8)
        #expect(!widgets.contains("healthkit"))
    }

    @Test func everyObserverPathCallsHealthKitsCompletionHandler() throws {
        let source = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/HealthProviding/HealthKitProvider.swift"), encoding: .utf8)
        let observers = try #require(source.range(of: "final class BackgroundObservers"))
        let code = RawDefaultsTests.code(String(source[observers.lowerBound...]))
        // Delivered: `done` is the completion handler. Failed: it is called here. Either way it is called.
        #expect(code.contains("wake { completion.call() }") && code.contains("} else {\n                    completion.call()"))
        #expect(code.contains("Completion(call: completionHandler)"))
    }

    @Test func theInventoryAndTheCodeAgreeAboutReadingHealthInTheBackground() throws {
        let entitlements = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Config/Noctis.entitlements"), encoding: .utf8)
        let provider = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/HealthProviding/HealthKitProvider.swift"), encoding: .utf8)
        let container = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"), encoding: .utf8)
        let inCode =
            entitlements.contains("healthkit.background-delivery") && provider.contains("enableBackgroundDelivery")
            && container.contains("startBackgroundDelivery")
        #expect(DataInventory.shared.facts.readsHealthInBackground == inCode)
        #expect(inCode)
    }

    @Test func whatTheAppSaysAboutWhenItReadsHealthFollowsTheInventory() {
        let shared = DataInventory.shared
        let said = PrivacyStatements.whenHealthIsRead(shared)
        #expect(said.contains("when you open the app") && said.contains("in the background") && said.contains("iOS decides when"))
        #expect(PrivacyStatements.helpStorage(shared).contains("in the background"))
        let center = PrivacyCenterBuilder.content(shared)
        #expect(center.readsNote?.contains("in the background") == true)
        // Without background reads, it says only that.
        let facts = shared.facts
        let quiet = DataInventory(
            categories: shared.categories, flows: shared.flows, networkUses: shared.networkUses, groups: shared.groups, retiredKeys: shared.retiredKeys,
            facts: DataInventoryFacts(
                healthAccess: facts.healthAccess, hasAccount: facts.hasAccount, coachUsesRemoteModel: facts.coachUsesRemoteModel,
                coachNeverSees: facts.coachNeverSees, readsHealthInBackground: false)
        )
        #expect(PrivacyStatements.whenHealthIsRead(quiet) == "It reads Apple Health when you open the app.")
        #expect(!PrivacyStatements.helpStorage(quiet).contains("background"))
    }

    @Test func theHealthUsageStringSaysTheWidgetsAreKeptUpToDate() throws {
        let project = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("project.yml"), encoding: .utf8)
        #expect(project.contains("keep your widgets up to date"))
    }

    @MainActor
    @Test func theAppIsToldOnceHealthHasBeenAskedSoDeliveryCanStart() async throws {
        let container = try ModelContainer(for: UserProfileRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .full), profileStore: ProfileStore(context: ModelContext(container)))
        let told = Count()
        model.onHealthAuthorizationRequested = { told.bump() }
        await model.requestHealthAuthorization()
        #expect(told.count == 1 && model.profile.healthAuthorizationRequested)
    }
}
