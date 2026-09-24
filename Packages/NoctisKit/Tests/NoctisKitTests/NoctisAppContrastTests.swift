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

    // MARK: - Home v2

    @Test(arguments: modes)
    func blockInkReadsOnLavenderAndButter(_ mode: String, _ palette: NoctisAppPalette) {
        let onLavender = ratio(palette.blockInk, palette.blockLavender)
        let onButter = ratio(palette.blockInk, palette.blockButter)
        #expect(onLavender >= 4.5, "\(mode): block ink on lavender \(onLavender)")
        #expect(onButter >= 4.5, "\(mode): block ink on butter \(onButter)")
    }

    @Test func cocoaIsTooLightForTextOnTheLavenderBlock() {
        // Why block ink is #2B1D14 rather than cocoa #4A2F22.
        #expect(ratio(NoctisAppPalette.light.cocoa, NoctisAppPalette.light.blockLavender) < 4.5)
        #expect(ratio("4A2F22", NoctisAppPalette.dark.blockLavender) < 4.5)
    }

    @Test(arguments: modes)
    func ivoryReadsOnTheNightPanel(_ mode: String, _ palette: NoctisAppPalette) {
        #expect(ratio(palette.nightInk, palette.nightPanel) >= 4.5, "\(mode): night ink")
        // Captions use the ink at 70%.
        let caption = blend(palette.nightInk, over: palette.nightPanel, alpha: 0.7)
        #expect(ratio(caption, palette.nightPanel) >= 4.5, "\(mode): night ink at 70%")
    }

    @Test(arguments: modes)
    func lavenderTextClearsDisplayContrast(_ mode: String, _ palette: NoctisAppPalette) {
        #expect(ratio(palette.lavenderText, palette.bg) >= 3, "\(mode): lavender text on bg")
    }

    @Test(arguments: modes)
    func theNightPanelIsTheDarkestSurface(_ mode: String, _ palette: NoctisAppPalette) {
        let panel = luminance(palette.nightPanel)
        for other in [palette.bg, palette.surface, palette.track, palette.blockLavender, palette.blockButter] {
            #expect(panel < luminance(other), "\(mode): night panel vs \(other)")
        }
    }

    /// Dark mode: no two neighboring surfaces within 1.2:1 of each other,
    /// as a plain relative-luminance ratio (L1 / L2).
    @Test func darkNeighboringSurfacesStayApart() {
        let dark = NoctisAppPalette.dark
        let neighbors: [(String, String, String)] = [
            ("paper / card", dark.bg, dark.surface),
            ("paper / night panel", dark.bg, dark.nightPanel),
            ("paper / panel edge", dark.bg, dark.nightBorder),
            ("panel edge / night panel", dark.nightBorder, dark.nightPanel),
            ("paper / card edge", dark.bg, dark.hairline),
            ("card / card edge", dark.surface, dark.hairline),
            ("paper / ring track", dark.bg, dark.ringTrack),
            ("card / bar track", dark.surface, dark.track),
            ("paper / lavender block", dark.bg, dark.blockLavender),
            ("paper / butter block", dark.bg, dark.blockButter),
        ]
        for (name, a, b) in neighbors {
            let la = luminance(a), lb = luminance(b)
            let value = max(la, lb) / min(la, lb)
            #expect(value >= 1.2, "\(name): \(value)")
        }
    }

    private func luminance(_ hex: String) -> Double {
        let (r, g, b) = noctisHexComponents(hex)
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func blend(_ foreground: String, over background: String, alpha: Double) -> String {
        let f = noctisHexComponents(foreground), b = noctisHexComponents(background)
        func mix(_ x: Double, _ y: Double) -> Int { Int(((alpha * x + (1 - alpha) * y) * 255).rounded()) }
        return String(format: "%02X%02X%02X", mix(f.0, b.0), mix(f.1, b.1), mix(f.2, b.2))
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
