import Foundation
import Testing

@testable import NoctisCore
@testable import ProfileFeature

// Stage 1B accessibility micro-fixes (audit findings P-1, P-5, P-8). The behaviour itself is checked with real VoiceOver and the hierarchy in
// `VoiceOverTraversalQATests`; these are the checks that run with the package tests.

struct AccessibilityMicroFixTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: RawDefaultsTests.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// P-8: a Settings row is one accessibility element with a joined label, so VoiceOver says "Notifications, 3 reminders on" once. The audit's repeated label was the
    /// icon and the title in the UI test tree, not something VoiceOver says. A change that stopped the row being one element would make it say both.
    @Test func aLinkRowIsOneAccessibilityElementWithOneJoinedLabel() throws {
        let text = RawDefaultsTests.code(try source("Packages/NoctisKit/Sources/DesignSystem/NoctisRows.swift"))
        let link = try #require(text.range(of: "public struct NoctisLinkRow: View"))
        let body = String(text[link.upperBound...].prefix(1800))
        #expect(body.contains(".accessibilityElement(children: .ignore)"))
        #expect(body.contains(".accessibilityLabel([title, value, detail].compactMap { $0 }.joined(separator: \", \"))"))
        #expect(body.contains(".accessibilityAddTraits(.isButton)"))
        #expect(RawDefaultsTests.code(try source("Packages/NoctisKit/Sources/DesignSystem/NoctisIconTile.swift")).contains(".accessibilityHidden(true)"), "the tile is hidden, as it was")
    }

    /// P-1: the real-VoiceOver sheet test names phrases that are only on the page under the Delete-all sheet. "Files set aside" was not one: the sheet's own
    /// "What is deleted" list names that kind of data, so VoiceOver saying it there was the sheet reading itself.
    @Test func theSheetsOwnTextSharesNothingWithThePhrasesTheLeakTestListens() throws {
        let sheetItems = DataManagementCopy.deleteAllRemoves(.shared).items
        #expect(sheetItems.contains("Files set aside"), "the collision that made the finding a false positive")
        let test = try source("Tests/UITests/VoiceOverTraversalQATests.swift")
        let line = try #require(test.components(separatedBy: "\n").first { $0.contains("(\"privacy.deleteAll\"") })
        #expect(!line.contains("Files set aside"), "the sheet test no longer listens for a phrase the sheet says itself")
        let phrases = ["Export my data", "Delete one kind at a time", "Delete what NOCTIS keeps"]
        for phrase in phrases {
            #expect(line.contains(phrase), Comment(rawValue: phrase))
            let sheetText = (sheetItems + [DataManagementCopy.deleteAllTitle, DataManagementCopy.deleteAllClosing] + DataManagementCopy.deleteAllKeeps).joined(separator: " ")
            #expect(!sheetText.localizedCaseInsensitiveContains(phrase), "the sheet itself says \"\(phrase)\"")
        }
    }

    /// P-5: the Recovery disclosure row stays the system's `DisclosureGroup`, which gives VoiceOver one stop that says collapsed or expanded; the
    /// finding was the group's own chevron, which VoiceOver does not stop on. Replacing the group would lose that.
    @Test func theRecoveryCalculationRowIsStillTheSystemDisclosureGroup() throws {
        let text = RawDefaultsTests.code(try source("Packages/NoctisKit/Sources/RecoveryFeature/RecoveryTodayViews.swift"))
        let row = try #require(text.range(of: "DisclosureGroup(isExpanded: $expanded)"))
        #expect(String(text[row.upperBound...].prefix(2000)).contains("How this is calculated"))
        #expect(text.contains(".accessibilityIdentifier(\"recovery.calculation\")"))
    }

    /// P-3: the onboarding progress bar keeps its spoken label ("Step 3 of 6") and is read-only, which is what stops Xcode's audit taking its 4 pt height
    /// for a control with a hit area that is too small. Hiding it instead would take the person's place in the flow away from VoiceOver.
    @Test func theOnboardingProgressIsLabelledAndReadOnly() throws {
        let text = RawDefaultsTests.code(try source("Packages/NoctisKit/Sources/DesignSystem/OnboardingStepScaffold.swift"))
        let bar = try #require(text.range(of: "ForEach(0..<totalSteps, id: \\.self)"))
        let body = String(text[bar.upperBound...].prefix(900))
        #expect(body.contains(".accessibilityLabel(\"Step \\(step + 1) of \\(totalSteps)\")"))
        #expect(body.contains(".accessibilityAddTraits(.isStaticText)"))
        #expect(!body.contains(".accessibilityHidden(true)"), "the progress stays readable")
    }

    /// P-3: the Coach field's bar stays 44 pt tall and taps anywhere in it. The UI test tree reports the text's own 21 pt frame; a real tap above and below
    /// the text is what `testTheCoachBarTypesWhereverItIsTapped` checks.
    @Test func theCoachFieldKeepsItsFortyFourPointBar() throws {
        let text = RawDefaultsTests.code(try source("Packages/NoctisKit/Sources/CoachFeature/CoachInputBar.swift"))
        #expect(text.contains(".frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)"))
        #expect(text.contains(".contentShape(Rectangle())"))
        #expect(text.contains(".onTapGesture { focused = true }"))
    }

    /// P-2: "REM" on Home is the night chart's lane label, drawn in the night card's secondary ink. The audit's 2.83:1 was measured on the floating tab bar's
    /// Home pill laid over that label; the label's own contrast is measured by `testTheRemLaneLabelOnHomeIsReadableOnceClearOfTheTabBar` (6.6:1) and the palette
    /// is held to 4.5:1 by `NoctisAppContrastTests.ivoryReadsOnTheNightPanel`. A change of the lane label's ink would have to meet the same bar.
    @Test func theLaneLabelsWearTheNightCardsSecondaryInk() throws {
        let text = RawDefaultsTests.code(try source("Packages/NoctisKit/Sources/HomeFeature/HomeNightChartViews.swift"))
        let labels = try #require(text.range(of: "private var laneLabels: some View"))
        #expect(String(text[labels.upperBound...].prefix(700)).contains(".foregroundStyle(.noctisNightInk2)"))
        let contrast = try source("Packages/NoctisKit/Tests/NoctisKitTests/NoctisAppContrastTests.swift")
        #expect(contrast.contains("func ivoryReadsOnTheNightPanel("))
    }

    /// P-3: the stage totals under Sleep's night chart are at least 44 pt wide (they were 38 and 42 wide: the button took the width of its label). The minimum
    /// is on the label, inside the button, so the button's own frame is 44 pt and the leading-aligned content does not move.
    @Test func theStageTotalButtonsAreFortyFourPointsWide() throws {
        let text = RawDefaultsTests.code(try source("Packages/NoctisKit/Sources/HomeFeature/HomeBlockViews.swift"))
        let totals = try #require(text.range(of: "struct NightStageTotalsView: View"))
        #expect(String(text[totals.upperBound...].prefix(2600)).contains(".frame(minWidth: 44, minHeight: 44, alignment: .leading)"))
    }

    /// The harness's touch-target check allows for rounding: a 44 pt button measures 43.999999999999986 in places (the audit's "Pause 43 x 44" at AX5).
    @Test func theTouchTargetCheckAllowsForRounding() throws {
        let text = try source("Tests/UITests/QASupport.swift")
        #expect(text.contains("s.frame.width < 43.99 || s.frame.height < 43.99"))
        #expect(!text.contains("s.frame.width < 44 || s.frame.height < 44"))
    }

    /// R-14: the sleep quality strip and its legend draw their marks with `QualityDotMark`, the one place that turns the band into a shape when Differentiate
    /// Without Color is on. A plain `Circle().fill(band.tint)` back in the strip would make colour the only signal again.
    @Test func theQualityStripDrawsItsMarksWithTheShapeAwareMark() throws {
        let text = RawDefaultsTests.code(try source("Packages/NoctisKit/Sources/SleepFeature/SleepRangeViews.swift"))
        #expect(text.contains("QualityDotMark(band: band, size: size)"))
        #expect(!text.contains(".fill(band.tint)"))
        let mark = RawDefaultsTests.code(try source("Packages/NoctisKit/Sources/SleepFeature/QualityDotMark.swift"))
        #expect(mark.contains("@Environment(\\.accessibilityDifferentiateWithoutColor)"))
    }

    /// The UI tests exist and are the ones that decide P-1, P-2, P-3, P-5 and P-8 on a simulator.
    @Test func theRealVoiceOverAndHierarchyTestsForTheFindingsExist() throws {
        let test = try source("Tests/UITests/VoiceOverTraversalQATests.swift")
        #expect(test.contains("func testRecoveryDisclosureIsOneVoiceOverStop()"))
        #expect(test.contains("func testSettingsRowsAreOneVoiceOverStopEach()"))
        #expect(test.contains("func testASheetKeepsVoiceOverInsideIt()"))
        #expect(test.contains("func testTheCoachBarTypesWhereverItIsTapped()"))
        #expect(test.contains("func testTheOnboardingProgressIsSpokenOnceAsText()"))
        #expect(try source("Tests/UITests/AuditQATests.swift").contains("func testTheRemLaneLabelOnHomeIsReadableOnceClearOfTheTabBar()"))
        #expect(try source("Tests/UITests/AuditQATests.swift").contains("func testTheTonightCatchUpLineIsReadableClearOfTheFloatingPill()"))
        #expect(test.contains("func testSleepStageTotalsAreFortyFourPointsWide()"))
        #expect(test.contains("func testTheCompactWakeDialDragsFromItsFortyFourPointBand()"))
    }
}
