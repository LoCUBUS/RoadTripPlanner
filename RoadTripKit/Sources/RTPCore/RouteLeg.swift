import Foundation
import SwiftData

/// A cached driving leg between two consecutive anchors. Legs are the unit
/// of MKDirections requests; `RouteCoordinator` (RTPRouting) only
/// invalidates and recomputes the legs touching an edited anchor, never the
/// whole route (docs/CONCEPT.md §2.4).
@Model
public final class RouteLeg {
    public var id: UUID = UUID()

    public var fromAnchorID: UUID = UUID()
    public var toAnchorID: UUID = UUID()

    public var distanceMeters: Double = 0
    public var expectedTravelTime: TimeInterval = 0

    /// Encoded polyline coordinates so the leg renders even offline.
    public var encodedPolyline: Data = Data()

    public var computedAt: Date = Date.distantPast

    /// True until a successful directions request replaces the straight-line
    /// fallback, or after an upstream edit invalidates this leg.
    public var isStale: Bool = true

    public var trip: Trip?

    public init(
        id: UUID = UUID(),
        fromAnchorID: UUID,
        toAnchorID: UUID,
        distanceMeters: Double = 0,
        expectedTravelTime: TimeInterval = 0,
        encodedPolyline: Data = Data(),
        computedAt: Date = .distantPast,
        isStale: Bool = true
    ) {
        self.id = id
        self.fromAnchorID = fromAnchorID
        self.toAnchorID = toAnchorID
        self.distanceMeters = distanceMeters
        self.expectedTravelTime = expectedTravelTime
        self.encodedPolyline = encodedPolyline
        self.computedAt = computedAt
        self.isStale = isStale
    }

    /// Convenience accessor decoding/encoding `encodedPolyline` as a plain
    /// `[Coordinate]`. A simple JSON encoding is used rather than a
    /// specialised polyline compression algorithm — it keeps `RTPCore` free
    /// of extra dependencies; revisit if leg storage size becomes a concern.
    public var polylineCoordinates: [Coordinate] {
        get {
            (try? JSONDecoder().decode([Coordinate].self, from: encodedPolyline)) ?? []
        }
        set {
            encodedPolyline = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}
