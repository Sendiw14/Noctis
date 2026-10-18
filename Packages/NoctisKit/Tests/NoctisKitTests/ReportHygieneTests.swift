import Foundation
import Testing

// QA_REPORT.md was once published with the literal text {unver_lines} where two lists belonged. Documents that are generated must not carry an unfilled
// placeholder, and every UNVERIFIED and OPEN ledger row must be in the report.
struct ReportHygieneTests {
    private let root = RawDefaultsTests.root

    @Test func theReportHasNoUnfilledPlaceholder() throws {
        for name in ["QA_REPORT.md", "QA_LEDGER.md", "QA_COVERAGE.md", "ROADMAP.md", "POST_LAUNCH.md"] {
            let url = root.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let placeholder = try Regex(#"\{[a-z][a-z0-9_]*\}"#)
            let found = text.split(separator: "\n").filter { (try? placeholder.firstMatch(in: String($0))) != nil }
            #expect(found.isEmpty, Comment(rawValue: "\(name) has an unfilled placeholder: \(found.prefix(3).joined(separator: " / "))"))
        }
    }

    @Test func everyOpenAndUnverifiedLedgerRowIsInTheReport() throws {
        let ledger = try String(contentsOf: root.appendingPathComponent("QA_LEDGER.md"), encoding: .utf8)
        let report = try String(contentsOf: root.appendingPathComponent("QA_REPORT.md"), encoding: .utf8)
        for line in ledger.split(separator: "\n") where line.hasPrefix("| QA-") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count > 5, cells[5] == "OPEN" || cells[5] == "UNVERIFIED" else { continue }
            #expect(report.contains("**\(cells[1])**"), Comment(rawValue: "\(cells[1]) is \(cells[5]) in the ledger and missing from QA_REPORT.md (run scripts/qa_report_lines.py)"))
        }
    }
}
