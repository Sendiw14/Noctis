import SwiftUI
import Testing
@testable import DesignSystem

/// APP_RULES.md R5 contrast floors, checked in both Light and Dark.
struct NoctisAppContrastTests {
    nonisolated static let modes: [(String, NoctisAppPalette)] = [("light", .light), ("dark", .dark)]

    private func ratio(_ a: String, _ b: String) -> Double {
        noctisContrastRatio(noctisHexColor(a), noctisHexColor(b))
    }

    @Test(arguments: modes)
    func inkTonesClearBodyContrastOnBackground(_ mode: String, _ palette: NoctisAppPalette) {
        for (name, ink) in [("ink", palette.ink), ("ink2", palette.ink2), ("ink3", palette.ink3)] {
            let value = ratio(ink, palette.bg)
            #expect(value >= 4.5, "\(mode): \(name) on bg contrast \(value) < 4.5:1")
        }
    }

    @Test(arguments: modes)
    func orangeTextClearsDisplayContrastOnBackground(_ mode: String, _ palette: NoctisAppPalette) {
        let value = ratio(palette.orangeText, palette.bg)
        #expect(value >= 3.0, "\(mode): orangeText on bg contrast \(value) < 3:1 (display)")
    }

    @Test(arguments: modes)
    func ctaLabelClearsBodyContrastOnCTAFill(_ mode: String, _ palette: NoctisAppPalette) {
        let value = ratio(palette.ctaLabel, palette.ctaFill)
        #expect(value >= 4.5, "\(mode): CTA label on CTA fill contrast \(value) < 4.5:1")
    }

    @Test(arguments: modes)
    func glyphsOnFillsClearBodyContrast(_ mode: String, _ palette: NoctisAppPalette) {
        for (name, fill) in [("sage", palette.sage), ("orange", palette.orange), ("butter", palette.butter), ("lavender", palette.lavender)] {
            let value = ratio(palette.onFill, fill)
            #expect(value >= 4.5, "\(mode): onFill on \(name) contrast \(value) < 4.5:1")
        }
    }

    /// Cocoa marks the Deep stage and last night's bar: a graphic, so 3:1
    /// against the card surface and the track it sits on.
    @Test(arguments: modes)
    func cocoaStandsOutOnCardsAndTracks(_ mode: String, _ palette: NoctisAppPalette) {
        #expect(ratio(palette.cocoa, palette.surface) >= 3, "\(mode): cocoa on surface")
        #expect(ratio(palette.cocoa, palette.track) >= 3, "\(mode): cocoa on track")
    }

    @Test func lightPaletteIsExactlyTheNoctisPaperTokens() {
        let light = NoctisAppPalette.light
        let pairs: [(String, Color)] = [
            (light.bg, NoctisPaper.bg), (light.surface, NoctisPaper.surface),
            (light.hairline, NoctisPaper.hairline), (light.track, NoctisPaper.track),
            (light.ink, NoctisPaper.ink), (light.ink2, NoctisPaper.ink2),
            (light.ink3, NoctisPaper.ink3), (light.orangeText, NoctisPaper.orangeText),
            (light.sage, NoctisPaper.sage), (light.orange, NoctisPaper.orange),
            (light.butter, NoctisPaper.butter), (light.lavender, NoctisPaper.lavender),
            (light.cocoa, NoctisPaper.cocoa), (light.ctaFill, NoctisPaper.cocoa),
            (light.ctaLabel, NoctisPaper.ivory),
        ]
        for (hex, token) in pairs {
            #expect(noctisContrastRatio(noctisHexColor(hex), token) == 1, "\(hex) differs from its NoctisPaper token")
        }
    }
}
