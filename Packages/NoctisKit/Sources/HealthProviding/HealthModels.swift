import Foundation

public nonisolated enum SleepStageValue: String, Sendable, CaseIterable, Codable {
    case inBed
    case awake
    case rem
    case core
    case deep
    case unspecified
}

nonisolated extension SleepStageValue {
    /// Core, deep, REM and unspecified: time that counts toward total sleep.
    public var isAsleep: Bool {
        switch self {
        case .core, .deep, .rem, .unspecified: true
        case .inBed, .awake: false
        }
    }
}

public nonisolated struct RawSleepSample: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let stage: SleepStageValue
    public let sourceName: String
    public let sourceBundleID: String
    /// The time zone the sample was recorded in (HealthKit's
    /// `HKMetadataKeyTimeZone`), when the source wrote one. Night keys and
    /// clock times use it, so a night recorded while traveling keeps its
    /// local bedtime.
    public let timeZone: TimeZone?

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        stage: SleepStageValue,
        sourceName: String,
        sourceBundleID: String,
        timeZone: TimeZone? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.timeZone = timeZone
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public nonisolated struct HeartRateSample: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let bpm: Double
    public let sourceName: String

    public init(id: UUID = UUID(), date: Date, bpm: Double, sourceName: String) {
        self.id = id
        self.date = date
        self.bpm = bpm
        self.sourceName = sourceName
    }
}

public nonisolated struct HRVSample: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let sdnnMilliseconds: Double

    public init(id: UUID = UUID(), date: Date, sdnnMilliseconds: Double) {
        self.id = id
        self.date = date
        self.sdnnMilliseconds = sdnnMilliseconds
    }
}

public nonisolated struct RespiratoryRateSample: Sendable, Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let breathsPerMinute: Double

    public init(id: UUID = UUID(), date: Date, breathsPerMinute: Double) {
        self.id = id
        self.date = date
        self.breathsPerMinute = breathsPerMinute
    }
}

public nonisolated enum HealthDataKind: String, Sendable, CaseIterable {
    case sleepAnalysis
    case heartRate
    case restingHeartRate
    case hrv
    case respiratoryRate

    public var displayName: String {
        switch self {
        case .sleepAnalysis: "Sleep"
        case .heartRate: "Heart Rate"
        case .restingHeartRate: "Resting Heart Rate"
        case .hrv: "Heart Rate Variability"
        case .respiratoryRate: "Respiratory Rate"
        }
    }

    public var benefit: String {
        switch self {
        case .sleepAnalysis: "Understand how long and consistently you sleep."
        case .heartRate: "Put your recovery trend into context."
        case .restingHeartRate: "Track how your body responds to rest over time."
        case .hrv: "Compare your recent recovery signal with your own baseline."
        case .respiratoryRate: "Add context to unusual nights."
        }
    }

    public var systemImage: String {
        switch self {
        case .sleepAnalysis: "bed.double.fill"
        case .heartRate: "heart.fill"
        case .restingHeartRate: "heart.text.square.fill"
        case .hrv: "waveform.path.ecg"
        case .respiratoryRate: "lungs.fill"
        }
    }
}

extension HealthDataKind {
    /// The kinds onboarding asks for, and the ones whose question decides whether Home, Sleep, Recovery and Insights load. Resting heart rate and
    /// respiratory rate are extras: they are asked for only from "Connect Apple Health", never as a side effect of the onboarding step, and a
    /// person who was never asked for them still sees every screen (those two readings are simply absent).
    public static let core: [HealthDataKind] = [.sleepAnalysis, .heartRate, .hrv]
}

public nonisolated enum HealthAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}
