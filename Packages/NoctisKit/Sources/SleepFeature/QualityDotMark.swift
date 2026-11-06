import DesignSystem
import NoctisCore
import SwiftUI

/// A night's mark on the sleep quality strip and in its legend. By default every band is a round dot and only the colour tells them apart; with "Differentiate
/// Without Color" on (S1B accessibility, R-14) the band is also its shape: a circle from 80, a square from 60, a diamond under 60. The mark is always `size`
/// square, so turning the setting on moves nothing.
struct QualityDotMark: View {
    let band: QualityDotRender.Band
    let size: CGFloat
    /// `showsShapes` fixes the answer (tests, previews); nil follows the setting.
    var showsShapes: Bool?
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemSetting

    var body: some View {
        let shapes = showsShapes ?? systemSetting
        return Group {
            switch shapes ? band : .high {
            case .high: mark(Circle(), scale: 1)
            case .middle: mark(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous), scale: 0.86)
            case .low: mark(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous), scale: 0.66).rotationEffect(.degrees(45))
            }
        }
        .frame(width: size, height: size)
    }

    private func mark<S: InsettableShape>(_ shape: S, scale: CGFloat) -> some View {
        shape
            .fill(band.tint)
            .overlay(shape.strokeBorder(NoctisAppColor.ink.opacity(0.22), lineWidth: 0.5))
            .frame(width: size * scale, height: size * scale)
    }
}
