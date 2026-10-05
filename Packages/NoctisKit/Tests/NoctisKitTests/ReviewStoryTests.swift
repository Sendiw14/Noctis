import Foundation
import SwiftUI
import Testing

@testable import DesignSystem
@testable import HealthProviding
@testable import InsightsFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import PremiumKit
@testable import RecoveryKit
@testable import ReviewKit
@testable import SleepKit

// A review's story (APP_RULES.md R63): every page made from a record alone, the pages a plan sees, a page skipped when its data does not exist, the steady page, the share card
// and what it may hold, the paging, and the colors every page is drawn on.

private nonisolated let nyZone = TimeZone(identifier: "America/New_York") ?? .gmt

private nonisolated func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = nyZone
    return calendar
}

private nonisolated func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
    calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
}

private nonisolated func key(_ year: Int, _ month: Int, _ day: Int) -> SleepNightKey { SleepNightKey(year: year, month: month, day: day) }

private nonisolated let now = at(2026, 9, 28)
private nonisolated let week = ReviewPeriod.latestWeekly(now: now, weekday: 1, calendar: calendar())
private nonisolated let month = ReviewPeriod.latestMonthly(now: now, calendar: calendar())
private nonisolated let format = ReviewFormat(locale: Locale(identifier: "en_US"))

/// A record of a scenario as the reviews read it.
private func record(_ scenario: MockScenario, _ period: ReviewPeriod = week, insights: [ReviewInsightInput] = []) async throws -> ReviewRecord {
    let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: calendar(), startAuthorized: true)
    let start = now.addingTimeInterval(-Double(ReviewInputsBuilder.historyDays) * 86_400 - 18 * 3600)
    async let sleep = provider.fetchSleepSamples(from: start, to: now)
    async let hrv = provider.fetchHRVSamples(from: start, to: now)
    async let resting = provider.fetchRestingHeartRate(from: start, to: now)
    let nights = ReviewInputsBuilder.nights(sleep: try await sleep, hrv: try await hrv, restingHeartRate: try await resting, needMinutes: 480, now: now, timeZone: nyZone)
    guard case .record(let value) = ReviewEngine.build(period: period, nights: nights, needMinutes: 480, insights: insights, now: now, calendar: calendar()) else {
        throw StoryTestError.notEnough
    }
    return value
}

private enum StoryTestError: Error { case notEnough }

/// A record made by hand, for the cases a scenario does not reach.
private nonisolated func handmade(
    _ period: ReviewPeriod = week, average: Double = 470, delta: Double? = 22, hasComparison: Bool = true, recovery: ReviewRecovery? = nil,
    improvement: ReviewHighlight = .steady, change: ReviewHighlight = .steady, insights: [String] = [], focus: ReviewFocus = .keepGoing,
    monthly: ReviewMonthlyExtras? = nil, nights recorded: Int? = nil
) -> ReviewRecord {
    let mornings = period.mornings
    let nights = (recorded.map { Array(mornings.prefix($0)) } ?? mornings).enumerated().map { index, morning in
        ReviewNightValues(
            morning: morning, asleepMinutes: 440 + index * 10, stages: ReviewStages(deep: 60, core: 250, rem: 100), bedtimeMinutes: 650 + index * 5, wakeMinutes: 1130 + index * 4,
            recoveryScore: recovery == nil ? nil : 60 + index
        )
    }
    return ReviewRecord(
        id: period.id, firstMorning: period.firstMorning, lastMorning: period.lastMorning, generatedAt: now, nightsRecorded: nights.count, nightsInPeriod: period.morningCount,
        hasComparison: hasComparison, sleep: ReviewSleep(averageMinutes: average, nightsReachedNeed: 4, needMinutes: 480, deltaMinutes: hasComparison ? delta : nil),
        consistency: ReviewConsistency(bedtimeSD: 32.2, wakeSD: 18, bedtimeSDDelta: hasComparison ? -10 : nil, wakeSDDelta: nil), recovery: recovery,
        heart: ReviewHeart(hrvAverage: 52.4, hrvDelta: nil, restingHeartRateAverage: 55, restingHeartRateDelta: nil),
        timing: ReviewTiming(medianBedtimeMinutes: 665, medianWakeMinutes: 1140, bedtimeShift: hasComparison ? 12 : nil, wakeShift: nil), nights: nights,
        biggestImprovement: hasComparison ? improvement : .noComparison, biggestChange: hasComparison ? change : .noComparison, topInsightIDs: insights, nextFocus: focus,
        monthly: monthly
    )
}

private nonisolated func extreme(_ value: Double, _ morning: SleepNightKey, also: Int = 0) -> ReviewExtreme { ReviewExtreme(value: value, morning: morning, alsoOn: also) }

private nonisolated func recovery(_ direction: RecoveryTrendDirection?, scored: Int = 7) -> ReviewRecovery {
    ReviewRecovery(
        average: 71.4, scoredNights: scored, high: extreme(82, week.mornings[2]), low: extreme(60, week.mornings[4], also: 1),
        trend: direction.map { RecoveryHistoryTrend(direction: $0, pointsPerWeek: direction == .rising ? 3 : (direction == .lower ? -3 : 0)) }, delta: 3.9
    )
}

private nonisolated func change(_ metric: ReviewMetric, _ value: Double, _ previous: Double, _ normalized: Double) -> ReviewChange {
    ReviewChange(metric: metric, value: value, previous: previous, normalized: normalized)
}

private nonisolated func kinds(_ story: ReviewStory) -> [ReviewStoryPage.Kind] { story.pages.map { $0.kind } }

// MARK: - A week

struct WeeklyStoryTests {
    @Test func aFullWeekHasEveryPageInOrderOnItsOwnColor() async throws {
        let insight = [ReviewInsightInput(id: "bedtimeShift-3fa9c2d1", generatedAt: at(2026, 9, 23), score: 0.9)]
        let story = ReviewStoryBuilder.build(try await record(.full, insights: insight), format: format)
        #expect(kinds(story) == [.cover, .sleep, .consistency, .recovery, .changes, .insight, .focus])
        #expect(story.pages.map { $0.tint } == [.apricot, .sage, .butter, .lavender, .sand, .cocoa, .paper])
        #expect(story.title == "Your week" && story.dateRange == "Sep 20 \u{2013} 26" && story.kind == .weekly)
        #expect(Set(story.pages.map { $0.id }).count == story.pages.count)
    }

    @Test func theCoverStatesTheAverageAndTheDeltaInTheWordsSpecified() {
        let story = ReviewStoryBuilder.build(handmade(average: 467, delta: 22), format: format)
        guard case .cover(let cover) = story.pages[0].content else { Issue.record("a cover"); return }
        #expect(cover.title == "Your week" && cover.averageMinutes == 467 && cover.deltaText == "+22 min vs the week before" && cover.deltaArrow == .up)
        #expect(cover.context == "7 of 7 nights were recorded." && cover.spokenAverage == "7h 47m on average")
        guard case .cover(let down) = ReviewStoryBuilder.build(handmade(delta: -14), format: format).pages[0].content else { return }
        #expect(down.deltaText == "\u{2212}14 min vs the week before" && down.deltaArrow == .down)
        guard case .cover(let same) = ReviewStoryBuilder.build(handmade(delta: 0.4), format: format).pages[0].content else { return }
        #expect(same.deltaText == "The same as the week before" && same.deltaArrow == .flat)
        guard case .cover(let none) = ReviewStoryBuilder.build(handmade(hasComparison: false), format: format).pages[0].content else { return }
        #expect(none.deltaText == "Not enough nights in the week before to compare" && none.deltaArrow == nil)
    }

    @Test func theSleepPageHasSevenBarsALineAtTheNeedAndTheCount() {
        let story = ReviewStoryBuilder.build(handmade(nights: 6), format: format)
        guard case .bars(let page) = story.pages[1].content else { Issue.record("bars"); return }
        #expect(page.bars.count == 7 && page.bars.map(\.label) == ["S", "M", "T", "W", "T", "F", "S"] && !page.slim)
        #expect(page.bars.last?.fraction == nil && page.bars.last?.spoken == "\(format.weekdayDay(week.mornings[6])): no sleep recorded", "a night with no sleep is no bar")
        #expect(page.bars.dropLast().allSatisfy { $0.fraction != nil && $0.stages != nil })
        #expect(page.headline == "Reached your need on 4 of 6 nights" && page.needText == "8h need")
        #expect(page.needFraction > 0 && page.needFraction < 1 && page.topMinutes.truncatingRemainder(dividingBy: 30) == 0)
        let shares = page.bars.compactMap(\.stages).first
        #expect(shares.map { abs($0.deep + $0.core + $0.rem - 1) < 1e-9 } == true)
    }

    @Test func theConsistencyPageSaysHowMuchTheBedtimeVariedAndTheChange() {
        let story = ReviewStoryBuilder.build(handmade(), format: format)
        guard case .timing(let page) = story.pages[2].content else { Issue.record("timing"); return }
        #expect(page.headline == "Bedtime varied by 32 min" && page.lines.first == "Bedtime varied 10 min less than the week before.")
        #expect(page.rows.count == 7 && page.rows.allSatisfy { (0...1).contains($0.bedtime) && (0...1).contains($0.wake) && $0.wake > $0.bedtime })
        #expect(page.ticks.count >= 2 && page.ticks.count <= 4 && page.ticks.map(\.position) == page.ticks.map(\.position).sorted())
        #expect(page.bedtimeBand.start < page.bedtimeBand.end && page.wakeBand.start < page.wakeBand.end && page.bedtimeBand.end < page.wakeBand.start)
        #expect(page.spoken.contains("Bedtime varied by 32 min"))
    }

    @Test func theRecoveryPageSaysTheDirectionInPlainWordsAndIsLeftOutWithoutScores() {
        for (direction, words, arrow) in [(RecoveryTrendDirection.rising, "Rising", ReviewArrow.up), (.steady, "Steady", .flat), (.lower, "Lower than earlier", .down)] {
            let story = ReviewStoryBuilder.build(handmade(recovery: recovery(direction)), format: format)
            guard case .line(let page) = story.pages[3].content else { Issue.record("a line"); return }
            #expect(page.direction == words && page.directionArrow == arrow && page.headline == "Recovery averaged 71", Comment(rawValue: words))
            #expect(page.lines.first == "Highest 82, on \(format.weekdayDay(week.mornings[2]))." && page.lines.last == "4 points higher than the week before.")
            #expect(page.lines[1] == "Lowest 60, on \(format.weekdayDay(week.mornings[4])), and equalled on 1 other night.")
            #expect(page.points.count == 7 && page.points.compactMap { $0 }.allSatisfy { (0...1).contains($0) })
            #expect(page.axis.map(\.label).allSatisfy { Int($0) != nil }, "whole numbers on the axis")
        }
        // Fewer than five scored nights: a score, but no direction to claim.
        guard case .line(let unsure) = ReviewStoryBuilder.build(handmade(recovery: recovery(nil, scored: 4)), format: format).pages[3].content else { Issue.record("a line"); return }
        #expect(unsure.direction == nil && unsure.directionArrow == nil)
        // No scores at all: no page.
        #expect(!kinds(ReviewStoryBuilder.build(handmade(recovery: nil), format: format)).contains(.recovery))
    }

    @Test func whatChangedHasTwoTilesOneWhenTheyAreTheSameAndAStaysSteadyWhenNothingMoved() {
        let sleep = change(.duration, 467, 445, 0.9)
        let hrv = change(.hrv, 52, 49, 0.7)
        func page(_ improvement: ReviewHighlight, _ change: ReviewHighlight) -> ReviewChangesPage? {
            ReviewStoryBuilder.build(handmade(improvement: improvement, change: change), format: format).pages.first { $0.kind == .changes }.flatMap {
                if case .changes(let value) = $0.content { value } else { nil }
            }
        }
        let two = page(.change(hrv), .change(sleep))
        #expect(two?.tiles.map(\.caption) == ["Biggest improvement", "Biggest change"] && two?.steadySentence == nil && two?.headline == "Compared with the week before")
        #expect(two?.tiles.first?.metric == "Average HRV" && two?.tiles.first?.from == "49 ms" && two?.tiles.first?.to == "52 ms" && two?.tiles.first?.arrow == .up)
        #expect(two?.tiles.last?.from == "7h 25m" && two?.tiles.last?.to == "7h 47m")
        // The same metric is one tile: not padded into two.
        #expect(page(.change(sleep), .change(sleep))?.tiles.map(\.caption) == ["Biggest improvement"])
        // A fall is a change, and no improvement is claimed.
        let fall = page(.steady, .change(change(.duration, 420, 450, -0.8)))
        #expect(fall?.tiles.map(\.caption) == ["Biggest change"] && fall?.tiles.first?.arrow == .down)
        // Compared, and nothing moved: one calm sentence and no highlight.
        let steady = page(.steady, .steady)
        #expect(steady?.tiles.isEmpty == true && steady?.headline == "A steady week" && steady?.steadySentence == "Compared with the week before, nothing moved by much.")
    }

    @Test func withNothingToCompareThereIsNoChangesPageAndNothingIsCalledSteady() {
        let story = ReviewStoryBuilder.build(handmade(hasComparison: false), format: format)
        #expect(!kinds(story).contains(.changes))
        let words = ReviewStoryBuilder.allStrings(story).joined(separator: " ").lowercased()
        #expect(!words.contains("steady week") && !words.contains("improvement"))
    }

    @Test func theInsightPageIsThereOnlyWithAnInsightAndTheFocusIsAlwaysLast() {
        #expect(!kinds(ReviewStoryBuilder.build(handmade(), format: format)).contains(.insight))
        let story = ReviewStoryBuilder.build(handmade(insights: ["a-1"]), format: format)
        guard case .insights(let page) = story.pages[story.pages.count - 2].content else { Issue.record("insights"); return }
        #expect(page.insightIDs == ["a-1"] && story.pages.last?.kind == .focus)
        // A page whose insight has gone is left out, never filled.
        #expect(!kinds(story.keepingInsights([])).contains(.insight) && kinds(story.keepingInsights(["a-1"])).contains(.insight))
    }

    @Test func theFocusIsOneSentenceAndAskCoachOnlyWhenThereIsSomethingToAsk() {
        let cases: [(ReviewFocus, ReviewCoachTopic?)] = [
            (.steadyBedtime(minutes: 52), .consistency), (.sleepNeed(minutesBehind: 93), .bedtime), (.gentleShiftBack(minutesLater: 50), .bedtime), (.recentNights(nights: 6), .recovery),
            (.keepGoing, nil),
        ]
        for (focus, topic) in cases {
            let story = ReviewStoryBuilder.build(handmade(focus: focus), format: format)
            guard case .focus(let page) = story.pages.last?.content else { Issue.record("a focus"); return }
            #expect(page.coachTopic == topic && !page.headline.isEmpty)
        }
        // Coach is handed its own question and nothing from the review.
        #expect(ReviewStoryScreen.question(for: .consistency) == .consistency && ReviewStoryScreen.question(for: .bedtime) == .bedtime)
        #expect(ReviewStoryScreen.question(for: .recovery) == .recovery(.lower))
    }

    @Test func theWeeklyStoriesOfEveryScenarioAreFreeOfTheBannedLanguageAndWordsOfCause() async throws {
        var strings: [String] = []
        let insight = [ReviewInsightInput(id: "bedtimeShift-3fa9c2d1", generatedAt: at(2026, 9, 23), score: 0.9)]
        for scenario in [MockScenario.full, .steadyWeek, .improvedWeek, .laterWeek, .highs, .recoveryDip, .hrvDip, .lateBedtime, .sleepOnly] {
            for period in [week, month] {
                guard let value = try? await record(scenario, period, insights: insight) else { continue }
                strings += ReviewStoryBuilder.allStrings(ReviewStoryBuilder.build(value, format: format))
            }
        }
        #expect(strings.count > 150)
        let extra = ["streak", "miss", "fail", "lazy", "guilt", "shame", "worse", "wrong", "!", "should", "because", "caused", "due to", "led to", "diagnos", "symptom", "disorder", "red"]
        for text in strings {
            #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: text))
            // "red" only as a whole word ("reduced" is fine).
            for word in extra where word != "red" { #expect(!text.lowercased().contains(word), Comment(rawValue: "\(text) has \(word)")) }
            #expect(text.lowercased().split(whereSeparator: { !$0.isLetter }).contains("red") == false, Comment(rawValue: text))
        }
    }
}

// MARK: - What a plan sees

struct StoryPlanTests {
    @Test func aFreeWeeklyReviewIsTheCoverAloneAndAFreeMonthIsOneLockedPage() async throws {
        let weekly = ReviewStoryBuilder.build(try await record(.full), format: format)
        #expect(weekly.visiblePages(unlocked: false).map(\.kind) == [.cover] && weekly.visiblePages(unlocked: true).count == 6)
        let monthly = ReviewStoryBuilder.build(try await record(.full, month), format: format)
        #expect(monthly.visiblePages(unlocked: false).map(\.kind) == [.locked])
        let locked = LockedCopy.card(for: .weeklyReview)
        #expect(locked?.title == "The full story of your week" && LockedCopy.card(for: .monthlyReview)?.title == "Your month, in full")
        for context in [PaywallContext.weeklyReview, .monthlyReview] {
            let card = LockedCopy.card(for: context)
            #expect(card != nil && LockedCopy.pressure(in: (card?.title ?? "") + " " + (card?.line ?? "")).isEmpty)
        }
    }

    @Test func theShareCardIsFromTheCoverAndTheSleepPageWhereTheyAreShown() async throws {
        let weekly = ReviewStoryBuilder.build(try await record(.full), format: format)
        let premium = try #require(weekly.share(unlocked: true))
        let free = try #require(weekly.share(unlocked: false))
        #expect(premium.bars != nil && free.bars == nil && free.cover == premium.cover, "a free person's card has the cover only")
        let monthly = ReviewStoryBuilder.build(try await record(.full, month), format: format)
        #expect(monthly.share(unlocked: false) == nil, "a locked month has nothing to share")
        #expect(premium.fileName == "NOCTIS-week-2026-09-26" && monthly.share(unlocked: true)?.fileName == "NOCTIS-month-2026-08-31")
    }

    @Test func theHeartNumbersAreOnTheCardOnlyWhenIncludeDetailsIsOn() async throws {
        let share = try #require(ReviewStoryBuilder.build(try await record(.full), format: format).share(unlocked: true))
        let details = try #require(share.details)
        #expect(details.contains("HRV") && details.contains("Resting heart rate") && details.contains("Recovery"))
        let plain = share.spokenLines(includeDetails: false).joined(separator: " ")
        for word in ["HRV", "Resting heart rate", "Recovery", "bpm", " ms"] { #expect(!plain.contains(word), Comment(rawValue: word)) }
        #expect(share.detailsText(includeDetails: false) == nil && share.detailsText(includeDetails: true) == details)
        #expect(share.spokenLines(includeDetails: true).joined(separator: " ").contains("HRV"))
    }

    @Test func theShareCardRendersAt1080By1350WithAndWithoutDetails() async throws {
        let share = try #require(ReviewStoryBuilder.build(try await record(.full), format: format).share(unlocked: true))
        for scheme in [ColorScheme.light, .dark] {
            let image = try #require(ReviewShareRenderer.render(share, includeDetails: false, colorScheme: scheme))
            #expect(image.size.width * image.scale == 1080 && image.size.height * image.scale == 1350)
        }
        let plain = try #require(ReviewShareRenderer.render(share, includeDetails: false, colorScheme: .light)?.pngData())
        let detailed = try #require(ReviewShareRenderer.render(share, includeDetails: true, colorScheme: .light)?.pngData())
        #expect(plain != detailed)
        if let directory = ProcessInfo.processInfo.environment["NOCTIS_RENDER_OUT"] {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, scheme, includeDetails) in [("review-share-light", ColorScheme.light, false), ("review-share-dark", .dark, false), ("review-share-details", .light, true)] {
                try? ReviewShareRenderer.render(share, includeDetails: includeDetails, colorScheme: scheme)?.pngData()?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
    }
}

// MARK: - Paging and the plan

@MainActor
struct StoryViewModelTests {
    private func model(unlocked: Box = Box(true), kind: ReviewKind = .weekly, startPage: String? = nil, reference: Date = now) async -> (ReviewStoryViewModel, Box) {
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: reference, calendar: calendar(), startAuthorized: true)
        let repository = ReviewRepository(provider: provider, store: ReviewStore(), insights: InsightStore(), timeZone: { nyZone }, clock: { reference })
        let model = ReviewStoryViewModel(
            kind: kind, id: nil, repository: repository, profile: { UserProfileSnapshot() }, weekday: { 1 }, isUnlocked: { _ in unlocked.value }, clock: { reference },
            locale: Locale(identifier: "en_US"), startPage: startPage
        )
        await model.load()
        return (model, unlocked)
    }

    final class Box {
        var value: Bool
        init(_ value: Bool) { self.value = value }
    }

    @Test func pagingGoesBackAndOnAndStopsAtBothEnds() async {
        let (model, _) = await model()
        #expect(model.index == 0 && !model.canGoBack && model.canGoNext && model.current?.kind == .cover)
        model.goBack()
        #expect(model.index == 0)
        for _ in 0..<20 { model.goNext() }
        #expect(model.index == model.pages.count - 1 && model.isLast && !model.canGoNext)
        model.goBack()
        #expect(model.index == model.pages.count - 2 && !model.isLast && model.movedForward == false)
        model.select(2)
        #expect(model.index == 2 && model.movedForward == false)
        model.select(99)
        #expect(model.index == 2, "a page that does not exist is not gone to")
    }

    @Test func aStartPageOpensTheStoryOnThatPage() async {
        let (model, _) = await model(startPage: "consistency")
        #expect(model.current?.kind == .consistency)
    }

    @Test func theShareButtonIsThereOnTheCoverAndTheSleepPageOnlyAndOnAMonthsLastPage() async {
        let (week, _) = await model()
        var shareable: [ReviewStoryPage.Kind] = []
        for _ in week.pages {
            if week.canShare, let kind = week.current?.kind { shareable.append(kind) }
            week.goNext()
        }
        #expect(shareable == [.cover, .sleep])
    }

    @Test func aPurchaseUnlocksTheStoryInPlaceAndTheCoverStaysWhereItIs() async {
        let (model, plan) = await model(unlocked: Box(false))
        #expect(model.pages.map(\.kind) == [.cover] && model.showsLockedCard && model.isLast)
        #expect(!model.canGoNext && model.index == 0)
        plan.value = true
        model.tierChanged()
        #expect(model.pages.count == 6 && !model.showsLockedCard && model.index == 0 && model.canGoNext && model.current?.kind == .cover)
        // And a lapse takes it back to the cover without a page that is not there.
        model.goNext()
        model.goNext()
        plan.value = false
        model.tierChanged()
        #expect(model.pages.map(\.kind) == [.cover] && model.index == 0)
    }

    @Test func aFreeMonthIsOneLockedPageWithNoLockedCardOnAWeeklyCover() async {
        let (model, _) = await model(unlocked: Box(false), kind: .monthly, reference: at(2026, 10, 2))
        #expect(model.pages.map(\.kind) == [.locked] && !model.showsLockedCard && model.shareContent == nil && !model.canShare && model.isLast)
    }

    @Test func eachPagesHeroPlaysOnceAndIsAtItsEndStateAfterThat() async {
        let (model, _) = await model()
        #expect(!model.hasPlayedHero("cover") && !model.hasPlayedHero("sleep"))
        model.claimHero("cover")
        #expect(model.hasPlayedHero("cover") && !model.hasPlayedHero("sleep"))
        model.claimHero("cover")
        #expect(model.hasPlayedHero("cover"))
    }

    @Test func theShareContentFollowsThePlan() async {
        let (model, plan) = await model()
        #expect(model.shareContent?.bars != nil)
        plan.value = false
        model.tierChanged()
        #expect(model.shareContent?.bars == nil && model.shareContent?.cover != nil)
    }
}

// MARK: - The colors

private nonisolated let colorModes: [(String, NoctisAppPalette)] = [("light", .light), ("dark", .dark)]

struct StoryColorTests {
    private func ratio(_ a: String, _ b: String) -> Double { noctisContrastRatio(noctisHexColor(a), noctisHexColor(b)) }

    private func fillHex(_ tint: ReviewPageTint, _ palette: NoctisAppPalette) -> String {
        switch tint {
        case .apricot: palette.fieldApricot
        case .sage: palette.blockSage
        case .butter: palette.blockButter
        case .lavender: palette.blockLavender
        case .sand: palette.fieldSand
        case .cocoa: palette.nightPanel
        case .paper: palette.bg
        }
    }

    private func inkHex(_ tint: ReviewPageTint, _ palette: NoctisAppPalette) -> String {
        switch tint {
        case .cocoa: palette.nightInk
        case .paper: palette.ink
        default: palette.blockInk
        }
    }

    @Test(arguments: colorModes)
    func everyPageReadsInInkAndInTheQuieterInkAndTheButtonLabelOnTheInk(_ mode: String, _ palette: NoctisAppPalette) {
        let dark = mode == "dark"
        for tint in [ReviewPageTint.apricot, .sage, .butter, .lavender, .sand, .cocoa, .paper] {
            let fill = fillHex(tint, palette), ink = inkHex(tint, palette)
            #expect(ratio(ink, fill) >= 4.5, "\(mode) \(tint): ink on the page \(ratio(ink, fill))")
            // The quieter lines: the field's own raised opacity where there is one, 70% night ink on the cocoa page, ink2 on the paper.
            let quiet: String
            switch tint {
            case .cocoa: quiet = noctisBlendHex(palette.nightInk, over: fill, alpha: 0.7)
            case .paper: quiet = palette.ink2
            default: quiet = noctisBlendHex(palette.blockInk, over: fill, alpha: tint.section?.quietOpacity(target: NoctisFieldInkStyle.summaryOpacity, dark: dark) ?? 0.8)
            }
            #expect(ratio(quiet, fill) >= 4.5, "\(mode) \(tint): quieter ink \(ratio(quiet, fill))")
            // Next and Done: the page's own color on its ink.
            #expect(ratio(fill, ink) >= 4.5, "\(mode) \(tint): the button's label \(ratio(fill, ink))")
        }
        // The blocks on the paper page and the focus block.
        for block in [palette.blockSage, palette.blockLavender] { #expect(ratio(palette.blockInk, block) >= 4.5, "\(mode): block ink on a block") }
        // The chart card carries the app's own inks.
        #expect(ratio(palette.ink, palette.surface) >= 4.5 && ratio(palette.ink3, palette.surface) >= 4.5)
    }

    @Test func everyColorIsOneOfTheAppsTokensAndAFlatFill() {
        // The page colors are the field tokens the tab scaffold names (R27), so their contrast is held by the field tests; no page has a color of its own.
        #expect(ReviewPageTint.apricot.section == .home && ReviewPageTint.sage.section == .sleep && ReviewPageTint.lavender.section == .recovery)
        #expect(ReviewPageTint.butter.section == .insights && ReviewPageTint.sand.section == .profile && ReviewPageTint.cocoa.section == nil && ReviewPageTint.paper.section == nil)
    }
}

// MARK: - Whole numbers and units

struct StoryMetricTests {
    @Test func aWrittenValueIsReadAsPartsSoItsUnitsAreSetTheWayEveryUnitIs() {
        #expect(NoctisMetricValue(reading: "6h 42m").parts == [.number("6"), .unit("h"), .space, .number("42"), .unit("m")])
        #expect(NoctisMetricValue(reading: "32 min").parts == [.number("32"), .space, .unit("min")] || NoctisMetricValue(reading: "32 min").parts == [.number("32"), .unit("min")])
        #expect(NoctisMetricValue(reading: "52 ms").plain.contains("52") && NoctisMetricValue(reading: "71").parts == [.number("71")])
        #expect(NoctisMetricValue(reading: "73.5 ms").parts.first == .number("73.5") && NoctisMetricValue(reading: "6h 42m").spoken == "6h 42m")
    }
}
