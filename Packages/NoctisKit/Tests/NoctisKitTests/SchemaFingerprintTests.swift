import Foundation
import SwiftData
import Testing

@testable import CoachKit
@testable import JournalKit
@testable import NoctisCore

// A change to a stored model without a new schema version is the one way an update can damage or lose someone's data (X-16, S1B-B01). The shape of each shipped version
// is written down here; a model that no longer matches fails this test until a version and a migration stage are added (Docs/MIGRATION_PROCEDURE.md) and the line
// below is updated with them. There is no second version and none is made up to exercise the machinery: the migration harness has its own tests with a synthetic one.

private func fingerprint(_ schema: any VersionedSchema.Type) -> String {
    Schema(versionedSchema: schema).entities
        .sorted { $0.name < $1.name }
        .map { entity in
            let attributes = entity.attributes.sorted { $0.name < $1.name }.map { "\($0.name):\($0.valueType)" }.joined(separator: ",")
            let relationships = entity.relationships.sorted { $0.name < $1.name }.map { "\($0.name)->\($0.destination)" }.joined(separator: ",")
            return "\(entity.name){\(attributes)|\(relationships)}"
        }
        .joined(separator: ";")
}

struct SchemaFingerprintTests {
    private static let message =
        "A stored model changed. Do not edit this line to make the test pass: add a VersionedSchema, a migration stage and an upgrade test first (Docs/MIGRATION_PROCEDURE.md)."

    @Test func theAppDatabaseIsVersion1AsShipped() {
        #expect(fingerprint(NoctisSchemaV1.self) == "AlarmConfiguration{alarmKitID:Optional<UUID>,lastStateRaw:String,minutesSinceMidnight:Int,repeatDaysRaw:Array<Int>,snoozeEnabled:Bool,snoozeMinutes:Int,updatedAt:Date|};UserProfileRecord{createdAt:Date,healthAuthorizationRequested:Bool,name:String,onboardingComplete:Bool,primaryGoalRaw:String,secondaryGoalRaw:Optional<String>,sleepGoalHours:Double,typicalWakeMinutes:Int|};WindDownSession{completed:Bool,id:UUID,plannedMinutes:Int,start:Date|}", Comment(rawValue: Self.message + " Now: " + fingerprint(NoctisSchemaV1.self)))
    }

    @Test func coachHistoryIsVersion1AsShipped() {
        #expect(fingerprint(CoachHistorySchemaV1.self) == "AIConversation{createdAt:Date,id:UUID,updatedAt:Date|messages->AIMessage};AIMessage{answerData:Data,answerSummary:String,createdAt:Date,feedbackRaw:Optional<String>,id:UUID,question:String|conversation->AIConversation}", Comment(rawValue: Self.message + " Now: " + fingerprint(CoachHistorySchemaV1.self)))
    }

    @Test func theJournalIsVersion1AsShipped() {
        #expect(fingerprint(JournalSchemaV1.self) == "JournalEntry{date:Date,energy:Optional<Int>,focus:Optional<Int>,id:UUID,mood:Optional<Int>,text:String|}", Comment(rawValue: Self.message + " Now: " + fingerprint(JournalSchemaV1.self)))
    }

    @Test func everyStoredModelBelongsToAVersionedSchemaThisTestKnows() throws {
        // A fourth SwiftData store would need a fingerprint here: any `@Model` outside the three is a failure of this list, not of the model.
        let files = RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources"])
        let models = files.filter { RawDefaultsTests.code($0.text).contains("@Model") }.map(\.path)
        let known = ["NoctisSchema", "CoachHistory", "JournalStore", "AppModels", "WindDownSession", "UserProfile", "AlarmConfiguration", "AIConversation", "JournalEntry"]
        for path in models {
            #expect(known.contains { path.contains($0) }, Comment(rawValue: "\(path) declares a @Model that no fingerprint above covers"))
        }
    }
}
