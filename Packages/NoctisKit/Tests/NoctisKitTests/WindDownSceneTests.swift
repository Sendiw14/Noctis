import Foundation
import Testing

@testable import NightFeature
@testable import NightKit

// The wind-down's sky (APP_RULES.md R32): where the stars may be, so none sits behind the words.

struct WindDownSceneTests {
    @Test func thereAreTwentyFourStarsAndTheFirstTwelveComeFirst() {
        #expect(WindDownScene.stars.count == WindDownVisuals.starsAtEnd)
        #expect(WindDownVisuals.starsAtStart == 12)
    }

    @Test func everyStarIsInAStripNoWordsReach() {
        for star in WindDownScene.stars {
            let inAStrip = WindDownScene.skyBands.contains { $0.range.contains(star.y) }
            #expect(inAStrip, Comment(rawValue: "a star at y \(star.y) is outside every strip"))
            #expect((0.04...0.96).contains(star.x))
        }
    }

    @Test func theStripsAvoidTheHeaderAndTheControls() {
        // The header sits between 0.09 and 0.19 of the height, the first control row from 0.40 on,
        // and the hills start at 0.70: the strips must stay clear of all three.
        for band in WindDownScene.skyBands {
            let clearOfHeader = band.range.upperBound <= 0.095 || band.range.lowerBound >= 0.19
            let clearOfControls = band.range.upperBound <= 0.38 || (band.range.lowerBound >= 0.60 && band.range.upperBound <= 0.70)
            #expect(clearOfHeader)
            #expect(clearOfControls)
        }
        let weight = WindDownScene.skyBands.reduce(0) { $0 + $1.weight }
        #expect(abs(weight - 1) < 1e-9)
    }

    @Test func starsAreSpreadAcrossTheStrips() {
        // The first twelve alone, the ones seen at the start, still fill more than one strip.
        let first = WindDownScene.stars.prefix(WindDownVisuals.starsAtStart)
        let strips = Set(first.compactMap { star in WindDownScene.skyBands.firstIndex { $0.range.contains(star.y) } })
        #expect(strips.count >= 2)
    }
}
