import Foundation
import Testing

@testable import AppRoot
@testable import NoctisWidgetKit

// The wind-down Live Activity on the Apple Watch (APP_RULES.md R56): the small presentation the Smart Stack shows, which carries a countdown and nothing
// from Health. The system's own Smart Stack is not in a unit test: these hold the declaration, the words and the gallery request.

struct WatchActivityTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RawDefaultsTests.root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theActivityAsksForTheSmallFamilyAndDrawsTheWatchViewForIt() throws {
        let code = RawDefaultsTests.code(try read("NoctisWidgets/NoctisWindDownActivity.swift"))
        #expect(code.contains(".supplementalActivityFamilies([.small])"))
        #expect(code.contains("@Environment(\\.activityFamily)") && code.contains("WindDownWatchView(state: context.state, isStale: context.isStale)"))
        // The iPhone's own presentation is what every other family gets.
        #expect(code.contains("WindDownLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)"))
    }

    @Test func theWatchViewIsAGlanceWithTheSystemsCountdownAndNoHealthAndNoButton() throws {
        let views = try read("Packages/NoctisKit/Sources/NoctisWidgetKit/WindDownActivityViews.swift")
        let start = try #require(views.range(of: "public struct WindDownWatchView"))
        let end = try #require(views.range(of: "// MARK: Dynamic Island"))
        let code = RawDefaultsTests.code(String(views[start.lowerBound..<end.lowerBound]))
        #expect(code.contains("WindDownTimerText(state: state)"), "the countdown is the system's, so it ticks with no help from the app")
        #expect(code.contains("moon.stars.fill") && code.contains("WindDownActivityCopy.title") && code.contains("NoctisNight"))
        for token in ["Button(", "HealthKit", "recovery", "Recovery", "sleepQuality", "heartRate", "hrv", "HRV"] {
            #expect(!code.contains(token), Comment(rawValue: "the Watch view has \(token)"))
        }
        // Every text on it is 12pt or more.
        let sizes = code.components(separatedBy: "noctisFont(").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
        #expect(!sizes.isEmpty && sizes.allSatisfy { $0 >= 12 }, "\(sizes)")
    }

    @Test func theActivityCarriesNothingFromHealthForTheWatchToShow() {
        let attributes = Mirror(reflecting: WindDownActivityAttributes(plannedMinutes: 20, startedAt: Date()))
        let state = Mirror(reflecting: WindDownActivityAttributes.ContentState(phase: .running, windowStart: Date(), windowEnd: Date().addingTimeInterval(60), pausedAt: nil))
        #expect(Set(attributes.children.compactMap(\.label)) == ["plannedMinutes", "startedAt"])
        #expect(Set(state.children.compactMap(\.label)) == ["phase", "windowStart", "windowEnd", "pausedAt"])
    }

    @Test func theWatchSaysTheSameWordsTheLockScreenDoes() {
        #expect(WindDownActivityCopy.title == "Wind down" && WindDownActivityCopy.complete == "Wind-down complete" && WindDownActivityCopy.paused == "Paused")
    }

    @Test func theGalleryCanBeAskedForTheWatchAlone() {
        #expect(ActivityGalleryRequest.requested(["-activityGallery", "watch"]) == .watch)
        #expect(ActivityGalleryRequest.requested(["-activityGallery", "lock"]) == .lock)
        #expect(ActivityGalleryRequest.requested(["-activityGallery"]) == .all && ActivityGalleryRequest.requested(["-nothing"]) == nil)
    }
}
