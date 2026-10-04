import Foundation

/// The Live Activities NOCTIS has started. It starts none itself yet: the wake alarm's snooze countdown is AlarmKit's, and it ends
/// when the alarm is cancelled (the delete-all step before this one). The wind-down's own Live Activity is in ROADMAP.md. This is
/// the one place that will end them, so "Delete all NOCTIS data" cannot leave one running when it exists.
enum LiveActivities {
    @MainActor
    static func endAll() async {}
}
