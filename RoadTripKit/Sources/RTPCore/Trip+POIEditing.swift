import Foundation

/// The result of `Trip.addPOI`, carrying whatever is needed to undo the
/// addition (docs/CONCEPT.md §1.5 "Phase 2 — Points of interest").
public struct POIAdditionResult {
    /// The newly created POI anchor.
    public let poi: Anchor
    /// The Phase 1 waypoint that was absorbed and removed, if any.
    public let absorbedWaypoint: Anchor?
}

/// Phase 2 anchor-chain editing: adding a fixed POI, the 10 km absorption
/// rule against coarse Phase 1 waypoints, and projection-based insertion
/// for POIs that don't absorb anything (docs/CONCEPT.md §2.5).
public extension Trip {
    /// Adds a POI to the anchor chain.
    ///
    /// If an absorbable (Phase 1 waypoint) anchor lies within
    /// `absorptionRadiusMeters` of `coordinate`, the *nearest* one is removed
    /// and the POI takes its place in the order — start and destination are
    /// never absorbed. Otherwise the POI is inserted into whichever existing
    /// leg its coordinate projects closest to, so the user usually doesn't
    /// need to reorder manually afterwards.
    @discardableResult
    func addPOI(
        title: String,
        coordinate: Coordinate,
        mapItemIdentifier: String? = nil,
        category: POICategory? = nil,
        dwellDuration: TimeInterval = 45 * 60,
        isOvernightCandidate: Bool = false,
        absorptionRadiusMeters: Double = 10_000
    ) -> POIAdditionResult {
        let poi = Anchor(
            kind: .poi,
            title: title,
            coordinate: coordinate,
            mapItemIdentifier: mapItemIdentifier,
            category: category,
            dwellDuration: dwellDuration,
            isOvernightCandidate: isOvernightCandidate
        )

        let nearestAbsorbable = anchors
            .filter { $0.kind.isAbsorbable }
            .map { (anchor: $0, distance: $0.coordinate.distance(to: coordinate)) }
            .filter { $0.distance <= absorptionRadiusMeters }
            .min { $0.distance < $1.distance }

        if let victim = nearestAbsorbable?.anchor {
            poi.order = victim.order
            anchors.removeAll { $0.id == victim.id }
            poi.trip = self
            anchors.append(poi)
            reindexOrder()
            updatedAt = .now
            markNeedsReview(after: .pointsOfInterest)
            return POIAdditionResult(poi: poi, absorbedWaypoint: victim)
        }

        // `insertByProjection` reads `orderedAnchors` to find the closest
        // leg — it must run before `poi.trip`/`anchors.append` link the POI
        // into the relationship, since SwiftData keeps `Anchor.trip` and
        // `Trip.anchors` in sync in both directions and would otherwise
        // make the still-unpositioned POI appear in its own projection.
        insertByProjection(poi)
        poi.trip = self
        reindexOrder()
        updatedAt = .now
        markNeedsReview(after: .pointsOfInterest)
        return POIAdditionResult(poi: poi, absorbedWaypoint: nil)
    }

    /// Reverts an `addPOI` call: removes the POI and, if it absorbed a
    /// waypoint, restores that waypoint to the chain.
    func undoPOIAddition(_ result: POIAdditionResult) {
        anchors.removeAll { $0.id == result.poi.id }
        if let waypoint = result.absorbedWaypoint {
            waypoint.trip = self
            anchors.append(waypoint)
        }
        reindexOrder()
        updatedAt = .now
        markNeedsReview(after: .pointsOfInterest)
    }

    /// Inserts a non-absorbing POI into the leg its coordinate projects
    /// closest to (measured against the leg's cached polyline when
    /// available, otherwise the straight line between its two anchors), so
    /// it lands in a sensible position without requiring a manual reorder.
    /// Falls back to appending like `addWaypoint` when there are fewer than
    /// two anchors to project against.
    ///
    /// Every anchor from the chosen leg's destination onward has its
    /// `order` shifted up by one to make room for the POI's order value —
    /// this is deliberate rather than relying on a tie-break, because
    /// SwiftData relationship arrays are not guaranteed to preserve
    /// insertion order (docs/CONCEPT.md §2.2), so a tied `order` value would
    /// sort unpredictably instead of always landing after its neighbour.
    /// Not `private` — reused by `Trip+CorridorEditing.addWaypoint` when the
    /// middle section already contains fixed Phase 2/3 anchors, so a new
    /// Phase 1 waypoint lands at a sensible position without re-sorting
    /// anchors a later phase has already refined (principle P2).
    func insertByProjection(_ poi: Anchor) {
        let chain = orderedAnchors
        guard chain.count >= 2 else {
            let maxMiddleOrder = orderedMiddleAnchors.map(\.order).max() ?? 0
            poi.order = maxMiddleOrder + 1
            anchors.append(poi)
            return
        }

        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude

        for index in 0..<(chain.count - 1) {
            let from = chain[index]
            let to = chain[index + 1]
            for (segmentStart, segmentEnd) in legSegments(from: from, to: to) {
                let distance = poi.coordinate.distance(toSegmentFrom: segmentStart, to: segmentEnd)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
        }

        let insertionOrder = chain[bestIndex + 1].order
        for anchor in anchors where anchor.order >= insertionOrder {
            anchor.order += 1
        }
        poi.order = insertionOrder
        anchors.append(poi)
    }

    /// The polyline sub-segments of the cached leg between two anchors, or
    /// the single straight-line segment between their coordinates if no leg
    /// has been computed yet.
    private func legSegments(from: Anchor, to: Anchor) -> [(Coordinate, Coordinate)] {
        if let leg = legs.first(where: { $0.fromAnchorID == from.id && $0.toAnchorID == to.id }) {
            let points = leg.polylineCoordinates
            if points.count >= 2 {
                return Array(zip(points, points.dropFirst()))
            }
        }
        return [(from.coordinate, to.coordinate)]
    }
}
