import Foundation
import HealthProviding
import SwiftData
import SwiftUI
import Testing

@testable import CoachFeature
@testable import DesignSystem
@testable import NightFeature
@testable import NightKit
@testable import NoctisCore
@testable import SoundKit

// The typed preferences (APP_RULES.md R38): round-trips, what the screens may offer, the appearance the
// whole window is asked for, and the guard that keeps raw defaults out of the rest of the code.

@MainActor
struct AppPreferencesTests {
    static func suite() -> (UserDefaults, String) {
        let name = "prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func aFreshInstallHasTheDefaults() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let values = AppPreferences(defaults: defaults).values
        #expect(values.appearance == .system && values.appHaptics)
        #expect(values.windDownMinutes == 20 && values.windDownSound == nil)
        #expect(values.breathingPattern == .calm && values.breathingMinutes == 5 && !values.breathingHaptics)
        #expect(values.soundsGainPercent == 40 && values.soundsTimer == .off)
        let n = values.notifications
        #expect(n.morningIsOn && n.morningMinutesAfterWake == 15 && n.windDownIsOn && n.windDownLeadMinutes == 20)
        #expect(n.weeklyIsOn && n.weeklyWeekday == 1 && n.weeklyMinutesSinceMidnight == 540)
    }

    @Test func everyPreferenceIsKeptAndReadBack() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.update {
            $0.appearance = .dark
            $0.appHaptics = false
            $0.windDownMinutes = 30
            $0.windDownSound = .fireplace
            $0.breathingPattern = .box
            $0.breathingMinutes = 10
            $0.breathingHaptics = true
            $0.soundsGainPercent = 65
            $0.soundsTimer = .minutes45
            $0.notifications.morningIsOn = false
            $0.notifications.morningMinutesAfterWake = 45
            $0.notifications.windDownIsOn = false
            $0.notifications.windDownLeadMinutes = 30
            $0.notifications.weeklyIsOn = false
            $0.notifications.weeklyWeekday = 6
            $0.notifications.weeklyMinutesSinceMidnight = 18 * 60 + 30
        }
        let again = AppPreferences(defaults: defaults).values
        #expect(again == preferences.values)
        #expect(again.appearance == .dark && !again.appHaptics && again.windDownMinutes == 30 && again.windDownSound == .fireplace)
        #expect(again.breathingPattern == .box && again.breathingMinutes == 10 && again.breathingHaptics)
        #expect(again.soundsGainPercent == 65 && again.soundsTimer == .minutes45)
        #expect(!again.notifications.morningIsOn && again.notifications.morningMinutesAfterWake == 45)
        #expect(!again.notifications.windDownIsOn && again.notifications.windDownLeadMinutes == 30)
        #expect(!again.notifications.weeklyIsOn && again.notifications.weeklyWeekday == 6 && again.notifications.weeklyMinutesSinceMidnight == 1110)
    }

    @Test func theWindDownAndBreathingKeepTheKeysTheyAlreadyUsed() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(30, forKey: "noctis.winddown.minutes")
        defaults.set("rain", forKey: "noctis.winddown.sound")
        defaults.set("relax", forKey: "noctis.breathing.pattern")
        defaults.set(10, forKey: "noctis.breathing.minutes")
        defaults.set(true, forKey: "noctis.breathing.haptics")
        let values = AppPreferences(defaults: defaults).values
        #expect(values.windDownMinutes == 30 && values.windDownSound == .rain)
        #expect(values.breathingPattern == .relax && values.breathingMinutes == 10 && values.breathingHaptics)
        // And writing goes back to them.
        let preferences = AppPreferences(defaults: defaults)
        preferences.update { $0.windDownSound = nil }
        #expect(defaults.string(forKey: "noctis.winddown.sound") == "none")
    }

    @Test func nothingOutsideWhatTheScreensOfferIsKept() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.update {
            $0.windDownMinutes = 17
            $0.breathingMinutes = 3
            $0.soundsGainPercent = 250
            $0.notifications.morningMinutesAfterWake = 7
            $0.notifications.windDownLeadMinutes = 25
            $0.notifications.weeklyWeekday = 9
            $0.notifications.weeklyMinutesSinceMidnight = 5000
        }
        let values = preferences.values
        #expect(values.windDownMinutes == 20 && values.breathingMinutes == 5)
        #expect(values.soundsGainPercent == 100)
        #expect(values.notifications.morningMinutesAfterWake == 15 && values.notifications.windDownLeadMinutes == 20)
        #expect(values.notifications.weeklyWeekday == 1 && values.notifications.weeklyMinutesSinceMidnight == 1439)
        preferences.set(\.soundsGainPercent, to: -4)
        #expect(preferences.values.soundsGainPercent == 0)
    }

    @Test func badSavedValuesFallBackToTheDefaults() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("neon", forKey: AppPreferences.Key.appearance)
        defaults.set(11, forKey: AppPreferences.Key.windDownMinutes)
        defaults.set("thunder", forKey: AppPreferences.Key.windDownSound)
        defaults.set(42, forKey: AppPreferences.Key.soundsTimer)
        defaults.set(500, forKey: AppPreferences.Key.soundsGain)
        let values = AppPreferences(defaults: defaults).values
        #expect(values.appearance == .system && values.windDownMinutes == 20 && values.windDownSound == nil)
        #expect(values.soundsTimer == .off && values.soundsGainPercent == 100)
    }

    @Test func aChangeSaysWhatChangedAndAnUnchangedOneSaysNothing() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        var heard: [PreferenceChange] = []
        preferences.onChange = { heard.append($0) }
        preferences.set(\.appearance, to: .light)
        preferences.set(\.appearance, to: .light)
        preferences.set(\.appHaptics, to: false)
        preferences.set(\.windDownMinutes, to: 10)
        preferences.update {
            $0.soundsTimer = .minutes30
            $0.notifications.weeklyIsOn = false
        }
        preferences.set(\.breathingHaptics, to: true)
        #expect(heard == [.appearance, .haptics, .windDown, .sounds, .notifications, .breathing])
    }

    @Test func everyKeyIsUnderNoctisSoAResetClearsIt() {
        let keys = [
            AppPreferences.Key.appearance, AppPreferences.Key.appHaptics, AppPreferences.Key.windDownMinutes, AppPreferences.Key.windDownSound,
            AppPreferences.Key.breathingPattern, AppPreferences.Key.breathingMinutes, AppPreferences.Key.breathingHaptics, AppPreferences.Key.soundsGain,
            AppPreferences.Key.soundsTimer, AppPreferences.Key.morningOn, AppPreferences.Key.morningMinutes, AppPreferences.Key.windDownReminderOn,
            AppPreferences.Key.windDownLead, AppPreferences.Key.weeklyOn, AppPreferences.Key.weeklyWeekday, AppPreferences.Key.weeklyTime,
        ]
        #expect(keys.allSatisfy { $0.hasPrefix("noctis.") })
        #expect(Set(keys).count == keys.count)
    }

    @Test func allOffIsWhatNotNowMeans() {
        #expect(!NotificationPreferences.allOff.anyIsOn)
        #expect(NotificationPreferences().anyIsOn)
    }

    @Test func theSoundPlayerStartsSoundsAtThePreferredVolumeUntilTheirOwnSliderMoves() {
        let bench = PlayerBench.make()
        #expect(bench.player.state.gain(for: .rain) == 0.4)
        bench.player.setDefaultGain(0.75)
        #expect(bench.player.state.gain(for: .rain) == 0.75 && bench.player.state.gain(for: .wind) == 0.75)
        bench.player.setGain(0.2, for: .rain)
        bench.player.setDefaultGain(0.9)
        #expect(bench.player.state.gain(for: .rain) == 0.2, "a sound with its own volume keeps it")
        #expect(bench.player.state.gain(for: .wind) == 0.9)
        bench.player.setDefaultGain(3)
        #expect(bench.player.state.defaultGain == 1)
    }

    @Test func aSoundStartedFromSilenceTakesThePreferredTimerAndOneTakingOverKeepsTheRunningOne() async {
        let bench = PlayerBench.make()
        var choice = SleepTimerChoice.off
        let sounds = SoundsViewModel(player: bench.player, now: { bench.time.now }, haptic: {}, defaultTimer: { choice }, sleeper: { await bench.time.sleep($0) })
        sounds.tap(.rain)
        #expect(bench.player.state.timer == nil, "off means no timer")
        sounds.tap(.rain)
        sounds.tap(.rain)
        bench.player.stop()
        await bench.time.advance(2)
        #expect(bench.player.state.phase == .stopped)
        choice = .minutes30
        sounds.tap(.ocean)
        #expect(bench.player.state.timer?.duration == 1800.0)
        choice = .minutes60
        sounds.tap(.wind)
        #expect(bench.player.state.timer?.duration == 1800.0, "taking over from another sound leaves its timer alone")
    }

    @Test func theAppsHapticsStartOnAndCanOnlyBeQuieted() {
        #expect(NoctisHaptics.isEnabled)
        NoctisHaptics.isEnabled = false
        NoctisHaptics.selection()
        NoctisHaptics.success()
        NoctisHaptics.isEnabled = true
        #expect(NoctisHaptics.isEnabled)
    }
}

nonisolated struct AppearanceTests {
    @Test func theChoiceMapsToTheSchemeTheWindowIsAskedFor() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
        #expect(AppAppearance.allCases.map(\.title) == ["System", "Light", "Dark"])
    }

    @Test(arguments: AppAppearance.allCases)
    func onboardingStaysLightWhateverTheChoiceIs(appearance: AppAppearance) {
        #expect(AppAppearance.scheme(showingMain: false, appearance: appearance) == .light)
    }

    @Test func theMainAppFollowsTheChoiceAtOnce() {
        #expect(AppAppearance.scheme(showingMain: true, appearance: .system) == nil)
        #expect(AppAppearance.scheme(showingMain: true, appearance: .light) == .light)
        #expect(AppAppearance.scheme(showingMain: true, appearance: .dark) == .dark)
    }
}

// MARK: - The reminders' schedule

nonisolated struct NotificationPlanTests {
    static func plan(wake: Int = 7 * 60, center: Int = 23 * 60, tier: Tier = .premium, _ change: (inout NotificationPreferences) -> Void = { _ in }) -> [ScheduledNotification] {
        var preferences = NotificationPreferences()
        change(&preferences)
        return NotificationPlan.make(preferences: preferences, wakeMinutes: wake, bedtimeCenterMinutes: center, tier: tier)
    }

    static func time(_ plan: [ScheduledNotification], _ identifier: String) -> (hour: Int, minute: Int, weekday: Int?)? {
        guard let item = plan.first(where: { $0.identifier == identifier }) else { return nil }
        return (item.components.hour ?? -1, item.components.minute ?? -1, item.components.weekday)
    }

    @Test func theDefaultPlanIsTheMorningTheWindDownAndTheWeek() {
        let plan = Self.plan()
        #expect(plan.map(\.identifier) == [NoctisNotification.morningSummary, NoctisNotification.windDown, NoctisNotification.weeklyReview])
        let morning = Self.time(plan, NoctisNotification.morningSummary)
        #expect(morning?.hour == 7 && morning?.minute == 15, "wake plus 15")
        let windDown = Self.time(plan, NoctisNotification.windDown)
        #expect(windDown?.hour == 22 && windDown?.minute == 40, "the centre less 20")
        let weekly = Self.time(plan, NoctisNotification.weeklyReview)
        #expect(weekly?.weekday == 1 && weekly?.hour == 9 && weekly?.minute == 0, "Sunday 9:00")
        #expect(plan.allSatisfy { $0.repeats })
    }

    @Test(arguments: NotificationPreferences.windDownLeads)
    func theWindDownComesItsLeadBeforeTheCentre(lead: Int) {
        let plan = Self.plan(center: 23 * 60 + 10) { $0.windDownLeadMinutes = lead }
        let windDown = Self.time(plan, NoctisNotification.windDown)
        let minutes = (windDown?.hour ?? 0) * 60 + (windDown?.minute ?? 0)
        #expect(minutes == 23 * 60 + 10 - lead)
        #expect(plan.first { $0.identifier == NoctisNotification.windDown }?.body == "Your wind-down window starts in \(lead) minutes.")
        #expect(Self.plan(center: 23 * 60 + 10, tier: .free) { $0.windDownLeadMinutes = lead }.first { $0.identifier == NoctisNotification.windDown }?.body == "Your bedtime window starts in \(lead) minutes.")
    }

    @Test(arguments: NotificationPreferences.morningOffsets)
    func theMorningSummaryComesItsOffsetAfterWaking(offset: Int) {
        let plan = Self.plan(wake: 6 * 60 + 30) { $0.morningMinutesAfterWake = offset }
        let morning = Self.time(plan, NoctisNotification.morningSummary)
        #expect((morning?.hour ?? 0) * 60 + (morning?.minute ?? 0) == 6 * 60 + 30 + offset)
    }

    @Test func aTimeThatCrossesMidnightWrapsIntoTheDay() {
        // Waking at 11:50 PM, a summary 30 minutes later is 12:20 AM.
        let late = Self.plan(wake: 23 * 60 + 50) { $0.morningMinutesAfterWake = 30 }
        let morning = Self.time(late, NoctisNotification.morningSummary)
        #expect(morning?.hour == 0 && morning?.minute == 20)
        // A bedtime at 12:10 AM with a 30 minute lead is 11:40 PM, the evening before.
        let early = Self.plan(center: 10) { $0.windDownLeadMinutes = 30 }
        let windDown = Self.time(early, NoctisNotification.windDown)
        #expect(windDown?.hour == 23 && windDown?.minute == 40)
        let farther = Self.plan(center: 10) { $0.windDownLeadMinutes = 45 }
        #expect(Self.time(farther, NoctisNotification.windDown)?.hour == 23 && Self.time(farther, NoctisNotification.windDown)?.minute == 25)
        // And a bedtime exactly at midnight.
        let midnight = Self.plan(center: 0) { $0.windDownLeadMinutes = 10 }
        #expect(Self.time(midnight, NoctisNotification.windDown)?.hour == 23 && Self.time(midnight, NoctisNotification.windDown)?.minute == 50)
    }

    @Test func minutesOutsideTheDayAreWrapped() {
        #expect(NotificationPlan.clock(-30).hour == 23 && NotificationPlan.clock(-30).minute == 30)
        #expect(NotificationPlan.clock(1440 + 75).hour == 1 && NotificationPlan.clock(1440 + 75).minute == 15)
        #expect(NotificationPlan.clock(0).hour == 0 && NotificationPlan.clock(0).minute == 0)
    }

    @Test func aSwitchedOffReminderIsNotInThePlan() {
        let noMorning = Self.plan { $0.morningIsOn = false }
        #expect(noMorning.map(\.identifier) == [NoctisNotification.windDown, NoctisNotification.weeklyReview])
        #expect(Self.plan { $0 = .allOff }.isEmpty)
        let weeklyOnly = Self.plan {
            $0 = .allOff
            $0.weeklyIsOn = true
            $0.weeklyWeekday = 6
            $0.weeklyMinutesSinceMidnight = 18 * 60 + 15
        }
        #expect(weeklyOnly.count == 1 && weeklyOnly[0].components.weekday == 6 && weeklyOnly[0].components.hour == 18 && weeklyOnly[0].components.minute == 15)
    }

    @Test func theWordsAreGenericAndCarryNoValueFromHealth() {
        let plan = Self.plan()
        #expect(plan.allSatisfy { $0.title == "NOCTIS" })
        #expect(plan.map(\.body) == ["Your morning summary is ready.", "Your wind-down window starts in 20 minutes.", "Your weekly review is ready."])
        #expect(Self.plan(tier: .free).map(\.body) == ["Your morning summary is ready.", "Your bedtime window starts in 20 minutes.", "Your weekly review is ready."])
        for item in plan where item.identifier != NoctisNotification.windDown {
            #expect(!item.body.contains(where: { $0.isNumber }), Comment(rawValue: item.body))
        }
        for banned in ["score", "streak", "hrv", "bpm", "recovery", "slept", "hours"] {
            #expect(!plan.map(\.body).joined().lowercased().contains(banned), Comment(rawValue: banned))
        }
    }

    // MARK: Daylight saving

    static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date(timeIntervalSince1970: 0)
    }

    static func clock(_ date: Date) -> (month: Int, day: Int, hour: Int, minute: Int) {
        let c = newYork.dateComponents([.month, .day, .hour, .minute], from: date)
        return (c.month ?? 0, c.day ?? 0, c.hour ?? -1, c.minute ?? -1)
    }

    @Test func aReminderKeepsItsWallClockTimeAcrossTheSpringClockChange() throws {
        // 7:15 AM: the day clocks go forward (Sunday 8 March 2026) it is still 7:15 on the wall, 23 hours on.
        let morning = try #require(Self.plan().first { $0.identifier == NoctisNotification.morningSummary })
        let saturday = try #require(NotificationPlan.nextFire(of: morning, after: Self.date(2026, 3, 7, 8), calendar: Self.newYork))
        let sunday = try #require(NotificationPlan.nextFire(of: morning, after: saturday, calendar: Self.newYork))
        #expect(Self.clock(saturday).day == 8 && Self.clock(saturday).hour == 7 && Self.clock(saturday).minute == 15)
        #expect(Self.clock(sunday).day == 9 && Self.clock(sunday).hour == 7 && Self.clock(sunday).minute == 15)
        #expect(sunday.timeIntervalSince(saturday) == 24 * 3600, "the next day is a full day later, the clock change is already past")
        let before = try #require(NotificationPlan.nextFire(of: morning, after: Self.date(2026, 3, 6, 8), calendar: Self.newYork))
        #expect(saturday.timeIntervalSince(before) == 23 * 3600, "the day of the change is 23 hours, and the reminder stays at 7:15")
    }

    @Test func aReminderSetForATimeTheClockSkipsFiresAtTheNextTimeThatExists() throws {
        // 2:30 AM does not exist on 8 March 2026 in New York.
        let skipped = ScheduledNotification(identifier: "x", title: "", body: "", components: NotificationPlan.clock(2 * 60 + 30))
        let fire = try #require(NotificationPlan.nextFire(of: skipped, after: Self.date(2026, 3, 7, 12), calendar: Self.newYork))
        #expect(Self.clock(fire).day == 8 && Self.clock(fire).hour == 3)
        let next = try #require(NotificationPlan.nextFire(of: skipped, after: fire, calendar: Self.newYork))
        #expect(Self.clock(next).day == 9 && Self.clock(next).hour == 2 && Self.clock(next).minute == 30, "and back to 2:30 the day after")
    }

    @Test func aReminderSetForATimeTheClockRepeatsFiresOnceOnTheFirstPass() throws {
        // 1:30 AM happens twice on 1 November 2026.
        let repeated = ScheduledNotification(identifier: "x", title: "", body: "", components: NotificationPlan.clock(60 + 30))
        let first = try #require(NotificationPlan.nextFire(of: repeated, after: Self.date(2026, 10, 31, 23), calendar: Self.newYork))
        #expect(Self.clock(first).day == 1 && Self.clock(first).hour == 1 && Self.clock(first).minute == 30)
        #expect(Self.newYork.timeZone.isDaylightSavingTime(for: first), "the first 1:30, still on summer time")
        let second = try #require(NotificationPlan.nextFire(of: repeated, after: first, calendar: Self.newYork))
        #expect(Self.clock(second).day == 2 && Self.clock(second).hour == 1 && Self.clock(second).minute == 30, "not a second time that night")
    }

    @Test func theWeeklyReviewStaysOnItsWeekdayAcrossTheChange() throws {
        let weekly = try #require(Self.plan().first { $0.identifier == NoctisNotification.weeklyReview })
        let first = try #require(NotificationPlan.nextFire(of: weekly, after: Self.date(2026, 3, 1, 10), calendar: Self.newYork))
        let second = try #require(NotificationPlan.nextFire(of: weekly, after: first, calendar: Self.newYork))
        #expect(Self.clock(first).month == 3 && Self.clock(first).day == 8 && Self.clock(first).hour == 9, "Sunday 8 March, 9:00 on the wall")
        #expect(Self.clock(second).day == 15 && Self.clock(second).hour == 9)
        #expect(Self.newYork.component(.weekday, from: second) == 1)
        #expect(second.timeIntervalSince(first) == 7 * 24 * 3600)
    }
}

// MARK: - The scheduler and the coordinator

struct NotificationSchedulerTests {
    static func preferences(_ change: (inout NotificationPreferences) -> Void = { _ in }) -> NotificationPreferences {
        var result = NotificationPreferences()
        change(&result)
        return result
    }

    @Test func allowedNotificationsGetTheThreeRemindersAndNoDuplicates() async {
        let center = InMemoryNotificationCenter(authorization: .allowed)
        let scheduler = NotificationScheduler(center: center)
        let first = await scheduler.rebuild(preferences: Self.preferences(), wakeMinutes: 420, bedtimeCenterMinutes: 1380)
        #expect(first.count == 3)
        _ = await scheduler.rebuild(preferences: Self.preferences(), wakeMinutes: 420, bedtimeCenterMinutes: 1380)
        #expect(Set(center.pendingNotifications.map(\.identifier)) == Set(NotificationPlan.identifiers))
        #expect(center.pendingNotifications.count == 3, "the same reminders again, not twice")
        #expect(center.removals.last == NotificationPlan.identifiers, "each rebuild clears the three it owns first")
    }

    @Test func aChangeOfWakeTimeMovesTheReminders() async {
        let center = InMemoryNotificationCenter(authorization: .allowed)
        let scheduler = NotificationScheduler(center: center)
        await scheduler.rebuild(preferences: Self.preferences(), wakeMinutes: 7 * 60, bedtimeCenterMinutes: 23 * 60)
        let before = center.pendingNotifications.first { $0.identifier == NoctisNotification.morningSummary }?.components
        #expect(before?.hour == 7 && before?.minute == 15)
        await scheduler.rebuild(preferences: Self.preferences(), wakeMinutes: 6 * 60 + 30, bedtimeCenterMinutes: 22 * 60 + 30)
        let after = center.pendingNotifications.first { $0.identifier == NoctisNotification.morningSummary }?.components
        #expect(after?.hour == 6 && after?.minute == 45)
        let windDown = center.pendingNotifications.first { $0.identifier == NoctisNotification.windDown }?.components
        #expect(windDown?.hour == 22 && windDown?.minute == 10)
    }

    @Test func aSwitchedOffReminderIsRemovedAndTheOthersStay() async {
        let center = InMemoryNotificationCenter(authorization: .allowed)
        let scheduler = NotificationScheduler(center: center)
        await scheduler.rebuild(preferences: Self.preferences(), wakeMinutes: 420, bedtimeCenterMinutes: 1380)
        await scheduler.rebuild(preferences: Self.preferences { $0.windDownIsOn = false }, wakeMinutes: 420, bedtimeCenterMinutes: 1380)
        #expect(Set(center.pendingNotifications.map(\.identifier)) == [NoctisNotification.morningSummary, NoctisNotification.weeklyReview])
        #expect(await scheduler.pending().sorted() == [NoctisNotification.morningSummary, NoctisNotification.weeklyReview].sorted())
    }

    @Test(arguments: [NotificationAuthorization.denied, .notDetermined])
    func withoutPermissionNothingIsScheduledAndNothingOfOursIsLeftPending(status: NotificationAuthorization) async {
        let stale = ScheduledNotification(identifier: NoctisNotification.windDown, title: "", body: "", components: NotificationPlan.clock(60))
        let center = InMemoryNotificationCenter(authorization: status, pending: [stale])
        let scheduler = NotificationScheduler(center: center)
        let scheduled = await scheduler.rebuild(preferences: Self.preferences(), wakeMinutes: 420, bedtimeCenterMinutes: 1380)
        #expect(scheduled.isEmpty && center.pendingNotifications.isEmpty)
    }

    @Test func itNeverTouchesAnyOtherPendingNotification() async {
        let trial = ScheduledNotification(identifier: "noctis.notification.trialEnding", title: "T", body: "B", components: NotificationPlan.clock(600), repeats: false)
        let center = InMemoryNotificationCenter(authorization: .allowed, pending: [trial])
        let scheduler = NotificationScheduler(center: center)
        await scheduler.rebuild(preferences: Self.preferences(), wakeMinutes: 420, bedtimeCenterMinutes: 1380)
        await scheduler.rebuild(preferences: .allOff, wakeMinutes: 420, bedtimeCenterMinutes: 1380)
        #expect(center.pendingNotifications.map(\.identifier) == ["noctis.notification.trialEnding"])
        #expect(center.removals.allSatisfy { Set($0) == Set(NotificationPlan.identifiers) })
        #expect(await scheduler.pending().isEmpty)
    }

    @Test func theSystemQuestionIsAskedOnceAndTheAnswerIsKept() async {
        let center = InMemoryNotificationCenter(authorization: .notDetermined, answer: false)
        let scheduler = NotificationScheduler(center: center)
        #expect(await scheduler.authorization() == .notDetermined)
        #expect(await scheduler.requestAuthorization() == false)
        #expect(await scheduler.authorization() == .denied)
        #expect(await scheduler.requestAuthorization() == false, "it never asks twice")
        let yes = InMemoryNotificationCenter(authorization: .notDetermined, answer: true)
        #expect(await NotificationScheduler(center: yes).requestAuthorization())
        #expect(yes.pendingNotifications.isEmpty)
    }
}

@MainActor
struct NotificationCoordinatorTests {
    struct Bench {
        let coordinator: NotificationCoordinator
        let preferences: AppPreferences
        let center: InMemoryNotificationCenter
        let defaults: UserDefaults
        let name: String
    }

    static func make(
        authorization: NotificationAuthorization = .allowed, answer: Bool = true,
        profile: @escaping () -> UserProfileSnapshot = { UserProfileSnapshot(typicalWakeMinutes: 7 * 60, needMinutes: 8 * 60) },
        center: @escaping (Int, Int) async -> Int = { wake, need in ((wake - need) % 1440 + 1440) % 1440 }
    ) -> Bench {
        let name = "coordinator-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let preferences = AppPreferences(defaults: defaults)
        let notificationCenter = InMemoryNotificationCenter(authorization: authorization, answer: answer)
        let coordinator = NotificationCoordinator(
            scheduler: NotificationScheduler(center: notificationCenter), preferences: preferences, profile: profile, bedtimeCenter: center
        )
        return Bench(coordinator: coordinator, preferences: preferences, center: notificationCenter, defaults: defaults, name: name)
    }

    @Test func itBuildsTheRemindersFromTheProfileAndTheCentre() async {
        let bench = Self.make()
        defer { bench.defaults.removePersistentDomain(forName: bench.name) }
        bench.coordinator.reschedule()
        await bench.coordinator.settled()
        let windDown = bench.center.pendingNotifications.first { $0.identifier == NoctisNotification.windDown }?.components
        #expect(windDown?.hour == 22 && windDown?.minute == 40, "7:00 less 8 hours is 11:00 PM; 20 minutes before")
        #expect(bench.coordinator.scheduled.count == 3 && bench.coordinator.authorization == .allowed)
    }

    @Test func aWakeTimeGivenExplicitlyWinsOverTheProfile() async {
        let bench = Self.make()
        defer { bench.defaults.removePersistentDomain(forName: bench.name) }
        bench.coordinator.reschedule(wakeMinutes: 6 * 60, needMinutes: 7 * 60)
        await bench.coordinator.settled()
        let morning = bench.center.pendingNotifications.first { $0.identifier == NoctisNotification.morningSummary }?.components
        #expect(morning?.hour == 6 && morning?.minute == 15)
        let windDown = bench.center.pendingNotifications.first { $0.identifier == NoctisNotification.windDown }?.components
        #expect(windDown?.hour == 22 && windDown?.minute == 40, "6:00 less 7 hours is 11:00 PM")
    }

    @Test func theLastRebuildWinsEvenIfAnEarlierOneIsSlow() async {
        var calls = 0
        var secondAnswered = false
        let bench = Self.make(center: { _, _ in
            calls += 1
            // The first answer comes after the second, whatever the machine is doing.
            if calls == 1 { _ = await waitFor { secondAnswered }; return 23 * 60 }
            secondAnswered = true
            return 22 * 60
        })
        defer { bench.defaults.removePersistentDomain(forName: bench.name) }
        bench.coordinator.reschedule()
        bench.coordinator.reschedule()
        await bench.coordinator.settled()
        let windDown = bench.center.pendingNotifications.first { $0.identifier == NoctisNotification.windDown }?.components
        #expect(windDown?.hour == 21 && windDown?.minute == 40, "the second centre (10:00 PM), not the slow first one")
        #expect(calls == 2)
    }

    @Test func deniedNotificationsScheduleNothingAndSayWhy() async {
        let bench = Self.make(authorization: .denied)
        defer { bench.defaults.removePersistentDomain(forName: bench.name) }
        bench.coordinator.reschedule()
        await bench.coordinator.settled()
        #expect(bench.center.pendingNotifications.isEmpty && bench.coordinator.authorization == .denied && bench.coordinator.scheduled.isEmpty)
    }

    @Test func grantingPermissionBuildsTheRemindersAtOnce() async {
        let bench = Self.make(authorization: .notDetermined, answer: true)
        defer { bench.defaults.removePersistentDomain(forName: bench.name) }
        let granted = await bench.coordinator.requestAuthorization()
        await bench.coordinator.settled()
        #expect(granted && bench.coordinator.authorization == .allowed && bench.center.pendingNotifications.count == 3)
    }

    @Test func refusingPermissionLeavesNothingScheduled() async {
        let bench = Self.make(authorization: .notDetermined, answer: false)
        defer { bench.defaults.removePersistentDomain(forName: bench.name) }
        let granted = await bench.coordinator.requestAuthorization()
        await bench.coordinator.settled()
        #expect(!granted && bench.coordinator.authorization == .denied && bench.center.pendingNotifications.isEmpty)
    }

    @Test func allowingNotificationsInSettingsIsNoticedWhenTheAppComesBack() async {
        let bench = Self.make(authorization: .denied)
        defer { bench.defaults.removePersistentDomain(forName: bench.name) }
        await bench.coordinator.refreshAuthorization()
        #expect(bench.coordinator.authorization == .denied)
        bench.center.setAuthorization(.allowed)
        await bench.coordinator.refreshAuthorization()
        bench.coordinator.reschedule()
        await bench.coordinator.settled()
        #expect(bench.coordinator.authorization == .allowed && bench.center.pendingNotifications.count == 3)
    }

    @Test func aChangeOfPreferenceRebuildsThroughTheHook() async {
        let bench = Self.make()
        defer { bench.defaults.removePersistentDomain(forName: bench.name) }
        let coordinator = bench.coordinator
        bench.preferences.onChange = { change in if change == .notifications { coordinator.reschedule() } }
        bench.preferences.update { $0.notifications.windDownLeadMinutes = 45 }
        await coordinator.settled()
        let windDown = bench.center.pendingNotifications.first { $0.identifier == NoctisNotification.windDown }?.components
        #expect(windDown?.hour == 22 && windDown?.minute == 15, "11:00 PM less 45")
        bench.preferences.update { $0.notifications.weeklyIsOn = false }
        await coordinator.settled()
        #expect(bench.center.pendingNotifications.count == 2)
        bench.preferences.update { $0.appearance = .dark }
        await coordinator.settled()
        #expect(bench.center.pendingNotifications.count == 2, "a change that is not about reminders leaves them be")
    }

    @Test func theProfileChangingTellsWhoeverListens() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        var told = 0
        model.onProfileChange = { told += 1 }
        model.updateProfile { $0.typicalWakeMinutes = 6 * 60 }
        #expect(told == 1)
        model.updateProfile { $0.needMinutes = 7 * 60 + 30 }
        #expect(told == 2 && model.profile.needMinutes == 450)
    }
}

// MARK: - Raw defaults live in one file

nonisolated struct RawDefaultsTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The code of a file: no comment lines and no trailing comments.
    static func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { return "" }
            if let range = line.range(of: " //") { return String(line[..<range.lowerBound]) }
            return String(line)
        }.joined(separator: "\n")
    }

    static func swiftFiles(under folders: [String]) -> [(path: String, text: String)] {
        var result: [(String, String)] = []
        for folder in folders {
            let base = root.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                if let text = try? String(contentsOf: url, encoding: .utf8) { result.append((url.path.replacingOccurrences(of: root.path + "/", with: ""), text)) }
            }
        }
        return result
    }

    @Test func onlyTheWrapperNamesTheSharedUserDefaults() {
        let files = Self.swiftFiles(under: ["Packages/NoctisKit/Sources", "App"])
        #expect(files.count > 150, "the scan found the sources")
        // Regular expressions with a boundary, so `NoctisUserDefaults.standard` (the wrapper's handle) is not a hit.
        let forbidden = [#"(^|[^A-Za-z_])UserDefaults\.standard"#, #"UserDefaults\s*=\s*\.standard"#, #"\?\?\s*\.standard"#, "@AppStorage", "@SceneStorage"]
        for file in files where file.path != "Packages/NoctisKit/Sources/NoctisCore/AppPreferences.swift" {
            let code = Self.code(file.text)
            for pattern in forbidden {
                #expect(code.range(of: pattern, options: .regularExpression) == nil, Comment(rawValue: "\(file.path) uses \(pattern)"))
            }
        }
    }

    @Test func theWrapperItselfIsTheOnePlaceItIsNamed() throws {
        let wrapper = try String(contentsOf: Self.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisCore/AppPreferences.swift"), encoding: .utf8)
        #expect(Self.code(wrapper).contains("static let standard: UserDefaults = .standard"))
        #expect(wrapper.contains("enum NoctisUserDefaults"))
    }
}

// MARK: - Destructive actions (APP_RULES.md R37)

/// Deleting anything the person wrote or kept always takes a second, deliberate step, and says exactly what
/// goes and what does not.
nonisolated struct DestructiveActionsTests {
    @Test func noDeleteIsEverOneSwipeAway() {
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources"]) {
            #expect(!RawDefaultsTests.code(file.text).contains("allowsFullSwipe: true"), Comment(rawValue: "\(file.path) lets a full swipe delete"))
        }
    }

    @Test func everyDeleteAllSaysWhatGoesWhatStaysAndThatItCannotBeUndone() {
        let messages = [
            ("Coach history", CoachHistoryContent.deleteAllMessage),
            ("Journal", ReflectCopy.deleteAllMessage),
        ]
        for (name, message) in messages {
            #expect(message.contains("can't be undone"), Comment(rawValue: "\(name) does not say it can't be undone"))
            #expect(message.contains("not affected"), Comment(rawValue: "\(name) does not say what is not deleted"))
            #expect(message.contains("this iPhone"), Comment(rawValue: "\(name) does not say where it goes from"))
        }
    }

    @Test func everyDestructiveDialogIsOnItsOwnButtonAndHasACancel() {
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources"]) {
            let code = RawDefaultsTests.code(file.text)
            guard code.contains("confirmationDialog") else { continue }
            #expect(code.contains("role: .cancel"), Comment(rawValue: "\(file.path) has a confirmation dialog with no Cancel"))
            #expect(code.contains("role: .destructive"), Comment(rawValue: "\(file.path) has a confirmation dialog with nothing destructive in it"))
        }
    }
}
