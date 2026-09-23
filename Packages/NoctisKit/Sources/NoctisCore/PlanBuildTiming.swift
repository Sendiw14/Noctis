import Foundation

/// How much longer Plan's build phase must stay on screen so it never
/// flashes, given how much time has already elapsed. Pure and testable in
/// isolation from the screen's own async `Task` — the real health query and
/// baseline seed can resolve in milliseconds against the mock provider, and
/// without this floor the loading moment would blink past unreadably.
public nonisolated func noctisPlanBuildFloorDelay(elapsedSeconds: Double, floorSeconds: Double = 1.6) -> Double {
    max(0, floorSeconds - elapsedSeconds)
}
