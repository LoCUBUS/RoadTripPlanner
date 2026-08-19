import Foundation

extension Trip {
    /// Creates a detached, unsaved copy of this trip: the anchor chain, its
    /// cached legs and the day segmentation are deep-copied; Phase 4 state
    /// (visited/comment/rating) and Phase 5 photos are intentionally
    /// **not** copied — a duplicate always starts as a fresh trip
    /// (docs/CONCEPT.md §1.5 "Trip management").
    ///
    /// The caller is responsible for inserting the returned `Trip` into a
    /// `ModelContext`.
    public func duplicate(name: String? = nil) -> Trip {
        let copy = Trip(
            name: name ?? "\(self.name) Copy",
            notes: notes,
            currentPhase: currentPhase
        )

        var anchorIDMap: [UUID: UUID] = [:]
        let sortedAnchors = anchors.sorted { $0.order < $1.order }
        copy.anchors = sortedAnchors.map { original in
            let newAnchor = Anchor(
                order: original.order,
                kind: original.kind,
                title: original.title,
                subtitle: original.subtitle,
                coordinate: original.coordinate,
                mapItemIdentifier: original.mapItemIdentifier,
                category: original.category,
                dwellDuration: original.dwellDuration
            )
            anchorIDMap[original.id] = newAnchor.id
            return newAnchor
        }

        copy.legs = legs.compactMap { original in
            guard let newFrom = anchorIDMap[original.fromAnchorID],
                  let newTo = anchorIDMap[original.toAnchorID]
            else { return nil }
            return RouteLeg(
                fromAnchorID: newFrom,
                toAnchorID: newTo,
                distanceMeters: original.distanceMeters,
                expectedTravelTime: original.expectedTravelTime,
                encodedPolyline: original.encodedPolyline,
                computedAt: original.computedAt,
                isStale: original.isStale
            )
        }

        copy.days = days.map { original in
            TripDay(
                index: original.index,
                budget: original.budget,
                plannedDate: nil, // a duplicate is a fresh plan; dates don't carry over
                startAnchorID: original.startAnchorID.flatMap { anchorIDMap[$0] },
                endAnchorID: original.endAnchorID.flatMap { anchorIDMap[$0] },
                timeUpPoint: original.timeUpPoint,
                searchRadiusMeters: original.searchRadiusMeters
            )
        }

        // phaseStatus and photos are deliberately left at their defaults
        // (empty) — nothing to review yet, no journal entries yet.
        return copy
    }
}
