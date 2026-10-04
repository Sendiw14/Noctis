import AppIntents
import Foundation
import NoctisWidgetKit

// "Show my recovery", "Show my sleep", "What time should I sleep" (APP_RULES.md R47): each says a short answer built by the widgets' own
// builders and opens the app on the matching screen through the app's one route path. Recovery and sleep are Health values, so they
// ask for the device to be unlocked before anything is said; the bedtime is the person's plan.

public struct ShowMyRecoveryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show my recovery"
    public static let description = IntentDescription("Says today's recovery and last night's sleep, and opens Recovery.", categoryName: "Sleep")
    public static let supportedModes: IntentModes = .foreground(.immediate)
    /// Health numbers: nothing is said until the device is unlocked.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    public init() {}

    /// What is said, from the widgets' snapshot (a test calls this for every data state).
    @MainActor
    public static func answer(_ runtime: IntentRuntime) -> String {
        let environment = runtime.environment
        return WidgetSpoken.recovery(environment.snapshot(), now: environment.now(), calendar: environment.calendar(), format: environment.format())
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = IntentRuntime.current
        let words = Self.answer(runtime)
        await runtime.host()?.open(.recovery)
        return .result(dialog: IntentDialog(stringLiteral: words))
    }
}

public struct ShowMySleepIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show my sleep"
    public static let description = IntentDescription("Says how long you slept last night, and opens Sleep.", categoryName: "Sleep")
    public static let supportedModes: IntentModes = .foreground(.immediate)
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    public init() {}

    @MainActor
    public static func answer(_ runtime: IntentRuntime) -> String {
        let environment = runtime.environment
        return WidgetSpoken.sleep(environment.snapshot(), now: environment.now(), calendar: environment.calendar(), format: environment.format())
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = IntentRuntime.current
        let words = Self.answer(runtime)
        await runtime.host()?.open(.sleep)
        return .result(dialog: IntentDialog(stringLiteral: words))
    }
}

public struct ShowRecommendedBedtimeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show my recommended bedtime"
    public static let description = IntentDescription("Says the bedtime NOCTIS recommends tonight, and opens Tonight.", categoryName: "Sleep")
    public static let supportedModes: IntentModes = .foreground(.immediate)

    public init() {}

    /// The bedtime only: it is the plan, not a Health value, so it needs no unlock to say.
    @MainActor
    public static func answer(_ runtime: IntentRuntime) -> String {
        let environment = runtime.environment
        return WidgetSpoken.bedtime(environment.snapshot(), format: environment.format())
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = IntentRuntime.current
        let words = Self.answer(runtime)
        await runtime.host()?.open(.bedtime)
        return .result(dialog: IntentDialog(stringLiteral: words))
    }
}
