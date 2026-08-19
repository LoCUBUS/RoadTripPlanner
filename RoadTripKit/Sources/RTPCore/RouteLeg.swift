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

    /// Encoded per-step distances, used only to interpolate the Phase 3
    /// time-up point at step granularity (docs/CONCEPT.md §2.6) — MKRoute
    /// exposes no per-step duration, only per-step distance.
    public var encodedSteps: Data = Data()

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
        encodedSteps: Data = Data(),
        computedAt: Date = .distantPast,
        isStale: Bool = true
    ) {
        self.id = id
        self.fromAnchorID = fromAnchorID
        self.toAnchorID = toAnchorID
        self.distanceMeters = distanceMeters
        self.expectedTravelTime = expectedTravelTime
        self.encodedPolyline = encodedPolyline
        self.encodedSteps = encodedSteps
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

    /// Convenience accessor decoding/encoding `encodedSteps` as a plain
    /// `[RouteLegStep]`.
    public var steps: [RouteLegStep] {
        get {
            (try? JSONDecoder().decode([RouteLegStep].self, from: encodedSteps)) ?? []
        }
        set {
            encodedSteps = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}

/// A framework-independent stand-in for `MKRoute.Step`: just enough to
/// distribute a leg's travel time along its length by distance share
/// (docs/CONCEPT.md §2.6). `RTPProviders.RouteStep` is the provider-facing
/// equivalent; keeping a separate type here means `RTPCore` doesn't need to
/// depend on `RTPProviders`.
public struct RouteLegStep: Codable, Sendable, Equatable {
    public var distanceMeters: Double
    public var endCoordinate: Coordinate

    public init(distanceMeters: Double, endCoordinate: Coordinate) {
        self.distanceMeters = distanceMeters
        self.endCoordinate = endCoordinate
    }
}
