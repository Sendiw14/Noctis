import Foundation
import NightKit
import SwiftData
import Testing

@testable import NoctisCore

/// The wake alarm's record (APP_RULES.md R30): kept locally, with the defaults the spec names.
@MainActor
struct AlarmConfigurationTests {
    private func makeStore() throws -> (AlarmConfigurationStore, ModelContext) {
        let schema = Schema([UserProfileRecord.self, AlarmConfiguration.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        return (AlarmConfigurationStore(context: context), context)
    }

    @Test func aNewRecordHasTheSpecsDefaults() {
        let record = AlarmConfiguration()
        #expect(record.minutesSinceMidnight == 7 * 60)
        #expect(record.repeatDaysRaw.isEmpty)
        #expect(!record.snoozeEnabled)
        #expect(record.snoozeMinutes == 9)
        #expect(record.alarmKitID == nil)
        #expect(record.settings.lastState == .off)
    }

    @Test func nothingIsSavedBeforeTheFirstSave() async throws {
        let (store, _) = try makeStore()
        #expect(await store.load() == nil)
    }

    @Test func theSettingsRoundTrip() async throws {
        let (store, context) = try makeStore()
        let id = UUID()
        let settings = AlarmSettings(
            minutesSinceMidnight: 6 * 60 + 40, repeatDays: [.monday, .thursday, .saturday], snoozeEnabled: true, snoozeMinutes: 10,
            alarmKitID: id, lastState: .armed
        )
        await store.save(settings)
        #expect(await store.load() == settings)
        // Saving again changes the one record, never adds another.
        await store.save(AlarmSettings(minutesSinceMidnight: 8 * 60))
        let records = try context.fetch(FetchDescriptor<AlarmConfiguration>())
        #expect(records.count == 1)
        #expect(await store.load()?.minutesSinceMidnight == 8 * 60)
        #expect(await store.load()?.alarmKitID == nil)
    }

    @Test func anUnknownStateOrDayIsReadSafely() async throws {
        let (store, context) = try makeStore()
        let record = AlarmConfiguration()
        record.lastStateRaw = "somethingNew"
        record.repeatDaysRaw = [2, 99, 6]
        context.insert(record)
        try context.save()
        let loaded = await store.load()
        #expect(loaded?.lastState == .off)
        #expect(loaded?.repeatDays == [.monday, .friday])
    }

    @Test func eraseForgetsTheAlarm() async throws {
        let (store, _) = try makeStore()
        await store.save(AlarmSettings(minutesSinceMidnight: 420, lastState: .armed))
        store.erase()
        #expect(await store.load() == nil)
    }

    @Test func serviceAndStoreWorkTogether() async throws {
        let (store, _) = try makeStore()
        let backend = MockAlarmBackend(mode: .authorized)
        let service = AlarmService(backend: backend, store: store, defaultMinutes: { 7 * 60 })
        let status = await service.enable(AlarmSettings(minutesSinceMidnight: 7 * 60, repeatDays: AlarmWeekday.weekdays))
        #expect(status.state == .armed)
        let saved = await store.load()
        #expect(saved?.lastState == .armed)
        #expect(saved?.repeatDays == AlarmWeekday.weekdays)
        #expect(saved?.alarmKitID == status.settings.alarmKitID)
    }
}
