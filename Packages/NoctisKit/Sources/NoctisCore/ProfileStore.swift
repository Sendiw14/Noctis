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
