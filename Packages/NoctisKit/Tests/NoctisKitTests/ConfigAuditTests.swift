import Foundation
import Testing

@testable import NoctisCore
@testable import NoctisWatchKit
@testable import NoctisWidgetKit

// QA part 1 (QA_LEDGER.md): the destinations, Info.plists and entitlements are what the app needs and nothing more. The files are read as they
// are checked in (project.yml, the generated project, each plist and entitlements file), so a key added later has to be added here too, with
// its reason.

private nonisolated func root(_ path: String) -> URL { RawDefaultsTests.root.appendingPathComponent(path) }

private nonisolated func plist(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root(path))
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

private nonisolated func text(_ path: String) throws -> String { try String(contentsOf: root(path), encoding: .utf8) }

/// Every `NAME = value;` line of the generated project, as (name, value).
private nonisolated func projectSettings(named name: String) throws -> [String] {
    try text("Noctis.xcodeproj/project.pbxproj").split(separator: "\n").compactMap { line -> String? in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(name + " = ") else { return nil }
        return String(trimmed.dropFirst(name.count + 3)).trimmingCharacters(in: CharacterSet(charactersIn: ";\" "))
    }
}

struct ConfigAuditTests {
    // MARK: Destinations

    @Test func everyTargetIsForIPhoneOrTheWatchAndNoneIsUniversal() throws {
        let families = try projectSettings(named: "TARGETED_DEVICE_FAMILY")
        // Noctis, NoctisUITests, the two widget extensions: 1 (two configurations each), the two Watch targets: 4, and the project: 1.
        #expect(!families.isEmpty)
        #expect(Set(families) == ["1", "4"], Comment(rawValue: "\(Set(families))"))
        #expect(families.filter { $0 == "4" }.count == 4, "the Watch app and its widgets, Debug and Release")
    }

    @Test func theMacAndVisionDesignedForIPhoneDestinationsAreOffAndNoCatalyst() throws {
        for name in ["SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD", "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD", "SUPPORTS_MACCATALYST"] {
            let values = try projectSettings(named: name)
            #expect(!values.isEmpty && values.allSatisfy { $0 == "NO" }, Comment(rawValue: "\(name) = \(values)"))
        }
    }

    @Test func strictConcurrencyIsCompleteForEveryTarget() throws {
        let values = try projectSettings(named: "SWIFT_STRICT_CONCURRENCY")
        #expect(!values.isEmpty && values.allSatisfy { $0 == "complete" }, Comment(rawValue: "\(values)"))
    }

    @Test func theAppIsPortraitOnlyOnIPhoneAndNamesNoIPadOrLandscape() throws {
        let yml = try text("project.yml")
        #expect(yml.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait"))
        #expect(!yml.contains("UISupportedInterfaceOrientations_iPad") && !yml.contains("Landscape") && !yml.contains("UIRequiresFullScreen"))
        let appPlist = try text("App/Info.plist")
        #expect(!appPlist.contains("Landscape") && !appPlist.contains("~ipad"))
    }

    // MARK: Minimum deployment

    @Test func everyIOSTargetStartsAtTheFirstSystemWhereEveryFeatureIsWhole() throws {
        // iOS 26.1: the bedtime accessory and AlarmKit's one-button alert (QA_LEDGER.md). The Watch has nothing above 26.0.
        let ios = try projectSettings(named: "IPHONEOS_DEPLOYMENT_TARGET")
        #expect(!ios.isEmpty && ios.allSatisfy { $0 == "26.1" }, Comment(rawValue: "\(ios)"))
        let watch = try projectSettings(named: "WATCHOS_DEPLOYMENT_TARGET")
        #expect(!watch.isEmpty && watch.allSatisfy { $0 == "26.0" }, Comment(rawValue: "\(watch)"))
        let package = try text("Packages/NoctisKit/Package.swift")
        #expect(package.contains("platforms: [.iOS(\"26.1\"), .watchOS(.v26)]"))
    }

    @Test func noAvailabilityGuardAsksForASystemTheAppAlreadyRequires() {
        // A guard for 26.0 or 26.1 is a dead branch: it hides a fallback nobody can reach. iOS 27 guards stay (the swipe actions, with the long press beside them).
        let guards = ShippedSource.lines.filter {
            $0.code.hasMatch(#"#available\(\s*iOS\s+26(\.[01])?\s*,"#) || $0.code.hasMatch(#"@available\(\s*iOS\s+26(\.[01])?\s*,"#)
        }
        #expect(guards.isEmpty, Comment(rawValue: guards.map { "\($0.path):\($0.number)" }.joined(separator: "\n")))
        let iOS27 = ShippedSource.lines.filter { $0.code.hasMatch(#"#available\(\s*iOS\s+27\s*,"#) }
        #expect(iOS27.count == 2, "the Home swipe actions container and the insight card's swipe actions, each beside a plain iOS 26 behavior")
    }

    // MARK: Info.plist

    @Test func theAppsPlistHoldsOnlyTheKeysThatHaveNoBuildSetting() throws {
        let app = try plist("App/Info.plist")
        // The URL scheme, the audio background mode (sleep sounds with the screen locked, R31) and AlarmKit's usage string (no build setting for it).
        #expect(Set(app.keys) == ["CFBundleURLTypes", "UIBackgroundModes", "NSAlarmKitUsageDescription"], Comment(rawValue: "\(app.keys.sorted())"))
        #expect(app["UIBackgroundModes"] as? [String] == ["audio"], "no fetch, processing, location or remote-notification mode")
        let alarm = try #require(app["NSAlarmKitUsageDescription"] as? String)
        #expect(alarm.lowercased().contains("alarm") && alarm.count > 30 && !alarm.lowercased().contains("placeholder"))
    }

    @Test func theGeneratedKeysAreTheOnesTheAppNeeds() throws {
        let yml = try text("project.yml")
        let keys = Set(
            yml.split(separator: "\n").compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("INFOPLIST_KEY_"), let colon = trimmed.firstIndex(of: ":") else { return nil }
                return String(trimmed[..<colon])
            })
        #expect(
            keys == [
                "INFOPLIST_KEY_CFBundleDisplayName", "INFOPLIST_KEY_UILaunchStoryboardName", "INFOPLIST_KEY_NSSupportsLiveActivities",
                "INFOPLIST_KEY_NSHealthShareUsageDescription", "INFOPLIST_KEY_UIApplicationSceneManifest_Generation", "INFOPLIST_KEY_UIStatusBarStyle",
                "INFOPLIST_KEY_UISupportedInterfaceOrientations",
                // Export compliance (QA-016): no encryption of its own; PrivacyEnforcementTests holds the claim to the code.
                "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption",
            ], Comment(rawValue: "\(keys.sorted())"))
        // Reads Health and says it never writes: there is no update description, because nothing is written.
        #expect(!yml.contains("NSHealthUpdateUsageDescription") && !yml.contains("NSHealthClinicalHealthRecords"))
        // Nothing the app never does is asked for: no camera, microphone, location, contacts, photos, tracking, speech, Bluetooth or local network.
        for key in [
            "NSCamera", "NSMicrophone", "NSLocation", "NSContacts", "NSPhotoLibrary", "NSUserTracking", "NSSpeechRecognition", "NSBluetooth", "NSLocalNetwork",
            "NSFaceID", "NSMotion", "NSCalendars",
        ] {
            #expect(!yml.contains(key), Comment(rawValue: "project.yml asks for \(key)"))
        }
    }

    @Test func theExtensionsAndTheWatchAppCarryOnlyTheirOwnKeys() throws {
        for path in ["Widgets/Alarm/Info.plist", "Widgets/Home/Info.plist", "Watch/Widgets/Info.plist"] {
            let info = try plist(path)
            let extensionPoint = (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
            #expect(extensionPoint == "com.apple.widgetkit-extension", Comment(rawValue: path))
            #expect(info["NSExtension"].flatMap { ($0 as? [String: Any])?.count } == 1, Comment(rawValue: "\(path): nothing but the extension point"))
            for key in info.keys where key.hasPrefix("NS") && key != "NSExtension" { Issue.record("\(path) has \(key)") }
            #expect(info["UIBackgroundModes"] == nil && info["WKBackgroundModes"] == nil && info["CFBundleURLTypes"] == nil)
        }
        let watch = try plist("Watch/App/Info.plist")
        #expect(watch["WKBackgroundModes"] as? [String] == ["mindfulness"], "the breathing session only (R55)")
        #expect(watch["WKCompanionAppBundleIdentifier"] as? String == "com.noctis.app")
        for key in watch.keys where key.hasPrefix("NS") { Issue.record("the Watch app has \(key): it reads nothing from Health (R34)") }
    }

    @Test func noPlistOrManifestOpensTheNetwork() throws {
        let files = [
            "App/Info.plist", "Widgets/Alarm/Info.plist", "Widgets/Home/Info.plist", "Watch/App/Info.plist", "Watch/Widgets/Info.plist", "project.yml",
        ]
        for path in files {
            let content = try text(path)
            for key in [
                "NSAppTransportSecurity", "NSAllowsArbitraryLoads", "NSExceptionDomains", "NSAllowsLocalNetworking", "NSBonjourServices",
                "NSExceptionAllowsInsecureHTTPLoads",
            ] {
                #expect(!content.contains(key), Comment(rawValue: "\(path) has \(key)"))
            }
        }
    }

    @Test func theURLSchemeTheAppRegistersIsTheOneEveryRouterAccepts() throws {
        let app = try plist("App/Info.plist")
        let types = try #require(app["CFBundleURLTypes"] as? [[String: Any]])
        #expect(types.count == 1)
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == [AppRoute.urlScheme])
        #expect(AppRoute.urlScheme == WidgetLink.scheme && WidgetLink.scheme == WatchLink.scheme && WidgetLink.scheme == "noctis")
        // The widgets' links, the premium link and every route the app writes are inside that one scheme, and the router opens each of them.
        for link in WidgetLink.allCases { #expect(WidgetURLRouter.destination(for: link.url) != nil, Comment(rawValue: "\(link.url) opens nothing")) }
        #expect(WidgetURLRouter.destination(for: PremiumLink(context: .general).url) != nil)
        for destination in AppRoute.destinations {
            #expect(destination.url.scheme == AppRoute.urlScheme)
            #expect(AppRoute(url: destination.url) == destination, Comment(rawValue: "\(destination.url)"))
        }
    }

    // MARK: Entitlements

    @Test func onlyTheIPhoneAppHasHealthKitAndEveryTargetSharesOneAppGroup() throws {
        let app = try plist("Config/Noctis.entitlements")
        #expect(app["com.apple.developer.healthkit"] as? Bool == true)
        #expect((app["com.apple.developer.healthkit.access"] as? [Any])?.isEmpty == true, "no clinical records")
        #expect(app["com.apple.developer.healthkit.background-delivery"] as? Bool == true, "R46: the morning wake")
        #expect(app["com.apple.developer.applesignin"] as? [String] == ["Default"], "R69: Sign in with Apple, optional and local")
        #expect(
            Set(app.keys) == [
                "com.apple.developer.applesignin", "com.apple.developer.healthkit", "com.apple.developer.healthkit.access",
                "com.apple.developer.healthkit.background-delivery", "com.apple.security.application-groups",
            ])

        let group = WidgetSnapshotStore.appGroupIdentifier
        #expect(app["com.apple.security.application-groups"] as? [String] == [group])
        for path in ["Config/NoctisWidgets.entitlements", "Config/NOCTISWatch.entitlements", "Config/NOCTISWatchWidgets.entitlements"] {
            let entitlements = try plist(path)
            #expect(
                Set(entitlements.keys) == ["com.apple.security.application-groups"], Comment(rawValue: "\(path): the App Group and nothing else (R34, R44)"))
            #expect(entitlements["com.apple.security.application-groups"] as? [String] == [group], Comment(rawValue: path))
        }
        // The alarm extension has none: it reads what AlarmKit hands it.
        #expect(!FileManager.default.fileExists(atPath: root("Config/NoctisAlarmWidget.entitlements").path))
        let yml = try text("project.yml")
        let alarmBlock = try #require(yml.range(of: "  NoctisAlarmWidget:\n"))
        let nextTarget = try #require(yml.range(of: "\n  # NOCTIS's widgets:", range: alarmBlock.upperBound..<yml.endIndex))
        #expect(!yml[alarmBlock.upperBound..<nextTarget.lowerBound].contains("entitlements"))
    }
}
