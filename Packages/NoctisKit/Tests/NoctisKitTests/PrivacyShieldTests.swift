import Foundation
import Testing
import UIKit

@testable import AppRoot

// Stage 1A, audit SEC-05: the app switcher must not show a recovery score, last night's sleep or a Journal entry. Whether iOS takes its picture of the
// cover and not of the app is a device fact (a unit test cannot open the app switcher), so these tests hold the part that is code: the cover goes up when
// the scene is about to leave the front, comes down when it is back, is started once, shows nothing from the app, and is wired at launch.
@MainActor
final class RecordingPresenter: PrivacyShieldPresenting {
    private(set) var shown: [UIWindowScene?] = []
    private(set) var hidden: [UIWindowScene?] = []
    func show(over scene: UIWindowScene?) { shown.append(scene) }
    func hide(over scene: UIWindowScene?) { hidden.append(scene) }
}

@MainActor
struct PrivacyShieldTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        _ = await waitFor(timeout: .seconds(5)) { condition() }
    }

    @Test func theCoverGoesUpWhenTheSceneIsAboutToLeaveTheFrontAndComesDownWhenItIsBack() async {
        let center = NotificationCenter()
        let presenter = RecordingPresenter()
        let shield = PrivacyShield(presenter: presenter, center: center)
        shield.start()
        #expect(!shield.isCovering && presenter.shown.isEmpty, "nothing is covered while the app is in front")

        center.post(name: UIScene.willDeactivateNotification, object: nil)
        await waitUntil { shield.isCovering }
        #expect(shield.isCovering && presenter.shown.count == 1, "covered before the system takes the app switcher's picture")

        center.post(name: UIScene.didActivateNotification, object: nil)
        await waitUntil { !shield.isCovering }
        #expect(!shield.isCovering && presenter.hidden.count == 1, "the app is back the moment the scene is active")
    }

    @Test func startingTwiceWatchesOnce() async {
        let center = NotificationCenter()
        let presenter = RecordingPresenter()
        let shield = PrivacyShield(presenter: presenter, center: center)
        shield.start()
        shield.start()
        center.post(name: UIScene.willDeactivateNotification, object: nil)
        await waitUntil { shield.isCovering }
        // Let anything else queued on the main queue run: a second observer would have covered again by now.
        for _ in 0..<50 { await Task.yield() }
        #expect(presenter.shown.count == 1, "a second start must not cover twice or leak an observer")
    }

    @Test func aCoverIsRaisedForEveryDeactivationAndLoweredForEveryActivation() async {
        let center = NotificationCenter()
        let presenter = RecordingPresenter()
        let shield = PrivacyShield(presenter: presenter, center: center)
        shield.start()
        for round in 1...3 {
            center.post(name: UIScene.willDeactivateNotification, object: nil)
            await waitUntil { presenter.shown.count == round }
            center.post(name: UIScene.didActivateNotification, object: nil)
            await waitUntil { presenter.hidden.count == round }
        }
        #expect(presenter.shown.count == 3 && presenter.hidden.count == 3 && !shield.isCovering)
    }

    @Test func theCoverShowsNothingFromTheApp() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/PrivacyShield.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(text)
        // The cover is a colour and a symbol: no text, no model, no store, no screen of the app.
        for forbidden in ["Text(", "AppModel", "@Environment", "Journal", "Recovery", "Sleep", "Coach", "Snapshot", "UserDefaults", "Logger", "NoctisAnalytics"] {
            #expect(!code.contains(forbidden), Comment(rawValue: "the privacy cover must not use \(forbidden)"))
        }
        #expect(code.contains("accessibilityHidden(true)"))
    }

    @Test func theCoverIsAnOwnWindowAboveTheAppThatTakesNoFocusAndIsThrownAwayOnReturn() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/PrivacyShield.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(text)
        #expect(code.contains("windowLevel = .alert + 1"), "above sheets: a Journal sheet would stay visible under a mere overlay on the root view")
        #expect(!code.contains("makeKeyAndVisible") && !code.contains("makeKey"), "taking key status would steal focus from the app")
        #expect(code.contains("windows.removeValue(forKey:") && code.contains("rootViewController = nil"), "kept for no longer than the inactive moment")
    }

    @Test func theAppStartsTheShieldAtLaunch() throws {
        let text = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/NoctisApp.swift"), encoding: .utf8)
        #expect(RawDefaultsTests.code(text).contains("PrivacyShield.shared.start()"), "without this call the app switcher shows the app")
    }
}
