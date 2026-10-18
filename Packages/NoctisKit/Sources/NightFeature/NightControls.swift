import DesignSystem
import SwiftUI

// The flat controls of the night screens (APP_RULES.md R32, R33, R34, R35): the wind-down and what opens
// over it. Fixed NoctisNight colors, because these screens look the same in system Light and Dark.

/// The one main action: a 58pt ivory capsule with night ink. Fixed colors: this screen is dark in
/// both modes.
struct NightPrimaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).noctisFont(17, .semibold, relativeTo: .body)
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(NoctisNight.night)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(NoctisNight.ivory, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A quiet 44pt text action.
struct NightQuietButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .noctisFont(15, .medium, relativeTo: .subheadline)
                .foregroundStyle(NoctisNight.ivory2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NightCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .tracking(1)
            .foregroundStyle(NoctisNight.ivory2)
            // The whole caption, on as many lines as it needs ("SOUND, IF YOU LI…" at AX5).
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A choice: ivory when chosen, a quiet ivory wash when not. 44pt.
struct NightChip: View {
    let title: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(isSelected ? NoctisNight.night : NoctisNight.ivory)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, NoctisSpacing.md)
                .frame(minHeight: 44)
                .background(isSelected ? NoctisNight.ivory : NoctisNight.ivory.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

struct NightPill: View {
    let title: String
    let symbol: String?
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).accessibilityHidden(true)
                }
                Text(title).noctisFont(15, .semibold, relativeTo: .subheadline)
            }
            .foregroundStyle(NoctisNight.ivory)
            .padding(.horizontal, NoctisSpacing.md)
            .frame(minHeight: 44)
            .background(NoctisNight.ivory.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

struct NightIconButton: View {
    let symbol: String
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NoctisNight.ivory)
                .frame(width: 44, height: 44)
                .background(NoctisNight.ivory.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

