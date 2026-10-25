import Foundation
import NoctisCore

/// Where Coach gets the app's snapshots.
public protocol CoachDataSource: Sendable {
    func snapshots(profile: UserProfileSnapshot) async -> CoachSnapshots
}

/// The four repositories the tabs already use. A snapshot they built within
/// `maxAge` is reused; an older one is refreshed (a refresh is coalesced with
/// any the tabs are running).
public struct RepositoryCoachDataSource: CoachDataSource {
    public let home: HomeRepository
    public let sleep: SleepRepository
    public let recovery: RecoveryRepository
    public let insights: InsightsRepository
    public let maxAge: TimeInterval
    private let clock: @Sendable () -> Date
    private let suggestedBedtime: @Sendable (UserProfileSnapshot, SleepSnapshot) async -> Int?

    /// `suggestedBedtime`: the bedtime Tonight shows for this plan, so Coach names the same time (nil keeps the wake time less the sleep need).
    public init(
        home: HomeRepository, sleep: SleepRepository, recovery: RecoveryRepository, insights: InsightsRepository,
        maxAge: TimeInterval = 600, clock: @escaping @Sendable () -> Date = { Date() },
        suggestedBedtime: @escaping @Sendable (UserProfileSnapshot, SleepSnapshot) async -> Int? = { _, _ in nil }
    ) {
        self.home = home
        self.sleep = sleep
        self.recovery = recovery
        self.insights = insights
        self.maxAge = maxAge
        self.clock = clock
        self.suggestedBedtime = suggestedBedtime
    }

    public func snapshots(profile: UserProfileSnapshot) async -> CoachSnapshots {
        let now = clock()
        func fresh(_ date: Date) -> Bool { now.timeIntervalSince(date) < maxAge }
        async let homeSnapshot: HomeSnapshot = {
            if let cached = await home.cachedSnapshot, fresh(cached.lastUpdated) { return cached }
            return await home.refresh(profile: profile)
        }()
        async let sleepSnapshot: SleepSnapshot = {
            if let cached = await sleep.cachedSnapshot, fresh(cached.lastUpdated) { return cached }
            return await sleep.refresh(profile: profile)
        }()
        async let recoverySnapshot: RecoverySnapshot = {
            if let cached = await recovery.cachedSnapshot, fresh(cached.lastUpdated) { return cached }
            return await recovery.refresh(profile: profile)
        }()
        async let insightsSnapshot: InsightsSnapshot = {
            if let cached = await insights.cachedSnapshot, fresh(cached.lastUpdated) { return cached }
            return await insights.refresh(profile: profile)
        }()
        let sleepResult = await sleepSnapshot
        return await CoachSnapshots(
            home: homeSnapshot, sleep: sleepResult, recovery: recoverySnapshot, insights: insightsSnapshot,
            suggestedBedtimeMinutes: suggestedBedtime(profile, sleepResult)
        )
    }
}

/// A fixed set of snapshots (tests, previews).
public struct StaticCoachDataSource: CoachDataSource {
    public let value: CoachSnapshots

    public init(_ value: CoachSnapshots) {
        self.value = value
    }

    public func snapshots(profile: UserProfileSnapshot) async -> CoachSnapshots { value }
}
