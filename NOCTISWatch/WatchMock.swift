#if DEBUG
import Foundation
import NoctisWidgetKit

/// `-watchMockSnapshot full|learning|sleepOnly|empty|stale|gap|waiting|noSnapshot` (APP_RULES.md R50): feeds the Watch app a sample snapshot without the
/// iPhone, so a screenshot or a test can show every state. A DEBUG aid and an explicit R13 exception: sample numbers appear nowhere else.
struct WatchMock {
    let snapshot: WidgetSnapshot?
    let receivedAt: Date?
    /// The moment the mock pretends it is when the app starts (10:00 today, or 21:30 with `-watchEvening`); the clock runs from there.
    let now: Date

    init?(arguments: [String]) {
        guard let flag = arguments.firstIndex(of: "-watchMockSnapshot") else { return nil }
        let name = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "full"
        let calendar = Calendar.autoupdatingCurrent
        // 10:00 this morning, so a morning state is today's; "evening" pins 21:30.
        let hour = arguments.contains("-watchEvening") ? 21 : 10
        let now = calendar.date(bySettingHour: hour, minute: arguments.contains("-watchEvening") ? 30 : 0, second: 0, of: Date()) ?? Date()
        var value: WidgetSnapshot?
        switch name {
        case "learning": value = WidgetSamples.snapshot(.learning(nightsSoFar: 3), now: now, calendar: calendar)
        case "sleepOnly": value = WidgetSamples.snapshot(.sleepOnly, now: now, calendar: calendar)
        case "empty": value = WidgetSamples.snapshot(.empty, now: now, calendar: calendar)
        case "stale": value = WidgetSamples.snapshot(.stale(hours: 14), now: now, calendar: calendar)
        case "gap": value = WidgetSamples.snapshot(.gap, now: now, calendar: calendar)
        case "waiting":
            var yesterday = WidgetSamples.snapshot(.full, now: now, calendar: calendar)
            yesterday.forDay = WidgetDay.today(at: now.addingTimeInterval(-86_400), calendar: calendar)
            value = yesterday
        case "noSnapshot": value = nil
        default: value = WidgetSamples.snapshot(.full, now: now, calendar: calendar)
        }
        snapshot = value
        self.now = now
        receivedAt = value == nil ? nil : now.addingTimeInterval(-3 * 3600)
    }
}
#endif
