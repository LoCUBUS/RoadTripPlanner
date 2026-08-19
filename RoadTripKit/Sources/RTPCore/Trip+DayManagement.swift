import Foundation

/// Phase 3 day CRUD built on top of `segmentDay`: opening the next day,
/// closing it with a chosen lodging, reopening, replacing/removing that
/// lodging, and updating a day's budget (docs/CONCEPT.md §1.5 "Phase 3 —
/// Overnight stays").
public extension Trip {
    /// The anchor a new day should start from: the previous day's end
    /// anchor if a day already exists, or the trip's start anchor
    /// otherwise. Nil if there is no start anchor yet, or the last day
    /// hasn't been closed with a lodging/destination.
    var nextDayStartAnchorID: UUID? {
        let candidate: UUID?
        if let lastDay = days.sorted(by: { $0.index < $1.index }).last {
            candidate = lastDay.endAnchorID
        } else {
            candidate = anchors.first(where: { $0.kind == .start })?.id
        }
        guard let candidate else { return nil }
        // Once a day has closed at the destination, there's nowhere left to plan.
        if anchors.first(where: { $0.id == candidate })?.kind == .destination { return nil }
        return candidate
    }

    /// Opens the next day with the given budget, appends it to `days`, and
    /// immediately runs `segmentDay` to populate its suggested time-up
    /// point — auto-closing it at the destination if the whole remaining
    /// chain fits in budget (the last day never needs a lodging).
    @discardableResult
    func openNextDay(budget: TimeInterval) -> TripDay? {
        guard let startAnchorID = nextDayStartAnchorID else { return nil }
        let day = TripDay(index: days.count, budget: budget, startAnchorID: startAnchorID)
        day.trip = self
        days.append(day)
        recomputeTimeUpPoint(for: day)
        updatedAt = .now
        return day
    }

    /// Re-runs `segmentDay` for `day` and updates its `timeUpPoint`,
    /// auto-closing the day at the destination if the outcome reaches it.
    /// Returns the segmentation result so the caller can react to a
    /// dwell-overrun or an unresolved leg.
    @discardableResult
    func recomputeTimeUpPoint(
        for day: TripDay,
        overshootAnchorIDs: Set<UUID> = [],
        skipDwellAnchorIDs: Set<UUID> = []
    ) -> DaySegmentationResult? {
        guard let startAnchorID = day.startAnchorID else { return nil }
        let result = segmentDay(
            startAnchorID: startAnchorID,
            budget: day.budget,
            overshootAnchorIDs: overshootAnchorIDs,
            skipDwellAnchorIDs: skipDwellAnchorIDs
        )

        switch result.outcome {
        case .reachedBudget(let timeUpPoint, _):
            day.timeUpPoint = timeUpPoint
        case .reachedDestination:
            day.timeUpPoint = nil
            if let destination = anchors.first(where: { $0.kind == .destination }) {
                day.endAnchorID = destination.id
            }
        case .dwellOverrun, .legNotYetResolved:
            day.timeUpPoint = nil
        }
        updatedAt = .now
        return result
    }

    /// Adds a lodging anchor right after `afterAnchorID` (typically the
    /// day's start anchor, or the last anchor a prior `segmentDay` call
    /// reported as contained) and closes the day there.
    @discardableResult
    func closeDay(
        _ day: TripDay,
        afterAnchorID: UUID,
        lodgingTitle: String,
        coordinate: Coordinate,
        mapItemIdentifier: String? = nil,
        category: POICategory? = .hotel
    ) -> Anchor {
        let lodging = Anchor(
            kind: .lodging,
            title: lodgingTitle,
            coordinate: coordinate,
            mapItemIdentifier: mapItemIdentifier,
            category: category
        )
        insertAnchor(lodging, afterAnchorID: afterAnchorID)
        day.endAnchorID = lodging.id
        day.timeUpPoint = nil
        updatedAt = .now
        return lodging
    }

    /// Reopens a closed day by clearing its end anchor. Any lodging anchor
    /// already in the chain is left in place — use `removeLodging(for:)` to
    /// also remove it and merge with the following day.
    func reopenDay(_ day: TripDay) {
        day.endAnchorID = nil
        updatedAt = .now
    }

    /// Updates an existing lodging anchor's title/coordinate in place
    /// without touching day boundaries.
    func replaceLodging(anchorID: UUID, title: String, coordinate: Coordinate, mapItemIdentifier: String? = nil) {
        guard let anchor = anchors.first(where: { $0.id == anchorID && $0.kind == .lodging }) else { return }
        anchor.title = title
        anchor.coordinate = coordinate
        anchor.mapItemIdentifier = mapItemIdentifier
        updatedAt = .now
    }

    /// Removes a day's lodging anchor and merges it with the following day
    /// (docs/CONCEPT.md §2.6 "Deleting a lodging merges the day with the
    /// following one and re-runs segmentation"): the following day's budget
    /// is added to this one, this day inherits the following day's end
    /// anchor, and the following `TripDay` is deleted with later indices
    /// shifted down. If there is no following day, this day is simply
    /// reopened. Call `recomputeTimeUpPoint(for:)` afterwards to re-segment.
    func removeLodging(for day: TripDay) {
        guard let lodgingID = day.endAnchorID,
              anchors.first(where: { $0.id == lodgingID })?.kind == .lodging
        else { return }

        anchors.removeAll { $0.id == lodgingID }
        day.endAnchorID = nil
        day.timeUpPoint = nil

        let sortedDays = days.sorted { $0.index < $1.index }
        if let dayPosition = sortedDays.firstIndex(where: { $0.id == day.id }),
           dayPosition + 1 < sortedDays.count {
            let nextDay = sortedDays[dayPosition + 1]
            day.budget += nextDay.budget
            day.endAnchorID = nextDay.endAnchorID
            days.removeAll { $0.id == nextDay.id }
            for laterDay in days where laterDay.index > nextDay.index {
                laterDay.index -= 1
            }
        }

        reindexOrder()
        updatedAt = .now
    }

    /// Updates a day's budget in place. Does not re-segment automatically —
    /// call `recomputeTimeUpPoint(for:)` afterwards.
    func updateBudget(day: TripDay, budget: TimeInterval) {
        day.budget = budget
        updatedAt = .now
    }

    /// Inserts `anchor` immediately after the anchor with `afterAnchorID`
    /// (or at the end of the middle section if it isn't found), shifting
    /// every later anchor's `order` up by one to make room — the same
    /// technique `Trip.addPOI`'s projection-based insertion uses, for the
    /// same reason: SwiftData relationship arrays don't preserve insertion
    /// order, so a tied `order` would sort unpredictably.
    private func insertAnchor(_ anchor: Anchor, afterAnchorID: UUID) {
        guard let after = anchors.first(where: { $0.id == afterAnchorID }) else {
            let maxMiddleOrder = orderedMiddleAnchors.map(\.order).max() ?? 0
            anchor.order = maxMiddleOrder + 1
            anchor.trip = self
            anchors.append(anchor)
            reindexOrder()
            return
        }

        let insertionOrder = after.order + 1
        for existing in anchors where existing.order >= insertionOrder {
            existing.order += 1
        }
        anchor.order = insertionOrder
        anchor.trip = self
        anchors.append(anchor)
        reindexOrder()
    }
}
