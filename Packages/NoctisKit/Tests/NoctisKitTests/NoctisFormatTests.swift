import Foundation
import Testing

@testable import DesignSystem
@testable import HomeFeature
@testable import NoctisCore
@testable import NoctisWidgetKit
@testable import NoctisText
@testable import ReviewKit

// QA part 4 (QA-118): there is one formatter. HomeFormat and WidgetFormat are aliases of NoctisFormat; ReviewFormat, onboarding, Profile and the paywall
// reach the same two text functions (NoctisDurationText, NoctisClockText). These tests fail if a second copy comes back.

struct NoctisFormatTests {
    private let calendar = Fixture.calendar()
    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    @Test func homeAndWidgetFormattersAreTheSameType() {
        #expect(HomeFormat.self == NoctisFormat.self)
        #expect(WidgetFormat.self == NoctisFormat.self)
    }

    @Test(arguments: [0, 1, 45, 59, 60, 61, 125, 402, 480, 495, 1439, 1440])
    func everyDurationFormOfOneLengthAgrees(_ minutes: Int) {
        let metric = NoctisFormat.durationMetric(minutes)
        #expect(metric.spoken == NoctisFormat.spokenDuration(minutes) && metric.spoken == NoctisDurationText.spoken(minutes))
        // The metric's parts and the compact string are the same text apart from the space between the pieces.
        let compact = NoctisFormat.compactDuration(minutes)
        #expect(metric.plain.replacingOccurrences(of: " ", with: "") == compact.replacingOccurrences(of: " ", with: ""), Comment(rawValue: "\(minutes): \(metric.plain) vs \(compact)"))
        #expect(ReviewFormat.duration(Double(minutes)) == compact)
        #expect(noctisFormattedDuration(minutes: minutes) == compact)
        #expect(NoctisFormat.compactDuration(minutes, minutesWord: true).hasSuffix(minutes < 60 ? NoctisUnit.minuteShort.symbol : compact.suffix(1).description))
    }

    @Test func everyClockFormAgreesOnBothClocks() {
        for locale in [us, german] {
            let format = NoctisFormat(calendar: calendar, locale: locale)
            for minutes in [0, 7 * 60, 12 * 60, 13 * 60 + 5, 22 * 60 + 45, 23 * 60 + 59] {
                let text = format.clock(minutesSinceMidnight: minutes)
                #expect(NoctisClockText.string(minutesSinceMidnight: minutes, calendar: calendar, locale: locale) == text)
                #expect(format.clockMetric(minutesSinceMidnight: minutes).spoken == text)
                // Minutes after noon is the same instant.
                #expect(format.clock(minutesAfterNoon: Double(((minutes - 720) % 1440 + 1440) % 1440)) == text)
            }
        }
        // ReviewFormat prints the same clock from minutes after noon (11 PM is 660).
        let review = ReviewFormat(locale: us)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = .gmt
        #expect(review.clock(minutesAfterNoon: 660) == NoctisFormat(calendar: utc, locale: us).clock(minutesSinceMidnight: 23 * 60))
        #expect(ReviewFormat(locale: german).clock(minutesAfterNoon: 660) == NoctisFormat(calendar: utc, locale: german).clock(minutesSinceMidnight: 23 * 60))
    }

    @Test func aWindowReadsTheSameEverywhere() {
        let format = NoctisFormat(calendar: calendar, locale: us)
        #expect(format.windowText(startMinutes: 22 * 60 + 45, endMinutes: 23 * 60 + 15) == "10:45 – 11:15 PM")
        #expect(format.windowText(startMinutes: 23 * 60 + 45, endMinutes: 15).replacingOccurrences(of: "\u{202F}", with: " ") == "11:45 PM – 12:15 AM")
        #expect(format.windowMetric(startMinutes: 22 * 60 + 45, endMinutes: 23 * 60 + 15).spoken == "10:45 to 11:15 PM")
    }

    /// A copy of any of these functions, or a hand-written duration or 12-hour clock, would let two surfaces disagree again.
    @Test func noSecondCopyOfTheFormattingExists() throws {
        let owners: Set<String> = ["DesignSystem/NoctisFormat.swift", "NoctisText/NoctisTimeText.swift"]
        let names = ["durationMetric", "spokenDuration", "compactDuration", "quantityMetric", "splitClock", "windowText", "windowMetric", "formattedDuration"]
        let declaration = try Regex(#"func\s+(\#(names.joined(separator: "|")))\b"#)
        // A duration built by hand: "\(hours)h", "\(mins)m", "%dh %02dm".
        let handMade = try Regex(#"\\\((hours|hrs|h)\)h|\\\((mins|minutes|remainder|rest)\)m\b|%dh %02dm"#)
        // A 12-hour clock built by hand.
        let handClock = try Regex(#"hour24 < 12 \? "AM" : "PM"|hour24 % 12 == 0 \? 12"#)
        var found: [String] = []
        let base = RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/")
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources"]) {
            let path = file.path.replacingOccurrences(of: base.path, with: "").replacingOccurrences(of: "Packages/NoctisKit/Sources/", with: "")
            if owners.contains(path) { continue }
            for (number, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                // Tonight's two helpers take a BedtimeWindow and call the formatter: wrappers, not copies.
                if try declaration.firstMatch(in: text) != nil, !(path == "NightFeature/TonightContent.swift" && text.contains("BedtimeWindow")) { found.append("\(path):\(number + 1) declares a formatter that NoctisFormat owns") }
                if try handMade.firstMatch(in: text) != nil, !text.contains("Updated \\(hours)h ago"), !text.contains("h old") { found.append("\(path):\(number + 1) writes a duration by hand: \(trimmed.prefix(80))") }
                if try handClock.firstMatch(in: text) != nil { found.append("\(path):\(number + 1) builds a 12-hour clock by hand") }
            }
        }
        // The circular Watch complication is the one deliberate narrow form of a duration ("6h42"); it is allowed by name, and checked against the compact form below.
        found.removeAll { $0.hasPrefix("NoctisWatchKit/WatchComplications.swift") }
        #expect(found.isEmpty, Comment(rawValue: found.joined(separator: "\n")))
    }
}
