import DesignSystem
import NoctisCore
import SwiftUI

/// "Health data settings": the way from a screen with no Health data to Settings, Health data, where the page says
/// what NOCTIS can find and how to change what it can read. It sits beside the state's own action (Connect Apple
/// Health, Open Health) on Home, Sleep, Recovery, Insights and Coach.
public struct HealthDataSettingsLink: View {
    /// Optional: a screen drawn on its own (a preview, a render in a test) has no app model, and then the link does nothing.
    @Environment(AppModel.self) private var model: AppModel?

    public init() {}

    public var body: some View {
        NoctisTextButton("Health data settings", adaptive: true) {
            model?.open(.settings(section: .healthData))
        }
        .accessibilityHint("Opens Settings, Health data.")
        .accessibilityIdentifier("state.healthDataSettings")
    }
}
