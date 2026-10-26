import Foundation
import SwiftData
import Testing

@testable import AppRoot
@testable import HealthProviding
@testable import NoctisCore
@testable import PremiumKit

// QA part 3, step 5 (notifications): the pending list after every kind of change, the words, and where a tap goes.

@MainActor
struct NotificationLifecycleTests {
    private let trial = ScheduledNotification(
        identifier: "noctis.trial.ending", title: "NOCTIS", body: "Your trial ends tomorrow.", components: DateComponents(hour: 9), repeats: false)

    private func expected(_ preferences: NotificationPreferences, wake: Int, bedtime: Int, tier: Tier) -> [ScheduledNotification] {
        NotificationPlan.make(preferences: preferences, wakeMinutes: wake, bedtimeCenterMinutes: bedtime, tier: tier)
    }

    /// After any sequence of changes to the preferences, the wake time, the bedtime and the plan, the pending list is exactly what a fresh build would
    /// schedule: at most three, none twice, none left over from an earlier setting, and nothing that is not NOCTIS's own touched.
    @Test func theInventoryAfterAnyRunOfChangesIsExactlyTheCurrentPlan() async {
        var rng = FuzzRandom(seed: FuzzConfig.seed &+ 11)
        for run in 0..<60 {
            let center = InMemoryNotificationCenter(authorization: .allowed, pending: [trial])
            let scheduler = NotificationScheduler(center: center)
            var preferences = NotificationPreferences()
            var wake = 7 * 60
            var bedtime = 23 * 60
            var tier = Tier.free
            for step in 0..<25 {
                switch Int.random(in: 0..<8, using: &rng) {
                case 0: preferences.morningIsOn.toggle()
                case 1: preferences.windDownIsOn.toggle()
                case 2: preferences.weeklyIsOn.toggle()
                case 3: preferences.windDownLeadMinutes = NotificationPreferences.windDownLeads.randomElement(using: &rng)!
                case 4: preferences.morningMinutesAfterWake = NotificationPreferences.morningOffsets.randomElement(using: &rng)!
                case 5: wake = Int.random(in: 0..<1440, using: &rng)
                case 6: bedtime = Int.random(in: 0..<1440, using: &rng)
                default: tier = tier == .free ? .premium : .free
                }
                if Int.random(in: 0..<10, using: &rng) == 0 { preferences.weeklyWeekday = Int.random(in: 1...7, using: &rng) }
                await scheduler.rebuild(preferences: preferences, wakeMinutes: wake, bedtimeCenterMinutes: bedtime, tier: tier)
                let want = expected(preferences, wake: wake, bedtime: bedtime, tier: tier)
                let have = center.pendingNotifications.filter { NotificationPlan.identifiers.contains($0.identifier) }
                #expect(Set(have.map(\.identifier)) == Set(want.map(\.identifier)), "run \(run) step \(step)")
                #expect(have.count == want.count && have.count <= 3, "run \(run) step \(step): \(have.count) pending")
                for item in want { #expect(have.first { $0.identifier == item.identifier } == item, "run \(run) step \(step): \(item.identifier) is stale") }
                #expect(center.pendingNotifications.contains(trial), "the trial's own notification must never be touched")
            }
        }
    }

    @Test func aTierChangeRewordsTheEveningReminderAndOnlyThat() async {
        let center = InMemoryNotificationCenter(authorization: .allowed)
        let scheduler = NotificationScheduler(center: center)
        let preferences = NotificationPreferences()
        await scheduler.rebuild(preferences: preferences, wakeMinutes: 420, bedtimeCenterMinutes: 1380, tier: .free)
        let free = Dictionary(uniqueKeysWithValues: center.pendingNotifications.map { ($0.identifier, $0) })
        await scheduler.rebuild(preferences: preferences, wakeMinutes: 420, bedtimeCenterMinutes: 1380, tier: .premium)
        let premium = Dictionary(uniqueKeysWithValues: center.pendingNotifications.map { ($0.identifier, $0) })
        #expect(free.keys == premium.keys && premium.count == 3)
        #expect(free[NoctisNotification.windDown]?.body != premium[NoctisNotification.windDown]?.body)
        #expect(free[NoctisNotification.windDown]?.components == premium[NoctisNotification.windDown]?.components)
        #expect(
            free[NoctisNotification.morningSummary] == premium[NoctisNotification.morningSummary]
                && free[NoctisNotification.weeklyReview] == premium[NoctisNotification.weeklyReview])
    }

    /// Every wording NOCTIS can send, over every plan, lead and offset: generic, one title, no number except the minutes the person chose.
    @Test func everyWordingIsGenericAndCarriesNothingFromHealth() {
        var bodies = Set<String>()
        for tier in [Tier.free, .premium] {
            for lead in NotificationPreferences.windDownLeads {
                for offset in NotificationPreferences.morningOffsets {
                    var preferences = NotificationPreferences()
                    preferences.windDownLeadMinutes = lead
                    preferences.morningMinutesAfterWake = offset
                    for item in expected(preferences, wake: 420, bedtime: 1380, tier: tier) {
                        #expect(item.title == "NOCTIS")
                        bodies.insert(item.body)
                        let digits = item.body.filter(\.isNumber)
                        if item.identifier == NoctisNotification.windDown {
                            #expect(digits == String(lead), Comment(rawValue: item.body))
                        } else {
                            #expect(digits.isEmpty, Comment(rawValue: item.body))
                        }
                        let lower = item.body.lowercased()
                        for banned in [
                            "score", "streak", "hrv", "bpm", "recovery", "slept", "hours", "%", "heart", "quality", "last night", "you missed", "don't forget",
                            "behind", "tired", "worse", "better",
                        ] {
                            #expect(!lower.contains(banned), Comment(rawValue: "\(banned) in \(item.body)"))
                        }
                        #expect(item.body.count <= 60 && item.body.hasSuffix("."), Comment(rawValue: item.body))
                    }
                }
            }
        }
        // Four wordings per lead (two plans) and two fixed ones: the whole set a person can ever receive.
        #expect(bodies.count == 2 + 2 * NotificationPreferences.windDownLeads.count, "\(bodies.sorted())")
    }

    @Test func refusedNotificationsLeaveNothingPendingWhateverChanges() async {
        let center = InMemoryNotificationCenter(authorization: .denied, pending: [trial])
        let scheduler = NotificationScheduler(center: center)
        for tier in [Tier.free, .premium] {
            let scheduled = await scheduler.rebuild(preferences: NotificationPreferences(), wakeMinutes: 420, bedtimeCenterMinutes: 1380, tier: tier)
            #expect(scheduled.isEmpty)
            #expect(await scheduler.pending().isEmpty)
        }
        #expect(center.pendingNotifications == [trial])
    }

    // MARK: Where a tap goes

    @Test(arguments: [Tier.free, .premium])
    func everyReminderTapsToItsPlace(_ tier: Tier) {
        #expect(NoctisNotification.route(for: NoctisNotification.windDown, tier: tier) == (tier == .premium ? .windDown(autostart: false) : .tonight))
        #expect(NoctisNotification.route(for: NoctisNotification.weeklyReview, tier: tier) == .review(kind: .weekly))
        #expect(NoctisNotification.route(for: NoctisNotification.morningSummary, tier: tier) == nil, "the morning summary just opens the app")
        #expect(NoctisNotification.route(for: "com.example.other", tier: tier) == nil, "a notification that is not NOCTIS's routes nowhere")
        #expect(NoctisNotification.route(for: "", tier: tier) == nil)
    }

    /// Warm: the app is running on some other tab. Cold: a fresh model, as at launch. Both end where the route says, and never start a wind-down.
    @Test(arguments: [Tier.free, .premium])
    func aTapOpensTheRightPlaceWarmAndCold(_ tier: Tier) throws {
        func model() throws -> AppModel {
            let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
            model.featureGate = FeatureGate(tier: tier)
            return model
        }
        for warm in [false, true] {
            let weekly = try model()
            if warm { weekly.selectedTab = .recovery }
            NotificationRouter(model: weekly).handle(identifier: NoctisNotification.weeklyReview)
            #expect(
                weekly.selectedTab == AppRoute.review(kind: .weekly).tab && weekly.insightsPath == [.review(kind: .weekly, id: nil)],
                "weekly, warm \(warm), \(tier)")

            let evening = try model()
            if warm { evening.selectedTab = .sleep }
            NotificationRouter(model: evening).handle(identifier: NoctisNotification.windDown)
            #expect(evening.selectedTab == .home)
            #expect(
                evening.homePath == (tier == .premium ? [.tonight, .windDown(autostart: false)] : [.tonight]),
                "evening, warm \(warm), \(tier): \(evening.homePath)")

            let morning = try model()
            if warm { morning.selectedTab = .insights }
            let before = morning.selectedTab
            NotificationRouter(model: morning).handle(identifier: NoctisNotification.morningSummary)
            #expect(morning.selectedTab == before, "the morning summary opens the app where it is")
        }
    }
}
