import SwiftUI

// The rows Profile and Settings are made of: a card holding rows, each row an icon tile, a title, what it
// holds and, where it opens something, a chevron. Every row is at least 56pt tall and a whole-row target.

/// A card of rows, divided by hairlines. The rows run edge to edge inside the card's 20pt padding.
public struct NoctisRowCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
    }
}

/// The hairline between two rows, indented past the icon tile.
public struct NoctisRowDivider: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(NoctisAppColor.hairline)
            .frame(height: 1)
            // Indented past the icon tile, which is not there at accessibility sizes (see NoctisRow).
            .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : NoctisRow<EmptyView>.tile + NoctisSpacing.sm)
            .accessibilityHidden(true)
    }
}

/// One row: an icon tile, a title with an optional line under it, the value it holds and an accessory (a
/// chevron, a switch). It is not a button on its own; `NoctisLinkRow` is.
public struct NoctisRow<Accessory: View>: View {
    /// The tile's diameter at the default text size.
    public static var tile: CGFloat { 36 }

    private let systemImage: String
    private let fill: Color
    private let title: String
    private let detail: String?
    private let value: String?
    private let accessory: Accessory

    public init(
        systemImage: String, fill: Color, title: String, detail: String? = nil, value: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.systemImage = systemImage
        self.fill = fill
        self.title = title
        self.detail = detail
        self.value = value
        self.accessory = accessory()
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { stacked } else { inline }
        }
        .padding(.vertical, NoctisSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    /// The icon, the title and its line, the value and the accessory in one row.
    private var inline: some View {
        HStack(spacing: NoctisSpacing.sm) {
            NoctisIconTile(systemImage: systemImage, fill: fill, foreground: NoctisAppColor.blockInk, size: Self.tile)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The title is laid out first: when the row is tight (an SE, "3 reminders on" beside "Notifications") it is the value that
            // wraps at a space, not the title that breaks inside its word ("Notification / s").
            .layoutPriority(1)
            Spacer(minLength: NoctisSpacing.xs)
            if let value {
                Text(value)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .multilineTextAlignment(.trailing)
                    .contentTransition(.numericText())
            }
            accessory
        }
    }

    /// At accessibility sizes the value goes under the title and the icon tile goes: beside a 40pt tile and a value, "Subscription" at AX5
    /// had a column of 90pt and broke into "Sub / scri / ptio / n". The title takes up to three lines and, where one word is wider than the
    /// row, scales down to its word (never below 0.6) instead of breaking it; the line under it and the value take the width.
    private var stacked: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let value {
                    Text(value)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            accessory
        }
    }
}

extension NoctisRow where Accessory == EmptyView {
    public init(systemImage: String, fill: Color, title: String, detail: String? = nil, value: String? = nil) {
        self.init(systemImage: systemImage, fill: fill, title: title, detail: detail, value: value) { EmptyView() }
    }
}

/// The chevron at a row's trailing edge: this row opens something.
public struct NoctisRowChevron: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.forward")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.noctisInk3)
            .accessibilityHidden(true)
    }
}

/// A row that opens something: the whole row is a button, and its label reads as title, then value.
public struct NoctisLinkRow: View {
    private let systemImage: String
    private let fill: Color
    private let title: String
    private let detail: String?
    private let value: String?
    private let hint: String
    private let identifier: String
    private let action: () -> Void

    public init(
        systemImage: String, fill: Color, title: String, detail: String? = nil, value: String? = nil, hint: String,
        identifier: String, action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.fill = fill
        self.title = title
        self.detail = detail
        self.value = value
        self.hint = hint
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button {
            NoctisHaptics.selection()
            action()
        } label: {
            NoctisRow(systemImage: systemImage, fill: fill, title: title, detail: detail, value: value) { NoctisRowChevron() }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, value, detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// A row that only reports: no chevron, no button.
public struct NoctisInfoRow: View {
    private let systemImage: String
    private let fill: Color
    private let title: String
    private let detail: String?
    private let value: String
    private let identifier: String

    public init(systemImage: String, fill: Color, title: String, detail: String? = nil, value: String, identifier: String) {
        self.systemImage = systemImage
        self.fill = fill
        self.title = title
        self.detail = detail
        self.value = value
        self.identifier = identifier
    }

    public var body: some View {
        NoctisRow(systemImage: systemImage, fill: fill, title: title, detail: detail, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([title, value, detail].compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier(identifier)
    }
}
