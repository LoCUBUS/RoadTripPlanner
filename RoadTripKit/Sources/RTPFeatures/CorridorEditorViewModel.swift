import Foundation
import Observation
import RTPCore
import RTPProviders
import RTPRouting

/// Drives Phase 1's corridor editor: mutates the trip's anchor chain and
/// keeps the cached route legs (`Trip.legs`) in sync via `RouteCoordinator`.
/// Kept independent of SwiftUI so the recalculation/persistence logic is
/// unit-testable with `StubMapProvider` (docs/CONCEPT.md §2.1, §2.4).
@MainActor
@Observable
public final class CorridorEditorViewModel {
    public let trip: Trip
    private let routeCoordinator: RouteCoordinator

    public private(set) var isRecalculating = false
    public private(set) var recalculationError: String?

    public init(trip: Trip, routeCoordinator: RouteCoordinator) {
        self.trip = trip
        self.routeCoordinator = routeCoordinator
    }

    public var orderedAnchors: [Anchor] {
        trip.orderedAnchors
    }

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

    public func setStart(title: String, coordinate: Coordinate, mapItemIdentifier: String? = nil) {
        trip.setStart(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
    }

    public func setDestination(title: String, coordinate: Coordinate, mapItemIdentifier: String? = nil) {
        trip.setDestination(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
    }

    public func addWaypoint(title: String, coordinate: Coordinate, mapItemIdentifier: String? = nil) {
        let anchor = trip.addWaypoint(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        Task { await routeCoordinator.invalidate(anchorID: anchor.id) }
    }

    public func removeAnchor(_ anchor: Anchor) {
        let id = anchor.id
        trip.removeAnchor(id: id)
        pruneOrphanedLegs()
        Task { await routeCoordinator.invalidate(anchorID: id) }
    }

    public func moveMiddleAnchors(fromOffsets: IndexSet, toOffset: Int) {
        trip.reorderMiddleAnchors(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    /// Recomputes only the legs invalidated since the last call, persisting
    /// the results into `trip.legs` via the shared `RouteRecalculator`.
    public func recalculateRoute() async {
        isRecalculating = true
        recalculationError = nil
        defer { isRecalculating = false }

        let outcome = await RouteRecalculator.recalculate(trip: trip, using: routeCoordinator)
        if outcome.hasStaleLegs {
            recalculationError = "Some legs could not be routed and use a straight-line estimate."
        }
    }

    /// Removes any cached leg whose endpoints are no longer both present in
    /// the anchor chain (e.g. after `removeAnchor`).
    private func pruneOrphanedLegs() {
        let validIDs = Set(orderedAnchors.map(\.id))
        trip.legs.removeAll { !validIDs.contains($0.fromAnchorID) || !validIDs.contains($0.toAnchorID) }
    }
}
