import DesignSystem
import NoctisCore
import SwiftUI

/// The paywall, for someone already in the app (Settings' "Upgrade"): the same screen onboarding ends with, over the
/// page that opened it. It follows the app's Light or Dark. `onFinished` is called when it closes,
/// subscribed or not.
public struct UpgradePaywall: View {
    private let wakeMinutes: Int
    private let needMinutes: Int
    private let onFinished: () -> Void
    private let context: PaywallContext?

    /// `context`: why it was opened, said in a line above the title (R58).
    public init(wakeMinutes: Int, needMinutes: Int, context: PaywallContext? = nil, onFinished: @escaping () -> Void) {
        self.wakeMinutes = wakeMinutes
        self.needMinutes = needMinutes
        self.context = context
        self.onFinished = onFinished
    }

    public var body: some View {
        PaywallScreen(wakeMinutes: wakeMinutes, needMinutes: needMinutes, onFinished: onFinished, context: context)
    }
}
