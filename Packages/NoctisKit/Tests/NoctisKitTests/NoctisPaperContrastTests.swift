import Testing
@testable import DesignSystem

/// R5's fixed paper-palette contrast floor — since `NoctisPaper` never
/// adapts to system light/dark or to any dynamic background, these ratios
/// are constants, not per-world loops like the old world-system test.
struct NoctisPaperContrastTests {
    @Test func inkTonesClearBodyContrastOnBackground() {
        let ratioInk = noctisContrastRatio(NoctisPaper.ink, NoctisPaper.bg)
        let ratioInk2 = noctisContrastRatio(NoctisPaper.ink2, NoctisPaper.bg)
        let ratioInk3 = noctisContrastRatio(NoctisPaper.ink3, NoctisPaper.bg)
        #expect(ratioInk >= 4.5, "ink on bg contrast \(ratioInk) < 4.5:1")
        #expect(ratioInk2 >= 4.5, "ink2 on bg contrast \(ratioInk2) < 4.5:1")
        #expect(ratioInk3 >= 4.5, "ink3 on bg contrast \(ratioInk3) < 4.5:1")
    }

    @Test func orangeTextClearsDisplayContrastOnBackground() {
        let ratio = noctisContrastRatio(NoctisPaper.orangeText, NoctisPaper.bg)
        #expect(ratio >= 3.0, "orangeText on bg contrast \(ratio) < 3:1 (display)")
    }

    @Test func ivoryClearsBodyContrastOnInk() {
        let ratio = noctisContrastRatio(NoctisPaper.ivory, NoctisPaper.ink)
        #expect(ratio >= 4.5, "ivory on ink contrast \(ratio) < 4.5:1")
    }
}
