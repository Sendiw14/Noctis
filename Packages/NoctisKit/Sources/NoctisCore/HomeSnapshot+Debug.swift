#if DEBUG
import Foundation
import InsightsKit
import RecoveryKit
import SleepKit

extension HomeSnapshot {
    /// A plain-text dump for checking mock scenarios in the simulator log.
    public nonisolated var debugSummary: String {
        var lines = ["[HomeSnapshot] dataState=\(dataState)"]
        switch recovery {
        case .scored(let result)?:
            lines.append("recovery=\(result.score) confidence=\(result.confidence) baselineNights=\(result.baselineNights) model=\(result.modelVersion)")
            for factor in result.factors {
                lines.append("  \(factor.kind.rawValue): score=\(factor.score) weight=\(String(format: "%.3f", factor.weight)) value=\(String(format: "%.1f", factor.value)) delta=\(factor.delta.map { String(format: "%+.1f", $0) } ?? "nil")")
            }
        case let other?:
            lines.append("recovery=\(other)")
        case nil:
            lines.append("recovery=nil")
        }
        if let lastNight {
            let totals = lastNight.totals
            lines.append("lastNight=\(lastNight.night) asleep=\(Int(totals.asleep / 60))m inBed=\(Int(totals.inBed / 60))m deep=\(Int(totals.deep / 60))m core=\(Int(totals.core / 60))m rem=\(Int(totals.rem / 60))m awake=\(Int(totals.awake / 60))m awakenings=\(lastNight.awakenings) efficiency=\(lastNight.efficiency.map { String(format: "%.2f", $0) } ?? "nil") coverage=\(String(format: "%.2f", lastNight.completeness.coverage))")
        } else {
            lines.append("lastNight=nil")
        }
        lines.append("recentNights=" + recentNights.map { "\($0.night):\($0.asleepMinutes.map { String(Int($0)) } ?? "-")" }.joined(separator: " "))
        lines.append("tonight bedtime=\(tonight.bedtimeMinutes) wake=\(tonight.wakeMinutes) need=\(tonight.needMinutes)")
        lines.append("insight=\(topInsight.map { "\($0.kind.rawValue): value=\(Int($0.evidence.value)) baseline=\(Int($0.evidence.baseline)) delta=\(Int($0.evidence.delta))" } ?? "nil")")
        lines.append("heart=\(lastNightHeart.map { "\($0.points.count) points, min \(Int($0.lowest.bpm))" } ?? "nil")")
        return lines.joined(separator: "\n")
    }
}
#endif
