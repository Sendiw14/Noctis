import Foundation
import Testing

@testable import CoachKit
@testable import DesignSystem
@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import NoctisWatchKit
@testable import NoctisWidgetKit
@testable import RecoveryFeature
@testable import RecoveryKit
@testable import ReviewKit
@testable import SleepFeature
@testable import SleepKit

// QA part 3, step 1: the same fact reads the same on every surface. For each mock scenario the facts are taken from Home, Sleep Day, Recovery Today,
// the widget presentation, the Apple Watch pages and the Siri answers, all built from the same fixtures, and compared as text. A mismatch is fixed at
// its source (one formatter), never by editing one surface's string.

/// The facts a surface shows, as the person reads them (clock spaces normalised: a narrow no-break space before AM or PM is the same space).
struct SurfaceFacts: Equatable, CustomStringConvertible {
    var surface: String
    var score: Int?
    var delta: String?
    var duration: String?
    var times: String?
    var quality: Int?
    var hrv: String?
    var restingHeartRate: String?
    var factorScores: [String: Int] = [:]
    /// The same duration as it is spoken ("6 hours 42 minutes").
    var spokenDuration: String?
    /// The bedtime last night alone ("11:07 PM").
    var bedtime: String?
    /// Tonight's planned bedtime ("11:00 PM").
    var plannedBedtime: String?
    /// The seven-night average, "7h 44m", and as spoken.
    var weekAverage: String?
    var weekAverageSpoken: String?

    var description: String {
        "\(surface): score \(score.map(String.init) ?? "-"), delta \(delta ?? "-"), duration \(duration ?? "-"), times \(times ?? "-"), quality \(quality.map(String.init) ?? "-"), hrv \(hrv ?? "-"), rhr \(restingHeartRate ?? "-"), factors \(factorScores.sorted { $0.key < $1.key }), spoken \(spokenDuration ?? "-"), bedtime \(bedtime ?? "-"), planned \(plannedBedtime ?? "-"), week \(weekAverage ?? "-")"
    }
}

private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
        .replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: "\u{2013}", with: "-")
}

struct CrossSurfaceConsistencyTests {
    private let now = Fixture.date(2026, 9, 24, 10)
    private let locale = Locale(identifier: "en_US")
    private var calendar: Calendar { Fixture.calendar() }

    private nonisolated static let scenarios: [MockScenario] = [
        .full, .sleepOnly, .steady, .messyNight, .recoveryDip, .highs, .earlyBird, .weekendShift, .hrvDip, .lateBedtime,
    ]

    private func provider(_ scenario: MockScenario) -> MockHealthKitProvider {
        MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: calendar, startAuthorized: true)
    }

    private func facts(_ scenario: MockScenario) async -> [SurfaceFacts] {
        let clock = now
        let profile = UserProfileSnapshot()
        let home = await HomeRepository(provider: provider(scenario), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: profile)
        let sleep = await SleepRepository(provider: provider(scenario), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: profile)
        let recovery = await RecoveryRepository(provider: provider(scenario), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: profile)

        var all: [SurfaceFacts] = []

        // Home.
        let screen = HomeScreenBuilder.build(home, now: now, calendar: calendar, locale: locale)
        var homeFacts = SurfaceFacts(surface: "home")
        if case .scored(let scored) = screen.recovery {
            homeFacts.score = scored.score
            homeFacts.delta = scored.chip.map { plain($0.text) }
            for cell in scored.factors { homeFacts.factorScores[cell.name] = cell.score }
        }
        if let night = screen.lastNight {
            homeFacts.duration = plain(night.duration.plain)
            homeFacts.spokenDuration = plain(night.duration.spoken)
            homeFacts.times = plain(night.timeRange)
            homeFacts.bedtime = plain(night.timeRange).components(separatedBy: " - ").first
            homeFacts.quality = night.sleepQuality.flatMap { Int($0.plain) }
        }
        if let detail = screen.detail {
            for row in detail.rows {
                if row.kind == .hrv { homeFacts.hrv = plain(row.value.plain) }
                if row.kind == .restingHeartRate { homeFacts.restingHeartRate = plain(row.value.plain) }
            }
        }
        homeFacts.plannedBedtime = plain(screen.tonight.bedtime.spoken)
        homeFacts.weekAverage = screen.week.flatMap { $0.average }.map { plain($0.plain) }
        homeFacts.weekAverageSpoken = screen.week.flatMap { $0.average }.map { plain($0.spoken) }
        all.append(homeFacts)

        // Sleep Day.
        let selection = SleepSelection(night: sleep.defaultNight, range: .day)
        let sleepModel = SleepRenderModelBuilder.build(sleep, selection: selection)
        let sleepScreen = SleepScreenBuilder.build(sleep, model: sleepModel, selection: selection, now: now, calendar: calendar, locale: locale)
        if let day = sleepScreen.day {
            all.append(
                SurfaceFacts(
                    surface: "sleep", duration: plain(day.duration.plain), times: plain(day.timeRange.replacingOccurrences(of: "slept ", with: "")),
                    quality: day.ring?.score
                ))
        }

        // Recovery Today.
        let recoverySelection = RecoverySelection(segment: .today)
        let recoveryModel = RecoveryRenderModelBuilder.build(recovery, selection: recoverySelection)
        let recoveryScreen = RecoveryScreenBuilder.build(
            recovery, model: recoveryModel, selection: recoverySelection, now: now, calendar: calendar, locale: locale)
        if let today = recoveryScreen.today {
            var recoveryFacts = SurfaceFacts(surface: "recovery", score: today.scored.score, delta: today.scored.chip.map { plain($0.text) })
            for cell in today.scored.factors { recoveryFacts.factorScores[cell.name] = cell.score }
            for row in today.factors {
                if row.kind == .hrv { recoveryFacts.hrv = plain(row.value.plain) }
                if row.kind == .restingHeartRate { recoveryFacts.restingHeartRate = plain(row.value.plain) }
            }
            all.append(recoveryFacts)
        }

        // Widget, Watch, Siri: all from the one snapshot Home's data makes.
        guard let snapshot = WidgetSnapshotMaker.make(home: home, profile: profile, bedtime: nil, alarm: nil, now: now, calendar: calendar, tier: .premium)
        else { return all }
        let format = WidgetFormat(calendar: calendar, locale: locale)
        let entry = WidgetEntryModel(date: now, mode: .day, scene: .ready, snapshot: snapshot)
        let presentation = WidgetPresentationBuilder.build(entry, format: format)
        if case .day(let body) = presentation.body {
            var widgetFacts = SurfaceFacts(surface: "widget", score: body.score, delta: body.delta.map { plain($0.text) })
            for line in body.rows {
                if line.label == "HRV" { widgetFacts.hrv = plain(line.value.plain) }
                if line.label == "Resting HR" || line.label == "Rest HR" { widgetFacts.restingHeartRate = plain(line.value.plain) }
            }
            if let night = body.night {
                widgetFacts.duration = plain(night.duration.value.plain)
                widgetFacts.times = plain(night.times)
                widgetFacts.quality = night.quality.flatMap { Int($0.value.plain) }
            }
            all.append(widgetFacts)
        }

        let input = WatchPageInput(snapshot: snapshot, now: now, receivedAt: now, format: format)
        let recoveryPage = WatchPages.recovery(input)
        let sleepPage = WatchPages.sleep(input)
        let heartPage = WatchPages.heart(input)
        var watchFacts = SurfaceFacts(
            surface: "watch", score: recoveryPage.score, delta: recoveryPage.delta.map { plain($0.text).replacingOccurrences(of: " vs your usual", with: "") })
        for row in recoveryPage.factors { watchFacts.factorScores[row.name] = row.score }
        watchFacts.duration = sleepPage.duration.map { plain($0.plain) }
        watchFacts.times = sleepPage.times.map(plain)
        watchFacts.quality = sleepPage.quality.flatMap { Int($0.filter(\.isNumber)) }
        for tile in heartPage.tiles {
            if tile.kind == .hrv { watchFacts.hrv = plain(tile.value.plain) }
            if tile.kind == .restingHeartRate { watchFacts.restingHeartRate = plain(tile.value.plain) }
        }
        all.append(watchFacts)

        // Siri: the sentences the intents speak, read back into facts.
        var siri = SurfaceFacts(surface: "siri")
        let recoveryLine = WidgetSpoken.recovery(snapshot, now: now, calendar: calendar, format: format)
        let sleepLine = WidgetSpoken.sleep(snapshot, now: now, calendar: calendar, format: format)
        let bedtimeLine = WidgetSpoken.bedtime(snapshot.with(tier: .free), format: format)
        func capture(_ text: String, _ pattern: String) -> String? {
            guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
            return String(text[range])
        }
        siri.score = capture(recoveryLine, #"(?<=Your recovery is )\d+"#).flatMap(Int.init)
        siri.spokenDuration = capture(sleepLine, #"(?<=You slept ).*?(?=\.)"#).map(plain)
        siri.quality = capture(sleepLine, #"(?<=Sleep quality was )\d+"#).flatMap(Int.init)
        siri.plannedBedtime = capture(bedtimeLine, #"(?<=Your bedtime tonight is ).*?(?=\.$)"#).map(plain)
        all.append(siri)

        // Coach: the facts its templates are written from, and the sentence they make.
        let insights = await InsightsRepository(provider: provider(scenario), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: profile)
        let snapshots = CoachSnapshots(home: home, sleep: sleep, recovery: recovery, insights: insights)
        let coachFormat = HomeFormat(calendar: calendar, locale: locale)
        let context = CoachContextBuilder(format: coachFormat).build(intent: .recoveryChange, direction: nil, snapshots: snapshots, profile: profile)
        func coach(_ id: String) -> CoachFact? { context.facts.first { $0.id == id } }
        var coachFacts = SurfaceFacts(surface: "coach")
        coachFacts.score = coach("recovery.score").map { Int($0.value.rounded()) }
        coachFacts.duration = coach("sleep.duration").map { plain($0.display) }
        coachFacts.spokenDuration = coach("sleep.duration").map { plain($0.spoken) }
        coachFacts.quality = coach("sleep.quality").map { Int($0.value.rounded()) }
        coachFacts.hrv = coach("hrv.today").map { plain($0.display) }
        coachFacts.bedtime = coach("bedtime.last").map { plain($0.display) }
        coachFacts.plannedBedtime = coach("bedtime.suggested").map { plain($0.display) }
        all.append(coachFacts)
        let template = TemplateCoachProvider(locale: locale)
        if let draft = Optional(template.compose(intent: .recoveryChange, context: context)),
            let answer = CoachAnswerAssembler.assemble(draft, context: context, source: .fromYourData, locale: locale)
        {
            let words = plain([answer.summary, answer.whatChanged, answer.whatToNotice].compactMap { $0 }.joined(separator: " "))
            if let score = homeFacts.score {
                coachFacts.score = score
                if !words.contains("\(score)") { Issue.record("\(scenario): Coach's answer never says today's score \(score): \(words)") }
            }
        }

        // The share card Home makes for the same night.
        if let card = screen.share {
            var share = SurfaceFacts(surface: "share")
            share.score = card.recovery?.score
            share.duration = card.lastNight.map { plain($0.plain) }
            share.spokenDuration = card.lastNight.map { plain($0.spoken) }
            if let details = card.details {
                for part in details.components(separatedBy: " · ") {
                    if part.hasPrefix("HRV ") { share.hrv = plain(String(part.dropFirst(4))) }
                    if part.hasPrefix("Resting HR ") { share.restingHeartRate = plain(String(part.dropFirst(11))) }
                }
            }
            all.append(share)
        }

        // Reviews: the week that ends this morning, from the same samples, and the share card made from it.
        let start = now.addingTimeInterval(-40 * 86_400)
        let sleepSamples = (try? await provider(scenario).fetchSleepSamples(from: start, to: now)) ?? []
        let hrvSamples = (try? await provider(scenario).fetchHRVSamples(from: start, to: now)) ?? []
        let restingSamples = (try? await provider(scenario).fetchRestingHeartRate(from: start, to: now)) ?? []
        let nights = ReviewInputsBuilder.nights(
            sleep: sleepSamples, hrv: hrvSamples, restingHeartRate: restingSamples, needMinutes: Double(profile.needMinutes), now: now,
            timeZone: Fixture.newYork)
        if let lastMorning = home.lastNight.map({ ReviewPeriod.morning(ofNight: $0.night) }) {
            let period = ReviewPeriod.weekly(reviewDate: lastMorning.adding(days: 1))
            if case .record(let record) = ReviewEngine.build(period: period, nights: nights, needMinutes: profile.needMinutes, now: now, calendar: calendar) {
                var review = SurfaceFacts(surface: "review")
                let story = ReviewStoryBuilder.build(record, format: ReviewFormat(locale: locale))
                if let last = record.nights.last {
                    review.score = last.recoveryScore
                    review.duration = ReviewFormat.duration(Double(last.asleepMinutes))
                }
                if let cover = story.share(unlocked: true)?.cover {
                    review.weekAverage = ReviewFormat.duration(Double(cover.averageMinutes))
                    review.weekAverageSpoken = plain(cover.spokenAverage).replacingOccurrences(of: " on average", with: "")
                }
                all.append(review)
            }
        }

        return all
    }

    /// Every pair of surfaces that shows the same fact shows the same text.
    @Test(arguments: scenarios)
    func theSameFactsReadTheSameOnEverySurface(_ scenario: MockScenario) async throws {
        let all = await facts(scenario)
        func agree<T: Equatable>(_ name: String, _ value: (SurfaceFacts) -> T?) {
            let seen = all.compactMap { fact in value(fact).map { (fact.surface, $0) } }
            guard let first = seen.first else { return }
            for (surface, item) in seen where item != first.1 {
                let listing = all.map(\.description).joined(separator: "\n")
                Issue.record("\(scenario): \(name) is \(first.1) on \(first.0) but \(item) on \(surface)\n\(listing)")
            }
        }
        agree("recovery score") { $0.score }
        agree("recovery delta") { $0.delta }
        agree("duration") { $0.duration }
        agree("bedtime and wake") { $0.times }
        agree("sleep quality") { $0.quality }
        agree("HRV") { $0.hrv.map { $0.replacingOccurrences(of: " ", with: "") } }
        agree("resting heart rate") { $0.restingHeartRate.map { $0.replacingOccurrences(of: " ", with: "") } }
        // Tonight's planned bedtime: the one bedtime (Premium's window around it is the Tonight tab's and Siri's own wording, listed in POST_LAUNCH.md).
        agree("planned bedtime") { $0.plannedBedtime }
        agree("duration, spoken") { $0.spokenDuration }
        agree("bedtime last night") { $0.bedtime }
        agree("seven-night average") { $0.weekAverage }
        agree("seven-night average, spoken") { $0.weekAverageSpoken }
        // Factor scores: by name, wherever two surfaces both name the factor.
        var byName: [String: [(String, Int)]] = [:]
        for fact in all { for (name, score) in fact.factorScores { byName[name, default: []].append((fact.surface, score)) } }
        for (name, seen) in byName where Set(seen.map(\.1)).count > 1 {
            Issue.record("\(scenario): factor \(name) differs: \(seen)")
        }
        // The test must not pass by comparing nothing: the scenario with a full night has facts on at least four surfaces.
        if scenario == .full { #expect(all.count >= 4) }
    }
}
