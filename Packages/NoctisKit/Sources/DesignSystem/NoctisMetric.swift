import SwiftUI

/// A number and its units, as parts: "6h 42m" is 6, h, a space, 42, m.
/// `spoken` is what VoiceOver reads ("6 hours 42 minutes").
public nonisolated struct NoctisMetricValue: Sendable, Equatable {
    public enum Part: Sendable, Equatable {
        case number(String)
        /// h, m, bpm, ms, %, AM/PM.
        case unit(String)
        /// A space between groups, set at the unit's size.
        case space
    }

    public let parts: [Part]
    public let spoken: String

    public init(parts: [Part], spoken: String) {
        self.parts = parts
        self.spoken = spoken
    }

    /// The same, as plain text: "6h 42m", "11:00PM".
    public var plain: String {
        parts.map { part in
            switch part {
            case .number(let text), .unit(let text): text
            case .space: " "
            }
        }
        .joined()
    }
}

/// Unit typography (R4): the number heavy and rounded; each unit at half
/// the number's size, semibold, in a quieter ink, on the same baseline 1pt
/// after its number. One `Text`, so it scales and shrinks as a whole and
/// VoiceOver reads it as `spoken`.
public struct NoctisMetric: View {
    public enum Tone: Sendable {
        /// Ink and ink2, on the paper and cards.
        case paper
        /// Night ink, and night ink at 70%, on the night panel.
        case nightPanel
        /// Block ink for both, on the color blocks.
        case block
        /// An accent number (the countdown) with ink2 units.
        case accent
    }

    private let value: NoctisMetricValue
    private let size: CGFloat
    private let weight: Font.Weight
    private let tone: Tone
    private let maxScale: CGFloat
    @ScaledMetric private var scaledSize: CGFloat

    public static let unitScale: CGFloat = 0.5
    /// A unit is never smaller than this, whatever the number's size (R4:
    /// no text under 12pt).
    public static let minimumUnitSize: CGFloat = 12
    /// The gap between a number and its unit.
    public static let unitGap: CGFloat = 1

    public init(
        _ value: NoctisMetricValue,
        size: CGFloat,
        weight: Font.Weight = .heavy,
        relativeTo style: Font.TextStyle = .largeTitle,
        maxScale: CGFloat = NoctisTypeScale.maxNumeralScale,
        tone: Tone = .paper
    ) {
        self.value = value
        self.size = size
        self.weight = weight
        self.tone = tone
        self.maxScale = maxScale
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    public var body: some View {
        let numberSize = min(scaledSize, size * maxScale)
        let numberFont = Font.system(size: numberSize, weight: weight, design: .rounded)
        let unitFont = Font.system(size: max(numberSize * Self.unitScale, Self.minimumUnitSize), weight: .semibold, design: .rounded)
        return value.parts.enumerated().reduce(Text(verbatim: "")) { text, item in
            let (index, part) = item
            let nextIsUnit = index + 1 < value.parts.count && { if case .unit = value.parts[index + 1] { true } else { false } }()
            switch part {
            case .number(let digits):
                return Text("\(text)\(number(digits, font: numberFont, gapAfter: nextIsUnit))")
            case .unit(let unit):
                return Text("\(text)\(Text(verbatim: unit).font(unitFont).foregroundStyle(unitStyle))")
            case .space:
                return Text("\(text)\(Text(verbatim: " ").font(unitFont))")
            }
        }
        .accessibilityLabel(value.spoken)
    }

    /// The number; its last character carries the 1pt gap to the unit.
    private func number(_ digits: String, font: Font, gapAfter: Bool) -> Text {
        guard gapAfter, let last = digits.last else {
            return Text(verbatim: digits).font(font).foregroundStyle(numberStyle)
        }
        let head = Text(verbatim: String(digits.dropLast())).font(font).foregroundStyle(numberStyle)
        let tail = Text(verbatim: String(last)).font(font).kerning(Self.unitGap).foregroundStyle(numberStyle)
        return Text("\(head)\(tail)")
    }

    private var numberStyle: AnyShapeStyle {
        switch tone {
        case .paper: AnyShapeStyle(NoctisAppColor.ink)
        case .nightPanel: AnyShapeStyle(NoctisAppColor.nightInk)
        case .block: AnyShapeStyle(NoctisAppColor.blockInk)
        case .accent: AnyShapeStyle(NoctisAppColor.orangeText)
        }
    }

    private var unitStyle: AnyShapeStyle {
        switch tone {
        case .paper, .accent: AnyShapeStyle(NoctisInkStyle(.secondary))
        case .nightPanel: AnyShapeStyle(NoctisNightInkStyle())
        case .block: AnyShapeStyle(NoctisAppColor.blockInk)
        }
    }
}
