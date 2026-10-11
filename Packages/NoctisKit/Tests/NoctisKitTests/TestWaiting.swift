import Foundation

// QA part 2 (QA_LEDGER.md): how a test waits. The whole suite shares the main actor and runs beside builds, sanitizers and a busy Mac, so a
// test that sleeps "long enough" or counts a hundred 20 ms turns (a 2 second budget) fails when the machine is slow and passes when it is
// not. A test waits for the state it needs, and the only number in it is a backstop that a healthy run never reaches.

/// A timer that never fires: what a model sleeps through when a test wants no real clock at all (a reveal, a grace period, a mode boundary).
/// It ends early only if its task is cancelled, which is how a model is meant to stop it.
nonisolated func held(_ seconds: Double) async {
    try? await Task.sleep(for: .seconds(3600))
}

/// Waits until `condition` is true and returns true, or returns false after `timeout` (a backstop, not an expectation: a healthy run returns at
/// once). Ten minutes, not two: every test here runs on the main actor, so under Thread Sanitizer one round through the 2,400 tests took longer
/// than two minutes and a wait gave up on work that was only queued (QA_LEDGER.md). The condition may read an actor: `await waitFor { await store.count() == 2 }`.
@MainActor
func waitFor(timeout: Duration = .seconds(600), _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !(await condition()) {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

/// A clock a test owns: `sleep` suspends until `fire()` (every sleeper wakes at once) or until its task is cancelled; `sleepers` says how many are
/// waiting, so a test fires only once the thing under test has actually started waiting.
actor ManualTimer {
    private var waiting: [UUID: (seconds: Double, continuation: CheckedContinuation<Void, Never>)] = [:]
    private var cancelled: Set<UUID> = []
    private(set) var requested: [Double] = []

    var sleepers: Int { waiting.count }

    nonisolated func sleep(_ seconds: Double) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task { await self.add(continuation, id: id, seconds: seconds) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func add(_ continuation: CheckedContinuation<Void, Never>, id: UUID, seconds: Double) {
        requested.append(seconds)
        // Cancelled before it was registered: it is already over.
        if cancelled.remove(id) != nil { continuation.resume(); return }
        waiting[id] = (seconds, continuation)
    }

    private func cancel(_ id: UUID) {
        if let entry = waiting.removeValue(forKey: id) { entry.continuation.resume() } else { cancelled.insert(id) }
    }

    /// Wakes the sleepers that asked for `seconds` (every sleeper when nil).
    func fire(seconds: Double? = nil) {
        let due = waiting.filter { seconds == nil || $0.value.seconds == seconds }
        for id in due.keys { waiting[id] = nil }
        for entry in due.values { entry.continuation.resume() }
    }
}
