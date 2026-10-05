#if os(watchOS)
import DesignSystem
import NoctisWidgetKit
import SwiftUI
import WidgetKit

// The four complications drawn (APP_RULES.md R50, R54): flat, the app's colors, `noctisFont` text (never under 12pt), no gradients. They draw a
// `WatchComplicationContent` and decide nothing; the extension adds `containerBackground(for: .widget)` and `widgetURL`, and the DEBUG gallery in the
// Watch app draws its own background. A Health value is hidden while the Watch is locked (`.privacy` redaction) and is also marked `privacySensitive`
// so the system's own redaction agrees.

public struct WatchComplicationView: View {
    let content: WatchComplicationContent
    let family: WatchComplicationFamily
    /// The gallery draws the accented look too; a real complication reads the system's.
    let forcedMode: WidgetRenderingMode?
    @Environment(\.widgetRenderingMode) private var environmentMode
    @Environment(\.redactionReasons) private var reasons

    public init(content: WatchComplicationContent, family: WatchComplicationFamily, renderingMode: WidgetRenderingMode? = nil) {
        self.content = content
        self.family = family
        self.forcedMode = renderingMode
    }

    private var mode: WidgetRenderingMode { forcedMode ?? environmentMode }
    private var isLocked: Bool { reasons.contains(.privacy) && content.kind.showsHealth }
    private var shown: WatchComplicationContent { isLocked ? content.locked() : content }
    private var tint: Color {
        guard mode == .fullColor else { return .primary }
        switch content.kind {
        case .recovery: return NoctisAppColor.lavender
        case .sleep, .quality: return NoctisAppColor.sage
        case .bedtime: return NoctisAppColor.butter
        }
    }

    public var body: some View {
        Group {
            switch family {
            case .circular: circular
            case .rectangular: rectangular
            case .inline: inline
            case .corner: corner
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.accessibilityLabel)
    }

    // MARK: Circular

    @ViewBuilder
    private var circular: some View {
        if content.isLocked {
            // A kind the plan does not include: the lock alone, whichever kind it is.
            center(size: 17)
                .widgetAccentable()
        } else {
            circularKind
        }
    }

    @ViewBuilder
    private var circularKind: some View {
        switch content.kind {
        case .recovery, .quality:
            if let gauge = shown.gauge {
                // The number inside a gauge.
                Gauge(value: gauge) {
                    Image(systemName: content.kind == .recovery ? "bolt.heart.fill" : "moon.zzz.fill")
                } currentValueLabel: {
                    center(size: 17)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(tint)
                .widgetAccentable()
            } else {
                // No number (a message, old numbers, locked): just the glyph, never an empty track that looks like a reading.
                center(size: 17)
                    .widgetAccentable()
            }
        case .sleep:
            center(size: 17)
                .widgetAccentable()
        case .bedtime:
            VStack(spacing: 0) {
                Image(systemName: "moon.stars.fill").noctisIcon(13, .semibold, relativeTo: .footnote).foregroundStyle(tint).widgetAccentable()
                center(size: 15)
            }
        }
    }

    /// The number in the middle: its glyph instead when there is none.
    @ViewBuilder
    private func center(size: CGFloat) -> some View {
        if let glyph = shown.centerGlyph, shown.centerText.isEmpty {
            Image(systemName: glyph).noctisIcon(16, .semibold, relativeTo: .body)
        } else {
            Text(shown.centerText).noctisFont(size, .bold, relativeTo: .headline).minimumScaleFactor(0.7).lineLimit(1)
                .privacySensitive(content.centerIsHealth)
        }
    }

    // MARK: Rectangular

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(shown.rectangular.enumerated()), id: \.offset) { index, line in
                lineText(line)
                    .noctisFont(index == 0 ? 14 : 13, index == 0 ? .semibold : .regular, relativeTo: .footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive(hasHealth(line))
                    .widgetAccentable(index == 0)
                if index == 0, let stages = shown.stages {
                    WidgetStageStrip(stages: stages, height: 8)
                        .frame(height: 8)
                        .privacySensitive()
                        .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Inline

    private var inline: some View {
        lineText(shown.inline).privacySensitive(hasHealth(shown.inline))
    }

    // MARK: Corner

    /// A gauge in the corner with the kind's name curved along the edge; the number where there is one.
    private var corner: some View {
        center(size: 17)
            .widgetCurvesContent()
            .widgetLabel {
                if !content.isLocked, shown.gauge != nil || content.kind == .recovery || content.kind == .quality {
                    Gauge(value: shown.gauge ?? 0) {
                        Text(content.cornerLabel)
                    } currentValueLabel: {
                        Text(shown.centerText)
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(tint)
                } else {
                    Text(content.cornerLabel)
                }
            }
            .widgetAccentable()
    }

    // MARK: Lines

    private func hasHealth(_ pieces: [WidgetLockPiece]) -> Bool {
        pieces.contains { if case .health = $0 { true } else { false } }
    }

    /// The pieces as one `Text`: a countdown is the system's timer style, which ticks by itself with no reload.
    private func lineText(_ pieces: [WidgetLockPiece]) -> Text {
        pieces.reduce(Text(verbatim: "")) { text, piece in
            switch piece {
            case .text(let string) where string == WidgetCopy.unlock: Text("\(text)\(Text(Image(systemName: "lock.fill")))\(Text(verbatim: " \(string)"))")
            case .text(let string), .health(let string): Text("\(text)\(Text(verbatim: string))")
            case .countdown(let date): Text("\(text)\(Text(date, style: .timer))")
            }
        }
    }
}
#endif
