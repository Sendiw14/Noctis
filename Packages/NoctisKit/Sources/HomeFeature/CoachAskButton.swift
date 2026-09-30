import DesignSystem
import NoctisCore
import SwiftUI

/// "Ask Coach why", "Ask Coach about this": a 44pt text button that opens the
/// Coach tab on a question, already asked. It is the only way another tab
/// reaches Coach, and it goes through `AppModel.open(.coach(question:))` like
/// every other route.
public struct CoachAskButton: View {
    private let title: String
    private let question: CoachQuestion
    private let identifier: String
    @Environment(AppModel.self) private var appModel

    public init(_ title: String, question: CoachQuestion, identifier: String) {
        self.title = title
        self.question = question
        self.identifier = identifier
    }

    public var body: some View {
        Button {
            NoctisHaptics.selection()
            appModel.open(.coach(question: question))
        } label: {
            HStack(spacing: NoctisSpacing.xs) {
                Image(systemName: "sparkles").noctisIcon(14, .semibold, relativeTo: .subheadline)
                Text(title).noctisFont(15, .semibold, relativeTo: .subheadline)
            }
            .foregroundStyle(NoctisSection.coach.ink)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Coach with this question.")
        .accessibilityIdentifier(identifier)
    }
}
