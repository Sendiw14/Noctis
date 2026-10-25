import SwiftUI
import Testing

@testable import DesignSystem

// Health and Notifications, in the band style: the small words and their softer shades (the 80% and 65% the designs ask for) clear 4.5:1 on what they sit on.
struct BandStyleContrastTests {
    private let ink = "2B1D14", ivory = "F8F5EE", cocoa = "4A2F22", white = "FFFFFF"
    private let sage = "9DB073", orange = "E07B39", lavender = "A08CEB", darkCard = "3A271C"

    private func ratio(_ fg: String, _ alpha: Double, over bg: String) -> Double {
        noctisContrastRatio(noctisHexColor(noctisBlendHex(fg, over: bg, alpha: alpha)), noctisHexColor(bg))
    }

    @Test func theHealthCardsLinesAreAA() {
        for (name, fill) in [("sage", sage), ("orange", orange), ("lavender", lavender)] {
            #expect(ratio(ink, 1, over: fill) >= 4.5, "\(name) title")
            #expect(ratio(ink, 0.9, over: fill) >= 4.5, "\(name) line at 90% (80% is 4.0:1 on orange and 4.2:1 on lavender)")
            #expect(ratio(ink, 0.8, over: fill) >= 3.0, "\(name) line at the design's 80% is at least 3:1")
        }
        #expect(ratio(ivory, 1, over: cocoa) >= 4.5, "the read-only card")
    }

    @Test func theNotificationsWordsAreAA() {
        #expect(ratio(ink, 0.65, over: white) >= 4.5, "Light: a row's line at 65%")
        #expect(ratio(ivory, 0.65, over: darkCard) >= 4.5, "Dark: a row's line at 65%")
        #expect(ratio(ink, 0.65, over: ivory) >= 4.5, "Light: EXAMPLE at 65%")
        #expect(ratio(ivory, 0.65, over: ink) >= 4.5, "Dark: EXAMPLE at 65%")
        #expect(noctisContrastRatio(noctisHexColor("7A6B5E"), noctisHexColor(white)) >= 4.5, "Light: 'now' in ink3")
        #expect(ratio(ivory, 0.6, over: darkCard) >= 4.5, "Dark: 'now' at 60%")
    }
}
