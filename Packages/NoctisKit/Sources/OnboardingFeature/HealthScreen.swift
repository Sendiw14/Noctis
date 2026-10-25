import DesignSystem
import HealthProviding
import NoctisCore
import SwiftUI

/// The three signals NOCTIS asks to read, in the order shown. Sourced from `HealthDataKind` (shared with the rest of the app) rather than hardcoded here,
/// so the label and icon shown always match what is actually requested. Activity/steps is deliberately excluded: `RecoveryFactorKind` has no case that
/// reads activity data today, and Recovery itself is never listed here: it is computed from these signals, not a permission of its own.
enum HealthStepFacts {
    static let requestedKinds: [HealthDataKind] = [.sleepAnalysis, .heartRate, .hrv]

    /// The line on each card (the longer `HealthDataKind.benefit` is the Privacy Center's).
    static func line(_ kind: HealthDataKind) -> String {
        switch kind {
        case .sleepAnalysis: "How long and consistently you sleep"
        case .heartRate: "Puts your recovery trend in context"
        case .hrv: "Your recovery signal vs your own baseline"
        default: kind.benefit
        }
    }

    static func title(_ kind: HealthDataKind) -> String {
        switch kind {
        case .sleepAnalysis: "Sleep"
        case .heartRate: "Heart rate"
        case .hrv: "HRV"
        default: kind.displayName
        }
    }

    /// What VoiceOver reads: "Sleep, how long and consistently you sleep".
    static func spoken(_ kind: HealthDataKind) -> String {
        let line = line(kind)
        return "\(title(kind)), \(line.prefix(1).lowercased() + line.dropFirst())"
    }
}

private enum ConnectOutcome {
    case idle
    case connecting
    /// `requestAuthorization` came back `.unavailable`: a genuine mid-flow failure, distinct from the person simply declining (which iOS never reports, so a
    /// plain decline is treated identically to authorized: proceed and advance).
    case error
}

/// Step 4/6, in the band style (APP_RULES.md R6, R69): what NOCTIS reads from Apple Health, and why. Real HealthKit authorization on "Connect" via the
/// existing `AppModel`/`HealthDataProviding` seam. iOS never says which read types were allowed, so no card ever claims "connected" (R13): the cards pulse
/// once as the sheet returns and the step moves on, whatever was chosen.
struct HealthScreen: View {
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var outcome: ConnectOutcome = .idle
    @State private var appeared = false
    @State private var pulsing = false

    private var isAvailable: Bool { model.isHealthDataAvailable }

    var body: some View {
        OnboardingStepScaffold(
            section: .coach, step: 3, title: ["Connect your", "signals."], bandHeight: 244,
            bandAccessory: AnyView(SignalsBadge(appeared: appeared || reduceMotion, reduceMotion: reduceMotion)), onBack: onBack
        ) {
            VStack(spacing: 8) {
                if !isAvailable { unavailableBanner }
                ForEach(Array(HealthStepFacts.requestedKinds.enumerated()), id: \.element) { index, kind in
                    SignalCard(kind: kind)
                        .opacity(isAvailable ? 1 : 0.4)
                        .scaleEffect(pulsing ? 1.03 : 1)
                        .slideUp(index: index, appeared: appeared || reduceMotion, reduceMotion: reduceMotion, stagger: 0.07)
                }
                privacyCard
                    .padding(.top, 6)
                    .slideUp(index: 3, appeared: appeared || reduceMotion, reduceMotion: reduceMotion, stagger: 0.07)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: pulsing)
        } actions: {
            bottomStack
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
        }
    }

    // MARK: Cards

    /// "Read-only." in bold, then the rest, from the inventory's own sentence (R41).
    private var privacyCard: some View {
        let inventoryNote = PrivacyStatements.readOnlyNote(.shared)
        let note = inventoryNote ?? "You control access in the Health app at any time."
        // The inventory's first sentence is the bold lead (R41); the fallback has none.
        let lead = inventoryNote.flatMap { text in text.firstIndex(of: ".").map { String(text[...$0]) } } ?? ""
        var text = AttributedString(lead)
        text.font = .system(size: 13, weight: .bold, design: .rounded)
        var rest = AttributedString(String(note.dropFirst(lead.count)))
        rest.font = .system(size: 13, weight: .regular, design: .rounded)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(NoctisPaper.ivory).accessibilityHidden(true)
            Text(text + rest)
                .foregroundStyle(NoctisPaper.ivory)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(NoctisPaper.cocoa))
        .overlay { if colorScheme == .dark { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(NoctisPaper.ivory.opacity(0.12), lineWidth: 1) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note)
        .accessibilityIdentifier("health.privacy")
    }

    private var unavailableBanner: some View {
        HStack(spacing: NoctisSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").noctisIcon(15, relativeTo: .subheadline).foregroundStyle(NoctisPaper.butter).accessibilityHidden(true)
            Text("Health data isn't available on this device.")
                .noctisFont(14, relativeTo: .subheadline)
                .foregroundStyle(colorScheme == .dark ? NoctisPaper.ivory : NoctisPaper.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(NoctisSpacing.sm)
        .background(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous).fill(NoctisPaper.butter.opacity(colorScheme == .dark ? 0.18 : 0.35)))
    }

    // MARK: Actions

    @ViewBuilder
    private var bottomStack: some View {
        if !isAvailable {
            OnboardingPrimaryButton("Continue without Health data", identifier: "health.skip", action: onNext)
        } else {
            switch outcome {
            case .error:
                VStack(spacing: 4) {
                    Text("Couldn't reach Health right now.")
                        .noctisFont(14, relativeTo: .subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(colorScheme == .dark ? NoctisPaper.ivory.opacity(0.8) : NoctisPaper.ink.opacity(0.8))
                    OnboardingPrimaryButton("Try again", identifier: "health.connect", action: connect)
                    OnboardingSecondaryButton("Continue without Health data", identifier: "health.skip", action: onNext)
                }
            case .idle, .connecting:
                VStack(spacing: 4) {
                    OnboardingPrimaryButton("Connect Apple Health", isEnabled: outcome != .connecting, identifier: "health.connect", action: connect)
                    OnboardingSecondaryButton("Continue without Health data", identifier: "health.skip", action: onNext)
                }
            }
        }
    }

    private func connect() {
        outcome = .connecting
        Task {
            await model.requestHealthAuthorization(for: HealthStepFacts.requestedKinds)
            guard model.healthAuthorization != .unavailable else {
                outcome = .error
                return
            }
            outcome = .idle
            // One synchronized settle pulse, never a per-row stagger and never a "connected" mark: iOS never reveals which of these were allowed (R13).
            pulsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pulsing = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { onNext() }
        }
    }
}

/// Three flat circles (sage, lavender, orange on top at 92%) with an ivory crescent in the middle: a small drawing, not a control.
private struct SignalsBadge: View {
    let appeared: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().fill(NoctisPaper.sage).frame(width: 46, height: 46).offset(x: appeared ? -18 : -4)
            Circle().fill(NoctisPaper.lavender).frame(width: 46, height: 46).offset(x: appeared ? 18 : 4)
            Circle().fill(NoctisPaper.orange.opacity(0.92)).frame(width: 46, height: 46).offset(y: -4)
            Image(systemName: "moon.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(NoctisPaper.ivory).offset(y: -4)
        }
        .frame(width: 84, height: 59)
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7).delay(0.2), value: appeared)
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }
}

/// The step's cards slide up 12 pt and fade in, one after another.
extension View {
    func slideUp(index: Int, appeared: Bool, reduceMotion: Bool, stagger: Double) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82).delay(Double(index) * stagger), value: appeared)
    }
}

/// One signal: an ivory circle with its icon, the name and one line, on its own colour. On a short screen (an SE) it gives a little height back so the
/// privacy card is whole above the buttons; at accessibility sizes the words go under the icon.
private struct SignalCard: View {
    let kind: HealthDataKind

    @Environment(\.onboardingScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var fill: Color {
        switch kind {
        case .sleepAnalysis: NoctisPaper.sage
        case .heartRate: NoctisPaper.orange
        case .hrv: NoctisPaper.lavender
        default: NoctisPaper.cocoa
        }
    }

    var body: some View {
        let wrap = dynamicTypeSize.isAccessibilitySize
        let compact = scale < 0.85
        let layout = wrap ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
        layout {
            ZStack {
                Circle().fill(NoctisPaper.ivory)
                Image(systemName: kind.systemImage).font(.system(size: compact ? 19 : 21, weight: .semibold)).foregroundStyle(NoctisPaper.ink)
            }
            .frame(width: compact ? 44 : 50, height: compact ? 44 : 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(HealthStepFacts.title(kind))
                    .noctisFont(19, .heavy, relativeTo: .headline, maxScale: 1.25)
                    .foregroundStyle(NoctisPaper.ink)
                Text(HealthStepFacts.line(kind))
                    .noctisFont(13, relativeTo: .footnote, maxScale: 1.25)
                    // 90%, not the design's 80%: on the orange and the lavender 80% is 4.0:1 and 4.2:1 (BandStyleContrastTests), and this is 13 pt text.
                    .foregroundStyle(NoctisPaper.ink.opacity(0.9))
                    .lineLimit(wrap ? 4 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !wrap { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, compact ? 8 : 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 78 : 92, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(fill))
        .shadow(color: NoctisPaper.ink.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 10, x: 0, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HealthStepFacts.spoken(kind))
        .accessibilityIdentifier("health.card.\(kind.rawValue)")
    }
}
