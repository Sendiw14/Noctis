import Foundation
import SwiftData

public final class ProfileStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func load() -> UserProfileSnapshot {
        let descriptor = FetchDescriptor<UserProfileRecord>()
        if let existing = try? context.fetch(descriptor).first {
            return existing.snapshot
        }
        let record = UserProfileRecord()
        context.insert(record)
        try? context.save()
        return record.snapshot
    }

    /// Deletes every profile record (Data management). The next `load()` starts a blank one.
    public func eraseAll() {
        for record in (try? context.fetch(FetchDescriptor<UserProfileRecord>())) ?? [] { context.delete(record) }
        try? context.save()
    }

    /// How many records the store holds, for a test.
    public var recordCount: Int {
        (try? context.fetchCount(FetchDescriptor<UserProfileRecord>())) ?? 0
    }

    public func save(_ snapshot: UserProfileSnapshot) {
        let descriptor = FetchDescriptor<UserProfileRecord>()
        let record = (try? context.fetch(descriptor).first) ?? {
            let new = UserProfileRecord()
            context.insert(new)
            return new
        }()
        record.apply(snapshot)
        try? context.save()
    }
}
