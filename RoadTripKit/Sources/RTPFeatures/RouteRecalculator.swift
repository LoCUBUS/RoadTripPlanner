import Foundation
import RTPCore
import RTPRouting

/// Shared route-leg recalculation used by every phase editor that mutates
/// the anchor chain (Phase 1 corridor, Phase 2 POIs, and later Phase 3 day
/// segmentation). Recomputes only the invalidated legs via
/// `RouteCoordinator`, persists results into `trip.legs` (matching existing
/// legs by `(fromAnchorID, toAnchorID)` so they're updated in place rather
/// than recreated), and prunes any leg whose endpoints are no longer
/// adjacent in the current anchor chain.
@MainActor
enum RouteRecalculator {
    struct Outcome {
        let hasStaleLegs: Bool
    }

    static func recalculate(trip: Trip, using routeCoordinator: RouteCoordinator) async -> Outcome {
        let chain = trip.orderedAnchors
        guard chain.count >= 2 else {
            trip.legs.removeAll()
            return Outcome(hasStaleLegs: false)
        }

        let anchorPoints = chain.map(AnchorPoint.init(anchor:))
        let results = await routeCoordinator.resolveLegs(for: anchorPoints)

        var legsByKey: [RouteCoordinator.LegKey: RouteLeg] = [:]
        for leg in trip.legs {
            legsByKey[RouteCoordinator.LegKey(from: leg.fromAnchorID, to: leg.toAnchorID)] = leg
        }

        var keptLegs: [RouteLeg] = []
        for result in results {
            let key = RouteCoordinator.LegKey(from: result.fromAnchorID, to: result.toAnchorID)
            let leg = legsByKey[key] ?? RouteLeg(fromAnchorID: result.fromAnchorID, toAnchorID: result.toAnchorID)
            leg.distanceMeters = result.route.distanceMeters
            leg.expectedTravelTime = result.route.expectedTravelTime
            leg.polylineCoordinates = result.route.polyline
            leg.steps = result.route.steps.map { RouteLegStep(distanceMeters: $0.distanceMeters, endCoordinate: $0.endCoordinate) }
            leg.computedAt = result.computedAt
            leg.isStale = result.isStale
            leg.trip = trip
            keptLegs.append(leg)
        }
        trip.legs = keptLegs

        return Outcome(hasStaleLegs: results.contains(where: \.isStale))
    }
}
