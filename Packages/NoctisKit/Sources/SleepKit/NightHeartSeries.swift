import Foundation
import HealthProviding

/// Heart rate across one night, for the night panel's heart-rate strip:
/// the real samples recorded between the session's start and end, placed
/// along the night (0...1) and downsampled to at most `maxPoints` by
/// averaging equal slices of time. Nil with no samples in the night.
public struct NightHeartSeries: Sendable, Equatable, Codable {
    public struct Point: Sendable, Equatable, Codable {
        /// 0...1 along the night.
        public let position: Double
        public let bpm: Double

        public init(position: Double, bpm: Double) {
            self.position = position
            self.bpm = bpm
        }
    }

    public static let maxPoints = 120

    /// Oldest first.
    public let points: [Point]

    public init(points: [Point]) {
        self.points = points
    }

    /// The line's lowest point.
    public var lowest: Point {
        points.min { $0.bpm < $1.bpm } ?? Point(position: 0, bpm: 0)
    }

    public var highest: Point {
        points.max { $0.bpm < $1.bpm } ?? Point(position: 0, bpm: 0)
    }

    public static func build(samples: [HeartRateSample], from start: Date, to end: Date, maxPoints: Int = maxPoints) -> NightHeartSeries? {
        let span = end.timeIntervalSince(start)
        guard span > 0, maxPoints > 0 else { return nil }
        let inside =
            samples
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
            .map { Point(position: $0.date.timeIntervalSince(start) / span, bpm: $0.bpm) }
        guard !inside.isEmpty else { return nil }
        guard inside.count > maxPoints else { return NightHeartSeries(points: inside) }
        // Equal slices of the night; each non-empty slice becomes the mean
        // position and mean bpm of its samples.
        var slices = Array(repeating: [Point](), count: maxPoints)
        for point in inside {
            slices[min(Int(point.position * Double(maxPoints)), maxPoints - 1)].append(point)
        }
        let points = slices.compactMap { slice -> Point? in
            guard !slice.isEmpty else { return nil }
            let count = Double(slice.count)
            return Point(position: slice.reduce(0) { $0 + $1.position } / count, bpm: slice.reduce(0) { $0 + $1.bpm } / count)
        }
        return NightHeartSeries(points: points)
    }

    /// Heart rate at `position`, interpolated between the nearest points;
    /// nil before the first point or after the last.
    public func bpm(at position: Double) -> Double? {
        guard let first = points.first, let last = points.last,
            position >= first.position, position <= last.position
        else { return nil }
        guard let upper = points.firstIndex(where: { $0.position >= position }) else { return last.bpm }
        guard upper > 0 else { return points[upper].bpm }
        let a = points[upper - 1], b = points[upper]
        let t = b.position > a.position ? (position - a.position) / (b.position - a.position) : 0
        return a.bpm + (b.bpm - a.bpm) * t
    }
}
