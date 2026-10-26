import SwiftData

// The app's database (APP_RULES.md R65). Every SwiftData store is opened through a `VersionedSchema` and a `SchemaMigrationPlan`, so a
// shipped store always has a named version and a way forward. A schema change is a new version in this file (or the Coach and Journal ones),
// a migration stage, and a test that opens a store written by the version before it: `SchemaMigrationTests` fails on a `@Model` that is in
// no version, and on a version that has no stage after it.
//
// Version 1 is the schema as it shipped: it names the live model classes. The first change freezes them: move the classes into
// `NoctisSchemaV1` as nested copies (the shipped shape), put the changed ones in `NoctisSchemaV2`, point the app at V2, and add the stage.

/// The app's own database (`default.store`): the profile, the wake alarm's settings and the wind-down record.
public nonisolated enum NoctisSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [UserProfileRecord.self, AlarmConfiguration.self, WindDownSession.self]
    }
}

/// Every version of the app's database, oldest first, and how to get from each to the next.
public nonisolated enum NoctisMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [NoctisSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

/// The version the app opens its database as.
public typealias NoctisCurrentSchema = NoctisSchemaV1
