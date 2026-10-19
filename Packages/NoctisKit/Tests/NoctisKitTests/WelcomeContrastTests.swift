import SwiftUI
import Testing

@testable import DesignSystem

// Welcome (APP_RULES.md R5, R69): the words on the four bands, the subtitle, the footer and the button labels clear 4.5:1 (AA) in Light and in Dark.
struct WelcomeContrastTests {
    private let ink = "2B1D14"
    private let ivory = "F8F5EE"
    private let cocoa = "4A2F22"

    @Test func theWordsAreAA_OnEveryBandInBothAppearances() {
        for palette in [NoctisAppPalette.light, .dark] {
            for section in [NoctisSection.home, .sleep, .recovery, .insights] {
                let ratio = noctisContrastRatio(noctisHexColor(ink), noctisHexColor(section.fillHex(palette)))
                #expect(ratio >= 4.5, "\(section) \(ratio)")
            }
        }
    }

    @Test func theSubtitleFooterAndButtonLabelsAreAA() {
        func ratio(_ fg: String, _ alpha: Double, over bg: String) -> Double {
            noctisContrastRatio(noctisHexColor(noctisBlendHex(fg, over: bg, alpha: alpha)), noctisHexColor(bg))
        }
        #expect(ratio(cocoa, 0.75, over: ivory) >= 4.5, "Light subtitle")
        #expect(ratio(ink, 0.72, over: ivory) >= 4.5, "Light footer")
        #expect(ratio(ivory, 0.72, over: ink) >= 4.5, "Dark subtitle")
        #expect(ratio(ivory, 0.68, over: ink) >= 4.5, "Dark footer")
        #expect(ratio(cocoa, 1, over: ivory) >= 4.5, "Light button label")
        #expect(ratio(ivory, 1, over: ink) >= 4.5, "Dark button label")
    }
}
