import Foundation

/// The small statistics the insight rules share.
public enum InsightStats {
    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (n − 1); nil under two values.
    public static func sampleSD(_ values: [Double]) -> Double? {
        guard values.count >= 2, let mean = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// The pooled standard deviation of two samples; nil when either has
    /// under two values.
    public static func pooledSD(_ a: [Double], _ b: [Double]) -> Double? {
        guard let sdA = sampleSD(a), let sdB = sampleSD(b) else { return nil }
        let df = Double(a.count + b.count - 2)
        guard df > 0 else { return nil }
        return ((Double(a.count - 1) * sdA * sdA + Double(b.count - 1) * sdB * sdB) / df).squareRoot()
    }

    /// `difference` over `pooledSD`, capped at ±99 so it can be stored (a
    /// group with no spread at all has an effect of any size).
    public static func effectSize(difference: Double, pooledSD: Double) -> Double {
        guard pooledSD > 0 else { return difference == 0 ? 0 : (difference > 0 ? 99 : -99) }
        return min(max(difference / pooledSD, -99), 99)
    }
}
