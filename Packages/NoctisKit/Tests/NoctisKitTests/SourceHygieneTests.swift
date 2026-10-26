import Foundation
import Testing

// QA part 1 (QA_LEDGER.md): what the shipped source may not contain. The scans read the real files (comments and string contents removed by
// `SwiftCodeScanner`, so a word in a sentence is not a call), so a new `print(`, force unwrap or `fatalError` fails here until it is removed or
// listed below with the reason it cannot go wrong.

// MARK: - The scanner

/// Replaces the contents of comments and string literals with spaces (newlines kept, interpolations kept as code), so a scan sees only code and
/// every line of the result is the line of the file.
nonisolated enum SwiftCodeScanner {
    private enum Mode {
        case code(depth: Int)
        case string(hashes: Int, multiline: Bool)
    }

    static func codeOnly(_ source: String) -> String {
        let chars = Array(source)
        let count = chars.count
        var out: [Character] = []
        out.reserveCapacity(count)
        var stack: [Mode] = [.code(depth: 0)]
        var i = 0

        func blank(_ character: Character) -> Character { character == "\n" || character == "\r\n" ? character : " " }
        func at(_ index: Int) -> Character? { index < count ? chars[index] : nil }
        func hashes(after index: Int, _ wanted: Int) -> Bool { (0..<wanted).allSatisfy { at(index + $0) == "#" } }

        while i < count {
            let c = chars[i]
            switch stack[stack.count - 1] {
            case .code(let depth):
                if c == "/", at(i + 1) == "/" {
                    while i < count, chars[i] != "\n", chars[i] != "\r\n" {
                        out.append(" ")
                        i += 1
                    }
                    continue
                }
                if c == "/", at(i + 1) == "*" {
                    var nesting = 0
                    while i < count {
                        if chars[i] == "/", at(i + 1) == "*" {
                            nesting += 1
                            out.append(" ")
                            out.append(" ")
                            i += 2
                            continue
                        }
                        if chars[i] == "*", at(i + 1) == "/" {
                            nesting -= 1
                            out.append(" ")
                            out.append(" ")
                            i += 2
                            if nesting == 0 { break }
                            continue
                        }
                        out.append(blank(chars[i]))
                        i += 1
                    }
                    continue
                }
                if c == "#" || c == "\"" {
                    var j = i
                    var pounds = 0
                    while at(j) == "#" {
                        pounds += 1
                        j += 1
                    }
                    if at(j) == "\"" {
                        let multiline = at(j + 1) == "\"" && at(j + 2) == "\""
                        let opening = j - i + (multiline ? 3 : 1)
                        out.append(contentsOf: repeatElement(" ", count: opening))
                        stack.append(.string(hashes: pounds, multiline: multiline))
                        i += opening
                        continue
                    }
                }
                if c == "(" { stack[stack.count - 1] = .code(depth: depth + 1) }
                if c == ")" {
                    if depth == 0, stack.count > 1 {
                        // The end of an interpolation: back into the string.
                        stack.removeLast()
                        out.append(" ")
                        i += 1
                        continue
                    }
                    stack[stack.count - 1] = .code(depth: max(0, depth - 1))
                }
                out.append(c)
                i += 1
            case .string(let pounds, let multiline):
                if c == "\\", hashes(after: i + 1, pounds) {
                    let next = at(i + 1 + pounds)
                    if next == "(" {
                        out.append(contentsOf: repeatElement(" ", count: 2 + pounds))
                        i += 2 + pounds
                        stack.append(.code(depth: 0))
                    } else {
                        out.append(contentsOf: repeatElement(" ", count: 1 + pounds))
                        i += 1 + pounds
                        if let next {
                            out.append(blank(next))
                            i += 1
                        }
                    }
                    continue
                }
                let closes = c == "\"" && (!multiline || (at(i + 1) == "\"" && at(i + 2) == "\"")) && hashes(after: i + (multiline ? 3 : 1), pounds)
                if closes {
                    let length = (multiline ? 3 : 1) + pounds
                    out.append(contentsOf: repeatElement(" ", count: length))
                    i += length
                    stack.removeLast()
                } else {
                    out.append(blank(c))
                    i += 1
                }
            }
        }
        return String(out)
    }
}

// MARK: - The shipped code

nonisolated struct ShippedLine: Sendable {
    let path: String
    let number: Int
    /// The line as written, trimmed.
    let text: String
    /// The line with comments and string contents blanked.
    let code: String
}

nonisolated enum ShippedSource {
    /// Every folder that goes into a binary: the package, the app, the widgets, the alarm extension and the two Watch targets. Not the tests.
    static let folders = ["Packages/NoctisKit/Sources", "App", "Widgets/Home", "Widgets/Alarm", "Watch/App", "Watch/Widgets"]

    static let lines: [ShippedLine] = {
        var result: [ShippedLine] = []
        for file in RawDefaultsTests.swiftFiles(under: folders) where !file.path.contains("Preview Content") {
            let original = file.text.split(separator: "\n", omittingEmptySubsequences: false)
            let code = SwiftCodeScanner.codeOnly(file.text).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in original.enumerated() where index < code.count {
                result.append(ShippedLine(path: file.path, number: index + 1, text: line.trimmingCharacters(in: .whitespaces), code: String(code[index])))
            }
        }
        return result
    }()

    static var fileCount: Int { Set(lines.map(\.path)).count }
}

extension StringProtocol {
    func hasMatch(_ pattern: String) -> Bool { range(of: pattern, options: .regularExpression) != nil }
}

// MARK: - The rules

struct SourceHygieneTests {
    /// The scan has to see the code, or every rule below passes for nothing.
    @Test func theScanReadsTheWholeShippedSource() {
        #expect(ShippedSource.fileCount > 250, Comment(rawValue: "\(ShippedSource.fileCount) files"))
        #expect(ShippedSource.lines.contains { $0.path.hasSuffix("AppRoot/AppContainer.swift") })
        #expect(ShippedSource.lines.contains { $0.path.hasPrefix("Widgets/Alarm/") })
        #expect(ShippedSource.lines.contains { $0.path.hasPrefix("Watch/Widgets/") })
    }

    @Test func theScannerSeesCodeAndNotWordsInCommentsOrStrings() {
        let sample = ##"""
            // print("a comment")
            /* print("a block /* nested */ comment") */
            let a = "print(\"a string\")"
            let b = #"print("a raw string")"#
            let c = """
            print("a multiline string")
            """
            let d = "\(print("inside an interpolation"))"
            let e = value!
            print("real")
            """##
        let code = SwiftCodeScanner.codeOnly(sample).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(code.count == sample.split(separator: "\n", omittingEmptySubsequences: false).count)
        let printing = code.indices.filter { code[$0].hasMatch(Self.printPattern) }
        // The interpolation's call and the real one are code; the comments and the strings are not.
        #expect(printing == [7, 9], Comment(rawValue: "\(printing)"))
        #expect(code.indices.filter { code[$0].hasMatch(Self.forcePattern) } == [8])
    }

    // MARK: No console output

    static let printPattern = #"(?<![\w.])(?:Swift\.)?(?:print|debugPrint|dump|NSLog)\s*\("#

    /// Nothing prints: the unified log, with its privacy levels, is the one place the app writes to (and only constants and enum names to it).
    @Test func nothingPrintsToTheConsole() {
        let found = ShippedSource.lines.filter { $0.code.hasMatch(Self.printPattern) }
        #expect(found.isEmpty, Comment(rawValue: found.map { "\($0.path):\($0.number)" }.joined(separator: "\n")))
        let stream = ShippedSource.lines.filter { $0.code.hasMatch(#"(?<![\w.])(?:fputs|puts|putchar)\s*\(|standardError|standardOutput"#) }
        #expect(stream.isEmpty, Comment(rawValue: stream.map { "\($0.path):\($0.number)" }.joined(separator: "\n")))
    }

    // MARK: Logging

    /// A log line says what happened by a constant or an enum's name; it never carries an error's description (which can hold a path or a value), a
    /// snapshot, a name or an id. `privacy: .public` is allowed on an enum case's `rawValue`, a domain, a code or a number the line computes.
    @Test func noLogLineMakesAnErrorOrAValueReadableToEveryone() {
        let logging = ShippedSource.lines.filter { $0.text.contains("privacy: .public") }
        #expect(!logging.isEmpty, "the audit found public-by-design log lines (enum names, codes)")
        let bad = logging.filter {
            $0.text.hasMatch(
                #"describing:\s*error|\\\(\s*error\b|localizedDescription|\\\(\s*(self\.)?(profile|snapshot|journal|message|prompt|question|answer|token|name|text|body)\b"#
            )
        }
        #expect(bad.isEmpty, Comment(rawValue: bad.map { "\($0.path):\($0.number): \($0.text)" }.joined(separator: "\n")))
    }

    /// Anything on a log line that is not a constant must say so: there is no interpolation without a privacy level other than a literal.
    @Test func everyLoggerInterpolationNamesItsPrivacyLevel() {
        let calls = ShippedSource.lines.filter {
            $0.text.hasMatch(#"(?:\b\w*[Ll]og(?:ger)?|Logger\([^)]*\))\s*\.\s*(?:debug|info|notice|error|fault|warning|trace|critical|log)\("#)
        }
        #expect(calls.count >= 8, Comment(rawValue: "\(calls.count) log calls"))
        for call in calls where call.text.contains("\\(") {
            // Every interpolation on the line is followed by `privacy:` before its closing parenthesis.
            let interpolations = call.text.components(separatedBy: "\\(").dropFirst()
            for part in interpolations {
                #expect(part.contains("privacy:"), Comment(rawValue: "\(call.path):\(call.number) has an interpolation without a privacy level"))
            }
        }
    }

    // MARK: Tests

    /// R66: a test does not sleep for a guessed duration. The few sleeps that stay are a simulated slow dependency (`HomeRepositoryTests`' provider
    /// latency), a backstop that returns the moment its condition is met (`AlarmServiceTests`), and the helpers themselves (`TestWaiting.swift`).
    @Test func noTestSleepsForAGuessedDuration() {
        let allowed: Set<String> = [
            "TestWaiting.swift", "HomeRepositoryTests.swift", "AlarmServiceTests.swift", "SourceHygieneTests.swift", "SoundPlayerTests.swift",
        ]
        let files = RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Tests/NoctisKitTests"])
        #expect(files.count > 50)
        var found: [String] = []
        for file in files where !allowed.contains((file.path as NSString).lastPathComponent) {
            let code = SwiftCodeScanner.codeOnly(file.text)
            for (index, line) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.hasMatch(#"Task\.sleep\(|Thread\.sleep|usleep\(|\bsleep\([0-9]"#) {
                // `held` is the one sleep that is meant never to end.
                found.append("\(file.path):\(index + 1)")
            }
        }
        #expect(found.isEmpty, Comment(rawValue: "Wait for the state (waitFor), or inject the timer:\n" + found.joined(separator: "\n")))
    }

    // MARK: Force unwraps, try!, fatalError

    static let forcePattern = #"(?<=[\w)\]])!(?!=)|\btry!|\bas!|(?<![\w.])fatalError\s*\(|(?<![\w.])preconditionFailure\s*\("#

    /// Each place the code can trap on purpose, with why it cannot happen in a build that ships. Keyed by path and the line as written.
    static let allowed: [String: String] = [
        "Packages/NoctisKit/Sources/NoctisWatchKit/WatchComplications.swift::return components.url ?? URL(string: \"\\(Self.scheme)://\\(rawValue)\")!":
            "The fallback of a URL built from the scheme `noctis` and one of four fixed hosts; URLComponents cannot fail on them (WatchLinkTests build every case).",
        "Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetLink.swift::return components.url ?? URL(string: \"\\(Self.scheme)://\\(rawValue)\")!":
            "The same, for the five widget hosts (WidgetLinkTests build every case).",
        "Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetLink.swift::return components.url ?? URL(string: \"\\(WidgetLink.scheme)://\\(Self.host)\")!":
            "The same, for `noctis://premium` (PremiumLinkTests).",
        "Packages/NoctisKit/Sources/NoctisCore/Store/StoreConstants.swift::public static let terms = URL(string: \"https://noctis.app/terms\")!":
            "A literal URL (SettingsTests checks it is https). The owner replaces it before release (ROADMAP.md).",
        "Packages/NoctisKit/Sources/NoctisCore/Store/StoreConstants.swift::public static let privacy = URL(string: \"https://noctis.app/privacy\")!":
            "A literal URL (SettingsTests checks it is https). The owner replaces it before release (ROADMAP.md).",
        "Packages/NoctisKit/Sources/CoachKit/CoachTokens.swift::static let pattern = try! NSRegularExpression(pattern: #\"\\{\\{\\s*([A-Za-z0-9_.]+)\\s*\\}\\}\"#)":
            "A constant pattern: every Coach test that replaces a token compiles it (CoachTokenTests).",
        "Packages/NoctisKit/Sources/NoctisCore/DataInventory.swift::guard let category = categories.first(where: { $0.id == id }) else { preconditionFailure(\"\\(id) is not in the inventory\") }":
            "A lookup by an enum case in a table the inventory tests prove holds every case (DataInventoryTests).",
        "Packages/NoctisKit/Sources/NoctisCore/NoctisStore.swift::return (try! inMemory(), .runningInMemory)":
            "The last resort after a database could not be opened or replaced: an in-memory container of the app's own schema cannot fail short of an invalid model, which every test that opens one would hit (QA-003, R65).",
        "Packages/NoctisKit/Sources/HomeFeature/HomePreviews.swift::fatalError(\"Preview store: \\(error)\")":
            "Inside `#if DEBUG`, a SwiftUI preview of an in-memory store: not compiled into a Release build (the Release symbol check).",
    ]

    @Test func everyForceUnwrapTryBangAndFatalErrorIsListedWithItsReason() {
        let found = ShippedSource.lines.filter { $0.code.hasMatch(Self.forcePattern) }
        let unlisted = found.filter { Self.allowed["\($0.path)::\($0.text)"] == nil }
        #expect(
            unlisted.isEmpty,
            Comment(
                rawValue: "Remove it, or list it in SourceHygieneTests.allowed with the reason it cannot trap:\n"
                    + unlisted.map { "\($0.path):\($0.number): \($0.text)" }.joined(separator: "\n")))
    }

    @Test func theAllowListHasNoEntryForCodeThatIsGone() {
        let present = Set(ShippedSource.lines.filter { $0.code.hasMatch(Self.forcePattern) }.map { "\($0.path)::\($0.text)" })
        let stale = Self.allowed.keys.filter { !present.contains($0) }
        #expect(stale.isEmpty, Comment(rawValue: stale.sorted().joined(separator: "\n")))
    }
}
