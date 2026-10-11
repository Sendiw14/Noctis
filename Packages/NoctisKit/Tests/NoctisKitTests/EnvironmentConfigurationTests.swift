import Foundation
import Testing

// QA part 2 (QA_LEDGER.md): NOCTIS.xctestplan runs the unit suite in four time zone, region, clock and first-weekday configurations. A configuration that
// did not take effect would make the whole run say nothing, so each one is asserted here against what the process really sees. Outside the plan
// (no NOCTIS_EXPECT_* variable) these tests check only that the zone, locale and calendar are readable.

struct EnvironmentConfigurationTests {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    @Test func theTimeZoneIsTheOneTheConfigurationAskedFor() {
        let current = TimeZone.current.identifier
        #expect(!current.isEmpty)
        if let expected = Self.environment["NOCTIS_EXPECT_TZ"] {
            #expect(current == expected, "TZ=\(expected) did not take effect: the process is in \(current)")
        }
    }

    @Test func theRegionIsTheOneTheConfigurationAskedFor() {
        if let expected = Self.environment["NOCTIS_EXPECT_REGION"] {
            #expect(Locale.current.region?.identifier == expected, "region \(expected): the process is in \(Locale.current.region?.identifier ?? "nil")")
        }
    }

    @Test func theClockIsTwelveOrTwentyFourHourAsAsked() {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        let is12 = template.contains("a") || template.contains("h")
        if let expected = Self.environment["NOCTIS_EXPECT_HOUR12"] {
            #expect(is12 == (expected == "1"), "the hour format is \(template)")
        }
    }

    @Test func theFirstWeekdayIsTheOneTheConfigurationAskedFor() {
        if let expected = Self.environment["NOCTIS_EXPECT_FIRST_WEEKDAY"].flatMap(Int.init) {
            #expect(Calendar.current.firstWeekday == expected, "first weekday \(Calendar.current.firstWeekday)")
        }
    }

    /// The four zones the plan names, regardless of which one the process is in: Lord Howe's daylight saving moves the clock by 30 minutes.
    @Test func theZonesTheAppMustSurviveAreKnownAndTheirShiftsAreWhatTheyAre() throws {
        let lordHowe = try #require(TimeZone(identifier: "Australia/Lord_Howe"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = lordHowe
        let summer = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12)))
        let winter = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)))
        #expect(lordHowe.daylightSavingTimeOffset(for: summer) == 1800, "a 30 minute shift")
        #expect(lordHowe.daylightSavingTimeOffset(for: winter) == 0)
        for name in ["Asia/Colombo", "America/Los_Angeles", "Pacific/Auckland"] { #expect(TimeZone(identifier: name) != nil) }
    }
}
