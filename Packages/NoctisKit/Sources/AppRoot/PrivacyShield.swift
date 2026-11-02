import DesignSystem
import SwiftUI
import UIKit

// What the app switcher may show (Stage 1A, audit SEC-05). iOS keeps a picture of the app's last screen for the app switcher, and it was a recovery score,
// last night's sleep or a Journal entry. While the app is not the active scene a plain screen covers everything, sheets included, and it goes the moment
// the scene is active again. Nothing underneath is touched: no view is rebuilt, no navigation resets, and alarms, audio, notifications, Live Activities
// and the Watch link never see it.
//
// It is a second window above the app's own (the way the system puts its alerts above an app), not a blur and not a screenshot trick: a SwiftUI overlay on
// the root view would leave a presented sheet visible, and a sheet is where the Journal opens. The window is not made key, so it takes no focus from the
// app, and it is thrown away on every return, so it keeps nothing.

/// Puts a cover over a scene, and takes it away.
@MainActor
public protocol PrivacyShieldPresenting: AnyObject {
    /// Covers `scene`, or every connected window scene when it is nil.
    func show(over scene: UIWindowScene?)
    func hide(over scene: UIWindowScene?)
}

/// Watches the scene's activity and asks the presenter to cover or uncover.
@MainActor
public final class PrivacyShield {
    /// The one the app uses.
    public static let shared = PrivacyShield()

    public private(set) var isCovering = false

    private let presenter: any PrivacyShieldPresenting
    private let center: NotificationCenter
    private var observers: [any NSObjectProtocol] = []

    public init(presenter: any PrivacyShieldPresenting = WindowShieldPresenter(), center: NotificationCenter = .default) {
        self.presenter = presenter
        self.center = center
    }

    /// Starts watching. A second call does nothing.
    public func start() {
        guard observers.isEmpty else { return }
        // `willDeactivate` comes before the system takes the app switcher's picture; `didActivate` is the return to the front.
        observers = [
            center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] note in
                let scene = note.object as? UIWindowScene
                MainActor.assumeIsolated { self?.cover(scene) }
            },
            center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
                let scene = note.object as? UIWindowScene
                MainActor.assumeIsolated { self?.uncover(scene) }
            },
        ]
    }

    func cover(_ scene: UIWindowScene?) {
        isCovering = true
        presenter.show(over: scene)
    }

    func uncover(_ scene: UIWindowScene?) {
        isCovering = false
        presenter.hide(over: scene)
    }
}

/// The real cover: one hidden-by-default window per scene, above every other window.
@MainActor
public final class WindowShieldPresenter: PrivacyShieldPresenting {
    private var windows: [ObjectIdentifier: UIWindow] = [:]

    public init() {}

    public func show(over scene: UIWindowScene?) {
        for target in targets(scene) where windows[ObjectIdentifier(target)] == nil {
            let window = UIWindow(windowScene: target)
            // Above the app's windows, its sheets and the system's own alerts raised by the app.
            window.windowLevel = .alert + 1
            let host = UIHostingController(rootView: PrivacyShieldView())
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.isHidden = false
            windows[ObjectIdentifier(target)] = window
        }
    }

    public func hide(over scene: UIWindowScene?) {
        for target in targets(scene) {
            guard let window = windows.removeValue(forKey: ObjectIdentifier(target)) else { continue }
            window.isHidden = true
            window.rootViewController = nil
        }
        // With no scene named, nothing may stay up: a window of a scene that has gone away is hidden too.
        if scene == nil {
            for window in windows.values { window.isHidden = true }
            windows.removeAll()
        }
    }

    private func targets(_ scene: UIWindowScene?) -> [UIWindowScene] {
        if let scene { return [scene] }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }
}

/// What the cover shows: the app's own background and one quiet symbol. No number, no name, no text, and nothing read from the app's data.
struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            NoctisAppColor.bg.ignoresSafeArea()
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(NoctisAppColor.ink3)
                .accessibilityHidden(true)
        }
    }
}
