#if os(iOS)
import DesignSystem
import SwiftUI
import WidgetKit

// The flat widget views (APP_RULES.md R44, R45): fills and hairlines only, the app's tokens, `NoctisMetric` units, no text under
// 12pt. They draw a `WidgetPresentation` and decide nothing: the wording, the omissions and which values are Health values are all in
// `WidgetPresentationBuilder`. The extension adds `containerBackground(for: .widget)`; the gallery draws its own.

// MARK: - Hiding Health on a locked iPhone

/// A Health value. While the iPhone is locked (`.privacy` redaction: the Lock Screen, StandBy) it is replaced by `locked`; it is also
/// marked `privacySensitive` so the system's own redaction agrees.
struct WidgetPrivate<Content: View, Locked: View>: View {
    @Environment(\.redactionReasons) private var reasons
    let content: Content
    let locked: Locked

    init(@ViewBuilder content: () -> Content, @ViewBuilder locked: () -> Locked) {
        self.content = content()
        self.locked = locked()
    }

    var body: some View {
        if reasons.contains(.privacy) {
            locked
        } else {
            content.privacySensitive()
        }
    }
}

/// A lock glyph and "Unlock to see".
struct WidgetUnlockView: View {
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .noctisIcon(compact ? 13 : 16, .semibold, relativeTo: .footnote)
            Text(WidgetCopy.unlock)
                .noctisFont(13, .semibold, relativeTo: .footnote)
        }
        .foregroundStyle(NoctisAppColor.ink2)
        .accessibilityElement(children: .combine)
    }
}

extension WidgetLockContent {
    /// The Lock Screen words while locked: every Health word becomes "Unlock to see" (once per line, and the lines after the first
    /// collapse into it), and the gauge has no number.
    public func locked() -> WidgetLockContent {
        func hidesHealth(_ pieces: [WidgetLockPiece]) -> Bool {
            pieces.contains { if case .health = $0 { true } else { false } }
        }
        var lines: [[WidgetLockPiece]] = []
        var shown = false
        for line in rectangular {
            if hidesHealth(line) {
                if !shown { lines.append([.text(WidgetCopy.unlock)]) }
                shown = true
            } else {
                lines.append(line)
            }
        }
        let inline = self.inline.map { piece -> WidgetLockPiece in
            if case .health = piece { return .text(WidgetCopy.unlock) }
            return piece
        }
        return WidgetLockContent(gaugeScore: nil, rectangular: lines, inline: inline)
    }
}

/// The paper behind a widget: the day's paper by day, the evening's by evening, light and dark.
public struct WidgetBackground: View {
    let mode: WidgetMode

    public init(mode: WidgetMode) {
        self.mode = mode
    }

    public var body: some View {
        (mode == .evening ? NoctisAppColor.eveningPaper : NoctisAppColor.bg)
    }
}

// MARK: - The widget

/// Home Screen widget: small, medium and large, in day and evening, with every state.
public struct NoctisTodayWidgetView: View {
    let presentation: WidgetPresentation
    let family: WidgetFamily

    public init(entry: WidgetEntryModel, family: WidgetFamily, format: WidgetFormat = WidgetFormat()) {
        presentation = WidgetPresentationBuilder.build(entry, format: format)
        self.family = family
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch presentation.body {
            case .message(let message):
                WidgetMessageView(message: message, family: family)
            case .day(let day):
                WidgetDayView(day: day, family: family)
            case .evening(let evening):
                WidgetEveningView(evening: evening, family: family)
            }
            if let footer = presentation.footer {
                Text(footer)
                    .noctisFont(12, .regular, relativeTo: .caption)
                    .foregroundStyle(NoctisAppColor.ink2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if presentation.isPreview {
                Text(WidgetCopy.sample)
                    .noctisFont(12, .semibold, relativeTo: .caption)
                    .foregroundStyle(NoctisAppColor.ink2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(NoctisAppColor.track, in: Capsule(style: .continuous))
            }
        }
        .widgetURL(presentation.link.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

// MARK: Messages

struct WidgetMessageView: View {
    let message: WidgetMessage
    let family: WidgetFamily

    var body: some View {
        let wide = family != .systemSmall
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: message.glyph)
                .noctisIcon(wide ? 26 : 22, .semibold, relativeTo: .title3)
                .foregroundStyle(NoctisAppColor.orangeText)
                .widgetAccentable()
            Text(message.title)
                .noctisFont(wide ? 18 : 15, .semibold, relativeTo: .headline)
                .foregroundStyle(NoctisAppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = message.detail {
                Text(detail)
                    .noctisFont(13, .regular, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Day

private func scoreValue(_ score: Int) -> NoctisMetricValue {
    NoctisMetricValue(parts: [.number("\(score)")], spoken: "\(score)")
}

/// The ring with the score at its centre; while locked, an empty ring with a lock.
struct WidgetRecoveryRing: View {
    let score: Int?
    let ring: [WidgetRingSegment]
    var lineWidth: CGFloat = 10
    var numberSize: CGFloat = 34

    var body: some View {
        WidgetPrivate {
            ZStack {
                if ring.isEmpty { WidgetEmptyRing(lineWidth: lineWidth) } else { WidgetRingView(segments: ring, lineWidth: lineWidth) }
                if let score {
                    NoctisMetric(scoreValue(score), size: numberSize, weight: .heavy, relativeTo: .title)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .widgetAccentable()
                        .padding(lineWidth + 2)
                }
            }
        } locked: {
            ZStack {
                WidgetEmptyRing(lineWidth: lineWidth)
                Image(systemName: "lock.fill")
                    .noctisIcon(numberSize * 0.6, .semibold, relativeTo: .title3)
                    .foregroundStyle(NoctisAppColor.ink2)
            }
        }
    }
}

struct WidgetDayView: View {
    let day: WidgetDayBody
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .systemLarge, .systemExtraLarge: large
        default: small
        }
    }

    private var small: some View {
        VStack(spacing: 6) {
            WidgetRecoveryRing(score: day.score, ring: day.ring, lineWidth: 10, numberSize: 34)
                .frame(width: 100, height: 100)
            Text("Recovery")
                .noctisFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(NoctisAppColor.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 6) {
                WidgetRecoveryRing(score: day.score, ring: day.ring, lineWidth: 10, numberSize: 32)
                    .frame(width: 96, height: 96)
                Text("Recovery")
                    .noctisFont(13, .semibold, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.ink2)
            }
            WidgetPrivate {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(day.rows.enumerated()), id: \.offset) { _, line in WidgetRow(line: line) }
                }
            } locked: {
                WidgetUnlockView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                WidgetRecoveryRing(score: day.score, ring: day.ring, lineWidth: 12, numberSize: 40)
                    .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recovery")
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                    if let delta = day.delta {
                        WidgetPrivate {
                            HStack(spacing: 8) {
                                WidgetDeltaChip(delta: delta)
                                Text("vs your usual")
                                    .noctisFont(13, .regular, relativeTo: .footnote)
                                    .foregroundStyle(NoctisAppColor.ink2)
                            }
                        } locked: {
                            WidgetUnlockView(compact: true)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if let night = day.night {
                WidgetPrivate {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(night.duration.label)
                                .noctisFont(13, .semibold, relativeTo: .footnote)
                                .foregroundStyle(NoctisAppColor.ink2)
                            Spacer(minLength: 0)
                            Text(night.times)
                                .noctisFont(12, .regular, relativeTo: .caption)
                                .foregroundStyle(NoctisAppColor.ink2)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            NoctisMetric(night.duration.value, size: 30, weight: .heavy, relativeTo: .title2)
                            if let quality = night.quality {
                                Text("\(quality.label) \(quality.value.plain)")
                                    .noctisFont(13, .regular, relativeTo: .footnote)
                                    .foregroundStyle(NoctisAppColor.ink2)
                            }
                        }
                        if let stages = night.stages { WidgetStageStrip(stages: stages) }
                    }
                } locked: {
                    WidgetUnlockView()
                }
            }
            Spacer(minLength: 0)
            WidgetTonightRow(tonight: day.tonight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WidgetRow: View {
    let line: WidgetLine
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(line.tint.map { WidgetPalette(mode: renderingMode).line($0) } ?? NoctisAppColor.ink2)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(line.label)
                .noctisFont(13, .regular, relativeTo: .footnote)
                .foregroundStyle(NoctisAppColor.ink2)
                .lineLimit(1)
            Spacer(minLength: 4)
            NoctisMetric(line.value, size: 20, weight: .heavy, relativeTo: .title3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct WidgetDeltaChip: View {
    let delta: WidgetDelta

    var body: some View {
        Text(delta.text)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .foregroundStyle(NoctisAppColor.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill, in: Capsule(style: .continuous))
            .widgetAccentable()
    }

    private var fill: Color {
        switch delta.tone {
        case .above: NoctisAppColor.sage.opacity(0.3)
        case .inLine: NoctisAppColor.track
        case .below: NoctisAppColor.orange.opacity(0.28)
        }
    }
}

struct WidgetTonightRow: View {
    let tonight: WidgetTonight

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .noctisIcon(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(NoctisAppColor.lavenderText)
                .accessibilityHidden(true)
            Text("Tonight")
                .noctisFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(NoctisAppColor.ink2)
            Spacer(minLength: 4)
            Text(tonight.bedtime)
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(NoctisAppColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(tonight.wake)
                .noctisFont(12, .regular, relativeTo: .caption)
                .foregroundStyle(NoctisAppColor.ink2)
                .lineLimit(1)
        }
    }
}

// MARK: Evening

struct WidgetEveningView: View {
    let evening: WidgetEveningBody
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .systemLarge, .systemExtraLarge: large
        default: small
        }
    }

    private func hero(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(evening.hasPassed ? "Bedtime was" : "Bedtime")
                    .noctisFont(13, .semibold, relativeTo: .footnote)
            } icon: {
                Image(systemName: "moon.stars.fill").noctisIcon(13, .semibold, relativeTo: .footnote)
            }
            .foregroundStyle(NoctisAppColor.lavenderText)
            NoctisMetric(evening.bedtimeText, size: size, weight: .heavy, relativeTo: .largeTitle, tone: .paper)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            if !evening.hasPassed {
                Text("in \(Text(evening.bedtime, style: .relative))")
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.lavenderText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let window = evening.windowText {
                Text(window)
                    .noctisFont(13, .regular, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.eveningInk3)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            hero(size: 32)
            Spacer(minLength: 0)
            Text("Wake \(evening.wakeText)")
                .noctisFont(13, .regular, relativeTo: .footnote)
                .foregroundStyle(NoctisAppColor.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 16) {
            hero(size: 38)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                if evening.score != nil {
                    WidgetRecoveryRing(score: evening.score, ring: evening.ring, lineWidth: 7, numberSize: 22)
                        .frame(width: 66, height: 66)
                }
                planLines
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero(size: 52)
            HStack(alignment: .center, spacing: 16) {
                if evening.score != nil {
                    WidgetRecoveryRing(score: evening.score, ring: evening.ring, lineWidth: 9, numberSize: 28)
                        .frame(width: 84, height: 84)
                }
                VStack(alignment: .leading, spacing: 10) {
                    planRow(evening.wake)
                    planRow(evening.need)
                    if let alarm = evening.alarm { planRow(alarm) }
                    if evening.score != nil {
                        Text("Recovery today")
                            .noctisFont(12, .regular, relativeTo: .caption)
                            .foregroundStyle(NoctisAppColor.ink2)
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var planLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Wake \(evening.wakeText)")
            Text("Need \(evening.need.value.plain)")
        }
        .noctisFont(13, .regular, relativeTo: .footnote)
        .foregroundStyle(NoctisAppColor.ink2)
    }

    private func planRow(_ line: WidgetLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.label)
                .noctisFont(13, .regular, relativeTo: .footnote)
                .foregroundStyle(NoctisAppColor.ink2)
            NoctisMetric(line.value, size: 20, weight: .heavy, relativeTo: .title3)
        }
    }
}

// MARK: - The Lock Screen widget

/// Lock Screen widget: a gauge, a few lines, one line. Health values are hidden while the iPhone is locked.
public struct NoctisLockWidgetView: View {
    let presentation: WidgetPresentation
    let family: WidgetFamily
    @Environment(\.redactionReasons) private var reasons

    public init(entry: WidgetEntryModel, family: WidgetFamily, format: WidgetFormat = WidgetFormat()) {
        presentation = WidgetPresentationBuilder.build(entry, format: format)
        self.family = family
    }

    private var content: WidgetLockContent {
        reasons.contains(.privacy) ? presentation.lock.locked() : presentation.lock
    }

    public var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            default: inline
            }
        }
        .widgetURL(presentation.link.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reasons.contains(.privacy) ? WidgetCopy.unlock : presentation.accessibilityLabel)
    }

    private var circular: some View {
        let score = content.gaugeScore
        return Gauge(value: Double(score ?? 0), in: 0...100) {
            Image(systemName: "bolt.heart.fill")
        } currentValueLabel: {
            if let score {
                Text("\(score)").noctisFont(16, .bold, relativeTo: .headline)
            } else if presentation.lock.gaugeScore != nil {
                Image(systemName: "lock.fill")
            } else {
                Image(systemName: "moon.stars.fill")
            }
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(content.rectangular.enumerated()), id: \.offset) { index, line in
                lineText(line)
                    .noctisFont(index == 0 ? 14 : 13, index == 0 ? .semibold : .regular, relativeTo: .footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable(index == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        lineText(content.inline)
    }

    private func lineText(_ pieces: [WidgetLockPiece]) -> Text {
        pieces.reduce(Text(verbatim: "")) { text, piece in
            switch piece {
            case .text(let string) where string == WidgetCopy.unlock: Text("\(text)\(Text(Image(systemName: "lock.fill")))\(Text(verbatim: " \(string)"))")
            case .text(let string), .health(let string): Text("\(text)\(Text(verbatim: string))")
            case .countdown(let date): Text("\(text)\(Text(date, style: .relative))")
            }
        }
    }
}
#endif
