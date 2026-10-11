#if DEBUG
import SwiftUI
import UIKit

// QA part 3 (QA_COVERAGE.md, APP_RULES.md R67): what the app itself sees of the device's settings. A run of the matrix under "Bold Text" or
// "Right-to-Left" counts only if the app read that setting, so the harness reads this element after launch and writes it beside the screenshots.
// `-noctisEnvironmentProbe` puts one invisible 2 x 2 element at the top of the window: identifier `debug.environment`, value `key=value;...`.

struct EnvironmentProbeModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.legibilityWeight) private var legibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @Environment(\.accessibilityShowButtonShapes) private var buttonShapes
    @Environment(\.accessibilityInvertColors) private var invertColors
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.displayScale) private var displayScale

    private var summary: String {
        let hourFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        let pairs: [(String, String)] = [
            ("textSize", "\(typeSize)"),
            ("boldText", legibility == .bold ? "1" : "0"),
            ("reduceMotion", reduceMotion ? "1" : "0"),
            ("reduceTransparency", reduceTransparency ? "1" : "0"),
            ("differentiateWithoutColor", differentiate ? "1" : "0"),
            ("buttonShapes", buttonShapes ? "1" : "0"),
            ("onOffLabels", UIAccessibility.isOnOffSwitchLabelsEnabled ? "1" : "0"),
            ("invertColors", invertColors ? "1" : "0"),
            ("increaseContrast", contrast == .increased ? "1" : "0"),
            ("colorScheme", colorScheme == .dark ? "dark" : "light"),
            ("layoutDirection", layoutDirection == .rightToLeft ? "rtl" : "ltr"),
            ("locale", locale.identifier),
            ("calendar", "\(calendar.identifier)"),
            ("timeZone", timeZone.identifier),
            ("hourFormat", hourFormat),
            ("firstWeekday", "\(calendar.firstWeekday)"),
            ("scale", "\(Int(displayScale))"),
            ("voiceOver", UIAccessibility.isVoiceOverRunning ? "1" : "0"),
        ]
        return pairs.map { "\($0.0)=\($0.1)" }.joined(separator: ";")
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 2, height: 2)
                .accessibilityElement()
                .accessibilityIdentifier("debug.environment")
                .accessibilityLabel("Environment")
                .accessibilityValue(summary)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Adds the environment probe when the app was launched with `-noctisEnvironmentProbe`.
    @ViewBuilder
    public func debugEnvironmentProbe() -> some View {
        if ProcessInfo.processInfo.arguments.contains("-noctisEnvironmentProbe") {
            modifier(EnvironmentProbeModifier())
        } else {
            self
        }
    }
}
#endif
