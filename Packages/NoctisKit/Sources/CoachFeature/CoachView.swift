import DesignSystem
import NoctisCore
import SwiftUI

public struct CoachView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                NoctisStateView(
                    systemImage: "sparkles",
                    title: "AI Coach isn't available yet.",
                    message: "NOCTIS explains your sleep and recovery with deterministic, on-device calculations today. A safety-reviewed AI Coach — built to explain, never to diagnose — arrives in a later update."
                )
                Spacer(minLength: 0)
            }
            .padding(NoctisSpacing.xl)
            .background(NoctisColor.canvas)
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
