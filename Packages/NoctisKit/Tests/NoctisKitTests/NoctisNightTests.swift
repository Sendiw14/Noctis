import SwiftUI
import Testing

@testable import DesignSystem

/// The night's tokens (APP_RULES.md R32): ink that reads on the sky at both ends, an accent that
/// shows, and hills that can be told from the sky.
struct NoctisNightTests {
    private func ratio(_ a: String, _ b: String) -> Double {
        noctisContrastRatio(noctisHexColor(a), noctisHexColor(b))
    }

    @Test(arguments: [NoctisNight.nightHex, NoctisNight.deepHex])
    func ivoryAndTheQuieterIvoryReadOnTheSky(sky: String) {
        #expect(ratio(NoctisNight.ivoryHex, sky) >= 7, Comment(rawValue: "ivory on \(sky): \(ratio(NoctisNight.ivoryHex, sky))"))
        #expect(ratio(NoctisNight.ivory2Hex, sky) >= 4.5, Comment(rawValue: "ivory2 on \(sky): \(ratio(NoctisNight.ivory2Hex, sky))"))
    }

    @Test(arguments: [NoctisNight.nightHex, NoctisNight.deepHex])
    func theLavenderAccentShowsOnTheSky(sky: String) {
        #expect(ratio(NoctisNight.lavenderHex, sky) >= 4.5, Comment(rawValue: "lavender on \(sky): \(ratio(NoctisNight.lavenderHex, sky))"))
    }

    @Test func theMoonIsIvory() {
        #expect(NoctisNight.moonHexMatchesIvory)
    }

    @Test func theNightIsDarkerThanTheHillsAndTheDeepDarkerStill() {
        func luminance(_ hex: String) -> Double { ratio(hex, "000000") }
        #expect(luminance(NoctisNight.deepHex) < luminance(NoctisNight.nightHex))
        #expect(luminance(NoctisNight.nightHex) < luminance(NoctisNight.hillBackHex))
        #expect(luminance(NoctisNight.hillBackHex) < luminance(NoctisNight.hillFrontHex))
    }

    @Test func theHillsCanBeToldFromTheSkyAtBothEnds() {
        for sky in [NoctisNight.nightHex, NoctisNight.deepHex] {
            #expect(ratio(NoctisNight.hillBackHex, sky) >= 1.05, Comment(rawValue: "back hill on \(sky)"))
            #expect(ratio(NoctisNight.hillFrontHex, NoctisNight.hillBackHex) >= 1.05)
        }
    }

    @Test func theSkyMovesFromTheNightToTheDeepInOneFlatColor() {
        let start = noctisHexComponents(NoctisNight.nightHex), end = noctisHexComponents(NoctisNight.deepHex)
        let resolve = { (t: Double) in NoctisNight.sky(t).resolve(in: EnvironmentValues()) }
        #expect(abs(Double(resolve(0).red) - start.0) < 0.01 && abs(Double(resolve(1).red) - end.0) < 0.01)
        let mid = resolve(0.5)
        #expect(abs(Double(mid.red) - (start.0 + end.0) / 2) < 0.01 && abs(Double(mid.blue) - (start.2 + end.2) / 2) < 0.01)
        #expect(abs(Double(resolve(-1).red) - start.0) < 0.01 && abs(Double(resolve(7).red) - end.0) < 0.01)
    }
}

extension NoctisNight {
    /// The moon is the ivory, not a color of its own.
    static var moonHexMatchesIvory: Bool { ivoryHex == "F4EDE3" && moon == ivory }
}
