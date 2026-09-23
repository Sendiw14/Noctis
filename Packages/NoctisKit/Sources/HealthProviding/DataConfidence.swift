public enum DataConfidence: String, Sendable, Comparable, CaseIterable {
    case low
    case moderate
    case high

    public var displayName: String {
        switch self {
        case .low: "Limited"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }

    public static func < (lhs: DataConfidence, rhs: DataConfidence) -> Bool { rank(lhs) < rank(rhs) }

    private static func rank(_ confidence: DataConfidence) -> Int {
        switch confidence {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }

    public static func forSampleCount(_ count: Int, fullAt: Int) -> DataConfidence {
        guard fullAt > 0 else { return .low }
        let ratio = Double(count) / Double(fullAt)
        if ratio >= 0.8 { return .high }
        if ratio >= 0.4 { return .moderate }
        return .low
    }
}
