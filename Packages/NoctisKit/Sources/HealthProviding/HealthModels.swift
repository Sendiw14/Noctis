import Foundation

public enum SleepStageValue: String, Sendable, CaseIterable, Codable {
    case inBed
    case awake
    case rem
    case core
    case deep
    case unspecified
}

public struct RawSleepSample: Sendable, Identifiable, Codable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let stage: SleepStageValue
    public let sourceName: String
    public let sourceBundleID: String

    public init(id: UUID = UUID(), start: Date, end: Date, stage: SleepStageValue, sourceName: String, sourceBundleID: String) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct HeartRateSample: Sendable, Identifiable, Codable {
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

public struct HRVSample: Sendable, Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let sdnnMilliseconds: Double

    public init(id: UUID = UUID(), date: Date, sdnnMilliseconds: Double) {
        self.id = id
        self.date = date
        self.sdnnMilliseconds = sdnnMilliseconds
    }
}

public struct RespiratoryRateSample: Sendable, Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let breathsPerMinute: Double

    public init(id: UUID = UUID(), date: Date, breathsPerMinute: Double) {
        self.id = id
        self.date = date
        self.breathsPerMinute = breathsPerMinute
    }
}

public enum HealthDataKind: String, Sendable, CaseIterable {
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

public enum HealthAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}
