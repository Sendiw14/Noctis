import Foundation
import NightKit
import SwiftData

/// One wind-down, kept on this device: when it began, how long it was planned for, and whether it
/// ran its whole time. Nothing else: no sound, no values, no words (APP_RULES.md R32).
@Model
public final class WindDownSession {
    public var id: UUID = UUID()
    public var start: Date = Date.now
    public var plannedMinutes: Int = 20
    public var completed: Bool = false

    public init() {}
}

/// Reads and writes the sessions, for the wind-down view model.
@MainActor
public final class WindDownSessionStore: WindDownSessionStoring {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func begin(start: Date, plannedMinutes: Int) async -> UUID {
        let session = WindDownSession()
        session.start = start
        session.plannedMinutes = plannedMinutes
        context.insert(session)
        try? context.save()
        return session.id
    }

    public func finish(_ id: UUID, completed: Bool) async {
        let all = (try? context.fetch(FetchDescriptor<WindDownSession>())) ?? []
        guard let session = all.first(where: { $0.id == id }) else { return }
        session.completed = completed
        try? context.save()
    }

    /// Every session, newest first.
    public func sessions() -> [WindDownSession] {
        ((try? context.fetch(FetchDescriptor<WindDownSession>())) ?? []).sorted { $0.start > $1.start }
    }

    /// Forgets every session (Data Management will call this).
    public func eraseAll() {
        for session in (try? context.fetch(FetchDescriptor<WindDownSession>())) ?? [] { context.delete(session) }
        try? context.save()
    }
}
