import Foundation
import Testing

// QA part 4 (QA-085): v1 ships English only, so no right-to-left language is in the app. The right-to-left run (D-RTL) is a check of the layout's readiness, not
// of a shipped language; this test fails the day a second language is added without the layout being walked in it (the QA matrix has the configurations).
struct ShippedLanguagesTests {
    private let root = RawDefaultsTests.root

    @Test func theAppShipsEnglishAndNoRightToLeftLanguage() throws {
        let rightToLeft: Set<String> = ["ar", "he", "fa", "ur", "ps", "sd", "ug", "yi", "dv", "ckb"]
        let pbx = try String(contentsOf: root.appendingPathComponent("Noctis.xcodeproj/project.pbxproj"), encoding: .utf8)
        let regions = try #require(pbx.range(of: #"knownRegions = \(([^)]*)\)"#, options: .regularExpression)).lowerBound
        let list = pbx[regions...].prefix(while: { $0 != ")" }).components(separatedBy: CharacterSet(charactersIn: ",\n\t ;=()")).filter {
            !$0.isEmpty && $0 != "knownRegions"
        }
        #expect(Set(list) == ["Base", "en"], "knownRegions: \(list)")
        var languages = Set<String>()
        let base = root.appendingPathComponent("Packages/NoctisKit/Sources")
        let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "xcstrings" else { continue }
            let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            languages.insert(json["sourceLanguage"] as? String ?? "?")
            for (_, entry) in json["strings"] as? [String: Any] ?? [:] {
                for key in ((entry as? [String: Any])?["localizations"] as? [String: Any])?.keys ?? [:].keys { languages.insert(key) }
            }
        }
        let appCatalog = root.appendingPathComponent("App/AppShortcuts.xcstrings")
        if let data = try? Data(contentsOf: appCatalog), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            languages.insert(json["sourceLanguage"] as? String ?? "?")
            for (_, entry) in json["strings"] as? [String: Any] ?? [:] {
                for key in ((entry as? [String: Any])?["localizations"] as? [String: Any])?.keys ?? [:].keys { languages.insert(key) }
            }
        }
        #expect(languages == ["en"], "string catalogs hold: \(languages.sorted())")
        #expect(languages.isDisjoint(with: rightToLeft))
        // No .lproj folder for another language.
        let lprojs = (FileManager.default.enumerator(at: root.appendingPathComponent("App"), includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "lproj" }.map(\.lastPathComponent)
        #expect(Set(lprojs).isSubset(of: ["en.lproj", "Base.lproj"]), "\(lprojs)")
    }
}
