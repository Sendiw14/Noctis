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

    // MARK: - Home v3

    /// Evening mode's paper: every ink that sits on it.
    @Test(arguments: modes)
    func inksReadOnTheEveningPaper(_ mode: String, _ palette: NoctisAppPalette) {
        for (name, ink) in [("ink", palette.ink), ("ink2", palette.ink2), ("eveningInk3", palette.eveningInk3)] {
            let value = ratio(ink, palette.eveningPaper)
            #expect(value >= 4.5, "\(mode): \(name) on eveningPaper \(value) < 4.5:1")
        }
        for (name, ink) in [("orangeText", palette.orangeText), ("lavenderText", palette.lavenderText)] {
            let value = ratio(ink, palette.eveningPaper)
            #expect(value >= 3, "\(mode): \(name) on eveningPaper \(value) < 3:1 (display)")
        }
        // Still fine back on the day paper.
        #expect(ratio(palette.eveningInk3, palette.bg) >= 4.5, "\(mode): eveningInk3 on bg")
    }

    @Test func ink3IsJustTooLightForTheLightEveningPaper() {
        // Why evening mode uses eveningInk3 rather than ink3.
        let value = ratio(NoctisAppPalette.light.ink3, NoctisAppPalette.light.eveningPaper)
        #expect(value < 4.5 && value > 4.4)
    }

    /// Deep on the night panel and in This week's bars, and the insight's
    /// cocoa on butter: graphics, 3:1.
    @Test(arguments: modes)
    func newGraphicsStandOut(_ mode: String, _ palette: NoctisAppPalette) {
        #expect(ratio(palette.nightDeep, palette.nightPanel) >= 3, "\(mode): nightDeep on the night panel")
        #expect(ratio(palette.nightDeep, palette.surface) >= 3, "\(mode): nightDeep on the week card")
        #expect(ratio(palette.blockCocoa, palette.blockButter) >= 3, "\(mode): cocoa on the insight block")
        #expect(ratio(palette.progressDot, palette.bg) >= 3, "\(mode): a recorded learning night")
        #expect(ratio(palette.progressDot, palette.track) >= 3, "\(mode): recorded vs. not yet")
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

    // MARK: - Color pass

    /// Block ink on all three blocks, and on the core tint.
    @Test(arguments: modes)
    func blockInkReadsOnEveryBlockAndTheCoreTint(_ mode: String, _ palette: NoctisAppPalette) {
        for (name, fill) in [("sage", palette.blockSage), ("lavender", palette.blockLavender), ("butter", palette.blockButter), ("coreTint", palette.coreTint)] {
            let value = ratio(palette.blockInk, fill)
            #expect(value >= 4.5, "\(mode): block ink on \(name) \(value) < 4.5:1")
        }
        // The factor header in orange takes ivory ink (part C): in Light that's the paper, in Dark the ink.
        #expect(ratio(palette.onFill, palette.orange) >= 4.5, "\(mode): ink on the orange fill")
    }

    /// The tab glyphs' section inks: 3:1 as graphics on the paper and the
    /// card, in both modes, for all five tabs.
    @Test(arguments: modes)
    func sectionInksStandOutAsGraphics(_ mode: String, _ palette: NoctisAppPalette) {
        for section in NoctisSection.allCases {
            let ink = section.inkHex(palette)
            #expect(ratio(ink, palette.bg) >= 3, "\(mode): \(section) glyph on the paper \(ratio(ink, palette.bg))")
            #expect(ratio(ink, palette.surface) >= 3, "\(mode): \(section) glyph on the card \(ratio(ink, palette.surface))")
        }
    }

    /// The core tint on the night panel (the ribbon) is a graphic: 3:1.
    @Test(arguments: modes)
    func theCoreTintReadsOnTheNightPanel(_ mode: String, _ palette: NoctisAppPalette) {
        #expect(ratio(palette.coreTint, palette.nightPanel) >= 3, "\(mode): core tint on the night panel")
    }

    /// Dark: the six most-used neighboring pairs, at least 1.25:1 (plain
    /// luminance ratio).
    @Test func darkMostUsedNeighborsStayAtLeast125Apart() {
        let dark = NoctisAppPalette.dark
        let pairs: [(String, String, String)] = [
            ("paper / card", dark.bg, dark.surface),
            ("paper / night panel", dark.bg, dark.nightPanel),
            ("card / track", dark.surface, dark.track),
            ("paper / sage block", dark.bg, dark.blockSage),
            ("paper / lavender block", dark.bg, dark.blockLavender),
            ("paper / butter block", dark.bg, dark.blockButter),
        ]
        for (name, a, b) in pairs {
            let la = luminance(a), lb = luminance(b)
            #expect(max(la, lb) / min(la, lb) >= 1.25, "\(name)")
        }
    }

    /// Cocoa ink on every field, in both modes: full ink, and the quieter
    /// inks (the caption's .7, the summary's .8) at 4.5:1, raised where a
    /// field needs it.
    @Test(arguments: modes)
    func fieldInkReadsOnEveryField(_ mode: String, _ palette: NoctisAppPalette) {
        let dark = mode == "dark"
        for section in NoctisSection.allCases {
            let fill = section.fillHex(palette)
            #expect(ratio(palette.blockInk, fill) >= 4.5, "\(mode): field ink on \(section)")
            for target in [NoctisFieldInkStyle.captionOpacity, NoctisFieldInkStyle.summaryOpacity] {
                let opacity = section.quietOpacity(target: target, dark: dark)
                #expect(opacity >= target && opacity <= 1, "\(mode) \(section) \(target)")
                let quieter = blend(palette.blockInk, over: fill, alpha: opacity)
                #expect(ratio(quieter, fill) >= 4.5, "\(mode): ink at \(opacity) on \(section) \(ratio(quieter, fill))")
            }
        }
    }

    /// The five field colors are the ones the tab scaffold names.
    @Test func theFiveFieldColorsAreTheScaffoldsTokens() {
        let light = NoctisAppPalette.light, dark = NoctisAppPalette.dark
        #expect([NoctisSection.home, .sleep, .recovery, .insights, .coach].map { $0.fillHex(light) } == ["F0B27F", "A9BC84", "A08CEB", "F2CE6B", "EBA79E"])
        #expect([NoctisSection.home, .sleep, .recovery, .insights, .coach].map { $0.fillHex(dark) } == ["D48A55", "8FA366", "8E7BDC", "E0B955", "C98580"])
        #expect([NoctisSection.home, .sleep, .recovery, .insights, .coach].map { $0.inkHex(light) } == ["B4622A", "6B8A3E", "6B55C4", "8A6A1F", "A4524A"])
        #expect(dark.sectionApricot == "D48A55")
    }

    /// The field runs under the status bar only where the system's status-bar
    /// text (black in Light, white in Dark) clears 3:1 over it; a field that
    /// can't starts below the safe area.
    @Test func theFieldRunsUnderTheStatusBarWhereItsTextStaysLegible() {
        for section in NoctisSection.allCases {
            #expect(section.extendsUnderStatusBar(dark: false), "Light \(section)")
        }
        // White on the dark fields, from their luminance.
        for section in NoctisSection.allCases {
            let ratio = ratio("FFFFFF", section.fillHex(.dark))
            #expect(section.extendsUnderStatusBar(dark: true) == (ratio >= 3), "Dark \(section) \(ratio)")
        }
        #expect(NoctisSection.recovery.extendsUnderStatusBar(dark: true), "white on the dark lavender is 3.5:1")
        #expect(!NoctisSection.sleep.extendsUnderStatusBar(dark: true), "white on the dark sage fails 3:1")
        #expect(!NoctisSection.insights.extendsUnderStatusBar(dark: true), "white on the dark butter fails 3:1")
    }

    /// The first card or hero below a field overlaps its bottom edge by 24pt;
    /// a ring's paper disc is 8pt wide, so the ring itself rides up 16.
    @Test func theFirstCardOverlapsTheFieldBy24pt() {
        #expect(TabScreenScaffold<EmptyView>.overlap == 24)
        #expect(NoctisSectionField<EmptyView, EmptyView>.overlap == 24)
        #expect(TabScreenScaffold<EmptyView>.discMargin == 8)
    }

    /// The daily gate the placeholders' wash uses: once per calendar day.
    @Test func theDailyGateClaimsOncePerCalendarDay() {
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? .standard
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 8)) ?? Date()
        let evening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 21)) ?? Date()
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 8)) ?? Date()
        #expect(!NoctisDailyGate.isClaimed(key: "noctis.insights.lastWashDay", now: morning, calendar: calendar, defaults: defaults))
        NoctisDailyGate.claim(key: "noctis.insights.lastWashDay", now: morning, calendar: calendar, defaults: defaults)
        #expect(NoctisDailyGate.isClaimed(key: "noctis.insights.lastWashDay", now: evening, calendar: calendar, defaults: defaults))
        #expect(!NoctisDailyGate.isClaimed(key: "noctis.insights.lastWashDay", now: nextDay, calendar: calendar, defaults: defaults))
        #expect(!NoctisDailyGate.isClaimed(key: "noctis.coach.lastWashDay", now: morning, calendar: calendar, defaults: defaults), "each tab has its own")
    }

    /// Each tab has its own glyph, and every field has a motif strip only
    /// where the motif needs one.
    @Test func everyTabHasItsOwnGlyphAndFieldMotif() {
        #expect(Set(NoctisSection.allCases.map(\.systemImage)).count == 5)
        #expect(NoctisSectionMotif.bottomStrip(.sleep) == 52 && NoctisSectionMotif.bottomStrip(.home) == 32)
        #expect([NoctisSection.recovery, .insights, .coach].allSatisfy { NoctisSectionMotif.bottomStrip($0) == 0 })
    }

    @Test func theDarkCardIsTheApprovedValue() {
        #expect(NoctisAppPalette.dark.bg == "17110E")
        #expect(NoctisAppPalette.dark.surface == "251C16")
        #expect(NoctisAppPalette.dark.nightPanel == "0E0A08")
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
