import DesignSystem
import Foundation
import HealthProviding
import HomeFeature
import NoctisCore
import RecoveryKit
import SleepKit
import NoctisText

// The Recovery tab's presentation model: every string and readable value,
// built by `RecoveryScreenBuilder` from a `RecoverySnapshot` and its render
// model. Views lay it out and add nothing (APP_RULES.md R18, R20). Wording
// compares nights with the person's own usual (Above, Within or Below it);
// it never judges a night, gives advice about health, or tells anyone to
// rest.

// MARK: - Today

/// One row under the stacked bar: a factor's points and how far they are
/// from its usual.
public nonisolated struct RecoveryBuildRow: Sendable, Equatable, Identifiable {
    public let kind: RecoveryFactorKind
    /// "Sleep", "HRV", "Resting HR", "Consistency".
    public let name: String
    /// "+24".
    public let pointsText: String
    /// "vs usual: −3"; nil under 5 nights to compare with.
    public let usualText: String?
    /// Where its segment sits on the 100-point bar, from the render model.
    public let start: Double
    public let width: Double
    public let accessibilityLabel: String

    public var id: RecoveryFactorKind { kind }
}

/// "How today's score was built".
public nonisolated struct RecoveryBuildContent: Sendable, Equatable {
    public let title: String
    public let rows: [RecoveryBuildRow]
    /// "= 70": the score shown, at the bar's right end.
    public let totalText: String
    /// "Capped at 50: your heart rate and HRV are both well outside your
    /// normal range." when the cap held the score down.
    public let capNote: String?
    public let accessibilityLabel: String
}

public nonisolated struct RecoveryChecklistItem: Sendable, Equatable, Identifiable {
    public let kind: RecoveryFactorKind
    public let name: String
    public let isUsed: Bool
    /// Why a missing factor is missing: "Not available from your sources".
    public let reason: String?
    public var id: RecoveryFactorKind { kind }
}

/// How far to trust today's score, in plain words.
public nonisolated struct RecoveryConfidenceContent: Sendable, Equatable {
    /// "High confidence".
    public let tier: String
    public let sentence: String
    public let checklist: [RecoveryChecklistItem]
    /// "Based on 14 nights".
    public let basedOn: String
    /// The one thing that would firm it up; nil when nothing would.
    public let nextStep: String?
    public let accessibilityLabel: String
}

public nonisolated struct RecoveryTodayContent: Sendable, Equatable {
    /// The score, ring segments, chip, why-line and confidence caption: the
    /// same content Home's ring shows.
    public let scored: ScoredRecoveryContent
    public let build: RecoveryBuildContent
    /// One card per scored factor, in ring order.
    public let factors: [FactorDetailRow]
    public let confidence: RecoveryConfidenceContent
    /// "How this is calculated", paragraph by paragraph.
    public let calculation: [String]
    /// "Model recovery-v3".
    public let modelVersion: String
    /// "Highest in 30 days" when today's score beats every other day of the
    /// last 30 (strictly, with enough scored days to compare with).
    public let highlight: String?
}

// MARK: - States

/// What the tab shows instead of a score when there's nothing to show.
public nonisolated enum RecoveryStateContent: Sendable, Equatable {
    /// Health access never requested, or no Health on this device.
    case connect(title: String, message: String, showsButton: Bool)
    /// Access asked for, but no sleep in Health.
    case noSleepData(title: String, message: String)
    case failed(message: String)
}

public nonisolated struct RecoveryLearningContent: Sendable, Equatable {
    public let nights: Int
    public let required: Int
    /// "3 of 5 nights".
    public let text: String
}

public nonisolated struct RecoveryNoSleepContent: Sendable, Equatable {
    public let title: String
    public let detail: String?
    /// Whether it offers "Open Health": Health's sync is behind (stale).
    public var opensHealth = false
}

public nonisolated struct RecoveryBanner: Sendable, Equatable {
    public let title: String
    public let detail: String
}

public nonisolated struct RecoveryScreenContent: Sendable, Equatable {
    /// "TUESDAY, SEPTEMBER 29".
    public let dateCaption: String
    public let segment: RecoverySegment
    public let state: RecoveryStateContent?
    public let banner: RecoveryBanner?
    public let learning: RecoveryLearningContent?
    public let noSleep: RecoveryNoSleepContent?
    public let today: RecoveryTodayContent?
    /// 7D, 30D or 90D.
    public let history: RecoveryHistoryContent?
    public var rangeTitle: String { segment.title }
}

// MARK: - Builder

public nonisolated enum RecoveryScreenBuilder {
    public static let factorOrder = RecoveryContributionEngine.factorOrder

    public static func build(
        _ snapshot: RecoverySnapshot,
        model: RecoveryRenderModel?,
        selection: RecoverySelection,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> RecoveryScreenContent {
        let format = HomeFormat(calendar: calendar, locale: locale)
        let state = stateContent(snapshot.dataState)
        let showsData = state == nil
        var learning: RecoveryLearningContent?
        var noSleep: RecoveryNoSleepContent?
        var today: RecoveryTodayContent?
        var history: RecoveryHistoryContent?
        if showsData, selection.segment != .today {
            // A history needs 5 scored nights; before that, the learning dots.
            history = historyContent(snapshot, segment: selection.segment, format: format)
            if history == nil {
                // While the baseline is still forming, the same count Today shows
                // (the recorded nights); otherwise the nights the range could score.
                let nights: Int
                if case .learning(let recorded)? = snapshot.recovery {
                    nights = recorded
                } else {
                    nights = snapshot.history(selection.segment.historyRange ?? .week)?.stats.scoredDays ?? 0
                }
                let required = RecoveryModelV1.learningNights
                learning = RecoveryLearningContent(nights: nights, required: required, text: "\(nights) of \(required) nights")
            }
        } else if showsData {
            switch snapshot.recovery {
            case .learning(let nights)?:
                let required = RecoveryModelV1.learningNights
                learning = RecoveryLearningContent(nights: nights, required: required, text: "\(nights) of \(required) nights")
            case .noSleepLastNight?:
                if let stale = banner(snapshot, format: format) {
                    // Sync is behind; it doesn't mean the person didn't sleep.
                    noSleep = RecoveryNoSleepContent(title: stale.title, detail: stale.detail, opensHealth: true)
                } else {
                    let latest = snapshot.scores.last
                    noSleep = RecoveryNoSleepContent(
                        title: "No sleep recorded last night.",
                        detail: latest.map { "Last recorded night ended \(format.shortDate($0.date))." }
                    )
                }
            case .scored(let result)?:
                if selection.segment == .today {
                    today = todayContent(result, snapshot: snapshot, model: model, format: format)
                }
            case nil:
                break
            }
        }
        return RecoveryScreenContent(
            dateCaption: format.longDate(now).uppercased(),
            segment: selection.segment,
            state: state,
            banner: noSleep == nil ? banner(snapshot, format: format) : nil,
            learning: learning,
            noSleep: noSleep,
            today: today,
            history: history
        )
    }

    // MARK: States

    static func stateContent(_ state: HomeDataState) -> RecoveryStateContent? {
        switch state {
        case .healthDataUnavailable:
            .connect(title: "Your first night starts here.", message: "Apple Health isn't available on this device.", showsButton: false)
        case .permissionRequired:
            .connect(title: "Your first night starts here.", message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true)
        case .empty, .learning(nightsSoFar: 0):
            .noSleepData(
                title: "No sleep data yet",
                message: "NOCTIS reads sleep from Apple Health. Track sleep with Apple Watch or set up Sleep in the Health app."
            )
        case .failed:
            .failed(message: "We couldn't read your latest sleep data.")
        case .stale, .learning, .noSleepLastNight, .ready:
            nil
        }
    }

    static func banner(_ snapshot: RecoverySnapshot, format: HomeFormat) -> RecoveryBanner? {
        guard case .stale(let newest) = snapshot.dataState else { return nil }
        return RecoveryBanner(
            title: "Apple Health hasn't updated since \(format.dayAndTime(newest)).",
            detail: "Open Health or pull to refresh."
        )
    }

    // MARK: Today

    static func todayContent(_ result: RecoveryResult, snapshot: RecoverySnapshot, model: RecoveryRenderModel?, format: HomeFormat) -> RecoveryTodayContent {
        let render = model?.today
        let scored = HomeScreenBuilder.scoredContent(result, ring: render?.ring)
        let contributions = snapshot.contributions ?? RecoveryContributionEngine.contributions(for: result)
        let report = snapshot.confidence ?? RecoveryConfidenceReportBuilder.report(for: result)
        let rows = factorOrder.compactMap { result.factor($0) }.map {
            HomeScreenBuilder.detailRow($0, result: result, needMinutes: snapshot.needMinutes, format: format)
        }
        return RecoveryTodayContent(
            scored: scored,
            build: build(contributions, render: render),
            factors: rows,
            confidence: confidence(report),
            calculation: HomeScreenBuilder.calculation(result, needMinutes: snapshot.needMinutes),
            modelVersion: "Model \(result.modelVersion)",
            highlight: snapshot.history(.month).flatMap { RecoveryHighlightEngine.highlight(days: $0.days) }.map { _ in "Highest in 30 days" }
        )
    }

    // MARK: How today's score was built

    static func build(_ contributions: RecoveryContributions, render: RecoveryTodayRender?) -> RecoveryBuildContent {
        let segments = Dictionary((render?.bar ?? []).map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = contributions.contributions.map { item -> RecoveryBuildRow in
            let name = HomeScreenBuilder.shortName(item.kind)
            let points = "+\(item.wholePoints)"
            let usual = item.deltaPoints.map { "vs usual: \(HomeScreenBuilder.signed(Int($0.rounded())))" }
            var label = "\(name), \(item.wholePoints) points"
            if let delta = item.deltaPoints {
                let size = Int(abs(delta).rounded())
                label += size == 0 ? ", the same as usual" : ", \(size) \(delta > 0 ? "above" : "below") usual"
            }
            return RecoveryBuildRow(
                kind: item.kind, name: name, pointsText: points, usualText: usual,
                start: segments[item.kind]?.start ?? 0, width: segments[item.kind]?.width ?? item.points / 100,
                accessibilityLabel: label
            )
        }
        var capNote: String?
        if let cap = contributions.capApplied {
            capNote = "Capped at \(cap.cap): your heart rate and HRV are both well outside your normal range."
        }
        let title = "How today's score was built"
        var label = "\(title): " + rows.map(\.accessibilityLabel).joined(separator: "; ") + ". Total \(contributions.score)."
        if let capNote { label += " " + capNote }
        return RecoveryBuildContent(title: title, rows: rows, totalText: "= \(contributions.score)", capNote: capNote, accessibilityLabel: label)
    }

    // MARK: Confidence

    static func confidence(_ report: RecoveryConfidenceReport) -> RecoveryConfidenceContent {
        let tier = switch report.tier {
        case .high: "High confidence"
        case .moderate: "Moderate confidence"
        case .low: "Low confidence"
        }
        let signals = "\(report.factorsUsed.count) of \(RecoveryFactorKind.allCases.count) signals"
        let nights = NoctisCount.nights(report.nights)
        let sentence: String
        switch report.tier {
        case .high:
            sentence = "Every signal was recorded, and today is compared with \(nights) of your own."
        case .moderate:
            sentence = "Built on \(signals) and \(nights) of your own. It's a fair guide, and it firms up as more nights arrive."
        case .low:
            sentence = "Built on \(signals) and \(nights) of your own, so it's a rough guide for now."
        }
        let checklist = factorOrder.map { kind -> RecoveryChecklistItem in
            let missing = report.factorsMissing.first { $0.kind == kind }
            return RecoveryChecklistItem(
                kind: kind, name: HomeScreenBuilder.shortName(kind), isUsed: missing == nil && report.factorsUsed.contains(kind),
                reason: missing.map { reason($0.reason) }
            )
        }
        let step = report.nextStep.map(nextStep)
        var label = "\(tier). \(sentence)"
        label += " " + checklist.map { $0.isUsed ? "\($0.name) used" : "\($0.name) missing: \($0.reason ?? "not used")" }.joined(separator: ". ") + "."
        label += " Based on \(nights)."
        if let step { label += " " + step }
        return RecoveryConfidenceContent(
            tier: tier, sentence: sentence, checklist: checklist, basedOn: "Based on \(nights)", nextStep: step, accessibilityLabel: label
        )
    }

    static func reason(_ gap: RecoveryFactorGap) -> String {
        switch gap {
        case .unavailable: "Not available from your sources"
        case .notRecorded: "Not recorded last night"
        case .buildingBaseline: "Baseline still forming"
        }
    }

    /// The smallest step, in words: only what the engine's facts say.
    static func nextStep(_ step: RecoveryNextStep) -> String {
        func names(_ kinds: [RecoveryFactorKind]) -> String {
            kinds.map(HomeScreenBuilder.spokenName).formatted(.list(type: .and))
        }
        switch step {
        case .recordAgain(let kinds):
            let verb = kinds.count > 1 ? "weren't" : "wasn't"
            return "\(names(kinds).prefix(1).uppercased() + names(kinds).dropFirst()) \(verb) recorded last night. Wearing your Apple Watch to sleep tonight would bring \(kinds.count > 1 ? "them" : "it") back."
        case .keepTracking(let nights):
            return "\(NoctisCount.moreNights(nights)) of tracking and the baselines that are still forming will be ready."
        case .wearWatchToSleep(let kinds):
            return "Wear your Apple Watch to sleep to add \(names(kinds))."
        case .reachHigh(let nights):
            return "\(NoctisCount.moreNights(nights)) and this reaches high confidence."
        }
    }
}
