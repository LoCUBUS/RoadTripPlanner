import Foundation
import Observation
import RTPCore
import RTPRouting

/// Drives Phase 2's POI editor: adds fixed stops with a dwell duration,
/// applies the 10 km absorption rule against Phase 1 waypoints, and keeps
/// route legs in sync via the shared `RouteRecalculator`
/// (docs/CONCEPT.md §1.5 "Phase 2 — Points of interest", §2.5).
@MainActor
@Observable
public final class POIEditorViewModel {
    public let trip: Trip
    private let routeCoordinator: RouteCoordinator

    public private(set) var isRecalculating = false
    public private(set) var recalculationError: String?

    /// Set after `addPOI` absorbs a waypoint, to drive an undoable
    /// "Replaced X with Y" notice in the view. Cleared by
    /// `dismissAbsorptionNotice()` or `undoLastAddition()`.
    public private(set) var lastAbsorption: (poiTitle: String, waypointTitle: String)?
    private var lastAdditionResult: POIAdditionResult?

    public init(trip: Trip, routeCoordinator: RouteCoordinator) {
        self.trip = trip
        self.routeCoordinator = routeCoordinator
    }

    public var orderedAnchors: [Anchor] {
        trip.orderedAnchors
    }

    /// Waypoints and POIs together, in route order — the Phase 2 editor
    /// shows both so the user can see (and reorder) whichever coarse
    /// waypoints haven't been absorbed yet alongside the fixed POIs.
    public var orderedMiddleAnchors: [Anchor] {
        trip.orderedMiddleAnchors
    }

    public var totalDistanceMeters: Double {
        trip.legs.reduce(0) { $0 + $1.distanceMeters }
    }

    public var totalTravelTime: TimeInterval {
        trip.legs.reduce(0) { $0 + $1.expectedTravelTime }
    }

    public var hasStaleLegs: Bool {
        !trip.legs.isEmpty && trip.legs.contains { $0.isStale }
    }

    @discardableResult
    public func addPOI(
        title: String,
        coordinate: Coordinate,
        mapItemIdentifier: String? = nil,
        category: POICategory? = nil,
        dwellDuration: TimeInterval = 45 * 60
    ) -> Anchor {
        let result = trip.addPOI(
            title: title,
            coordinate: coordinate,
            mapItemIdentifier: mapItemIdentifier,
            category: category,
            dwellDuration: dwellDuration
        )
        lastAdditionResult = result
        if let waypoint = result.absorbedWaypoint {
            lastAbsorption = (poiTitle: result.poi.title, waypointTitle: waypoint.title)
        } else {
            lastAbsorption = nil
        }
        Task { await routeCoordinator.invalidate(anchorID: result.poi.id) }
        return result.poi
    }

    /// Reverts the most recent `addPOI` call: removes the POI and restores
    /// any waypoint it absorbed.
    public func undoLastAddition() {
        guard let result = lastAdditionResult else { return }
        trip.undoPOIAddition(result)
        lastAdditionResult = nil
        lastAbsorption = nil
        Task { await routeCoordinator.invalidate(anchorID: result.poi.id) }
    }

    public func dismissAbsorptionNotice() {
        lastAbsorption = nil
    }

    public func removePOI(_ anchor: Anchor) {
        let id = anchor.id
        trip.removeAnchor(id: id)
        Task { await routeCoordinator.invalidate(anchorID: id) }
    }

    public func setDwellDuration(_ duration: TimeInterval, for anchor: Anchor) {
        anchor.dwellDuration = Swift.max(0, duration)
        trip.updatedAt = .now
        trip.markNeedsReview(after: .pointsOfInterest)
    }

    public func setCategory(_ category: POICategory?, for anchor: Anchor) {
        anchor.category = category
        trip.updatedAt = .now
    }

    public func moveMiddleAnchors(fromOffsets: IndexSet, toOffset: Int) {
        trip.reorderMiddleAnchors(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    public func recalculateRoute() async {
        isRecalculating = true
        recalculationError = nil
        defer { isRecalculating = false }

        let outcome = await RouteRecalculator.recalculate(trip: trip, using: routeCoordinator)
        if outcome.hasStaleLegs {
            recalculationError = "Some legs could not be routed and use a straight-line estimate."
        }
    }
}
