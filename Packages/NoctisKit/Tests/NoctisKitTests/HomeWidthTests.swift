import Foundation
import SwiftUI
import Testing
@testable import DesignSystem
@testable import HealthProviding
@testable import HomeFeature
@testable import NoctisCore

/// R21: Home at 320, 390, 440, 700 and 1000pt, rendered off-screen with
/// the full mock. Images go to `NOCTIS_RENDER_OUT` when it's set (pass it
/// as `TEST_RUNNER_NOCTIS_RENDER_OUT`).
struct HomeWidthTests {
    static let compactWidths: [CGFloat] = [320, 390, 440]
    static let regularWidths: [CGFloat] = [700, 1000]

    private func viewModel(_ scenario: MockScenario = .full) async -> HomeViewModel {
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let model = HomeViewModel(
            repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }),
            profile: { UserProfileSnapshot() },
            introGate: HomeIntroGate(defaults: UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard),
            reduceMotion: { true },
            clock: { now },
            calendar: Fixture.calendar(),
            locale: Locale(identifier: "en_US")
        )
        await model.refresh()
        return model
    }

    private func render(
        _ model: HomeViewModel,
        width: CGFloat,
        sizeClass: UserInterfaceSizeClass,
        name: String? = nil,
        typeSize: DynamicTypeSize = .large,
        weight: LegibilityWeight = .regular
    ) -> CGSize? {
        let renderer = ImageRenderer(content: HomeRenderHarness(viewModel: model)
            .environment(\.horizontalSizeClass, sizeClass)
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.legibilityWeight, weight)
            .frame(width: width))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        if let name, let directory = ProcessInfo.processInfo.environment["NOCTIS_RENDER_OUT"] {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? image.pngData()?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        return image.size
    }

    @Test func everyWidthLaysOutAtExactlyThatWidth() async throws {
        let model = await viewModel()
        for width in Self.compactWidths {
            let size = try #require(render(model, width: width, sizeClass: .compact, name: "home-\(Int(width))-compact"))
            #expect(size.width == width)
        }
        for width in Self.regularWidths {
            let size = try #require(render(model, width: width, sizeClass: .regular, name: "home-\(Int(width))-regular"))
            #expect(size.width == width)
        }
    }

    @Test func regularWidthUsesTwoColumns() async throws {
        let model = await viewModel()
        for width in Self.regularWidths {
            let twoColumns = try #require(render(model, width: width, sizeClass: .regular))
            let oneColumn = try #require(render(model, width: width, sizeClass: .compact))
            // Side by side, the same cards stack far less tall.
            #expect(twoColumns.height < oneColumn.height * 0.75, "\(width): \(twoColumns.height) vs \(oneColumn.height)")
        }
    }

    @Test func theSingleColumnStopsAt680Points() async throws {
        let model = await viewModel()
        // Both are wider than 680 + margins, so the column is identical.
        let at800 = try #require(render(model, width: 800, sizeClass: .compact))
        let at1000 = try #require(render(model, width: 1000, sizeClass: .compact, name: "home-1000-compact"))
        #expect(at800.height == at1000.height)
        // Narrower than the cap, the column fills the width and grows taller.
        let at320 = try #require(render(model, width: 320, sizeClass: .compact))
        #expect(at320.height > at1000.height)
    }

    @Test func emptyStatesAdaptToo() async throws {
        let model = await viewModel(.empty)
        let size = try #require(render(model, width: 1000, sizeClass: .regular, name: "home-1000-regular-empty"))
        #expect(size.width == 1000)
    }

    // MARK: - Dynamic Type and Bold Text

    /// Every Dynamic Type size, regular and bold, at 390pt: Home lays out
    /// at exactly that width and only grows taller as text grows.
    @Test func everyTextSizeAndBoldTextLayOut() async throws {
        let model = await viewModel()
        var previous: CGFloat = 0
        for size in DynamicTypeSize.allCases {
            for weight in [LegibilityWeight.regular, .bold] {
                let name = "type-\(String(describing: size))-\(weight == .bold ? "bold" : "regular")"
                let rendered = try #require(render(model, width: 390, sizeClass: .compact, name: name, typeSize: size, weight: weight))
                #expect(rendered.width == 390, "\(name)")
                if weight == .regular {
                    #expect(rendered.height >= previous, "\(name) should be at least as tall as the size before it")
                    previous = rendered.height
                }
            }
        }
    }

    // MARK: - Rings

    @Test func ringsTakeTheOfferedWidthUpToTheirSize() {
        #expect(NoctisRingLayout.diameter(forWidth: 150, maxDiameter: 200) == 150)
        #expect(NoctisRingLayout.diameter(forWidth: 200, maxDiameter: 200) == 200)
        #expect(NoctisRingLayout.diameter(forWidth: 480, maxDiameter: 200) == 200)
        #expect(NoctisRingLayout.diameter(forWidth: nil, maxDiameter: 200) == 200)
        #expect(NoctisRingLayout.diameter(forWidth: .infinity, maxDiameter: 200) == 200)
    }

    @Test func aRingInANarrowSpaceDrawsSmaller() throws {
        let ring = NoctisRingLayout(maxDiameter: 200) {
            NoctisRecoveryRing(segments: [NoctisRingSegment(color: NoctisAppColor.sage, weight: 1, fraction: 0.8)])
            Text("80")
        }
        let narrow = try #require(ImageRenderer(content: ring.frame(width: 120)).uiImage)
        #expect(narrow.size == CGSize(width: 120, height: 120))
        let wide = try #require(ImageRenderer(content: ring.frame(width: 400)).uiImage)
        #expect(wide.size.height == 200)
    }
}

/// `HomeContent` outside its scroll view, with the namespace its zoom
/// source needs, and the width and margins the tab scaffold gives it.
private struct HomeRenderHarness: View {
    let viewModel: HomeViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var zoom

    var body: some View {
        HomeContent(viewModel: viewModel, zoomNamespace: zoom, actions: HomeActions())
            .frame(maxWidth: sizeClass == .regular ? HomeContent.regularMaxWidth : HomeContent.compactMaxWidth)
            .padding(.horizontal, NoctisSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(NoctisAppColor.bg)
    }
}
