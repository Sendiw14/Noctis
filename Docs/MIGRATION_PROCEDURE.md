# Changing a stored model (migration procedure)

NOCTIS keeps three SwiftData databases, each opened through a `VersionedSchema` and a `SchemaMigrationPlan`:

| Database | Schema | Plan | Holds |
| --- | --- | --- | --- |
| `default.store` | `NoctisSchemaV1` | `NoctisMigrationPlan` | profile, wake alarm settings, wind-down history |
| `coach-history.store` | `CoachHistorySchemaV1` | `CoachHistoryMigrationPlan` | Coach conversations |
| `journal.store` | `JournalSchemaV1` | `JournalMigrationPlan` | Journal entries |

The insights, the reviews, the widget summary and the preference files are JSON with their own version number and are read only if the version matches; they are not covered here.

Every plan has one version and no stages. There is no second version, and none is made up to exercise the machinery: `SchemaMigrationTests` proves the harness with a synthetic version.

## When this applies

Any change to a `@Model` class in one of those schemas: a property added, removed, renamed or retyped, a default changed, a relationship changed. A change that is not to a stored property (a computed property, a method) does not.

`SchemaFingerprintTests` records the shape of each shipped version. A model change makes it fail with "A stored model changed". The failure is the reminder. **Do not edit the recorded line to make the test pass.**

## Steps

1. Add `NoctisSchemaV2` (or the Coach or Journal one) as a new `VersionedSchema` with its own `versionIdentifier`. Keep V1's model types as they shipped (nested copies of the old classes), so the old file can still be read.
2. Add the schema to the plan's `schemas` list and a `MigrationStage` from V1 to V2 to `stages`. A lightweight stage is enough for an added optional property or a property with a default; anything that changes meaning needs a custom stage that moves the data and is written so it can be run again.
3. Point the current schema at V2: for the app database change the alias `NoctisCurrentSchema` (`NoctisSchema.swift`); Coach and Journal have no alias, so change the `schema` constant in `CoachHistoryContainer` (`CoachHistory.swift`) or `JournalContainer` (`JournalStore.swift`), which names `CoachHistorySchemaV1` or `JournalSchemaV1` directly.
4. Build the upgrade fixture: a real V1 store with data in it, made by the shipped build (see below), kept as a test resource.
5. Write the upgrade test: copy the fixture to a temporary folder, open it through the plan, and assert that every row is there with the values it had. Include a row with every optional property set and unset.
6. Update the line in `SchemaFingerprintTests` for the new version, and add a line for the old one so the old shape stays on record.
7. Run `SchemaVersionTests`, `SchemaMigrationTests`, `StoreDamageTests`, `SchemaFingerprintTests` and the new upgrade test.

## Making a V1 fixture

Install the build that is on the App Store (or the TestFlight build that shipped V1) on a simulator, use the app until each model has rows, then copy `default.store`, its `-wal` and `-shm` files (and the Coach and Journal stores, which live in their own folder under Application Support) out of the app's data container. Run `PRAGMA wal_checkpoint(TRUNCATE);` on the copy so the rows are in the one file.

## Before a release that changes a model

Real upgrade test on a device [D]: install the previous release, add data (a profile, an alarm, a wind-down, Journal entries, a Coach conversation), update to the new build, and check that every screen shows the data. Keep the device's store: it is the next fixture.

## What happens when it goes wrong

A store that will not open is set aside whole under `Noctis/Quarantine`, never deleted, and the app starts with an empty one (`StoreRecovery`). That keeps the app running, not the person's data in view: it is the last line, not a migration strategy.
