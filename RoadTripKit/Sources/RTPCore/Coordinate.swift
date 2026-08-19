import Foundation

/// A plain, `Codable`, framework-independent coordinate. RTPCore intentionally
/// avoids importing CoreLocation/MapKit types directly so the domain layer
/// stays testable and provider-agnostic (see docs/CONCEPT.md §2.3).
public struct Coordinate: Codable, Sendable, Equatable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double = 0, longitude: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance to another coordinate, in meters (haversine formula).
    /// Used by the Phase 2 absorption rule (10 km radius) and lodging search.
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    /// Approximate distance in meters from this coordinate to the line
    /// segment between `start` and `end`. Used by the Phase 2 projection-
    /// based POI insertion (docs/CONCEPT.md §2.5) to find the leg a new,
    /// non-absorbed POI is closest to. Projects onto a local equirectangular
    /// plane centred on `start` — accurate at route-segment scale, not
    /// intended for continental spans.
    public func distance(toSegmentFrom start: Coordinate, to end: Coordinate) -> Double {
        let metersPerDegreeLat = 111_320.0
        let latRad = start.latitude * .pi / 180
        let metersPerDegreeLon = 111_320.0 * cos(latRad)

        func planar(_ c: Coordinate) -> (x: Double, y: Double) {
            ((c.longitude - start.longitude) * metersPerDegreeLon, (c.latitude - start.latitude) * metersPerDegreeLat)
        }

        let p = planar(self)
        let b = planar(end)
        let lengthSquared = b.x * b.x + b.y * b.y
        let t: Double = lengthSquared == 0 ? 0 : Swift.max(0, Swift.min(1, (p.x * b.x + p.y * b.y) / lengthSquared))
        let closestX = t * b.x
        let closestY = t * b.y
        let dx = p.x - closestX
        let dy = p.y - closestY
        return (dx * dx + dy * dy).squareRoot()
    }
}
