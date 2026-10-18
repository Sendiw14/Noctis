import Foundation
import Testing

@testable import NoctisText

// QA part 3 (QA_COVERAGE.md 4, APP_RULES.md R68): what has to be true before a translator is handed the app. The English stays the source of truth; none
// of this makes a translation (no machine translation). The numbers in the ratchets below are today's; they may go down and never up.

struct LocalizationReadinessTests {
    private nonisolated static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private nonisolated static func files(under folder: String, extension ext: String) -> [URL] {
        let base = repository.appending(path: folder, directoryHint: .isDirectory)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == ext && !$0.path.contains("/.build/") }
    }

    private nonisolated struct Catalog: @unchecked Sendable {
        let path: String
        let strings: [String: [String: Any]]
    }

    private nonisolated static func catalogs() throws -> [Catalog] {
        var found: [URL] = []
        for folder in ["Packages/NoctisKit/Sources", "App", "NoctisWidgets", "NOCTISWatch", "NOCTISWatchWidgets", "NoctisAlarmWidget"] {
            found += files(under: folder, extension: "xcstrings")
        }
        return try found.map { url in
            let data = try Data(contentsOf: url)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = (object["strings"] as? [String: [String: Any]]) ?? [:]
            return Catalog(path: url.path.replacingOccurrences(of: repository.path + "/", with: ""), strings: strings)
        }
    }

    private nonisolated static func englishValue(_ entry: [String: Any]) -> String? {
        let localizations = entry["localizations"] as? [String: Any]
        let english = localizations?["en"] as? [String: Any]
        if let unit = english?["stringUnit"] as? [String: Any] { return unit["value"] as? String }
        let plural = (english?["variations"] as? [String: Any])?["plural"] as? [String: Any]
        let other = (plural?["other"] as? [String: Any])?["stringUnit"] as? [String: Any]
        return other?["value"] as? String
    }

    // MARK: The catalogs

    @Test nonisolated func everyKeyHasAnEnglishValueAndATranslatorComment() throws {
        let all = try Self.catalogs()
        #expect(all.count >= 6, "found \(all.map(\.path))")
        var total = 0
        for catalog in all {
            for (key, entry) in catalog.strings {
                total += 1
                #expect(Self.englishValue(entry)?.isEmpty == false, "\(catalog.path): '\(key)' has no English value")
                let comment = (entry["comment"] as? String) ?? ""
                #expect(comment.count >= 20, "\(catalog.path): '\(key)' has no translator comment (or a one-word one)")
            }
        }
        #expect(total >= 300, "the scan found \(total) keys")
    }

    @Test nonisolated func everyKeyThatCountsHasPluralVariations() throws {
        // A key whose English value holds a count has `one` and `other`; a language adds the forms it needs.
        for catalog in try Self.catalogs() {
            for (key, entry) in catalog.strings where key.hasPrefix("count.") || key.hasSuffix(".spoken") {
                if key.hasPrefix("count.adjective") || key == "unit.percent.spoken" || key == "unit.perWeek.spoken" { continue }
                let english = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any]
                let plural = (english?["variations"] as? [String: Any])?["plural"] as? [String: Any]
                #expect(plural?["one"] != nil && plural?["other"] != nil, "\(key) is a count with no plural variations")
            }
        }
    }

    @Test nonisolated func everyCoachKeyTheSourcesNameIsInTheCatalog() throws {
        let catalog = try #require(try Self.catalogs().first { $0.path.hasSuffix("Coach.xcstrings") })
        // Only the keys a source asks the catalog for (`CoachCopy.string("coach.…")`, `copy("coach.…")`): "coach.history.screen" is an identifier, not a key.
        let pattern = try NSRegularExpression(pattern: #"(?:CoachCopy\.string|copy|string)\("(coach\.[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)""#)
        var named: Set<String> = []
        for folder in ["Packages/NoctisKit/Sources/CoachKit", "Packages/NoctisKit/Sources/CoachFeature"] {
            for url in Self.files(under: folder, extension: "swift") {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let range = Range(match.range(at: 1), in: text) { named.insert(String(text[range])) }
                }
            }
        }
        #expect(named.count > 20, "the scan found the keys the sources name")
        let missing = named.filter { catalog.strings[$0] == nil }
        // A prefix that a key is built from at run time ("coach.q.") is not a key.
        let real = missing.filter { name in !catalog.strings.keys.contains { $0.hasPrefix(name + ".") } }
        #expect(real.isEmpty, "named in the sources and missing from Coach.xcstrings: \(real.sorted())")
    }

    @Test nonisolated func theTranslatorsFileHasEveryCatalogKey() throws {
        let csv = try String(contentsOf: Self.repository.appending(path: "Localizations/needs-translation.csv"), encoding: .utf8)
        for catalog in try Self.catalogs() {
            for key in catalog.strings.keys {
                #expect(csv.contains("\n\(key),") || csv.contains("\n\"\(key)\","), "Localizations/needs-translation.csv has no row for \(key) (scripts/qa_localization.py csv)")
            }
        }
        #expect(csv.hasPrefix("key,english,comment,context,max_length_hint,catalog"))
    }

    // MARK: The code

    @Test func unitsAndCountsSpeakTheLanguagesPlural() {
        #expect(NoctisCount.nights(1) == "1 night")
        #expect(NoctisCount.nights(2) == "2 nights")
        #expect(NoctisCount.nights(0) == "0 nights")
        #expect(NoctisCount.minutesLeft(1) == "1 minute left")
        #expect(NoctisCount.otherNights(3) == "3 other nights")
        #expect(NoctisCount.freeQuestions(1) == "1 free question")
        #expect(NoctisCount.period(1, .month) == "1 month")
        #expect(NoctisCount.adjective(7, .day) == "7-day")
        #expect(NoctisUnit.hour.spoken(1) == "1 hour")
        #expect(NoctisUnit.minute.spoken(45) == "45 minutes")
        #expect(NoctisUnit.beatsPerMinute.spoken(52) == "52 beats per minute")
        #expect(NoctisUnit.hour.symbol == "h" && NoctisUnit.minuteShort.symbol == "min" && NoctisUnit.percent.symbol == "%")
        #expect(NoctisCount.insightsFromThisMonth(1) == "An insight from this month.")
        #expect(NoctisCount.insightsFromThisMonth(2) == "Insights from this month.")
    }

    /// The code of a Swift file with comments removed (a line comment is enough here: the scanned patterns are not in strings that hold `//`).
    private nonisolated static func code(_ text: String) -> [(number: Int, text: String)] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("//") ? nil : (index + 1, String(line))
        }
    }

    @Test nonisolated func noUnitIsSpelledOutsideTheUnitLayer() throws {
        let symbols = ["h", "m", "min", "s", "%", "bpm", "ms", "pts", "points", "/ wk"]
        let pattern = try NSRegularExpression(pattern: #"\.unit\("([^"]*)"\)|unit: "(?:%|bpm|ms|min|pts|h|m|s)""#)
        var hits: [String] = []
        for url in Self.files(under: "Packages/NoctisKit/Sources", extension: "swift") where !url.path.contains("/NoctisText/") {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for line in Self.code(text) {
                for match in pattern.matches(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)) {
                    let literal = Range(match.range(at: 1), in: line.text).map { String(line.text[$0]) }
                    if literal == nil || symbols.contains(literal ?? "") { hits.append("\(url.lastPathComponent):\(line.number)") }
                }
            }
        }
        #expect(hits.isEmpty, "a unit is spelled outside NoctisUnit: \(hits)")
    }

    @Test nonisolated func noPluralIsMadeByHandWhereACountIsPrinted() throws {
        var hits: [String] = []
        for url in Self.files(under: "Packages/NoctisKit/Sources", extension: "swift") where !url.path.contains("/NoctisText/") {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for line in Self.code(text) where line.text.contains("== 1 ? \"") && !line.text.contains("copy(") { hits.append("\(url.lastPathComponent):\(line.number)") }
        }
        #expect(hits.isEmpty, "a plural is made with `== 1 ? \"` (use NoctisCount): \(hits)")
    }

    /// Literal text in views and builders that is in no catalog: it can only go down. `scripts/qa_localization.py csv` lists every one with its file and
    /// line; moving one into a catalog (with a key and a comment) lowers the number.
    @Test nonisolated func theLiteralsNotYetInACatalogOnlyShrink() throws {
        let pattern = try NSRegularExpression(pattern: #"\b(Text|Button|Label|NoctisCTA|NoctisTextButton)\("([^"\\]{2,})"|\.(navigationTitle|accessibilityLabel|accessibilityHint)\("([^"\\]{2,})""#)
        var count = 0
        for folder in ["Packages/NoctisKit/Sources", "App", "NoctisWidgets", "NOCTISWatch", "NOCTISWatchWidgets"] {
            for url in Self.files(under: folder, extension: "swift") {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    let string = String(line)
                    count += pattern.matches(in: string, range: NSRange(string.startIndex..., in: string)).count
                }
            }
        }
        #expect(count <= 300, "\(count) literals; the baseline is 300 and may only go down")
        #expect(count >= 150, "the scan found the literals (\(count))")
    }

    @Test nonisolated func layoutNamesLeadingAndTrailingNeverLeftAndRight() throws {
        let pattern = try NSRegularExpression(pattern: #"\.padding\(\.(left|right)\b|Edge\.Set\.(left|right)|alignment: \.(left|right)\b|\.frame\(.*alignment: \.(left|right)"#)
        var hits: [String] = []
        for url in Self.files(under: "Packages/NoctisKit/Sources", extension: "swift") {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for line in Self.code(text) where pattern.firstMatch(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)) != nil {
                hits.append("\(url.lastPathComponent):\(line.number)")
            }
        }
        #expect(hits.isEmpty, "physical directions in layout (use leading and trailing): \(hits)")
    }

    /// QA part 3 (the D-RTL run): a "chevron.right" at a row's trailing edge pointed into the row in a right-to-left language, because that symbol
    /// does not mirror. The symbols that mean "on" and "back" are the forward and backward ones, which do.
    @Test nonisolated func directionalSymbolsAreForwardAndBackwardNeverRightAndLeft() throws {
        // `arrow.up.right` is an arrow that stays put as well: the one that says "opens in another app" is `arrow.up.forward` (up and to the
        // left in a right-to-left language, as in Apple's own apps).
        let pattern = try NSRegularExpression(pattern: #""(chevron\.(left|right)|arrow\.(left|right)|arrow\.up\.right)""#)
        // Trends and the sleep-need line read "steady" or "up" and mean it physically; they are not navigation.
        let allowed: Set<String> = ["ReviewStoryCharts.swift", "RecoveryHistoryContent.swift"]
        var hits: [String] = []
        for url in Self.files(under: "Packages/NoctisKit/Sources", extension: "swift") where !allowed.contains(url.lastPathComponent) {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for line in Self.code(text) where pattern.firstMatch(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)) != nil {
                hits.append("\(url.lastPathComponent):\(line.number)")
            }
        }
        #expect(hits.isEmpty, "use chevron.forward, chevron.backward, arrow.forward and arrow.up.forward, which mirror: \(hits)")
    }
}
