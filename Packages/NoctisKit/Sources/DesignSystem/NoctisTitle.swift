import SwiftUI

/// R4's onboarding title: an ink line and one emphasized `orangeText`
/// phrase, revealed with the existing `NoctisRevealText` (words rise 14pt,
/// 70ms stagger, ending fully opaque). R3: the title takes its own natural
/// height (never a reserved 3-line block — that used to leave a phantom
/// blank line under every 1- or 2-line title, which R6 now forbids) with
/// `lineLimit(3)`, `minimumScaleFactor` and `fixedSize` as the never-
/// truncate guarantee — callers should still keep `line1`/`line2` short
/// enough to each read as one line at the base size, since
/// `NoctisRevealText`'s per-word renderer does not reliably wrap a single
/// fragment (see its own doc comment).
public struct NoctisTitle: View {
    private let line1: String
    private let line2: String?

    public init(_ line1: String, emphasis line2: String? = nil) {
        self.line1 = line1
        self.line2 = line2
    }

    public var body: some View {
        NoctisRevealText(line1, line2: line2, style: .paperTitle, color: NoctisPaper.ink, accent: NoctisPaper.orangeText)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}
