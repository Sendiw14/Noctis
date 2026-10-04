import Foundation
import Testing

@testable import HealthProviding
@testable import NoctisCore

// App/PrivacyInfo.xcprivacy is written from an audit of the code (APP_RULES.md R43, PRIVACY_REPORT.md). These tests hold each entry to the
// code, so the manifest cannot say less than the code does, or more.

private let inventory = DataInventory.shared

private nonisolated func root(_ path: String) -> URL { RawDefaultsTests.root.appendingPathComponent(path) }

/// The app's own code, for the scans: the package's sources, the app and the extension, comments removed.
private nonisolated func appCode() -> [(path: String, code: String)] {
    RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App", "NoctisAlarmWidget", "NoctisWidgets"])
        // The inventory and the privacy words name APIs as strings; that is not a use.
        .filter { !$0.path.contains("NoctisCore/DataInventory") && !$0.path.contains("NoctisCore/Privacy") }
        .map { ($0.path, RawDefaultsTests.code($0.text)) }
}

private nonisolated func manifest() throws -> [String: Any] {
    let data = try Data(contentsOf: root("App/PrivacyInfo.xcprivacy"))
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

/// The categories of required-reason API (Apple's list) and the code that calls them.
private nonisolated enum RequiredReasonAPI: String, CaseIterable {
    case fileTimestamp = "NSPrivacyAccessedAPICategoryFileTimestamp"
    case systemBootTime = "NSPrivacyAccessedAPICategorySystemBootTime"
    case diskSpace = "NSPrivacyAccessedAPICategoryDiskSpace"
    case activeKeyboards = "NSPrivacyAccessedAPICategoryActiveKeyboards"
    case userDefaults = "NSPrivacyAccessedAPICategoryUserDefaults"

    /// Plain tokens that mean the category is used.
    var tokens: [String] {
        switch self {
        case .fileTimestamp:
            ["creationDate", "modificationDate", "contentModificationDate", "creationDateKey", "fileModificationDate", "fileCreationDate",
             "NSFileCreationDate", "NSFileModificationDate", "getattrlist", "fstatat", "fstat(", "lstat("]
        case .systemBootTime: ["systemUptime", "mach_absolute_time", "mach_continuous_time", "clock_gettime_nsec_np"]
        case .diskSpace: ["volumeAvailableCapacity", "volumeTotalCapacity", "systemFreeSize", "NSFileSystemFreeSize", "NSFileSystemSize", "statfs", "statvfs"]
        case .activeKeyboards: ["activeInputModes"]
        case .userDefaults: ["UserDefaults", "@AppStorage", "NSUserDefaults"]
        }
    }

    /// A regular expression for the C call `stat(path, &buffer)`, which a plain token would confuse with a function named `stat`.
    var pattern: String? { self == .fileTimestamp ? #"(?<![A-Za-z_.])stat\s*\([^)\n]*,\s*&"# : nil }

    func isUsed(in code: String) -> Bool {
        tokens.contains { code.contains($0) } || (pattern.map { code.range(of: $0, options: .regularExpression) != nil } ?? false)
    }
}

struct PrivacyManifestTests {
    @Test func theManifestIsWellFormedAndInTheApp() throws {
        let manifest = try manifest()
        #expect(Set(manifest.keys) == ["NSPrivacyTracking", "NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"])
        let project = try String(contentsOf: root("Noctis.xcodeproj/project.pbxproj"), encoding: .utf8)
        #expect(project.contains("PrivacyInfo.xcprivacy in Resources"), "the manifest is a resource of the app target")
    }

    @Test func trackingIsOffBecauseTheCodeHasNothingThatTracks() throws {
        let manifest = try manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        for file in appCode() {
            for token in ["import AdSupport", "import AppTrackingTransparency", "ATTrackingManager", "ASIdentifierManager", "advertisingIdentifier", "identifierForVendor"] {
                #expect(!file.code.contains(token), Comment(rawValue: "\(file.path) uses \(token); tracking would need an answer"))
            }
        }
        let project = try String(contentsOf: root("project.yml"), encoding: .utf8)
        #expect(!project.contains("NSUserTrackingUsageDescription"))
        let package = try String(contentsOf: root("Packages/NoctisKit/Package.swift"), encoding: .utf8)
        #expect(!package.contains(".package(url:"), "no third-party package: none can track, and none needs a manifest of its own")
        #expect(!project.contains("url:"), "the app has no remote package either")
    }

    @Test func nothingIsCollectedBecauseNothingLeavesForNOCTISOrAPartner() throws {
        let manifest = try manifest()
        let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [Any])
        // A category that goes to a company that is not Apple, or a flow that is not the person's own, would need an entry.
        let leaves = inventory.categories.filter { category in
            if case .thirdParty = category.destination { return true }
            return false
        }
        #expect(leaves.isEmpty, "a category goes to a third party: add NSPrivacyCollectedDataTypes entries for it")
        #expect(inventory.flows.allSatisfy { $0.trigger == .onlyWhenYouChoose || $0.trigger == .byApple })
        #expect(!inventory.facts.coachUsesRemoteModel)
        #expect(!inventory.facts.hasAccount)
        if leaves.isEmpty && !inventory.facts.coachUsesRemoteModel { #expect(collected.isEmpty) }
        // No code of NOCTIS's own reaches a network: the only network-capable APIs are the listed system ones.
        for use in inventory.networkUses { #expect(["import StoreKit", "import MessageUI"].contains(use.token), Comment(rawValue: "\(use.token) needs a decision in PRIVACY_REPORT.md")) }
    }

    @Test func everyRequiredReasonAPIInTheCodeIsDeclaredAndNothingElseIs() throws {
        let manifest = try manifest()
        let entries = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let declared = Set(entries.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
        #expect(declared.count == entries.count, "each category once")

        let files = appCode()
        var used: Set<String> = []
        for api in RequiredReasonAPI.allCases {
            let by = files.filter { api.isUsed(in: $0.code) }.map(\.path)
            if !by.isEmpty { used.insert(api.rawValue) }
            #expect(by.isEmpty || declared.contains(api.rawValue), Comment(rawValue: "\(api.rawValue) is used by \(by.prefix(3)) and is not declared"))
            #expect(!by.isEmpty || !declared.contains(api.rawValue), Comment(rawValue: "\(api.rawValue) is declared and nothing uses it"))
        }
        #expect(used == declared)
        #expect(declared == [RequiredReasonAPI.userDefaults.rawValue], "the audit found UserDefaults only")
    }

    @Test func eachReasonIsTheOneTheCodeMatches() throws {
        let manifest = try manifest()
        let entries = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let defaults = try #require(entries.first { $0["NSPrivacyAccessedAPIType"] as? String == RequiredReasonAPI.userDefaults.rawValue })
        #expect(defaults["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
        // CA92.1 is for defaults only the app itself reads and writes; sharing defaults with an extension through an App Group is 1C8F.1.
        // The App Group holds two small files (the widgets' summary, R44, and the control's status, R48) and no defaults suite: nothing is shared through UserDefaults.
        for file in appCode() {
            #expect(!file.code.contains("UserDefaults(suiteName: \"group."), Comment(rawValue: "\(file.path) shares defaults through an app group"))
            #expect(!file.code.contains("suiteName: WidgetSnapshotStore"), Comment(rawValue: "\(file.path) shares defaults through the widgets' app group"))
        }
        // The alarm extension reads no defaults and no timestamps: it has no manifest because it uses none. The widgets' extension has
        // one of its own, which says the same.
        for file in appCode() where file.path.hasPrefix("NoctisAlarmWidget/") || file.path.hasPrefix("NoctisWidgets/") {
            for api in RequiredReasonAPI.allCases { #expect(!api.isUsed(in: file.code), Comment(rawValue: "\(file.path) uses \(api.rawValue): the extension needs its own manifest")) }
        }
    }

    @Test func theWidgetsExtensionHasItsOwnManifestAndUsesNoRequiredReasonAPI() throws {
        let data = try Data(contentsOf: root("NoctisWidgets/PrivacyInfo.xcprivacy"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true && (plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        // The kit it links is scanned with the rest of the package: nothing in it uses a category, so none is declared.
        let declared = (plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]]) ?? []
        #expect(declared.isEmpty)
        let kitFiles = appCode().filter { $0.path.contains("NoctisWidgetKit/") || $0.path.hasPrefix("NoctisWidgets/") }
        #expect(kitFiles.count >= 8)
        for api in RequiredReasonAPI.allCases {
            for file in kitFiles { #expect(!api.isUsed(in: file.code), Comment(rawValue: "\(file.path) uses \(api.rawValue): declare it in NoctisWidgets/PrivacyInfo.xcprivacy")) }
        }
        let project = try String(contentsOf: root("Noctis.xcodeproj/project.pbxproj"), encoding: .utf8)
        #expect(project.components(separatedBy: "PrivacyInfo.xcprivacy in Resources").count - 1 == 4, "the app's and the widgets', each as a file and in a build phase")
        let yml = try String(contentsOf: root("project.yml"), encoding: .utf8)
        #expect(yml.contains("NoctisWidgets:") && yml.contains("com.noctis.app.widgets"))
        // No HealthKit, no network and no iCloud for the extension: its entitlements are the App Group alone.
        let entitlements = try String(contentsOf: root("NoctisWidgets/NoctisWidgets.entitlements"), encoding: .utf8)
        #expect(entitlements.contains("com.apple.security.application-groups") && !entitlements.contains("healthkit") && !entitlements.contains("icloud") && !entitlements.contains("network"))
    }

    @Test func theHealthUsageDescriptionNamesEverythingTheAppReadsAndThatItNeverWrites() throws {
        let project = try String(contentsOf: root("project.yml"), encoding: .utf8)
        let line = try #require(project.split(separator: "\n").first { $0.contains("INFOPLIST_KEY_NSHealthShareUsageDescription") })
        let text = String(line).lowercased()
        let phrases: [HealthDataKind: String] = [
            .sleepAnalysis: "sleep", .heartRate: "heart rate", .restingHeartRate: "resting heart rate", .hrv: "heart rate variability",
            .respiratoryRate: "respiratory rate",
        ]
        for kind in HealthDataKind.allCases {
            #expect(text.contains(try #require(phrases[kind])), Comment(rawValue: "the description does not name \(kind)"))
        }
        #expect(text.contains("never writes"))
        #expect(!project.contains("NSHealthUpdateUsageDescription"))
    }

    @Test func theReportExistsAndLeavesTheAnswersToTheOwner() throws {
        let report = try String(contentsOf: root("PRIVACY_REPORT.md"), encoding: .utf8)
        #expect(report.contains("for owner review"))
        #expect(report.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(report.contains("CA92.1"))
        for category in inventory.categories { #expect(report.contains(category.name), Comment(rawValue: "the report does not cover \(category.name)")) }
    }
}
