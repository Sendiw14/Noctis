import CoreTransferable
import DesignSystem
import HomeFeature
import NoctisCore
import ReviewKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Sharing a review (APP_RULES.md R63): a preview of the 1080x1350 card, made from the cover and the sleep page as they are on screen, in the Home share card's style (paper,
// grain, the wordmark). "Include details" is off by default: HRV, resting heart rate and recovery appear only when it is on. Nothing leaves the app unless the person taps
// Share, and nothing about what was shared is recorded anywhere.

struct ReviewSharePreviewSheet: View {
    let content: ReviewShareContent

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
                        NoctisAppCard {
                            Toggle(isOn: $includeDetails) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Include details")
                                        .noctisFont(17, .semibold, relativeTo: .body)
                                        .foregroundStyle(NoctisAppColor.ink)
                                    Text("Adds recovery, HRV and resting heart rate.")
                                        .noctisFont(13, relativeTo: .footnote)
                                        .foregroundStyle(.noctisInk3)
                                }
                            }
                            .tint(NoctisAppColor.sage)
                            .accessibilityIdentifier("review.share.details")
                        }
                    }
                    shareButton
                }
                .frame(maxWidth: 560)
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
                .aspectRatio(ReviewShareCardView.size.width / ReviewShareCardView.size.height, contentMode: .fit)
                .frame(maxWidth: 360)
                .clipShape(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
                // A picture of a card is a picture: Smart Invert leaves it as it was drawn (S1B-A03).
                .accessibilityIgnoresInvertColors()
                .accessibilityLabel("Share card preview")
                .accessibilityIdentifier("review.share.preview")
        } else {
            RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous)
                .fill(NoctisAppColor.track)
                .aspectRatio(ReviewShareCardView.size.width / ReviewShareCardView.size.height, contentMode: .fit)
                .frame(maxWidth: 360)
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let image, let png = image.pngData() {
            ShareLink(
                item: NoctisShareImage(png: png, fileName: content.fileName),
                preview: SharePreview("\(content.title), \(content.dateRange)", image: Image(uiImage: image))
            ) {
                HStack(spacing: 6) {
                    Text("Share").noctisFont(17, .semibold, relativeTo: .body)
                    Image(systemName: "square.and.arrow.up").noctisIcon(15)
                }
                .foregroundStyle(NoctisAppColor.ctaLabel)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(NoctisAppColor.ctaFill, in: Capsule(style: .continuous))
            }
            .buttonStyle(NoctisCardButtonStyle())
            .accessibilityIdentifier("review.share.send")
        }
    }

    private func render() {
        image = ReviewShareRenderer.render(content, includeDetails: includeDetails, colorScheme: colorScheme)
    }
}

/// The shared image as PNG data with a dated file name (the Home share card's own, `NoctisShareImage`, is internal to Home: this one is the same).
struct NoctisShareImage: Transferable {
    let png: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { $0.fileName + ".png" }
    }
}

/// Renders `ReviewShareCardView` at 1080x1350 (360x450pt at 3x), at a fixed type size: the card is an image, the same for everyone.
enum ReviewShareRenderer {
    static let scale: CGFloat = 3

    static func render(_ content: ReviewShareContent, includeDetails: Bool, colorScheme: ColorScheme) -> UIImage? {
        let card = ReviewShareCardView(content: content, includeDetails: includeDetails)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(ReviewShareCardView.size)
        return renderer.uiImage
    }
}

/// The share card: paper and grain, the date and the wordmark, the average night and how it compares, the week's bars (where the sleep page is shown), and, only with
/// "Include details", the heart numbers.
struct ReviewShareCardView: View {
    let content: ReviewShareContent
    let includeDetails: Bool

    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                NoctisCaption(content.dateRange.uppercased(), style: NoctisAppColor.ink3)
                Spacer(minLength: NoctisSpacing.xs)
                Text("NOCTIS")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(NoctisAppColor.ink)
            }
            Text(content.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(NoctisAppColor.ink)
            NoctisMetric(HomeFormat.durationMetric(content.cover.averageMinutes), size: 56, relativeTo: .largeTitle)
            Text("average a night")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(NoctisAppColor.ink2)
            HStack(spacing: 6) {
                if let arrow = content.cover.deltaArrow { ReviewArrowGlyph(arrow: arrow, size: 15) }
                Text(content.cover.deltaText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(NoctisAppColor.ink)
            if let bars = content.bars {
                // The same chart as the sleep page, on the paper's own card, with no motion.
                ReviewBarsChart(page: bars, revealed: true, compact: true)
                    .padding(NoctisSpacing.md)
                    .background(NoctisAppColor.surface, in: RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
            }
            Spacer(minLength: 0)
            if let details = content.detailsText(includeDetails: includeDetails) {
                Text(details)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(NoctisAppColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(PaperBackground(adaptive: true))
    }
}
