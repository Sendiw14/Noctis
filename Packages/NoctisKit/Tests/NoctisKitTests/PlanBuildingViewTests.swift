import SwiftUI
import Testing

@testable import DesignSystem
@testable import OnboardingFeature

// "Building your plan", in the sunrise style: the three lines say what they always said, a step is shown for at least 0.7 s, VoiceOver is told as each one
// finishes, the rings never reach the rows, and the words clear 4.5:1 on the paper and on the cocoa (Light and Dark).
struct PlanBuildingViewTests {
    @Test func theThreeLinesAreTheOnesTheChecklistAlwaysHad() {
        #expect(PlanBuildLine.allCases.map(\.label) == ["Reading your recent nights", "Finding your typical bedtime", "Setting your sleep need"])
        #expect(PlanBuildFacts.startingFresh == "Starting fresh. We'll learn your pattern as you sleep.")
    }

    @Test func theTimingsAreTheBriefs() {
        #expect(PlanBuildFacts.minimumGap == 0.7)
        #expect(PlanBuildFacts.holdSeconds == 0.6)
        #expect(PlanBuildFacts.radii == [430, 340, 250, 160])
        #expect(PlanBuildFacts.moonRadius == 34 && PlanBuildFacts.centreBelow == 56)
    }

    @Test func theRowColoursAreSageOrangeLavender() {
        #expect(PlanBuildLine.allCases.map(\.color) == [NoctisPaper.sage, NoctisPaper.orange, NoctisPaper.lavender])
    }

    @Test func eachFinishedStepIsAnnouncedByItsShortName() {
        #expect(PlanBuildFacts.announcement(done: PlanBuildFacts.startingFresh) == "Starting fresh step done")
        #expect(PlanBuildFacts.announcement(done: "Reading your recent nights") == "Reading your recent nights step done")
        #expect(PlanBuildFacts.announcement(done: "Setting your sleep need") == "Setting your sleep need step done")
    }

    @Test func theRingsAtDesignSizeStandAtTheDesignsHeight() {
        let scale = PlanBuildFacts.ringScale(width: 402, totalHeight: 874, contentHeight: 430)
        #expect(scale == 1, "room to spare on a 17 Pro: the rings are drawn at their size")
        #expect(PlanBuildFacts.ringTop(totalHeight: 874, scale: scale) == 500, "lavender's top at y 500 (930 - 430)")
    }

    @Test func theRingsStayClearOfTheRowsOnShortScreensAndAtLargeText() {
        // (width, height, the height of the header and rows): a 17 Pro, an SE, an SE with the rows a line taller, and a screen the large text fills.
        for (width, height, content) in [(402.0, 874.0, 430.0), (375.0, 667.0, 392.0), (375.0, 667.0, 412.0), (402.0, 874.0, 700.0)] {
            let scale = PlanBuildFacts.ringScale(width: width, totalHeight: height, contentHeight: content)
            let top = PlanBuildFacts.ringTop(totalHeight: height, scale: scale)
            // At the spring's overshoot the biggest ring is 8% bigger, and still 12 pt under the rows.
            let overshotTop = height + PlanBuildFacts.centreBelow * scale - PlanBuildFacts.radii[0] * PlanBuildFacts.overshoot * scale
            if scale > 0.3 { #expect(overshotTop >= content + 11.9, "\(width)x\(height): \(overshotTop) vs \(content)") }
            #expect(top < height, "\(width)x\(height)")
        }
        #expect(PlanBuildFacts.ringScale(width: 402, totalHeight: 874, contentHeight: 2000) == 0.3, "never smaller than 0.3: the screen scrolls instead")
    }

    @Test func theStarsAreTwentyFourTinyDotsInTheTopOfTheScreenAndOffTheWords() {
        let stars = PlanBuildFacts.stars
        #expect(stars.count == 24)
        for star in stars {
            #expect(star.y <= 230 && star.x >= 0 && star.x <= 402)
            #expect((1.0...2.0).contains(star.d) && (0.5...0.8).contains(star.a), "\(star)")
            // The first title line, the second, and the small caps above them.
            let onFirst = (28.0...330.0).contains(star.x) && (96.0...148.0).contains(star.y)
            let onSecond = (28.0...140.0).contains(star.x) && (148.0...192.0).contains(star.y)
            let onCaps = (28.0...100.0).contains(star.x) && (82.0...100.0).contains(star.y)
            #expect(!onFirst && !onSecond && !onCaps, "\(star) is on the words")
        }
    }

    @Test func theWordsAreAA_OnThePaperAndOnTheCocoa() {
        func ratio(_ fg: String, _ alpha: Double, over bg: String) -> Double {
            noctisContrastRatio(noctisHexColor(noctisBlendHex(fg, over: bg, alpha: alpha)), noctisHexColor(bg))
        }
        let ink = "2B1D14", ivory = "F8F5EE", butter = "F2CE6B", orangeText = "B14F18", white = "FFFFFF"
        #expect(ratio(orangeText, 1, over: ivory) >= 4.5, "Light: the title's second line")
        #expect(ratio(butter, 1, over: ink) >= 4.5, "Dark: the title's second line")
        #expect(ratio(ink, 1, over: white) >= 4.5, "Light: a row")
        // Dark rows are ivory at 9% over the cocoa; the words are ivory.
        let row = noctisBlendHex(ivory, over: ink, alpha: 0.09)
        #expect(ratio(ivory, 1, over: row) >= 4.5, "Dark: a row")
    }
}

// "Your plan is ready", in the band style: the values are the person's own choices, the chips follow the goals they picked, and the copy under "Your first
// two weeks" is the copy the plan always had.
struct PlanReadyTests {
    @Test func bedtimeAndWakeAreTheClockWithItsPeriodApart() {
        let bedtime = PlanReadyFacts.clockParts(minutesSinceMidnight: 23 * 60)
        let wake = PlanReadyFacts.clockParts(minutesSinceMidnight: 7 * 60)
        #expect(bedtime.number == "11:00" && bedtime.period.uppercased().hasPrefix("P"))
        #expect(wake.number == "7:00" && wake.period.uppercased().hasPrefix("A"))
    }

    @Test func theSleepNeedShowsMinutesOnlyWhenThereAreSome() {
        func text(_ minutes: Int) -> String { PlanReadyFacts.needParts(minutes: minutes).map { $0.number + $0.unit }.joined(separator: " ") }
        #expect(text(480) == "8h", "a whole number of hours is just hours")
        #expect(text(450) == "7h 30m", "7 h 30 m shows its minutes")
        #expect(text(300) == "5h" && text(330) == "5h 30m")
        #expect(text(45) == "45m", "never an empty value")
    }

    @Test func theCopyUnderFirstTwoWeeksIsTheCopyThePlanAlwaysHad() {
        #expect(
            PlanReadyFacts.legacyTimeline(nightCount: 0) == [
                "Today: tonight is your first night, read in the morning", "Day 7: your first weekly review", "Day 14: early patterns appear",
            ])
        #expect(PlanReadyFacts.legacyTimeline(nightCount: 12)[0] == "Today: you already have 12 nights, so NOCTIS starts learning")
        #expect(PlanReadyFacts.timeline(nightCount: 0).map(\.day) == [.today, .daySeven, .dayFourteen])
    }

    @Test func theBadgesSayTheDayAndVoiceOverReadsItInWords() {
        #expect(PlanReadyDay.allCases.map(\.badge) == ["TODAY", "DAY 7", "DAY 14"])
        #expect(PlanReadyDay.allCases.map(\.spoken) == ["Today", "Day 7", "Day 14"])
        #expect(PlanReadyDay.allCases.map(\.color) == [NoctisSection.home.fill, NoctisPaper.lavender, NoctisPaper.sage])
        #expect(PlanReadyFacts.tileSpoken(label: "Bedtime", value: "11:00 PM") == "Bedtime, 11:00 PM")
    }

    @Test func eachGoalsChipIsItsTileFromTheGoalStep() {
        #expect(GoalPresentation.fill(.betterFocus) == NoctisPaper.cocoa)
        #expect(GoalPresentation.fill(.betterConsistency) == NoctisPaper.butter)
        #expect(GoalPresentation.fill(.betterSleep) == NoctisPaper.lavender)
        #expect(GoalPresentation.fill(.moreEnergy) == NoctisPaper.orange)
        #expect(GoalPresentation.fill(.betterRecovery) == NoctisPaper.sage)
        #expect(GoalPresentation.title(.betterFocus) == "Clearer focus" && GoalPresentation.title(.betterConsistency) == "Steady routine")
        #expect(GoalPresentation.title(.betterSleep) == "Better sleep" && GoalPresentation.title(.betterRecovery) == "Faster recovery")
    }

    @Test func theTileWordsAreAAOnTheirColours() {
        func ratio(_ fg: String, _ alpha: Double, over bg: String) -> Double {
            noctisContrastRatio(noctisHexColor(noctisBlendHex(fg, over: bg, alpha: alpha)), noctisHexColor(bg))
        }
        for (name, fill) in [("lavender", "A08CEB"), ("butter", "F2CE6B"), ("sage", "9DB073")] {
            #expect(ratio("2B1D14", 0.9, over: fill) >= 4.5, "\(name): the small caps and the unit at 90%")
        }
        #expect(ratio("2B1D14", 0.75, over: "A08CEB") < 4.5, "why the designs' 75% is 90%: on the lavender it is 3.8:1")
    }
}
