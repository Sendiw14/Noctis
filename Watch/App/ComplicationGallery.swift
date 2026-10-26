#if DEBUG
import NoctisWatchKit
import NoctisWidgetKit
import SwiftUI
import WidgetKit

/// `-complicationGallery recovery|sleep|bedtime|quality [-complicationAccented] [-watchRedacted]` with the Watch app's mock flags (`-watchMockSnapshot`,
/// `-watchEvening`): one kind in all four families, drawn from the same `WatchComplications` content the extension uses, at nominal sizes (the real slot
/// varies with the watch and the face). A DEBUG aid: a face, a tinted face and the system's redaction need a real Watch. The corner's curved label is
/// the system's and only draws on a face, so it is written under the corner here.
struct ComplicationGallery: View {
    let kind: WatchComplicationKind
    let input: WatchPageInput
    let accented: Bool
    /// `-watchRedacted`: drawn as the system draws it while the Watch is locked.
    let redacted: Bool

    /// Nominal sizes in points: a circular and a corner slot, the rectangular slot, the inline line.
    static let circular = CGSize(width: 52, height: 52)
    static let corner = CGSize(width: 64, height: 64)
    static let rectangular = CGSize(width: 172, height: 74)
    static let inline = CGSize(width: 190, height: 22)

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-complicationGallery") else { return nil }
        let name = arguments.indices.contains(index + 1) ? arguments[index + 1] : "recovery"
        kind = WatchComplicationKind.allCases.first { $0.rawValue.lowercased().contains(name.lowercased()) } ?? .recovery
        // The same mock the Watch app uses; a gallery with no state named draws a full day.
        let mock = WatchMock(arguments: arguments.contains("-watchMockSnapshot") ? arguments : arguments + ["-watchMockSnapshot", "full"])
        input = WatchPageInput(snapshot: mock?.snapshot, now: mock?.now ?? Date())
        accented = arguments.contains("-complicationAccented")
        redacted = arguments.contains("-watchRedacted")
    }

    /// The content with its countdowns moved onto the system's clock: a timer-style `Text` counts to a real date, and the mock pretends it is another time.
    private var content: WatchComplicationContent {
        var made = WatchComplications.content(kind, input: input)
        let shift = Date().timeIntervalSince(input.now)
        func moved(_ pieces: [WidgetLockPiece]) -> [WidgetLockPiece] {
            pieces.map { if case .countdown(let date) = $0 { .countdown(date.addingTimeInterval(shift)) } else { $0 } }
        }
        made.rectangular = made.rectangular.map(moved)
        made.inline = moved(made.inline)
        return made
    }
    private var mode: WidgetRenderingMode { accented ? .accented : .fullColor }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(kind.displayName)\(accented ? " - accented" : "")").noctisFont(12, .semibold, relativeTo: .caption2).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 10) {
                slot(.circular, size: Self.circular, shape: Circle())
                VStack(spacing: 0) {
                    slot(.corner, size: Self.corner, shape: Circle())
                    Text("curved: \(content.cornerLabel)").noctisFont(12, relativeTo: .caption2).foregroundStyle(.white.opacity(0.6))
                }
            }
            slot(.rectangular, size: Self.rectangular, shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
            slot(.inline, size: Self.inline, shape: Rectangle(), fill: .clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .redacted(reason: redacted ? .privacy : [])
    }

    private func slot<S: Shape>(_ family: WatchComplicationFamily, size: CGSize, shape: S, fill: Color = Color.white.opacity(0.14)) -> some View {
        WatchComplicationView(content: content, family: family, renderingMode: mode)
            .padding(family == .rectangular ? 8 : 0)
            .frame(width: size.width, height: size.height)
            .background(shape.fill(fill))
            .clipShape(shape)
    }
}
#endif
