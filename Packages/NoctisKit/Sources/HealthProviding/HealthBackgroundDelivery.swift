import Foundation

/// How often Apple Health may wake NOCTIS for each kind of data (APP_RULES.md R46). `HKUpdateFrequency` offers immediate, hourly, daily and
/// weekly; the choice here is the least frequent that still serves a morning widget:
///
/// - Sleep: hourly. The night's sleep arrives once, when the watch syncs after waking; a daily wake could already have been spent
///   earlier in the day, and the widget would wait until tomorrow. Immediate would wake the app for every stage that is written.
/// - Heart rate variability and resting heart rate: daily. They arrive overnight with the sleep, and any wake refreshes everything, so
///   these only matter when they change alone.
///
/// Weekly would leave the morning widget a week behind, so it is not used. HealthKit may deliver less often than asked (it says so for
/// some types) and iOS decides when the app runs: delivery is best-effort.
public nonisolated enum HealthBackgroundPlan {
    public enum Frequency: Sendable, Equatable { case hourly, daily }

    public static let observed: [(kind: HealthDataKind, frequency: Frequency)] = [
        (.sleepAnalysis, .hourly), (.hrv, .daily), (.restingHeartRate, .daily),
    ]
}

/// Background delivery: Apple Health wakes the app when new data arrives, and the app has until it calls `done` to read it (APP_RULES.md R46).
/// The real provider registers an observer query for each kind in `HealthBackgroundPlan` and asks Health to deliver in the background;
/// the mock records the calls.
public protocol HealthBackgroundDelivering: Sendable {
    /// Registers for background delivery and starts observing. `wake` is called for each delivery with a `done` closure that MUST be
    /// called once the app has finished with it (it is HealthKit's own completion handler), on every path. Safe to call again: it
    /// replaces the earlier observers.
    func startBackgroundDelivery(wake: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) async

    /// Stops observing and asks Health to stop waking the app (Delete all NOCTIS data).
    func stopBackgroundDelivery() async
}
