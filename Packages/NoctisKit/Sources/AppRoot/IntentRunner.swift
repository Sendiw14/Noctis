#if DEBUG
import AppIntents
import DesignSystem
import NoctisIntentKit
import NoctisWidgetKit
import PremiumKit
import SoundKit
import SwiftUI

// The DEBUG intent runner (APP_RULES.md R47, R62): `-intentRunner [-intentRunnerTier free|premium]` (premium when absent). Each intent is run for real under a recording host and a chosen snapshot (data,
// sleep only, learning, empty, stale, no sleep, waiting, no snapshot), and shown as the words Siri would speak and what the app was asked to
// do. A screenshot of it is the "spoken-text preview" of each intent. It is not Siri: the real phrases, the unlock before Health numbers
// and the audio-without-a-launch are for an iPhone.

public enum IntentRunnerRequest {
    public static func requested(_ arguments: [String]) -> Bool { arguments.contains("-intentRunner") }
}

@MainActor
private final class RecordingHost: IntentHost {
    var done: [String] = []
    var alarmAllowed = true
    /// The last sound the pretend player played (Wind, for the runner's "last sound is no longer included" row).
    var lastSleepSound: SoundKind?
    /// Today's free Coach questions are used up.
    var coachLimited = false

    func open(_ destination: IntentDestination) { done.append("open \(destination)") }
    func startWindDown(minutes: Int?) { done.append("start wind-down \(minutes.map(String.init) ?? "last length")") }
    func playSleepSounds(_ kind: SoundKind) -> Bool {
        done.append("play \(kind.rawValue)")
        return true
    }
    func stopSleepSounds() { done.append("stop sleep sounds") }
    func endWindDown() { done.append("end wind-down") }
    func setTonightAlarm(minutes: Int) async -> AlarmIntentOutcome {
        guard alarmAllowed else { return .needsAuthorization }
        done.append("alarm \(minutes)")
        return .set(minutes: minutes)
    }
    func askCoach(_ text: String) -> AskCoachOutcome {
        guard !coachLimited else {
            done.append("open coach (question not kept)")
            return .limitReached
        }
        done.append("ask Coach (\(text.count) characters)")
        return .asked
    }
}

private struct RunnerRow: Identifiable {
    let id = UUID()
    let phrase: String
    let spoken: String
    let did: [String]
    let policy: String
}

private struct RunnerScene: Identifiable {
    let id: String
    let title: String
    var rows: [RunnerRow]
}

@MainActor
private enum IntentRunnerScenes {
    static func make(tier: Tier) async -> [RunnerScene] {
        let calendar = Calendar.autoupdatingCurrent
        let now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
        func snapshot(_ state: WidgetDataState) -> WidgetSnapshot { WidgetSamples.snapshot(state, now: now, calendar: calendar, tier: tier) }
        var yesterday = snapshot(.full)
        yesterday.forDay = WidgetDay.today(at: now.addingTimeInterval(-86_400), calendar: calendar)
        let cases: [(String, String, WidgetSnapshot?)] = [
            ("data", "Full data", snapshot(.full)), ("sleepOnly", "Sleep only", snapshot(.sleepOnly)),
            ("learning", "Learning (3 of 5 nights)", snapshot(.learning(nightsSoFar: 3))), ("empty", "Empty, or Apple Health not connected", snapshot(.noPermission)),
            ("stale", "Stale (14 hours)", snapshot(.stale(hours: 14))), ("gap", "No sleep last night", snapshot(.gap)),
            ("waiting", "Waiting: the snapshot is for yesterday", yesterday), ("none", "No snapshot yet", nil),
        ].map { ($0.0, "\($0.1) · \(tier.rawValue)", $0.2) }
        var scenes: [RunnerScene] = []
        for (id, title, value) in cases {
            let host = RecordingHost()
            let runtime = IntentRuntime(environment: IntentEnvironment(snapshot: { value }, now: { now }, calendar: { calendar }), host: host)
            var rows: [RunnerRow] = []
            func run<I: AppIntent>(_ phrase: String, _ intent: I, _ spoken: String, policy: IntentAuthenticationPolicy) async {
                host.done = []
                _ = try? await IntentRuntime.$override.withValue(runtime) { try await intent.perform() }
                rows.append(RunnerRow(phrase: phrase, spoken: spoken, did: host.done, policy: policy == .alwaysAllowed ? "no unlock needed" : "asks to unlock first"))
            }
            await run("Show my recovery in NOCTIS", ShowMyRecoveryIntent(), ShowMyRecoveryIntent.answer(runtime), policy: ShowMyRecoveryIntent.authenticationPolicy)
            await run("Show my sleep in NOCTIS", ShowMySleepIntent(), ShowMySleepIntent.answer(runtime), policy: ShowMySleepIntent.authenticationPolicy)
            await run("What time should I sleep in NOCTIS", ShowRecommendedBedtimeIntent(), ShowRecommendedBedtimeIntent.answer(runtime), policy: ShowRecommendedBedtimeIntent.authenticationPolicy)
            scenes.append(RunnerScene(id: id, title: title, rows: rows))
        }
        // The intents that do something, with their sentences.
        let host = RecordingHost()
        // The actions read the plan from the snapshot, as they do for real: the sample for this plan stands in for the App Group's file.
        let planSnapshot = snapshot(.full)
        let runtime = IntentRuntime(environment: IntentEnvironment(snapshot: { planSnapshot }, now: { now }, calendar: { calendar }), host: host)
        var actions: [RunnerRow] = []
        func act<I: AppIntent>(_ phrase: String, _ intent: I, _ spoken: String) async {
            host.done = []
            _ = try? await IntentRuntime.$override.withValue(runtime) { try await intent.perform() }
            actions.append(RunnerRow(phrase: phrase, spoken: spoken, did: host.done, policy: "no unlock needed"))
        }
        await act(
            "Start my wind-down in NOCTIS", StartWindDownIntent(length: .twentyMinutes),
            IntentGate.includesStartWindDown(in: tier) ? StartWindDownIntent.dialog(length: .twentyMinutes) : IntentGate.startWindDownLocked
        )
        await act("Start my sleep sounds in NOCTIS", PlaySleepSoundsIntent(sound: SoundEntity(.ocean)), PlaySleepSoundsIntent.dialog(kind: .ocean))
        await act("Play Wind in NOCTIS", PlaySleepSoundsIntent(sound: SoundEntity(.wind)), tier == .premium ? PlaySleepSoundsIntent.dialog(kind: .wind) : IntentGate.premiumSoundDialog(.wind))
        host.lastSleepSound = .fireplace
        await act("Play sleep sounds in NOCTIS (the last one was Fireplace)", PlaySleepSoundsIntent(sound: nil), tier == .premium ? PlaySleepSoundsIntent.dialog(kind: .fireplace) : PlaySleepSoundsIntent.dialog(kind: .brown))
        host.lastSleepSound = nil
        await act("Set tonight's alarm for 6:30 AM", SetTonightAlarmIntent(time: DateComponents(hour: 6, minute: 30)), SetTonightAlarmIntent.dialog(.set(minutes: 390)))
        host.alarmAllowed = false
        await act("Set tonight's alarm (alarms not allowed yet)", SetTonightAlarmIntent(time: DateComponents(hour: 6, minute: 30)), SetTonightAlarmIntent.dialog(.needsAuthorization))
        await act("Ask Coach in NOCTIS: why was my sleep short?", AskCoachIntent(question: "Why was my sleep short?"), AskCoachIntent.opening)
        host.coachLimited = true
        await act("Ask Coach (today's free questions used up)", AskCoachIntent(question: "Why was my sleep short?"), IntentGate.coachLimitReached)
        scenes.append(RunnerScene(id: "actions", title: "Intents that do something · \(tier.rawValue)", rows: actions))
        return scenes
    }
}

public struct IntentRunnerView: View {
    @State private var scenes: [RunnerScene] = []
    private let tier: Tier
    /// `-intentRunnerScenes data,actions`: only these scenes (ids as in the runner: data, sleepOnly, learning, empty, stale, gap, waiting, none, actions).
    private let only: Set<String>?

    public init() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? { arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } }
        tier = value("-intentRunnerTier").flatMap(Tier.init(rawValue:)) ?? .premium
        only = value("-intentRunnerScenes").map { Set($0.split(separator: ",").map(String.init)) }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(scenes.filter { only?.contains($0.id) ?? true }) { scene in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(scene.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(NoctisAppColor.ink)
                        ForEach(scene.rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\u{201C}\(row.phrase)\u{201D}")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(NoctisAppColor.ink2)
                                Text(row.spoken)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(NoctisAppColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(([row.policy] + row.did.map { "did: \($0)" }).joined(separator: " · "))
                                    .font(.system(size: 12))
                                    .foregroundStyle(NoctisAppColor.ink2)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NoctisAppColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(NoctisAppColor.bg)
        .accessibilityIdentifier("intentRunner")
        .task { scenes = await IntentRunnerScenes.make(tier: tier) }
    }
}
#endif
