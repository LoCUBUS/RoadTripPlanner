import Foundation

/// Why a Phase 3 day-segmentation walk stopped (docs/CONCEPT.md §2.6
/// "Phase 3 — Day segmentation algorithm").
public enum DaySegmentationOutcome: Equatable {
    /// The daily budget ran out partway through a leg. `timeUpPoint` is the
    /// interpolated point on that leg — approximate (±10%-ish on non-
    /// motorway legs), which the UI should label "≈". `consumedTime` is the
    /// exact travel+dwell time used to reach it.
    case reachedBudget(timeUpPoint: Coordinate, consumedTime: TimeInterval)
    /// The whole remaining chain was consumed within budget: this is the
    /// final day, ending at the trip's destination.
    case reachedDestination(consumedTime: TimeInterval)
    /// A POI's own dwell time, added to what's already consumed, would on
    /// its own exceed the budget. The caller/UI resolves this by choosing
    /// to overshoot, end the day before the POI, or shorten its dwell time.
    case dwellOverrun(anchorID: UUID, anchorTitle: String, consumedTimeBeforeAnchor: TimeInterval, overshoot: TimeInterval)
    /// The chain from `startAnchorID` includes a leg that hasn't been
    /// routed yet (`Trip.legs` has no cached entry) — the caller must
    /// recalculate the route (`RouteRecalculator`/`RouteCoordinator`)
    /// before day segmentation can proceed past this point.
    case legNotYetResolved(consumedTime: TimeInterval)
}

/// The result of walking the anchor chain forward from a day's start anchor
/// against its travel-time budget.
public struct DaySegmentationResult: Equatable {
    public var outcome: DaySegmentationOutcome
    /// IDs of every anchor consumed by this day, in route order, between
    /// the start anchor (exclusive) and wherever the day stopped.
    public var containedAnchorIDs: [UUID]

    public init(outcome: DaySegmentationOutcome, containedAnchorIDs: [UUID]) {
        self.outcome = outcome
        self.containedAnchorIDs = containedAnchorIDs
    }
}

/// Phase 3 day segmentation: walking the cached anchor chain forward from a
/// day's start against its travel-time budget (docs/CONCEPT.md §1.5 "Phase
/// 3 — Overnight stays", §2.6). Pure and synchronous — it only reads
/// already-resolved `legs`/`dwellDuration`, it never performs routing itself.
public extension Trip {
    /// Runs the day-segmentation algorithm forward from `startAnchorID`
    /// against `budget` (the sum of driving time and Phase-2 POI dwell time
    /// the user wants for this day).
    ///
    /// - Parameters:
    ///   - overshootAnchorIDs: POI anchors the user has already approved
    ///     overshooting the budget for (dwell-overrun resolution "(a)") —
    ///     their full dwell time is added even though it exceeds `budget`,
    ///     and the day then naturally ends immediately afterwards.
    ///   - skipDwellAnchorIDs: POI anchors the user chose to end the day
    ///     before, rather than dwell at today (resolution "(b)") — the day
    ///     stops at that anchor's own coordinate without including it.
    func segmentDay(
        startAnchorID: UUID,
        budget: TimeInterval,
        overshootAnchorIDs: Set<UUID> = [],
        skipDwellAnchorIDs: Set<UUID> = []
    ) -> DaySegmentationResult {
        let chain = orderedAnchors
        guard let startIndex = chain.firstIndex(where: { $0.id == startAnchorID }) else {
            return DaySegmentationResult(outcome: .reachedDestination(consumedTime: 0), containedAnchorIDs: [])
        }

        var consumed: TimeInterval = 0
        var containedAnchorIDs: [UUID] = []

        guard startIndex < chain.count - 1 else {
            // Already at the destination.
            return DaySegmentationResult(outcome: .reachedDestination(consumedTime: 0), containedAnchorIDs: [])
        }

        for index in startIndex..<(chain.count - 1) {
            let from = chain[index]
            let to = chain[index + 1]

            guard let leg = legs.first(where: { $0.fromAnchorID == from.id && $0.toAnchorID == to.id }) else {
                return DaySegmentationResult(outcome: .legNotYetResolved(consumedTime: consumed), containedAnchorIDs: containedAnchorIDs)
            }

            let travelTime = leg.expectedTravelTime
            if consumed + travelTime > budget {
                let remaining = Swift.max(0, budget - consumed)
                let timeUpPoint = Self.interpolateTimeUpPoint(leg: leg, remainingTime: remaining, totalTime: travelTime)
                return DaySegmentationResult(
                    outcome: .reachedBudget(timeUpPoint: timeUpPoint, consumedTime: consumed + remaining),
                    containedAnchorIDs: containedAnchorIDs
                )
            }

            consumed += travelTime

            if to.kind.contributesDwellTime, to.dwellDuration > 0 {
                if overshootAnchorIDs.contains(to.id) {
                    // Overshoot approved: add the full dwell even past budget.
                    consumed += to.dwellDuration
                } else {
                    let dwellCandidate = consumed + to.dwellDuration
                    if dwellCandidate > budget {
                        if skipDwellAnchorIDs.contains(to.id) {
                            return DaySegmentationResult(
                                outcome: .reachedBudget(timeUpPoint: to.coordinate, consumedTime: consumed),
                                containedAnchorIDs: containedAnchorIDs
                            )
                        }
                        return DaySegmentationResult(
                            outcome: .dwellOverrun(
                                anchorID: to.id,
                                anchorTitle: to.title,
                                consumedTimeBeforeAnchor: consumed,
                                overshoot: dwellCandidate - budget
                            ),
                            containedAnchorIDs: containedAnchorIDs
                        )
                    }
                    consumed = dwellCandidate
                }
            }

            containedAnchorIDs.append(to.id)
        }

        return DaySegmentationResult(outcome: .reachedDestination(consumedTime: consumed), containedAnchorIDs: containedAnchorIDs)
    }

    /// Interpolates the point where the daily budget runs out inside a leg.
    /// Uses step-level distance shares when steps are cached (accurate to a
    /// few minutes on motorway legs, since MKRoute exposes no per-step
    /// duration — only per-step distance), falling back to a plain
    /// distance-fraction index into the polyline otherwise.
    private static func interpolateTimeUpPoint(leg: RouteLeg, remainingTime: TimeInterval, totalTime: TimeInterval) -> Coordinate {
        guard totalTime > 0 else {
            return leg.polylineCoordinates.first ?? Coordinate()
        }
        let fraction = Swift.max(0, Swift.min(1, remainingTime / totalTime))

        let steps = leg.steps
        let totalStepDistance = steps.reduce(0) { $0 + $1.distanceMeters }
        if !steps.isEmpty, totalStepDistance > 0 {
            let targetDistance = totalStepDistance * fraction
            var accumulated: Double = 0
            for step in steps {
                accumulated += step.distanceMeters
                if accumulated >= targetDistance {
                    return step.endCoordinate
                }
            }
            return steps.last?.endCoordinate ?? Coordinate()
        }

        let polyline = leg.polylineCoordinates
        guard polyline.count >= 2 else { return polyline.first ?? Coordinate() }
        let index = Swift.min(polyline.count - 1, Int((Double(polyline.count - 1) * fraction).rounded()))
        return polyline[index]
    }
}
