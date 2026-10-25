import Foundation
import SwiftData
import Testing

@testable import HealthProviding
@testable import NoctisCore
@testable import PremiumKit

// The lock components and the paywall's context (APP_RULES.md R58, R59): honest words, nothing that presses, a paywall that opens only on a tap and always has
// a way out, one comparison made from the one table.

struct PremiumLockTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: RawDefaultsTests.root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: Words

    @Test func everyLockedCardSaysExactlyWhatIsIncludedInOneLine() {
        var titles: Set<String> = []
        var count = 0
        for context in PaywallContext.allCases {
            guard let card = LockedCopy.card(for: context) else { continue }
            count += 1
            #expect(!card.title.isEmpty && card.line.hasSuffix("."), Comment(rawValue: context.rawValue))
            #expect(card.line.contains("Premium"), "the line says what Premium has")
            #expect(titles.insert(card.title).inserted)
            #expect(card.line.split(separator: ".").count <= 2, "one line, not a paragraph")
        }
        #expect(count == 6, "sleep quality, insights, Coach at zero, Tonight's window, the weekly review and the monthly review")
        #expect(LockedCopy.card(for: .coachQuestions)?.title == "You've used today's free questions.")
        #expect(LockedCopy.card(for: .coachQuestions)?.line.hasPrefix("They reset at midnight.") == true)
        #expect(LockedCopy.seePremium == "See Premium")
    }

    @Test func nothingPressesHurriesOrShames() {
        var everything: [String] = PaywallContext.allCases.map(\.line) + Feature.allCases.map { FeatureTable.title(of: $0) } + [LockedCopy.seePremium]
        for context in PaywallContext.allCases { if let card = LockedCopy.card(for: context) { everything += [card.title, card.line] } }
        everything += [CoachQuota.usedUpTitle, CoachQuota.usedUpDetail, CoachQuota.line(remaining: 2)]
        for text in everything { #expect(LockedCopy.pressure(in: text).isEmpty, Comment(rawValue: "\"\(text)\" presses: \(LockedCopy.pressure(in: text))")) }
        #expect(LockedCopy.pressure(in: "Last chance: 50% off, hurry!").count >= 3, "the check itself works")
    }

    @Test func thePaywallsAndTheComparisonCopyIsHeldToTheSameWords() throws {
        for path in ["Packages/NoctisKit/Sources/OnboardingFeature/PaywallScreen.swift", "Packages/NoctisKit/Sources/OnboardingFeature/PaywallFacts.swift", "Packages/NoctisKit/Sources/OnboardingFeature/PremiumComparisonSheet.swift"] {
            let code = RawDefaultsTests.code(try read(path))
            let strings = code.components(separatedBy: "\"").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            for text in strings where !LockedCopy.pressure(in: text).isEmpty {
                // The paywall's own pre-existing words about a free trial ending are the store's, not pressure: they are about the real trial.
                #expect(text.lowercased().contains("trial"), Comment(rawValue: "\(path): \"\(text)\""))
            }
        }
    }

    // MARK: Context

    @Test func theParagraphAboveThePaywallsTitleNamesWhatWasTapped() {
        #expect(PaywallContext(feature: .recovery90D).line == "Unlock 90-day Recovery trends")
        #expect(PaywallContext(feature: .sleepNightPicker14).line == "Unlock your last 14 nights")
        #expect(PaywallContext(feature: .coachUnlimited).line == "Unlock unlimited Coach questions")
        #expect(PaywallContext(feature: .recoveryToday) == .general, "a free feature has nothing to unlock")
    }

    @MainActor
    @Test func thePaywallIsPresentedAndDismissedByTheModelAndStartsClosed() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        #expect(model.paywall == nil, "never on launch")
        model.presentPaywall(for: .recovery30D)
        #expect(model.paywall == .recovery30D)
        model.dismissPaywall()
        #expect(model.paywall == nil, "closing changes nothing else")
    }

    @Test func noCodePresentsThePaywallFromAnAppearanceATaskOrAChange() {
        var calls = 0
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources"]) {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated() where line.contains("presentPaywall(") && !line.contains("func presentPaywall") {
                calls += 1
                let window = lines[max(0, index - 4)...index].joined(separator: "\n")
                for trigger in [".onAppear", ".task", ".onChange", ".onDisappear"] {
                    #expect(!window.contains(trigger), Comment(rawValue: "\(file.path):\(index + 1) opens the paywall near \(trigger)"))
                }
            }
        }
        _ = calls
    }

    @Test func everyPaywallSheetHasAVisibleWayOut() throws {
        let paywall = try read("Packages/NoctisKit/Sources/OnboardingFeature/PaywallScreen.swift")
        #expect(paywall.contains("xmark") && paywall.contains(".accessibilityLabel(\"Close\")") && paywall.contains("dismissWithoutSubscribing"))
        let comparison = try read("Packages/NoctisKit/Sources/OnboardingFeature/PremiumComparisonSheet.swift")
        #expect(comparison.contains("Button(\"Done\")"))
        let root = try read("Packages/NoctisKit/Sources/AppRoot/RootView.swift")
        #expect(root.contains(".sheet(item: Bindable(model).paywall)") && root.contains("model.dismissPaywall()"))
    }

    // MARK: One comparison, one table

    @Test func theComparisonIsMadeFromTheTableAndTheOldFreeFormCopyIsGone() throws {
        let sheet = try read("Packages/NoctisKit/Sources/OnboardingFeature/PremiumComparisonSheet.swift")
        #expect(sheet.contains("FeatureTable.comparison()") && sheet.contains("Not included") && sheet.contains("Included"))
        let paywall = try read("Packages/NoctisKit/Sources/OnboardingFeature/PaywallScreen.swift")
        #expect(paywall.contains("PremiumComparisonSheet()") && !paywall.contains("includedFree") && !paywall.contains("private struct CompareSheet"))
        #expect(!paywall.contains("Trends up to a year"), "nothing is promised that is not built")
        let settings = try read("Packages/NoctisKit/Sources/ProfileFeature/SettingsPages.swift")
        #expect(settings.contains("What Premium includes") && settings.contains("PremiumComparisonSheet()"))
    }

    @Test func theLockComponentsHaveTheTargetsAndTextSizesTheRulesAsk() throws {
        let code = RawDefaultsTests.code(try read("Packages/NoctisKit/Sources/DesignSystem/NoctisPremium.swift"))
        #expect(code.contains("minHeight: 44"), "See Premium is at least 44pt")
        #expect(code.contains("noctisFont(12, .semibold") && code.contains("Text(\"Premium\")"), "the badge says Premium at 12pt")
        for size in code.components(separatedBy: "noctisFont(").dropFirst().compactMap({ Int($0.prefix { $0.isNumber }) }) { #expect(size >= 12) }
        #expect(code.contains("accessibilityLabel(\"\\(title), Premium\")"), "a locked row says it is Premium")
        #expect(!code.contains("blur") && !code.contains(".redacted"), "no blurred fake data over a locked area")
    }

    @Test func atMostOneLockedCardIsOnAScreen() {
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources"]) where !file.path.hasSuffix("NoctisPremium.swift") {
            let code = RawDefaultsTests.code(file.text)
            let count = code.components(separatedBy: "LockedCard(").count - 1
            #expect(count <= 1, Comment(rawValue: "\(file.path) has \(count) locked cards"))
        }
    }
}
