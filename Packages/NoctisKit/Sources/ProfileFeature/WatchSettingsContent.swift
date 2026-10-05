import Foundation
import NoctisCore

/// The words of the Apple Watch page in Settings (APP_RULES.md R20, R29, R50, R52): what the link to the person's own Watch is doing, in plain
/// sentences, and what "Send update now" did. Made from the status the iPhone can really read, and from nothing else, so a state the system cannot
/// report (a Watch that is on but out of range, and one that is off, look the same to an iPhone) is not described as if it could.
public nonisolated struct WatchSettingsContent: Equatable, Sendable {
    /// The headline: "Connected", "Not reachable", "Watch app not installed".
    public var statusTitle: String
    /// One sentence under it.
    public var statusDetail: String
    /// The Settings row's value: "Connected", "Not reachable", "Not installed", "Connecting".
    public var rowValue: String
    /// "Last sent today at 7:02 AM", or that nothing was sent yet. Nil where nothing can be sent at all.
    public var lastSent: String?
    /// How to put NOCTIS on the Watch, only while it is not there.
    public var installInstruction: String?
    /// Whether "Send update now" can do anything: only with the Watch app installed.
    public var canSend: Bool

    /// What the Watch shows, one line each (the list the page shows).
    public static let appears: [String] = [
        "Your recovery score and what went into it",
        "Last night's sleep: how long, when, and its stages",
        "Heart rate variability and resting heart rate, against your usual",
        "Tonight's bedtime, wake time and alarm",
    ]

    /// What the Watch does not do, said once under the list.
    public static let readsNothing = "Your Watch shows a short summary sent from this iPhone. It reads nothing from Apple Health itself, and nothing else is sent."
    public static let deleteNote = "Deleting all NOCTIS data on this iPhone clears the Watch too, when it next connects."
    public static let sendButton = "Send update now"
    public static let sendHint = "Sends the latest summary to your Apple Watch."
    public static let installSteps = "Open the Watch app on your iPhone, find NOCTIS under Available Apps and tap Install."

    public static func make(_ status: WatchConnectionStatus, now: Date, calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> WatchSettingsContent {
        let lastSent = lastSentLine(status.lastSentAt, now: now, calendar: calendar, locale: locale)
        switch status.connection {
        case .notSupported:
            return WatchSettingsContent(
                statusTitle: "Not available", statusDetail: "This iPhone can't connect to an Apple Watch.", rowValue: "Not available", lastSent: nil,
                installInstruction: nil, canSend: false
            )
        case .noWatchPaired:
            return WatchSettingsContent(
                statusTitle: "No Apple Watch paired", statusDetail: "Pair an Apple Watch with this iPhone to see NOCTIS on your wrist.", rowValue: "None paired",
                lastSent: nil, installInstruction: nil, canSend: false
            )
        case .notActivated:
            return WatchSettingsContent(
                statusTitle: "Connecting", statusDetail: "NOCTIS is setting up the link to your Watch. This takes a moment.", rowValue: "Connecting",
                lastSent: nil, installInstruction: nil, canSend: false
            )
        case .appNotInstalled:
            return WatchSettingsContent(
                statusTitle: "Watch app not installed", statusDetail: "NOCTIS isn't on your Apple Watch yet.", rowValue: "Not installed", lastSent: nil,
                installInstruction: installSteps, canSend: false
            )
        case .connected:
            return WatchSettingsContent(
                statusTitle: "Connected", statusDetail: "Your Apple Watch can be reached now.", rowValue: "Connected", lastSent: lastSent,
                installInstruction: nil, canSend: true
            )
        case .notReachable:
            return WatchSettingsContent(
                statusTitle: "Not reachable", statusDetail: "Your Watch is out of range or asleep. It gets the latest update when it connects.", rowValue: "Not reachable",
                lastSent: lastSent, installInstruction: nil, canSend: true
            )
        }
    }

    /// "Last sent today at 7:02 AM", "Last sent yesterday at 11:14 PM", "Last sent Sep 21 at 7:02 AM", or "Nothing sent yet".
    public static func lastSentLine(_ date: Date?, now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let date else { return "Nothing sent yet" }
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return "Last sent today at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Last sent yesterday at \(time)" }
        let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
        return "Last sent \(day) at \(time)"
    }

    /// What "Send update now" did, said plainly: sent or queued, or the reason it could not be.
    public static func sendResult(_ outcome: WatchSendOutcome, reachable: Bool) -> String {
        switch outcome {
        case .sent: reachable ? "Update sent to your Watch." : "Update queued. Your Watch gets it when it connects."
        case .nothingToSend: "There's nothing to send yet. Open Home once your sleep has loaded, then try again."
        case .appNotInstalled: "NOCTIS isn't installed on your Watch yet."
        case .noWatchPaired, .notSupported: "No Apple Watch is paired with this iPhone."
        case .notActivated: "The link to your Watch isn't ready yet. Try again in a moment."
        case .failed(let reason): "Couldn't send the update. \(reason)"
        }
    }
}
