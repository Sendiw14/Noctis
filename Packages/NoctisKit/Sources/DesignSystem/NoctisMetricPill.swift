import SwiftUI

public struct NoctisMetricPill: View {
    private let systemImage: String
    private let value: String
    private let label: String
    private let tint: Color

    public init(systemImage: String, value: String, label: String, tint: Color = NoctisColor.textSecondary) {
        self.systemImage = systemImage
        self.value = value
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            NoctisText(value, style: .headline)
            NoctisText(label, style: .caption, color: NoctisColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

public struct NoctisMetricRowItem: Identifiable {
    public let id = UUID()
    public let systemImage: String
    public let value: String
    public let label: String
    public let tint: Color

    public init(systemImage: String, value: String, label: String, tint: Color = NoctisColor.textSecondary) {
        self.systemImage = systemImage
        self.value = value
        self.label = label
        self.tint = tint
    }
}

public struct NoctisMetricRow: View {
    private let items: [NoctisMetricRowItem]

    public init(_ items: [NoctisMetricRowItem]) {
        self.items = items
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { item in
                NoctisMetricPill(systemImage: item.systemImage, value: item.value, label: item.label, tint: item.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.id != items.last?.id {
                    Rectangle()
                        .fill(NoctisColor.divider)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, NoctisSpacing.xxs)
                }
            }
        }
    }
}
