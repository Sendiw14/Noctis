import Foundation
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import NoctisCore
@testable import NoctisWidgetKit
@testable import PremiumKit

// The plan in the shared snapshot (APP_RULES.md R62): a free or premium flag the app writes and the extensions and the Watch read, so that nothing outside
// the app ever calls StoreKit. Additive to version 2, small, free when it is missing or unreadable, written the moment the plan changes.

private nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var snapshots: [WidgetSnapshot] = []
    func bump() { lock.withLock { value += 1 } }
    func received(_ snapshot: WidgetSnapshot) { lock.withLock { snapshots.append(snapshot) } }
    var count: Int { lock.withLock { value } }
    var sent: [WidgetSnapshot] { lock.withLock { snapshots } }
}

private actor TierBox {
    var value: Tier
    init(_ value: Tier) { self.value = value }
    func set(_ tier: Tier) { value = tier }
}

struct TierSnapshotShapeTests {
    /// The snapshot's JSON as a dictionary, edited, and back to bytes.
    private func edited(_ snapshot: WidgetSnapshot, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func aVersionTwoSnapshotWithoutTheFieldIsFree() throws {
        let data = try edited(WidgetFixture.full.with(tier: .premium)) { $0.removeValue(forKey: "t") }
        let decoded = try #require(WidgetSnapshot.decode(data))
        #expect(decoded.version == 2 && WidgetSnapshot.currentVersion == 2, "additive: still version 2")
        #expect(decoded.tier == .free, "written before the flag existed: free")
        #expect(decoded == WidgetFixture.full, "everything else is as it was")
    }

    @Test func aNewSnapshotIsFreeUntilTheAppSaysOtherwise() {
        #expect(WidgetFixture.full.tier == .free)
        #expect(WidgetFixture.full.with(tier: .premium).tier == .premium)
    }

    @Test func theFlagRoundTripsAsOneShortWord() throws {
        for tier in Tier.allCases {
            let data = try WidgetFixture.full.with(tier: tier).encoded()
            #expect(WidgetSnapshot.decode(data)?.tier == tier)
            let text = String(decoding: data, as: UTF8.self)
            #expect(text.contains("\"t\":\"\(tier.rawValue)\""), Comment(rawValue: text))
        }
    }

    @Test func aFlagThatCannotBeReadNeverUnlocksAnything() throws {
        for junk in [NSNull(), "gold", 7, "PREMIUM", ["premium"]] as [Any] {
            let data = try edited(WidgetFixture.full.with(tier: .premium)) { $0["t"] = junk }
            #expect(WidgetSnapshot.decode(data)?.tier == .free, Comment(rawValue: "\(junk)"))
        }
    }

    @Test func theSizeCapStillHolds() throws {
        let data = try WidgetFixture.full.with(tier: .premium).encoded()
        #expect(data.count < WidgetSnapshot.maximumBytes / 2, "\(data.count) bytes")
        #expect(WidgetSnapshot.maximumBytes == 3072)
        let directory = try WidgetFixture.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(WidgetSnapshotStore(directory: directory).save(WidgetFixture.full.with(tier: .premium)))
    }

    @Test func theMakerCarriesTheTier() async throws {
        let now = WidgetFixture.now
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let home = await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        for tier in Tier.allCases {
            let made = try #require(WidgetSnapshotMaker.make(home: home, profile: UserProfileSnapshot(), bedtime: nil, alarm: nil, now: now, calendar: WidgetFixture.calendar, tier: tier))
            #expect(made.tier == tier)
        }
        let unspecified = try #require(WidgetSnapshotMaker.make(home: home, profile: UserProfileSnapshot(), bedtime: nil, alarm: nil, now: now, calendar: WidgetFixture.calendar))
        #expect(unspecified.tier == .free, "no tier given is free")
    }

    @Test func theSnapshotNamesNothingAboutAPurchase() throws {
        let source = RawDefaultsTests.code(try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetSnapshot.swift"), encoding: .utf8))
        for word in ["StoreKit", "Transaction", "productID", "expiration", "originalTransaction", "receipt"] {
            #expect(!source.contains(word), Comment(rawValue: "the snapshot mentions \(word)"))
        }
    }
}

struct TierPublishingTests {
    private let now = WidgetFixture.now

    private func bench(tier: TierBox, counter: Counter) throws -> (WidgetPublisher, WidgetSnapshotStore, URL) {
        let directory = try WidgetFixture.directory()
        let store = WidgetSnapshotStore(directory: directory)
        let inputs = WidgetInputSource(profile: { UserProfileSnapshot() })
        inputs.setTier { await tier.value }
        let clock = now
        let publisher = WidgetPublisher(
            store: store, inputs: inputs, reload: { counter.bump() }, clock: { clock }, calendar: WidgetFixture.calendar,
            afterWrite: { counter.received($0) }
        )
        return (publisher, store, directory)
    }

    private func repository(_ publisher: WidgetPublisher) -> HomeRepository {
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let clock = now
        return HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }, widgets: publisher)
    }

    @Test func aChangeOfTierWritesTheSnapshotAndReloadsTheWidgetsAndTheWatchIsSentIt() async throws {
        let tier = TierBox(.free)
        let counter = Counter()
        let (publisher, store, directory) = try bench(tier: tier, counter: counter)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = await repository(publisher).refresh(profile: UserProfileSnapshot())
        #expect(store.load()?.tier == .free && counter.count == 1)

        await tier.set(.premium)
        await publisher.republish()
        #expect(store.load()?.tier == .premium, "the moment the tier changes the file says so")
        #expect(counter.count == 2, "and the widgets are redrawn")
        #expect(counter.sent.last?.tier == .premium && counter.sent.count == 2, "and the same snapshot goes to the Watch")

        await tier.set(.free)
        await publisher.republish()
        #expect(store.load()?.tier == .free && counter.count == 3, "a lapse locks them again")
        #expect(counter.sent.last?.tier == .free)
    }

    @Test func theSameTierWritesAndReloadsNothing() async throws {
        let tier = TierBox(.premium)
        let counter = Counter()
        let (publisher, store, directory) = try bench(tier: tier, counter: counter)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = await repository(publisher).refresh(profile: UserProfileSnapshot())
        await publisher.republish()
        await publisher.republish()
        #expect(counter.count == 1 && store.load()?.tier == .premium, "the system's reload budget is for real changes")
    }

    @Test func deleteAllStillWipesAndTheFlagIsNotKeptAnywhereElse() async throws {
        let tier = TierBox(.premium)
        let counter = Counter()
        let (publisher, store, directory) = try bench(tier: tier, counter: counter)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = await repository(publisher).refresh(profile: UserProfileSnapshot())
        #expect(store.exists)
        await publisher.forget()
        #expect(store.load() == nil && !store.exists, "the file, and with it the flag, are gone")
        let reloadsAfterForget = counter.count
        await publisher.republish()
        #expect(store.load() == nil && counter.count == reloadsAfterForget, "nothing is written back with no Home data")
    }

    @Test func theAppRewritesTheSnapshotWhenThePlanChanges() throws {
        let container = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"), encoding: .utf8)
        #expect(container.contains("widgetInputs.setTier { await MainActor.run { gate.tier } }"), "the snapshot says what the gate says")
        let hook = try #require(container.range(of: "store.entitlementManager.onTierChange = { new, old in"))
        #expect(container[hook.upperBound...].prefix(400).contains("widgetPublisher.republish()"), "a change of tier writes it again at once")
    }

    @Test func noExtensionOrWatchTargetCallsStoreKit() throws {
        for folder in ["NoctisWidgets", "NOCTISWatch", "NOCTISWatchWidgets", "Packages/NoctisKit/Sources/NoctisWidgetKit", "Packages/NoctisKit/Sources/NoctisWatchKit", "Packages/NoctisKit/Sources/NoctisIntentKit"] {
            let found = RawDefaultsTests.swiftFiles(under: [folder])
            #expect(!found.isEmpty, Comment(rawValue: folder))
            for file in found {
                #expect(!file.text.contains("import StoreKit"), Comment(rawValue: "\(file.path) imports StoreKit"))
            }
        }
    }
}
