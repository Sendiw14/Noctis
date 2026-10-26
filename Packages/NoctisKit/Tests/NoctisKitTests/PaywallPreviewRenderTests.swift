import SwiftUI
import Testing

@testable import OnboardingFeature

/// QA only: renders Paywall's DEBUG plan-card preview (the loaded state,
/// which StoreKit can't produce in automation) at each QA device width, at
/// default text size and AX3. Runs only when `QA_OUT` is set.
@MainActor
struct PaywallPreviewRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["QA_OUT"] != nil))
    func renderLoadedPlanCards() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QA_OUT"]!)
            .appendingPathComponent("paywall-loaded-preview", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let widths: [(name: String, width: CGFloat, height: CGFloat)] = [
            ("SE", 375, 667), ("Pro", 402, 874), ("ProMax", 440, 956),
        ]
        let sizes: [(name: String, size: DynamicTypeSize)] = [("default", .large), ("AX3", .accessibility3)]
        for device in widths {
            for size in sizes {
                for selected in [PlanCardPreviewHarness.yearlyID, PlanCardPreviewHarness.monthlyID] {
                    let view = PlanCardPreviewHarness(selectedID: selected)
                        .environment(\.dynamicTypeSize, size.size)
                        .frame(width: device.width, height: device.height)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 3
                    let image = try #require(renderer.uiImage)
                    let data = try #require(image.pngData())
                    try data.write(to: out.appendingPathComponent("\(device.name)-\(size.name)-\(selected)-selected.png"))
                }
            }
        }
    }
}
