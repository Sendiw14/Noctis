import Foundation
import PremiumKit

/// Sample snapshots for the widget gallery's preview and for the debug-build gallery (APP_RULES.md R45): the only place invented numbers
/// exist. A real timeline never contains one: `WidgetTimelineBuilder.build` takes a snapshot from the store, and a preview entry is
/// marked `isPreview` and drawn with a "Sample" tag.
public enum WidgetSamples {
    /// A snapshot in `state`, for the day of `now`. A sample is an unlocked one (Premium) unless the caller says otherwise: it shows what a surface can draw (R62).
    public static func snapshot(_ state: WidgetDataState, now: Date, calendar: Calendar, tier: Tier = .premium) -> WidgetSnapshot {
        #if DEBUG
        // QA part 5: with `-phoneFixtures <folder>` the numbers are the iPhone's own for the same scenario (the snapshot its WidgetSnapshotMaker wrote),
        // so the Watch and the widget gallery show the same night as Home. Only the day, the moment, the state and the plan come from the caller.
        if let folder = phoneFixtureFolder, var fixture = phoneFixture(for: state, in: folder) {
            fixture.forDay = WidgetDay.today(at: now, calendar: calendar)
            fixture.generatedAt = now
            fixture.state = state
            fixture.tier = tier
            return fixture
        }
        #endif
        let plan = WidgetPlan(
            wakeMinutes: 7 * 60, needMinutes: 8 * 60, bedtimeMinutes: 23 * 60, windowStartMinutes: 22 * 60 + 45, windowEndMinutes: 23 * 60 + 15)
        let night = WidgetNight(
            asleepMinutes: 402, stages: WidgetStages(deep: 74, core: 236, rem: 92), bedtimeMinutes: 23 * 60 + 4, wakeMinutes: 6 * 60 + 52, quality: 81)
        let fullRing = [
            WidgetRingSegment(kind: .sleepDuration, weight: 0.35, fraction: 0.82), WidgetRingSegment(kind: .hrv, weight: 0.25, fraction: 0.64),
            WidgetRingSegment(kind: .restingHeartRate, weight: 0.2, fraction: 0.71), WidgetRingSegment(kind: .sleepConsistency, weight: 0.2, fraction: 0.9),
        ]
        let sleepRing = [
            WidgetRingSegment(kind: .sleepDuration, weight: 0.6, fraction: 0.82), WidgetRingSegment(kind: .sleepConsistency, weight: 0.4, fraction: 0.9),
        ]
        let fullFactors = [
            WidgetRecoveryFactor(kind: .sleepDuration, score: 82, value: 402, baseline: 450),
            WidgetRecoveryFactor(kind: .hrv, score: 64, value: 54, baseline: 61, range: .within),
            WidgetRecoveryFactor(kind: .restingHeartRate, score: 71, value: 52, baseline: 50, range: .above),
            WidgetRecoveryFactor(kind: .sleepConsistency, score: 90, value: 12, baseline: nil),
        ]
        var snapshot = WidgetSnapshot(
            forDay: WidgetDay.today(at: now, calendar: calendar), generatedAt: now, plan: plan, state: state,
            alarm: WidgetAlarm(minutes: 7 * 60, isOn: true), tier: tier
        )
        switch state {
        case .full:
            snapshot.recovery = WidgetRecovery(score: 70, delta: 6, confidence: .high, ring: fullRing)
            snapshot.lastNight = night
            snapshot.factors = WidgetFactors(hrv: 54, restingHeartRate: 52)
            snapshot.recoveryFactors = fullFactors
            snapshot.nightsOfHistory = 14
        case .sleepOnly:
            snapshot.recovery = WidgetRecovery(score: 68, delta: 2, confidence: .moderate, ring: sleepRing)
            snapshot.lastNight = night
            snapshot.recoveryFactors = Array(fullFactors.filter { $0.kind == .sleepDuration || $0.kind == .sleepConsistency })
            snapshot.nightsOfHistory = 9
        case .stale:
            snapshot.recovery = WidgetRecovery(score: 70, delta: 6, confidence: .high, ring: fullRing)
            snapshot.lastNight = night
            snapshot.factors = WidgetFactors(hrv: 54, restingHeartRate: 52)
            snapshot.recoveryFactors = fullFactors
            snapshot.nightsOfHistory = 14
        case .learning:
            snapshot.lastNight = night
        case .empty, .noPermission, .gap:
            break
        }
        return snapshot
    }

    #if DEBUG
    /// The folder `-phoneFixtures` named: one `<scenario>.json` per state, written by `scripts/qa_phone_fixtures.sh` from the iPhone's mock scenarios.
    public nonisolated(unsafe) static var phoneFixtureFolder: URL?

    /// Reads `-phoneFixtures <folder>` from a launch's arguments.
    public static func usePhoneFixtures(arguments: [String]) {
        guard let flag = arguments.firstIndex(of: "-phoneFixtures"), arguments.indices.contains(flag + 1) else { return }
        phoneFixtureFolder = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    }

    static func phoneFixture(for state: WidgetDataState, in folder: URL) -> WidgetSnapshot? {
        let name: String
        switch state {
        case .full: name = "full"
        case .sleepOnly: name = "sleepOnly"
        case .learning: name = "learning"
        case .empty, .noPermission: name = "empty"
        case .stale: name = "stale"
        case .gap: name = "gap"
        }
        guard let data = try? Data(contentsOf: folder.appending(path: "\(name).json", directoryHint: .notDirectory)) else { return nil }
        return WidgetSnapshot.decode(data)
    }
    #endif
}
