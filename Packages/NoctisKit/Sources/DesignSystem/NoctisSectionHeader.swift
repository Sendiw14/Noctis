import SwiftUI

public struct NoctisSectionHeader: View {
    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            NoctisText(title, style: .eyebrow, color: NoctisColor.textTertiary)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    NoctisText(actionTitle, style: .caption, color: NoctisColor.textSecondary)
                }
                .buttonStyle(.noctisPress)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}
