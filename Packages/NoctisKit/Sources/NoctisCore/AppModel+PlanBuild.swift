import Foundation
import HealthProviding
import RecoveryKit

/// The two real, independently-awaitable operations behind Plan's build
/// checklist (`PlanScreen`, onboarding step 6). Kept on `AppModel` rather
/// than exposed via `healthProvider` directly so `OnboardingFeature` (which
/// depends only on `DesignSystem` + `NoctisCore`) never needs SleepKit,
/// RecoveryKit or HealthProviding as direct dependencies just to build the
/// plan preview.
extension AppModel {
    /// "Reading your recent nights": counts real sleep sessions in the
    /// trailing `windowDays`. Returns 0 — never throws — when health data
    /// is unavailable or unauthorized, since the screen treats "no
    /// permission" and "no data" identically (both read as "starting
    /// fresh"). A thrown error here means a genuine query failure despite
    /// good authorization, which the screen surfaces as a real failure.
    public func fetchRecentNightCount(windowDays: Int = 30, asOf now: Date = .now) async throws -> Int {
        try await fetchRecentNights(windowDays: windowDays, asOf: now).count
    }

    /// The distinct nights (each keyed by the evening it started on) that
    /// contain a real main sleep session built from actual samples — never
    /// the calendar days in the window. A bedtime after midnight belongs to
    /// the previous evening's night, and two main sessions split by a data
    /// gap on the same night count once.
    func fetchRecentNights(windowDays: Int = 30, asOf now: Date = .now) async throws -> [Date] {
        guard isHealthDataAvailable else { return [] }
        guard await healthProvider.authorizationStatus() == .authorized else { return [] }
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let raw = try await fetchSleepSamples(from: windowStart, to: now)
        let sessions = constructSessions(from: raw, asOf: now)?.mainSessions ?? []
        let nights = Set(sessions.map { calendar.startOfDay(for: $0.bedtime.addingTimeInterval(-12 * 3600)) }).sorted()
        return nights
    }

    /// "Finding your typical bedtime": a real, independent query + baseline
    /// computation (deliberately not reusing `fetchRecentNightCount`'s
    /// samples — each checklist line represents its own genuine unit of
    /// work). The computed baseline isn't surfaced anywhere yet, so nothing
    /// public is returned; this exists so the checklist line represents
    /// real work rather than a decorative delay.
    public func seedTypicalBedtimeBaseline(windowDays: Int = 30, asOf now: Date = .now) async throws {
        guard isHealthDataAvailable else { return }
        guard await healthProvider.authorizationStatus() == .authorized else { return }
        let windowStart = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let raw = try await fetchSleepSamples(from: windowStart, to: now)
        guard let construction = constructSessions(from: raw, asOf: now), !construction.mainSessions.isEmpty else { return }
        let bedtimeMinutes = construction.mainSessions.map { session -> Double in
            let components = Calendar.current.dateComponents([.hour, .minute], from: session.bedtime)
            return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        }
        _ = BaselineEngine.baseline(from: bedtimeMinutes)
    }
}
