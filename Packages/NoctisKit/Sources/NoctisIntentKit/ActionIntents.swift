import AppIntents
import DesignSystem
import Foundation
import NoctisWidgetKit
import SoundCatalog

// The intents that do something (APP_RULES.md R47): start a wind-down, play a sleep sound, set tonight's alarm, ask Coach.
// Each asks the running app (the host) through the one path the app has; none holds navigation or audio logic of its own.

public struct StartWindDownIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start my wind-down"
    public static let description = IntentDescription("Opens NOCTIS and starts a wind-down of 10, 20 or 30 minutes.", categoryName: "Sleep")
    public static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Length", description: "10, 20 or 30 minutes. Your last choice if you leave it out.")
    public var length: WindDownLength?

    public init() {}

    public init(length: WindDownLength?) {
        self.length = length
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Start my wind-down for \(\.$length)")
    }

    /// What is said (a test and the debug runner use the same sentences).
    public static func dialog(length: WindDownLength?) -> String {
        length.map { "Starting a \($0.minutes) minute wind-down." } ?? "Starting your wind-down."
    }

    public static let withoutApp = "Open NOCTIS to start your wind-down."

    /// The wind-down session is Premium (R62): on the free plan nothing is started. The app opens on the paywall sheet, saying what Premium includes, and says so.
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = IntentRuntime.current
        guard let host = await runtime.host() else { return .result(dialog: IntentDialog(stringLiteral: Self.withoutApp)) }
        guard IntentGate.includesStartWindDown(in: runtime.environment.tier()) else {
            host.open(.paywall(.windDown))
            return .result(dialog: IntentDialog(stringLiteral: IntentGate.startWindDownLocked))
        }
        host.startWindDown(minutes: length?.minutes)
        return .result(dialog: IntentDialog(stringLiteral: Self.dialog(length: length)))
    }
}

public struct PlaySleepSoundsIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Play sleep sounds"
    public static let description = IntentDescription(
        "Plays a sleep sound, without opening NOCTIS. The last one you played if you leave it out.", categoryName: "Sleep")

    @Parameter(title: "Sound")
    public var sound: SoundEntity?

    public init() {}

    public init(sound: SoundEntity?) {
        self.sound = sound
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$sound)")
    }

    /// The sound the intent asks for, if it is one NOCTIS has.
    public var requestedKind: SoundKind? { sound?.kind }

    public static func dialog(kind: SoundKind) -> String { "Playing \(kind.title.lowercased())." }

    public static let withoutApp = "Open NOCTIS to play sleep sounds."

    /// Brown noise, Rain and Ocean are free; a Premium sound on the free plan plays nothing and says so (R62). Naming none plays the last one the plan includes.
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = IntentRuntime.current
        guard let host = await runtime.host() else { return .result(dialog: IntentDialog(stringLiteral: Self.withoutApp)) }
        switch IntentGate.soundChoice(requested: requestedKind, last: host.lastSleepSound, tier: runtime.environment.tier()) {
        case .premiumNeeded(let kind):
            return .result(dialog: IntentDialog(stringLiteral: IntentGate.premiumSoundDialog(kind)))
        case .play(let kind):
            // The existing sound player starts it, and handles interruptions as it always does; its own guard has the last word on the plan.
            guard host.playSleepSounds(kind) else { return .result(dialog: IntentDialog(stringLiteral: IntentGate.premiumSoundDialog(kind))) }
            return .result(dialog: IntentDialog(stringLiteral: Self.dialog(kind: kind)))
        }
    }
}

public struct SetTonightAlarmIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set tonight's alarm"
    public static let description = IntentDescription(
        "Sets your wake alarm. If NOCTIS has not been allowed to set alarms yet, it opens the alarm settings instead.", categoryName: "Sleep"
    )
    public static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Time", kind: .time)
    public var time: DateComponents

    public init() {}

    public init(time: DateComponents) {
        self.time = time
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Set tonight's alarm for \(\.$time)")
    }

    /// Minutes since midnight, from the time given.
    public var minutes: Int { ((time.hour ?? 0) * 60 + (time.minute ?? 0) + 1440) % 1440 }

    /// What is said for each outcome.
    public static func dialog(_ outcome: AlarmIntentOutcome, format: WidgetFormat = WidgetFormat()) -> String {
        switch outcome {
        case .set(let minutes): WidgetSpoken.alarmSet(minutes: minutes, format: format)
        case .couldNotSet: "I couldn't set the alarm. Open NOCTIS to try again."
        case .needsAuthorization: "Allow alarms in NOCTIS first. I've opened the alarm settings."
        }
    }

    public static let withoutApp = "Open NOCTIS to set your alarm."

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = IntentRuntime.current
        guard let host = await runtime.host() else { return .result(dialog: IntentDialog(stringLiteral: Self.withoutApp)) }
        let outcome = await host.setTonightAlarm(minutes: minutes)
        // Without alarm access nothing was changed: the alarm sheet asks the person, with the system's own question.
        if outcome == .needsAuthorization { host.open(.alarm) }
        return .result(dialog: IntentDialog(stringLiteral: Self.dialog(outcome, format: runtime.environment.format())))
    }
}

public struct AskCoachIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask Coach"
    public static let description = IntentDescription("Opens Coach on your question. The answer is in the app, not read out.", categoryName: "Coach")
    public static let supportedModes: IntentModes = .foreground(.immediate)
    /// The longest a question can be: Coach's own limit.
    public static let maximumLength = 200

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask Coach?")
    public var question: String

    public init() {}

    public init(question: String) {
        self.question = question
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Ask Coach \(\.$question)")
    }

    /// The question as Coach will get it: trimmed and no longer than Coach allows.
    public var cleaned: String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > Self.maximumLength ? String(trimmed.prefix(Self.maximumLength)) : trimmed
    }

    public static let noQuestion = "There was no question to ask."
    public static let opening = "Opening Coach."
    public static let withoutApp = "Open NOCTIS to ask Coach."

    /// Opens Coach on the question; it does not answer here, and the intent keeps no copy of the text.
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !cleaned.isEmpty else { return .result(dialog: IntentDialog(stringLiteral: Self.noQuestion)) }
        guard let host = await IntentRuntime.current.host() else { return .result(dialog: IntentDialog(stringLiteral: Self.withoutApp)) }
        // The free questions are counted by the app (R60): with today's used up Coach opens on its card and the question is neither asked nor kept.
        let outcome = host.askCoach(cleaned)
        return .result(dialog: IntentDialog(stringLiteral: outcome == .asked ? Self.opening : IntentGate.coachLimitReached))
    }
}
