import Foundation
import HomeFeature
import NoctisCore

// Week and month content: filled in with the Week and Month views.

public nonisolated struct SleepWeekContent: Sendable, Equatable {}
public nonisolated struct SleepMonthContent: Sendable, Equatable {}

nonisolated extension SleepScreenBuilder {
    static func weekContent(_ snapshot: SleepSnapshot, model: SleepRenderModel, format: HomeFormat) -> SleepWeekContent {
        SleepWeekContent()
    }

    static func monthContent(_ snapshot: SleepSnapshot, model: SleepRenderModel, format: HomeFormat) -> SleepMonthContent {
        SleepMonthContent()
    }
}
