import CoreTransferable
import DesignSystem
import NoctisCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share today" / "Share this night": a preview of the 1080×1350 card,
/// "Include details" (off by default; HRV and resting heart rate appear
/// only when it's on), and a `ShareLink`. Nothing leaves the app unless
/// the person taps Share.
struct SharePreviewSheet: View {
    let content: ShareCardContent

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var includeDetails = false
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NoctisSpacing.lg) {
                    preview
                    if content.details != nil {
                        Toggle(isOn: $includeDetails) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Include details")
                                    .noctisFont(17, .semibold, relativeTo: .body)
                                    .foregroundStyle(NoctisAppColor.ink)
                                Text("Adds HRV and resting heart rate.")
                                    .noctisFont(13, relativeTo: .footnote)
                                    .foregroundStyle(.noctisInk3)
                            }
                        }
                        .tint(NoctisAppColor.sage)
                        .padding(NoctisSpacing.lg)
                        .background(NoctisAppColor.surface, in: RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
                        .noctisContrastBorder()
                    }
                    shareButton
                }
                .frame(maxWidth: HomeContent.compactMaxWidth)
                .padding(.horizontal, NoctisSpacing.lg)
                .padding(.bottom, NoctisSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .background { PaperBackground(adaptive: true).ignoresSafeArea() }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .task(id: includeDetails) { render() }
        .onChange(of: colorScheme) { render() }
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(ShareCardView.size.width / ShareCardView.size.height, contentMode: .fit)
                .frame(maxWidth: 360)
                .clipShape(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous)
                        .strokeBorder(NoctisAppColor.hairline, lineWidth: 1)
                )
                .accessibilityLabel("Share card preview")
                .accessibilityIdentifier("home.share.preview")
        } else {
            RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous)
                .fill(NoctisAppColor.track)
                .aspectRatio(ShareCardView.size.width / ShareCardView.size.height, contentMode: .fit)
                .frame(maxWidth: 360)
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let image, let png = image.pngData() {
            ShareLink(
                item: NoctisShareImage(png: png, fileName: content.fileName),
                preview: SharePreview(content.title, image: Image(uiImage: image))
            ) {
                HStack(spacing: 6) {
                    Text("Share")
                        .noctisFont(17, .semibold, relativeTo: .body)
                    Image(systemName: "square.and.arrow.up")
                        .noctisIcon(15)
                }
                .foregroundStyle(NoctisAppColor.ctaLabel)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(NoctisAppColor.ctaFill, in: Capsule(style: .continuous))
            }
            .buttonStyle(NoctisCardButtonStyle())
        }
    }

    private func render() {
        image = ShareCardRenderer.render(content, includeDetails: includeDetails, colorScheme: colorScheme)
    }
}

/// The shared image, as PNG data with a dated file name.
struct NoctisShareImage: Transferable {
    let png: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { $0.fileName + ".png" }
    }
}

/// Renders `ShareCardView` at 1080×1350 (360×450pt at 3×).
enum ShareCardRenderer {
    static let scale: CGFloat = 3

    static func render(_ content: ShareCardContent, includeDetails: Bool, colorScheme: ColorScheme) -> UIImage? {
        let card = ShareCardView(content: content, includeDetails: includeDetails)
            .environment(\.colorScheme, colorScheme)
            // A fixed type size: the card is an image, the same for everyone.
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(ShareCardView.size)
        return renderer.uiImage
    }
}

/// The share card: paper and grain, the ring and score, last night's
/// length and chart, the date, and a small NOCTIS wordmark. HRV and
/// resting heart rate only with "Include details".
struct ShareCardView: View {
    let content: ShareCardContent
    let includeDetails: Bool

    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                NoctisCaption(content.date.uppercased(), style: NoctisAppColor.ink3)
                Spacer(minLength: NoctisSpacing.xs)
                Text("NOCTIS")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(NoctisAppColor.ink)
            }
            if let recovery = content.recovery {
                HStack(spacing: NoctisSpacing.lg) {
                    NoctisRingLayout(maxDiameter: 112) {
                        NoctisRecoveryRing(
                            segments: recovery.segments.map(\.ringSegment),
                            diameter: 112,
                            lineWidth: 11
                        )
                        Text("\(recovery.score)")
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(NoctisAppColor.ink)
                    }
                    .frame(width: 112)
                    VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                        Text("Recovery")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(NoctisAppColor.ink)
                        if let lastNight = content.lastNight {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("Last night")
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundStyle(NoctisAppColor.ink2)
                                NoctisMetric(lastNight, size: 17, relativeTo: .body)
                            }
                        }
                    }
                }
            } else if let lastNight = content.lastNight {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Last night")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(NoctisAppColor.ink)
                    NoctisMetric(lastNight, size: 34)
                }
            }
            if let chart = content.chart(includeDetails: includeDetails) {
                // The night panel's chart, lanes a little shorter to fit.
                NightChartView(chart: chart, laneHeightOverride: 20)
                    .padding(NoctisSpacing.md)
                    .background(NoctisAppColor.nightPanel, in: RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
            }
            Spacer(minLength: 0)
            if includeDetails, let details = content.details {
                Text(details)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(NoctisAppColor.ink2)
            }
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(PaperBackground(adaptive: true))
    }
}
