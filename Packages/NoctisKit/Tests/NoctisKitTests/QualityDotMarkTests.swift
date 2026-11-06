import NoctisCore
import SwiftUI
import Testing
import UIKit

@testable import SleepFeature

// Differentiate Without Color on the sleep quality strip (S1B accessibility, R-14): off, the three bands are the same round dot in three colours; on, each band is
// also a shape, in the same square, in the same colour.

@MainActor
struct QualityDotMarkTests {
    private static let bands: [QualityDotRender.Band] = [.high, .middle, .low]

    private func render(_ band: QualityDotRender.Band, shapes: Bool) throws -> UIImage {
        let content = QualityDotMark(band: band, size: 40, showsShapes: shapes).padding(4).background(Color.white)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return try #require(renderer.uiImage)
    }

    /// The pixels that are not white: the mark's silhouette.
    private func mask(_ image: UIImage) throws -> [Bool] {
        let cg = try #require(image.cgImage)
        let data = try #require(cg.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let step = cg.bitsPerPixel / 8
        var out: [Bool] = []
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let o = y * cg.bytesPerRow + x * step
                out.append(bytes[o] < 235 || bytes[o + 1] < 235 || bytes[o + 2] < 235)
            }
        }
        return out
    }

    private func centre(_ image: UIImage) throws -> [UInt8] {
        let cg = try #require(image.cgImage)
        let data = try #require(cg.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let step = cg.bitsPerPixel / 8
        let o = (cg.height / 2) * cg.bytesPerRow + (cg.width / 2) * step
        return [bytes[o], bytes[o + 1], bytes[o + 2]]
    }

    private func differing(_ a: [Bool], _ b: [Bool]) -> Int { zip(a, b).filter { $0 != $1 }.count }

    @Test func offTheThreeBandsAreTheSameRoundDot() throws {
        let masks = try Self.bands.map { try mask(render($0, shapes: false)) }
        #expect(differing(masks[0], masks[1]) == 0)
        #expect(differing(masks[0], masks[2]) == 0)
    }

    @Test func onEachBandIsItsOwnShape() throws {
        let masks = try Self.bands.map { try mask(render($0, shapes: true)) }
        #expect(differing(masks[0], masks[1]) > 60, "circle against square")
        #expect(differing(masks[0], masks[2]) > 200, "circle against diamond")
        #expect(differing(masks[1], masks[2]) > 200, "square against diamond")
    }

    @Test func onTheMarkKeepsItsSizeAndItsColor() throws {
        for band in Self.bands {
            let off = try render(band, shapes: false), on = try render(band, shapes: true)
            #expect(off.size == on.size, "\(band): nothing moves")
            #expect(try centre(off) == centre(on), "\(band): the same colour")
        }
    }

    @Test func theThreeColorsStillDifferFromEachOther() throws {
        let centres = try Self.bands.map { try centre(render($0, shapes: true)) }
        #expect(Set(centres).count == 3)
    }
}
