import Foundation
import Testing

@testable import NoctisCore
@testable import ProfileFeature

// A "Delete all NOCTIS data" that was cut short is finished at the next launch (S1B-B02). Every step is safe to run again, so the whole list runs once more.

@MainActor
struct DeleteAllResumeTests {
    struct Boom: Error {}

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "noctis.resume.\(UUID().uuidString)") ?? .standard }

    private func manager(_ defaults: UserDefaults, steps: [DeleteStep]) -> DataManager {
        DataManager(erasers: [:], providers: [:], deleteAllSteps: steps, defaults: defaults)
    }

    @Test func theMarkerIsSetBeforeTheFirstStepAndGoneWhenEveryStepWorked() async {
        let defaults = defaults()
        var seenByFirstStep: Bool?
        let steps = [DeleteStep(id: "a", title: "A") { seenByFirstStep = defaults.bool(forKey: DataManager.pendingDeleteAllKey) }]
        let manager = manager(defaults, steps: steps)
        #expect(!manager.hasInterruptedDeletion)
        let report = await manager.deleteEverything()
        #expect(seenByFirstStep == true, "a kill from the first step on leaves the marker behind")
        #expect(report.succeeded && !manager.hasInterruptedDeletion && defaults.object(forKey: DataManager.pendingDeleteAllKey) == nil)
    }

    @Test func aStepThatFailedLeavesTheMarkerEvenIfAnEarlierStepClearedIt() async {
        let defaults = defaults()
        let steps = [
            DeleteStep(id: "a", title: "A") { throw Boom() },
            // The preferences step removes every `noctis.` key, the marker with them.
            DeleteStep(id: "preferences", title: "Clearing preferences") { defaults.removeObject(forKey: DataManager.pendingDeleteAllKey) },
        ]
        let manager = manager(defaults, steps: steps)
        let report = await manager.deleteEverything()
        #expect(!report.succeeded && manager.hasInterruptedDeletion, "the next launch tries again")
    }

    @Test func aLaunchThatFindsTheMarkerRunsEveryStepAgainAndSaysToStartOver() async {
        let defaults = defaults()
        defaults.set(true, forKey: DataManager.pendingDeleteAllKey)
        var ran: [String] = []
        let steps = [
            DeleteStep(id: "silence", title: "S") { ran.append("silence") },
            DeleteStep(id: "databases", title: "D") { ran.append("databases") },
            DeleteStep(id: "preferences", title: "P") { ran.append("preferences") },
        ]
        let manager = manager(defaults, steps: steps)
        #expect(manager.hasInterruptedDeletion)
        #expect(await manager.resumeInterruptedDeletion(), "the app starts over, as Done does")
        #expect(ran == ["silence", "databases", "preferences"], "the whole list, in order")
        #expect(!manager.hasInterruptedDeletion && manager.steps.isEmpty && manager.deleteAllReport == nil, "nothing is left to show or to repeat")
    }

    @Test func noMarkerMeansNothingRunsAndNothingRestarts() async {
        var ran = 0
        let manager = manager(defaults(), steps: [DeleteStep(id: "a", title: "A") { ran += 1 }])
        #expect(await manager.resumeInterruptedDeletion() == false && ran == 0)
    }

    @Test func aStepThatKeepsFailingIsTriedAtMostThreeLaunchesThenGivenUp() async {
        let defaults = defaults()
        defaults.set(true, forKey: DataManager.pendingDeleteAllKey)
        let manager = manager(defaults, steps: [DeleteStep(id: "a", title: "A") { throw Boom() }])
        #expect(DataManager.maximumResumeAttempts == 3)
        #expect(await manager.resumeInterruptedDeletion())
        #expect(manager.hasInterruptedDeletion && defaults.integer(forKey: DataManager.pendingDeleteAllKey) == 2, "still asked for: the next launch tries again")
        #expect(await manager.resumeInterruptedDeletion())
        #expect(defaults.integer(forKey: DataManager.pendingDeleteAllKey) == 3)
        #expect(await manager.resumeInterruptedDeletion())
        #expect(!manager.hasInterruptedDeletion, "the third try was the last: no more launches start over")
        #expect(manager.unfinishedSteps == ["a"] && manager.unfinishedStepTitles == ["A"], "but the step that could not be finished is on record, by its name")
        #expect(defaults.string(forKey: DataManager.unfinishedDeleteAllKey) == "a", "written down, not only held in memory")
        #expect(await manager.resumeInterruptedDeletion() == false, "the next launch is a normal one")
        // A relaunch: a new manager over the same defaults still knows.
        let relaunched = self.manager(defaults, steps: [DeleteStep(id: "a", title: "A") { throw Boom() }])
        #expect(relaunched.unfinishedSteps == ["a"], "the notice survives a relaunch")
    }

    @Test func aDeleteAllThatWorksLaterClearsTheRecord() async {
        let defaults = defaults()
        defaults.set("databases,setup", forKey: DataManager.unfinishedDeleteAllKey)
        let manager = manager(defaults, steps: [DeleteStep(id: "databases", title: "Removing database files") {}])
        #expect(manager.unfinishedSteps == ["databases", "setup"])
        #expect(manager.unfinishedStepTitles == ["Removing database files", "setup"], "an id the list no longer has is shown as it is")
        let report = await manager.deleteEverything()
        #expect(report.succeeded && manager.unfinishedSteps.isEmpty && defaults.object(forKey: DataManager.unfinishedDeleteAllKey) == nil)
    }

    @Test func aResumeThatWorksClearsAnOldRecordToo() async {
        let defaults = defaults()
        defaults.set(true, forKey: DataManager.pendingDeleteAllKey)
        defaults.set("a", forKey: DataManager.unfinishedDeleteAllKey)
        let manager = manager(defaults, steps: [DeleteStep(id: "a", title: "A") {}])
        #expect(await manager.resumeInterruptedDeletion())
        #expect(manager.unfinishedSteps.isEmpty && defaults.object(forKey: DataManager.unfinishedDeleteAllKey) == nil)
    }

    @Test func theNoticeNamesWhatIsLeftAndHowToTryAgain() {
        let text = DataManagementCopy.unfinishedNotice(["Removing database files", "Deleting Journal"])
        #expect(text.contains("did not finish") && text.contains("Removing database files, Deleting Journal"))
        #expect(text.contains(DataManagementCopy.deleteAllButton), "it points at the button that tries again")
        #expect(DataManagementCopy.unfinishedHeader == "NEEDS ATTENTION")
    }

    @Test func dataManagementShowsTheNoticeOnlyWhileSomethingIsOutstanding() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/ProfileFeature/DataManagementViews.swift"), encoding: .utf8)
        #expect(text.contains("if !manager.unfinishedSteps.isEmpty {") && text.contains("data.unfinished"))
    }

    @Test func aResumeThatWorkedLeavesNothingOnRecord() async {
        let defaults = defaults()
        defaults.set(true, forKey: DataManager.pendingDeleteAllKey)
        let manager = manager(defaults, steps: [DeleteStep(id: "a", title: "A") {}])
        #expect(await manager.resumeInterruptedDeletion())
        #expect(manager.unfinishedSteps.isEmpty && !manager.hasInterruptedDeletion && manager.deleteAllReport == nil)
    }

    @Test func theBackgroundWorkStopsWhileADeletionIsUnfinished() throws {
        let defaults = defaults()
        #expect(!DataManager.hasPendingDeleteAll(defaults: defaults))
        defaults.set(true, forKey: DataManager.pendingDeleteAllKey)
        #expect(DataManager.hasPendingDeleteAll(defaults: defaults), "a marker written as a plain true still counts")
        defaults.set(3, forKey: DataManager.pendingDeleteAllKey)
        #expect(DataManager.hasPendingDeleteAll(defaults: defaults))
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"), encoding: .utf8)
        let refresher = try #require(text.range(of: "let backgroundRefresher = BackgroundRefresher("))
        #expect(text[refresher.upperBound...].prefix(500).contains("!DataManager.hasPendingDeleteAll()"), "a Health wake does not refresh a half-deleted app")
        let watch = try #require(text.range(of: "onUpdateRequested: {"))
        #expect(text[watch.upperBound...].prefix(200).contains("hasPendingDeleteAll()"), "nor does the Watch's request")
    }

    @Test func theAppFinishesAnInterruptedDeletionBeforeItShowsAnything() throws {
        let app = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/NoctisApp.swift"), encoding: .utf8)
        #expect(app.contains("container.finishInterruptedDeletion()") && app.contains("AppContainer(restarted: true)"))
        let container = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"), encoding: .utf8)
        #expect(
            container.contains("interruptedDeletion = DataManager.hasPendingDeleteAll() && Self.resumeOnce.claim()"),
            "started when the container is made, so a background launch (no screen) finishes it too, and once per process")
    }

    @Test func theMarkerIsUnderTheAppPrefixSoThePreferencesStepClearsIt() {
        #expect(DataManager.pendingDeleteAllKey.hasPrefix("noctis."))
    }
}

// A file that stays is a failed step (S1B-R-03): the real wiring, against a database file that cannot be removed.
@MainActor
struct DeleteAllFileFailureTests {
    @Test func aDatabaseFileThatCannotBeRemovedIsAFailedStepAndKeepsTheMarker() async throws {
        let bench = try DataBench()
        bench.wire()
        let file = bench.roots.url(.applicationSupport).appending(path: "default.store", directoryHint: .notDirectory)
        try Data("not empty".utf8).write(to: file)
        var locked = file
        var values = URLResourceValues()
        values.isUserImmutable = true
        try locked.setResourceValues(values)
        defer {
            values.isUserImmutable = false
            try? locked.setResourceValues(values)
            try? FileManager.default.removeItem(at: bench.root)
        }
        let report = await bench.manager.deleteEverything()
        #expect(FileManager.default.fileExists(atPath: file.path), "the file is still there")
        #expect(report.failures.map(\.id) == ["databases"], "\(report.failures)")
        #expect(report.failures.first?.failure?.contains("could not be removed") == true)
        #expect(bench.manager.hasInterruptedDeletion, "so the next launch tries again")
    }

    @Test func whenEveryFileGoesTheStepWorksAndTheMarkerIsGone() async throws {
        let bench = try DataBench()
        bench.wire()
        defer { try? FileManager.default.removeItem(at: bench.root) }
        let file = bench.roots.url(.applicationSupport).appending(path: "default.store", directoryHint: .notDirectory)
        try Data("not empty".utf8).write(to: file)
        let report = await bench.manager.deleteEverything()
        #expect(report.succeeded, "\(report.failures)")
        #expect(!FileManager.default.fileExists(atPath: file.path) && !bench.manager.hasInterruptedDeletion)
    }
}
