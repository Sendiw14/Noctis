import OSLog

public enum NoctisAnalyticsEvent: String {
    case paywallViewed = "paywall_viewed"
    case planSelected = "plan_selected"
    case trialStarted = "trial_started"
    case purchaseCompleted = "purchase_completed"
    case paywallDismissed = "paywall_dismissed"
    case onboardingCompleted = "onboarding_completed"
}

/// A minimal, real logging sink (Apple's unified logging, inspectable in
/// Console.app/Xcode) rather than a fabricated call to a network analytics
/// SDK this project doesn't have. Callers must never pass health/biometric
/// values as parameters — only identifiers, plan choices and flags.
public enum NoctisAnalytics {
    private static let logger = Logger(subsystem: "com.noctis.app", category: "analytics")

    public static func log(_ event: NoctisAnalyticsEvent, parameters: [String: String] = [:]) {
        guard !parameters.isEmpty else {
            logger.log("\(event.rawValue, privacy: .public)")
            return
        }
        let paramString = parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        logger.log("\(event.rawValue, privacy: .public) { \(paramString, privacy: .public) }")
    }
}
