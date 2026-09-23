import Foundation
import HealthProviding
import InsightsKit
import Observation
import RecoveryKit
import SleepKit
import SwiftData

@Observable
public final class AppModel {
    public private(set) var profile: UserProfileSnapshot
    public private(set) var dataState: NoctisDataState = .loading
    public private(set) var today: TodaySnapshot?
    public private(set) var insights: [Insight] = []
    public private(set) var healthAuthorization: HealthAuthorizationStatus = .notDetermined
    public var selectedTab: AppTab = .home

    let healthProvider: any HealthDataProviding
    let sourceResolver: any SourceResolving
    private let profileStore: ProfileStore
    private let insightFatigueStore: InsightFatigueStore
    let historyWindowDays = 120
    let baselineWindowDays = BaselineEngine.windowDays

    public init(
        healthProvider: any HealthDataProviding,
        profileStore: ProfileStore,
        insightFatigueStore: InsightFatigueStore,
        sourceResolver: any SourceResolving = DefaultSourceResolver()
    ) {
        self.healthProvider = healthProvider
        self.profileStore = profileStore
        self.insightFatigueStore = insightFatigueStore
        self.sourceResolver = sourceResolver
        self.profile = profileStore.load()
    }

    public var isOnboarded: Bool { profile.onboardingComplete }
    public var healthSourceName: String { healthProvider.sourceName }
    public var isHealthDataAvailable: Bool { healthProvider.isHealthDataAvailable }

    public func requestHealthAuthorization(for kinds: [HealthDataKind] = HealthDataKind.allCases) async {
        healthAuthorization = await healthProvider.requestAuthorization(for: kinds)
        profile.healthAuthorizationRequested = true
        profileStore.save(profile)
    }

    public func completeOnboarding(_ snapshot: UserProfileSnapshot) async {
        var updated = snapshot
        updated.onboardingComplete = true
        profile = updated
        profileStore.save(updated)
        await refresh()
    }

    public func updateProfile(_ transform: (inout UserProfileSnapshot) -> Void) {
        transform(&profile)
        profileStore.save(profile)
    }

    /// Orchestrates the pipeline defined in `AppModel+RefreshPipeline.swift`:
    /// Health Data → Session Construction → Metrics → Baselines → Recovery
    /// → History → Insights → Presentation. Each arrow below is one call
    /// into a stage of that same name.
    public func refresh() async {
        guard isHealthDataAvailable else {
            dataState = .healthKitUnavailable
            return
        }
        healthAuthorization = await healthProvider.authorizationStatus()
        guard healthAuthorization == .authorized else {
            dataState = .permissionRequired
            return
        }

        dataState = .loading
        let now = Date.now
        let windowStart = Calendar.current.date(byAdding: .day, value: -historyWindowDays, to: now) ?? now

        do {
            // Health Data (sleep) → Session Construction
            let sleepSamples = try await fetchSleepSamples(from: windowStart, to: now)
            guard let construction = constructSessions(from: sleepSamples, asOf: now) else {
                dataState = .noData
                today = nil
                return
            }

            // Health Data (supplementary — scoped to the latest night)
            let supplementary = try await fetchSupplementaryHealthData(windowStart: windowStart, now: now, latest: construction.latest)

            // Metrics
            guard let metrics = computeMetrics(mainSessions: construction.mainSessions, needHours: profile.sleepGoalHours) else {
                dataState = .error("We couldn't read your latest sleep data.")
                return
            }

            // Baselines
            let baselines = computeBaselines(
                hrvSamples: supplementary.hrvSamples,
                restingSamples: supplementary.restingSamples,
                before: construction.latest.bedtime
            )

            // Recovery → History
            let recovery = computeRecoveryAndHistory(
                scored: metrics.scored,
                latestScored: metrics.latestScored,
                hrvSamples: supplementary.hrvSamples,
                restingSamples: supplementary.restingSamples,
                baselines: baselines,
                consistencyScore: metrics.consistencyScore
            )

            // Insights
            let generatedInsights = generateInsights(scored: metrics.scored, recoveryHistory: recovery.history)
            insightFatigueStore.recordShown(generatedInsights, on: now)

            // Presentation
            today = TodaySnapshot(
                session: construction.latest,
                quality: metrics.latestScored.quality,
                recovery: recovery.today,
                balance: metrics.balance,
                recoveryHistory: recovery.history,
                scoredSessions: metrics.scored,
                nightHeartRateSamples: supplementary.nightHeartRate,
                nightRespiratoryRate: supplementary.nightRespiratory.first?.breathsPerMinute
            )
            insights = generatedInsights
            dataState = .ready
        } catch {
            dataState = .error("We couldn't read your latest sleep data.")
        }
    }
}
