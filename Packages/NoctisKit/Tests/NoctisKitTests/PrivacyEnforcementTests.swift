import Foundation
import SwiftData
import Testing

@testable import CoachKit
@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import JournalKit
@testable import NoctisCore
@testable import NoctisText
@testable import NoctisWatchKit
@testable import ProfileFeature
@testable import NoctisWidgetKit
@testable import ReviewKit
@testable import SleepKit

// QA part 3, step 6: the privacy statements, held to the bytes. The inventory says, per category, whether it is in backups and how it is protected on disk;
// these tests make the real files with the real stores and read the attributes back from the file system.

private let inventory = DataInventory.shared

struct PrivacyEnforcementTests {
    private func root() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "noctis.privacy.\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func excluded(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false }
    private func protection(_ url: URL) -> FileProtectionType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey]) as? FileProtectionType
    }

    /// What the real store made for each on-disk category: the category, and every file or folder it owns.
    private func produce(in root: URL) async throws -> [(DataCategoryID, [URL])] {
        var made: [(DataCategoryID, [URL])] = []
        let support = root.appending(path: "Noctis", directoryHint: .isDirectory)

        let snapshot = HomeSnapshotStore(directory: support)
        let home = HomeSnapshotBuilder.placeholder(.permissionRequired, profile: UserProfileSnapshot(), now: Date(timeIntervalSince1970: 1_790_000_000), timeZone: .gmt)
        _ = home
        // A snapshot that is persistable needs data: build one from the mock.
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: Date(timeIntervalSince1970: 1_790_000_000), calendar: Calendar(identifier: .gregorian), startAuthorized: true)
        let built = await HomeRepository(provider: provider, timeZone: .gmt, clock: { Date(timeIntervalSince1970: 1_790_000_000) }).refresh(profile: UserProfileSnapshot())
        snapshot.save(built)
        made.append((.cachedSummaries, [snapshot.fileURL]))

        let widgets = WidgetSnapshotStore(directory: root.appending(path: "group", directoryHint: .isDirectory))
        #expect(widgets.save(WidgetSamples.snapshot(.full, now: Date(timeIntervalSince1970: 1_790_000_000), calendar: Calendar(identifier: .gregorian))))
        made.append((.widgetSnapshot, [widgets.fileURL]))
        let sounds = SleepSoundsStore(directory: root.appending(path: "group", directoryHint: .isDirectory))
        #expect(sounds.save(SleepSoundsState(endsAt: Date(timeIntervalSince1970: 1_790_001_000))))
        made.append((.sleepSoundsState, [sounds.fileURL]))

        let insights = InsightFileStore(directory: support)
        insights.save(InsightLibrary())
        made.append((.insightHistory, [insights.fileURL]))
        let reviews = ReviewFileStore(directory: support)
        var library = ReviewLibrary()
        library.put(ReviewTestRecords.stored())
        reviews.save(library)
        made.append((.reviews, [reviews.fileURL]))

        let journalFolder = support.appending(path: "Journal", directoryHint: .isDirectory)
        let journal = try JournalContainer.make(directory: journalFolder)
        let journalContext = ModelContext(journal)
        journalContext.insert(JournalEntry())
        try journalContext.save()
        JournalContainer.protect(journalFolder)
        made.append((.journal, [journalFolder] + ((try? FileManager.default.contentsOfDirectory(at: journalFolder, includingPropertiesForKeys: nil)) ?? [])))

        let coachFolder = support.appending(path: "CoachHistory", directoryHint: .isDirectory)
        let coach = try CoachHistoryContainer.make(directory: coachFolder)
        let coachContext = ModelContext(coach)
        coachContext.insert(AIConversation())
        try coachContext.save()
        CoachHistoryContainer.protect(coachFolder)
        made.append((.coachHistory, [coachFolder] + ((try? FileManager.default.contentsOfDirectory(at: coachFolder, includingPropertiesForKeys: nil)) ?? [])))
        return made
    }

    @Test func everyOnDiskCategoryIsExcludedFromBackupAndProtectedAsTheInventorySays() async throws {
        let dir = try root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let made = try await produce(in: dir)
        #expect(made.count == 7)
        for (id, urls) in made {
            let category = inventory[id]
            #expect(!urls.isEmpty, "\(id) made nothing")
            for url in urls {
                if !category.inBackup { #expect(excluded(url), Comment(rawValue: "\(id): \(url.lastPathComponent) is in backups but the inventory says it is not")) }
                switch category.protection {
                case .completeWhileLocked:
                    // The simulator reports no protection class for any file or folder (nil everywhere, even where the code sets one), so a class that
                    // does read back must be complete, and where nothing reads back the code is held to the claim instead (the next test).
                    if let found = protection(url) { #expect(found == .complete, Comment(rawValue: "\(id): \(url.lastPathComponent) is \(found.rawValue)")) }
                case .standard:
                    // Readable after first unlock: the App Group files say so explicitly; anything else keeps iOS's default (nil or that class).
                    #expect(protection(url) != .complete, Comment(rawValue: "\(id): \(url.lastPathComponent) is stricter than the inventory says"))
                default: break
                }
            }
        }
    }

    @Test func theInventoryClaimsNothingStricterThanTheCodeWrites() {
        // Every category that claims complete protection is one of the stores above; the others claim standard or Apple's.
        let claimsComplete = DataCategoryID.allCases.filter { inventory[$0].protection == .completeWhileLocked }
        #expect(Set(claimsComplete) == [.cachedSummaries, .insightHistory, .reviews, .journal, .coachHistory, .setAsideFiles])
        // Backup: what is in backups is exactly what the person wrote or set, and nothing derived.
        let inBackup = DataCategoryID.allCases.filter { inventory[$0].inBackup }
        for id in inBackup { #expect(inventory[id].holdsUserContent || [.watchSync, .appState, .alarm, .windDownHistory].contains(id), "\(id) is in backups") }
    }

    /// Where the platform reports no protection class (the simulator), the claim is held to the code: the source that makes each complete-while-locked
    /// category's files asks for complete protection, and the App Group's two files ask for the until-first-unlock class and nothing stricter (a widget
    /// must be able to read them with the phone locked after the first unlock).
    @Test func theCodeAsksForTheProtectionTheInventoryClaims() throws {
        func source(_ path: String) throws -> String { try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/" + path), encoding: .utf8) }
        for path in ["NoctisCore/HomeSnapshotStore.swift", "NoctisCore/InsightStore.swift", "NoctisCore/ReviewStore.swift"] {
            let text = try source(path)
            #expect(text.contains(".completeFileProtection]") || text.contains(".completeFileProtection)"), Comment(rawValue: path))
            #expect(!text.contains("UntilFirstUserAuthentication"), Comment(rawValue: path))
            #expect(text.contains("isExcludedFromBackup = true"), Comment(rawValue: path))
        }
        for path in ["JournalKit/JournalStore.swift", "CoachKit/CoachHistory.swift", "NoctisCore/StoreRecovery.swift"] {
            let text = try source(path)
            #expect(text.contains("FileProtectionType.complete") && text.contains("isExcludedFromBackup = true"), Comment(rawValue: path))
        }
        for path in ["NoctisWidgetKit/WidgetSnapshotStore.swift", "NoctisWidgetKit/SleepSoundsState.swift"] {
            let text = try source(path)
            #expect(text.contains("completeFileProtectionUntilFirstUserAuthentication") && text.contains("isExcludedFromBackup = true"), Comment(rawValue: path))
        }
    }

    /// A positive control for the request recorder the UI run relies on: a request through URLSession.shared is counted, so a count of zero in the UI run
    /// means something.
    @Test func theRequestRecorderCountsARequestThroughTheSharedSession() async {
        RequestRecorder.installOnce()
        let before = RequestRecorder.count
        _ = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:9/noctis-control")!)
        #expect(RequestRecorder.count > before, "the control request was not recorded")
    }

    // MARK: Copy

    private func swiftFiles(_ folder: String) throws -> [(path: String, text: String)] {
        let base = RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/" + folder)
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        var found: [(String, String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            found.append((url.path.replacingOccurrences(of: base.path + "/", with: ""), try String(contentsOf: url, encoding: .utf8)))
        }
        return found
    }

    /// Words that would make NOCTIS sound like a medical device or promise a health result, in any string a person can read. Every place one appears
    /// is listed with why it is allowed: a denial ("doesn't diagnose"), the banned-language list itself, a scripted refusal, or a data word.
    @Test func noStringClaimsToDiagnoseTreatCureOrPromiseAHealthResult() throws {
        let claim = try Regex(#"(?i)(diagnos|\btreat|\bcure\b|prevent|clinical|medical.grade|improves? your sleep|therap|disease|disorder|insomnia|apnea|symptom|\bheal(s|ing)?\b|prescri|clinically|guarantee|proven)"#)
        // File -> why every hit in it is fine.
        let justified: [String: String] = [
            "CoachKit/CoachPrompt.swift": "the instruction to the model: never diagnose, never give medical advice",
            "CoachKit/MockAIProvider.swift": "a deliberately bad answer the validator must reject (a test fixture, DEBUG)",
            "CoachKit/CoachTypes.swift": "the footer: it isn't medical advice",
            "CoachFeature/CoachPrivacySheet.swift": "the not-medical-advice section, and the refusal to diagnose",
            "ProfileFeature/SettingsContent.swift": "About: isn't a medical device and doesn't diagnose or treat",
            "NoctisText/NoctisMedicalNotice.swift": "the one denial, said everywhere",
            "NightFeature/TonightContent.swift": "the window 'isn't a medical measurement'",
            "SleepFeature/SleepScreen.swift": "sleep quality 'isn't a medical measurement'",
            "SleepFeature/SleepRangeContent.swift": "the balance line 'isn't a medical measure'",
            "InsightsKit/BannedLanguage.swift": "the list of words insights may never use",
            "NoctisCore/DataInventory+Shared.swift": "'Diagnostic log': the iPhone's log, not a medical term",
            "ProfileFeature/PrivacyViews.swift": "the enum case .diagnosticLog (the iPhone's log), an identifier and not copy",
            "NoctisCore/CoachQuestion.swift": "doc comments quoting the question 'Why was my sleep better / worse'",
        ]
        var unexplained: [String] = []
        for (path, text) in try swiftFiles("") {
            if justified[path] != nil { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), trimmed.contains("\""), (try? claim.firstMatch(in: String(line))) != nil else { continue }
                unexplained.append("\(path):\(number + 1): \(trimmed.prefix(120))")
            }
        }
        // The string catalogs hold the rest of what a person reads (Coach's answers, Help): every value is held to the same words.
        let catalogJustified: [String: String] = [
            "CoachKit/Resources/Coach.xcstrings": "the scripted medical refusal, the footer, and what Coach will not do",
            "ProfileFeature/Resources/Help.xcstrings": "Help says NOCTIS is not a medical device and where to turn for medical questions",
        ]
        let base = RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources")
        let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "xcstrings" else { continue }
            let path = url.path.replacingOccurrences(of: base.path + "/", with: "")
            if catalogJustified[path] != nil { continue }
            let data = try Data(contentsOf: url)
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = json["strings"] as? [String: Any] ?? [:]
            for (key, entry) in strings {
                let values = ((entry as? [String: Any])?["localizations"] as? [String: Any])?.values.compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String } ?? []
                for value in values + [key] where (try? claim.firstMatch(in: value)) != nil { unexplained.append("\(path): \(value.prefix(100))") }
            }
        }
        #expect(unexplained.isEmpty, "copy with a medical or outcome claim that no one has justified: \(unexplained.joined(separator: "\n"))")
    }

    @Test func theMedicalDisclaimerIsOnTheWelcomeScreenThePaywallAboutAndTheWatch() throws {
        #expect(NoctisMedicalNotice.statement == "NOCTIS isn't a medical device and doesn't diagnose or treat any condition.")
        for path in ["OnboardingFeature/WelcomeScreen.swift", "OnboardingFeature/PaywallScreen.swift"] {
            let text = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/" + path), encoding: .utf8)
            #expect(text.contains("NoctisMedicalNotice.statement"), Comment(rawValue: path))
        }
        #expect(AboutContent.medical == NoctisMedicalNotice.statement)
        #expect(WatchCopy.about == NoctisMedicalNotice.statement)
        // Coach's footer says the matching thing about advice, in the string catalog.
        let coach = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/CoachKit/Resources/Coach.xcstrings"), encoding: .utf8)
        #expect(coach.contains("Coach shares patterns from your data. It isn't medical advice."))
    }

    /// The paywall against the subscription rules: the price and period come from the product StoreKit returns (no price typed into the source), the
    /// words say it renews automatically and how to cancel, Restore, Terms and Privacy are on the screen, and closing is always possible.
    @Test func thePaywallStatesPriceTermAndRenewalFromStoreKitAndCanAlwaysBeLeft() throws {
        let text = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/OnboardingFeature/PaywallScreen.swift"), encoding: .utf8)
        #expect(text.contains("product.displayPrice") && text.contains("renewing automatically. Cancel anytime in Settings."))
        let typedPrice = try Regex(#"[$€£¥]\s?\d+[.,]\d\d"#)
        let shipped = text.components(separatedBy: "#Preview").first ?? text   // previews carry sample prices; they are not in the app
        #expect(try typedPrice.firstMatch(in: shipped) == nil, "a price typed into the paywall instead of read from the product")
        #expect(text.contains("StoreLegalLinks.terms") && text.contains("StoreLegalLinks.privacy") && text.contains("Restore Purchases"))
        // 'Continue with the free plan' is the way out in every phase: loading, unavailable and ready.
        #expect(text.components(separatedBy: "Continue with the free plan").count - 1 >= 3)
        // The trial's length is read from the product's own introductory offer.
        #expect(text.contains("TrialLength(") && text.contains("free, then"))
    }

    /// Export compliance: the app and the Watch app declare that they use no encryption beyond the system's, and that is true: no source of NOCTIS names a cryptography
    /// API (the Release binaries link none either, qa/privacy/symbols.txt), and it makes no network request of its own.
    @Test func theAppsDeclareNoNonExemptEncryptionAndUseNone() throws {
        // The key has a build setting (Export Compliance), so it is set there for the app and the Watch app, not in a plist (ConfigAuditTests).
        let project = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("project.yml"), encoding: .utf8)
        #expect(project.components(separatedBy: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO").count - 1 == 2, "the app and the Watch app declare it")
        let crypto = try Regex(#"import (CryptoKit|CommonCrypto|Security|CryptoTokenKit)\b|\bCCCrypt\b|\bSecKey[A-Z]|\bSymmetricKey\b|\bAES\.GCM\b|\bChaChaPoly\b|\bkSec[A-Z]"#)
        var hits: [String] = []
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App", "NOCTISWatch", "NOCTISWatchWidgets", "NoctisWidgets", "NoctisAlarmWidget"]) {
            // The one Keychain item (Sign in with Apple's identifier, R69) is the system's storage, not encryption NOCTIS performs: no key, cipher or
            // certificate is made or handled.
            if file.path.hasSuffix("NoctisCore/Account/AccountStore.swift") { continue }
            for line in file.text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                if try crypto.firstMatch(in: String(line)) != nil { hits.append(file.path) }
            }
        }
        #expect(hits.isEmpty, Comment(rawValue: "a cryptography API in \(hits)"))
    }

    /// An outcome promise is a sentence that says NOCTIS makes the person sleep or feel better. Goals the person picks may name what they want; nothing NOCTIS says
    /// about itself may promise it (QA-141). The goal subtitle once read "Fall asleep easier, wake less"; it is now about the evening and the routine, which the app
    /// does help with (the wind-down, the reminders), not about a result in the body.
    @Test func noStringPromisesAnOutcomeOfUsingTheApp() throws {
        let promise = try Regex(#"(?i)fall asleep (faster|easier|quicker)|asleep (faster|easier)|improve your (sleep|health|energy)|sleep (better|more soundly|deeper) with|wake less|will help you (sleep|relax|fall)|helps you (sleep|fall asleep)|guarantee|feel (rested|refreshed) (every|each)"#)
        // File -> why: owner-visible copy that names a goal, not a promise.
        let allowed: [String: String] = [:]
        var hits: [String] = []
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources"]) where allowed[file.path] == nil {
            for (number, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), trimmed.contains("\""), !file.path.contains("BannedLanguage") else { continue }
                if try promise.firstMatch(in: String(line)) != nil { hits.append("\(file.path):\(number + 1)") }
            }
        }
        #expect(hits.isEmpty, Comment(rawValue: "an outcome promise: \(hits.joined(separator: ", "))"))
        let goals = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/OnboardingFeature/GoalScreen.swift"), encoding: .utf8)
        #expect(goals.contains("A calmer wind-down and a steadier routine"))
    }
}
