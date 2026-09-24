import SwiftUI

/// The placeholder for a main-app tab that isn't built yet (APP_RULES.md
/// R19): the tab's title and a plain "Coming soon" card, nothing
/// tappable. Every screen using it is listed in ROADMAP.md.
public struct NoctisComingSoonView: View {
    private let title: String
    private let systemImage: String

    public init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        ScrollView {
            // R3/R6: content starts exactly 24pt below the title.
            VStack(alignment: .leading, spacing: NoctisSpacing.xl) {
                Text(title)
                    .noctisFont(38, .bold, relativeTo: .largeTitle)
                    .tracking(-0.6)
                    .foregroundStyle(NoctisAppColor.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: systemImage)
                        .noctisIcon(17)
                        .foregroundStyle(NoctisAppColor.orangeText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coming soon")
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                        Text("This part of NOCTIS isn't ready yet.")
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(NoctisSpacing.lg)
                .background(NoctisAppColor.surface, in: RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, NoctisSpacing.xl)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
    }
}

#Preview("Light") {
    NoctisComingSoonView(title: "Sleep", systemImage: "moon.zzz")
}

#Preview("Dark") {
    NoctisComingSoonView(title: "Sleep", systemImage: "moon.zzz")
        .preferredColorScheme(.dark)
}
