import DesignSystem
import SwiftUI

// Welcome's four bands (APP_RULES.md R6, R69): the tab colours stacked from the top, the top band in front, each lower one tucked under the curved
// bottom of the one above it. Flat colour only. The numbers are the 402 x 874 design's, scaled.

/// One band: its tab colour, its word and its icon.
struct WelcomeBandSpec: Identifiable {
    enum Icon { case ring, moon, sparkles, sun }

    let id: Int
    let section: NoctisSection
    let word: String
    let icon: Icon
    /// In the 402 x 640 band area of the design.
    let top: CGFloat
    let bottom: CGFloat
    /// The icon's distance from the band's own top (the moon and the sparkles sit 12 pt lower than the design's 54, so they clear the curve of the band above).
    let iconOffset: CGFloat

    static let all: [WelcomeBandSpec] = [
        WelcomeBandSpec(id: 0, section: .home, word: "Better", icon: .ring, top: 0, bottom: 238, iconOffset: 96),
        WelcomeBandSpec(id: 1, section: .sleep, word: "nights.", icon: .moon, top: 184, bottom: 380, iconOffset: 66),
        WelcomeBandSpec(id: 2, section: .recovery, word: "A brighter", icon: .sparkles, top: 318, bottom: 514, iconOffset: 66),
        WelcomeBandSpec(id: 3, section: .insights, word: "you.", icon: .sun, top: 444, bottom: 640, iconOffset: 96),
    ]

    static let designHeight: CGFloat = 640
    static let readout = "Better nights. A brighter you."
}

/// How much of each band's motion has arrived.
struct WelcomeReveal: Equatable {
    var band = [Bool](repeating: false, count: 4)
    var word = [Bool](repeating: false, count: 4)
    var icon = [Bool](repeating: false, count: 4)
    var twinkle = false
    var controls = false

    static let final = WelcomeReveal(band: [true, true, true, true], word: [true, true, true, true], icon: [true, true, true, true], twinkle: true, controls: true)
}

struct WelcomeBands: View {
    /// The band area's height (the screen less the controls) and the width.
    let size: CGSize
    /// The screen's top safe area (the status bar).
    let safeTop: CGFloat
    /// The design's scale: min(width / 402, height / 874).
    let scale: CGFloat
    let reveal: WelcomeReveal

    private var k: CGFloat { size.height / WelcomeBandSpec.designHeight }
    private var margin: CGFloat { 28 * scale }
    private var corner: CGFloat { 48 * scale }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The lowest band first, so the top one is in front.
            ForEach(WelcomeBandSpec.all.reversed()) { spec in band(spec) }
            // Art, like the words: it keeps its size at every Dynamic Type setting.
            Text("NOCTIS")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(NoctisPaper.ink)
                .padding(.leading, margin)
                .padding(.top, max(84 * scale, safeTop + 22))
                .opacity(reveal.word[0] ? 1 : 0)
                .zIndex(10)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WelcomeBandSpec.readout)
        .accessibilityAddTraits(.isHeader)
    }

    private func band(_ spec: WelcomeBandSpec) -> some View {
        let top = spec.top * k
        let height = (spec.bottom - spec.top) * k
        let iconSide = 54 * scale
        // Offsets shrink with the bands when they are squeezed (an SE), so an icon never reaches the band above's edge.
        let iconY = spec.iconOffset * min(scale, k)
        return ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(bottomLeadingRadius: corner, bottomTrailingRadius: corner, style: .continuous)
                .fill(spec.section.fill)
            Text(spec.word)
                .font(.system(size: 70 * scale, weight: .heavy, design: .rounded))
                .tracking(-3 * scale)
                .foregroundStyle(NoctisPaper.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, margin)
                .padding(.bottom, 24 * scale)
                .frame(width: size.width, height: height, alignment: .bottomLeading)
                .opacity(reveal.word[spec.id] ? 1 : 0)
            WelcomeIcon(kind: spec.icon, side: iconSide, shown: reveal.icon[spec.id], twinkle: reveal.twinkle)
                .frame(width: iconSide, height: iconSide)
                .padding(.top, iconY)
                .padding(.leading, size.width - margin - iconSide)
        }
        .frame(width: size.width, height: height, alignment: .topLeading)
        .offset(y: top + (reveal.band[spec.id] ? 0 : -(top + height + 24)))
        .zIndex(Double(4 - spec.id))
    }
}

// MARK: - Icons

nonisolated struct CrescentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let outer = Path(ellipseIn: rect)
        let bite = Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.26, y: rect.minY - rect.height * 0.04, width: rect.width * 0.86, height: rect.height * 0.86))
        return outer.subtracting(bite)
    }
}

nonisolated struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let pinch = rect.width * 0.09
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
        p.addQuadCurve(to: CGPoint(x: c.x, y: rect.maxY), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
        p.addQuadCurve(to: CGPoint(x: c.x, y: rect.minY), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
        p.closeSubpath()
        return p
    }
}

private struct WelcomeIcon: View {
    let kind: WelcomeBandSpec.Icon
    let side: CGFloat
    let shown: Bool
    let twinkle: Bool

    var body: some View {
        switch kind {
        case .ring: ring
        case .moon:
            CrescentShape().fill(NoctisPaper.ivory)
                .rotationEffect(.degrees(shown ? 0 : 10))
                .opacity(shown ? 1 : 0)
        case .sparkles: sparkles
        case .sun: sun
        }
    }

    /// The app's own segmented ring, in its own arc colours, drawn clockwise.
    private var ring: some View {
        let segments = [
            NoctisRingSegment(color: NoctisPaper.sage, weight: 1, fraction: 1),
            NoctisRingSegment(color: NoctisPaper.lavender, weight: 1, fraction: 1),
            NoctisRingSegment(color: NoctisPaper.orange, weight: 1, fraction: 1),
            NoctisRingSegment(color: NoctisPaper.butter, weight: 1, fraction: 1),
        ]
        return NoctisRingLayout(maxDiameter: side) {
            NoctisRecoveryRing(segments: segments, reveal: shown ? 1 : 0, highlight: nil, dim: 0, showsUsual: false, diameter: side, lineWidth: 22 * side / 260 * 2.2)
        }
    }

    private var sparkles: some View {
        ZStack {
            SparkleShape().fill(NoctisPaper.ivory).frame(width: side * 0.62, height: side * 0.62).position(x: side * 0.38, y: side * 0.62)
            SparkleShape().fill(NoctisPaper.ivory).frame(width: side * 0.30, height: side * 0.30).position(x: side * 0.80, y: side * 0.20)
            SparkleShape().fill(NoctisPaper.ivory).frame(width: side * 0.24, height: side * 0.24).position(x: side * 0.86, y: side * 0.66)
        }
        .scaleEffect(shown ? 1 : 0.6)
        .opacity(shown ? (twinkle ? 1 : 0.6) : 0)
    }

    private var sun: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule().fill(NoctisPaper.orange)
                    .frame(width: max(side * 0.055, 2.5), height: side * 0.15)
                    .offset(y: -side * 0.40)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            .rotationEffect(.degrees(shown ? 45 : 0))
            Circle().fill(NoctisPaper.orange).frame(width: side * 0.46, height: side * 0.46)
        }
        .opacity(shown ? 1 : 0)
    }
}
