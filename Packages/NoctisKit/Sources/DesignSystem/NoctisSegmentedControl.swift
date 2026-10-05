import SwiftUI

/// One choice of a `NoctisSegmentedControl`. A locked one (Premium, APP_RULES.md R57) shows a lock glyph before its title and says "Premium" to VoiceOver.
public struct NoctisSegment<Value: Hashable>: Identifiable {
    public let value: Value
    public let title: String
    public var isLocked: Bool

    public var id: Value { value }

    public init(_ value: Value, title: String, isLocked: Bool = false) {
        self.value = value
        self.title = title
        self.isLocked = isLocked
    }
}

/// The range control of Recovery and Sleep: the system's segmented look (a soft track, a lifted pill under the choice) with room for a lock glyph, which a
/// native segmented control cannot draw. Choosing a segment sets `selection`; the owner decides what a locked one means (it opens the paywall and leaves the
/// selection where it was, R58), so the pill only moves when the selection really does. Each segment is a 44pt target, the pill slides with the select spring
/// (and steps under Reduce Motion), and the group is one container of buttons with the chosen one selected.
public struct NoctisSegmentedControl<Value: Hashable>: View {
    private let label: String
    private let segments: [NoctisSegment<Value>]
    private let identifier: String
    @Binding private var selection: Value
    @Namespace private var pill
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ label: String, segments: [NoctisSegment<Value>], selection: Binding<Value>, identifier: String) {
        self.label = label
        self.segments = segments
        self._selection = selection
        self.identifier = identifier
    }

    private var trackFill: Color { colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
    private var pillFill: Color { colorScheme == .dark ? Color.black.opacity(0.30) : Color.white }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(trackFill))
        .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: selection)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func segmentButton(_ segment: NoctisSegment<Value>) -> some View {
        let isSelected = segment.value == selection
        return Button {
            selection = segment.value
        } label: {
            HStack(spacing: 4) {
                if segment.isLocked { LockGlyph(size: 11) }
                Text(segment.title)
                    .noctisFont(15, isSelected ? .semibold : .medium, relativeTo: .subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(NoctisAppColor.ink)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(pillFill)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            // The control is 36pt tall, as the system's is; the target around each segment is 44pt.
            .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.isLocked ? "\(segment.title), Premium" : segment.title)
        .accessibilityHint(segment.isLocked ? "Opens what Premium includes." : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("\(identifier).\(segment.title)")
    }
}
