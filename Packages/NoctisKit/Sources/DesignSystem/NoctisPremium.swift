import SwiftUI

// What a locked area looks like (APP_RULES.md R58): a flat card, a row, a segment's label and a badge, all saying exactly what unlocks and nothing else. No
// blur over fake data, no sample numbers, no countdown, no scarcity. The words come from the caller (from `PremiumKit`'s tables); these only lay them out. The
// tap target of everything here is at least 44pt, and the lock is a glyph with a word beside it, never a color alone.

/// "Premium": a cocoa capsule with ivory text, 12pt.
public struct PremiumBadge: View {
    public init() {}

    public var body: some View {
        Text("Premium")
            .noctisFont(12, .semibold, relativeTo: .caption)
            .foregroundStyle(NoctisNight.ivory)
            .padding(.horizontal, NoctisSpacing.sm)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(NoctisAppColor.blockCocoa))
            .accessibilityLabel("Premium")
    }
}

/// A small lock glyph, for a label that opens the paywall instead of what it names.
public struct LockGlyph: View {
    private let size: CGFloat

    public init(size: CGFloat = 12) {
        self.size = size
    }

    public var body: some View {
        Image(systemName: "lock.fill")
            .noctisIcon(size, .semibold, relativeTo: .caption)
            .accessibilityHidden(true)
    }
}

/// A locked area of a screen: an icon tile, a title, ONE honest line saying exactly what is included, the Premium badge, and a secondary "See Premium" button.
/// At most one on a screen.
public struct LockedCard: View {
    private let systemImage: String
    private let title: String
    private let line: String
    private let buttonTitle: String
    private let identifier: String
    private let action: () -> Void

    public init(systemImage: String = "lock.fill", title: String, line: String, buttonTitle: String = "See Premium", identifier: String = "locked.card", action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.line = line
        self.buttonTitle = buttonTitle
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(alignment: .center) {
                    NoctisIconTile(systemImage: systemImage, fill: NoctisAppColor.blockButter, size: 36)
                    Spacer(minLength: NoctisSpacing.sm)
                    PremiumBadge()
                }
                Text(title)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(line)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NoctisHaptics.selection()
                    action()
                } label: {
                    Text(buttonTitle)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule(style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1.5))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens what Premium includes.")
                .accessibilityIdentifier("\(identifier).see")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// A segment's label: its title, with a small lock glyph before it while it is Premium. A segmented control has no room for a badge, so the glyph is the
/// mark; the control's own handler opens the paywall and leaves the selection where it was.
public func lockedSegmentLabel(_ title: String, locked: Bool) -> Text {
    locked ? Text("\(Image(systemName: "lock.fill")) \(title)") : Text(title)
}
