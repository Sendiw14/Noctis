import DesignSystem
import SwiftUI

/// The paywall, for someone already in the app (Settings' "Upgrade"): the same screen onboarding ends with, over the
/// page that opened it. It is the light paper like the rest of onboarding. `onFinished` is called when it closes,
/// subscribed or not.
public struct UpgradePaywall: View {
    private let wakeMinutes: Int
    private let needMinutes: Int
    private let onFinished: () -> Void

    public init(wakeMinutes: Int, needMinutes: Int, onFinished: @escaping () -> Void) {
        self.wakeMinutes = wakeMinutes
        self.needMinutes = needMinutes
        self.onFinished = onFinished
    }

    public var body: some View {
        PaywallScreen(wakeMinutes: wakeMinutes, needMinutes: needMinutes, onFinished: onFinished)
            .preferredColorScheme(.light)
    }
}
