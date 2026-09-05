import Foundation

/// A Phase-2-selected overnight candidate anchor considered for automatic
/// promotion to a Phase 3 lodging, together with how much of the day's
/// budget would be consumed reaching it (docs/CONCEPT.md §2.6 "Overnight
/// candidates").
public struct OvernightCandidateMatch: Equatable, Sendable {
    public var anchorID: UUID
    /// Travel + dwell time consumed by the time this candidate is reached.
    public var consumedTime: TimeInterval
    /// `consumedTime - budget`. Negative means the candidate is reached
    /// before the budget is used up; positive means it overshoots (by up to
    /// the tolerance).
    public var deviation: TimeInterval

    public init(anchorID: UUID, consumedTime: TimeInterval, deviation: TimeInterval) {
        self.anchorID = anchorID
        self.consumedTime = consumedTime
        self.deviation = deviation
    }
}

/// Phase 2 → Phase 3 overnight candidate matching: a POI the user flagged
/// `isOvernightCandidate` while refining the route (Phase 2) is
/// automatically promoted to that day's lodging if it falls within the
/// trip's tolerance of the day's time budget, sparing the user a separate
/// lodging search in the common case where they already picked a hotel
/// along the way (docs/CONCEPT.md §1.5 "Phase 2 — Points of interest",
/// §2.6). Pure and synchronous, mirroring `segmentDay`'s forward walk over
/// the cached anchor chain.
public extension Trip {
    /// Walks the anchor chain forward from `startAnchorID`, collecting
    /// every `.poi` anchor flagged `isOvernightCandidate` together with the
    /// travel+dwell time needed to reach it, up to
    /// `budget * (1 + toleranceFraction)` — beyond that point no candidate
    /// could ever qualify, so the walk stops early. Stops at an unresolved
    /// leg (mirroring `segmentDay`'s `legNotYetResolved`) or the
    /// destination.
    func overnightCandidates(
        startAnchorID: UUID,
        budget: TimeInterval,
        toleranceFraction: Double
    ) -> [OvernightCandidateMatch] {
        let chain = orderedAnchors
        guard let startIndex = chain.firstIndex(where: { $0.id == startAnchorID }),
              startIndex < chain.count - 1
        else {
            return []
        }

        let ceiling = budget * (1 + Swift.max(0, toleranceFraction))
        var consumed: TimeInterval = 0
        var matches: [OvernightCandidateMatch] = []

        for index in startIndex..<(chain.count - 1) {
            let from = chain[index]
            let to = chain[index + 1]

            guard let leg = legs.first(where: { $0.fromAnchorID == from.id && $0.toAnchorID == to.id }) else {
                break
            }

            consumed += leg.expectedTravelTime
            if consumed > ceiling { break }

            if to.kind.contributesDwellTime, to.dwellDuration > 0 {
                consumed += to.dwellDuration
            }

            if to.kind == .poi, to.isOvernightCandidate {
                matches.append(OvernightCandidateMatch(anchorID: to.id, consumedTime: consumed, deviation: consumed - budget))
            }

            if consumed > ceiling || to.kind == .destination { break }
        }

        return matches
    }

    /// The best overnight candidate for `day` — whichever match's deviation
    /// from the budget has the smallest absolute value, filtered to matches
    /// within tolerance of the budget. `excludingAnchorIDs` lets a caller
    /// (e.g. after the user undoes an automatic promotion) omit a candidate
    /// that would otherwise immediately re-match.
    func bestOvernightCandidate(
        for day: TripDay,
        excludingAnchorIDs: Set<UUID> = [],
        toleranceFraction: Double? = nil
    ) -> OvernightCandidateMatch? {
        guard let startAnchorID = day.startAnchorID else { return nil }
        let fraction = toleranceFraction ?? overnightToleranceFraction
        let tolerance = day.budget * Swift.max(0, fraction)
        return overnightCandidates(startAnchorID: startAnchorID, budget: day.budget, toleranceFraction: fraction)
            .filter { !excludingAnchorIDs.contains($0.anchorID) && Swift.abs($0.deviation) <= tolerance }
            .min { Swift.abs($0.deviation) < Swift.abs($1.deviation) }
    }

    /// Promotes `anchorID` (must be a `.poi` anchor flagged
    /// `isOvernightCandidate`) to a `.lodging` anchor in place — keeping its
    /// existing position in the chain rather than re-inserting — and closes
    /// `day` there. `isOvernightCandidate` is left set so
    /// `removeLodging(for:)` can revert the anchor to `.poi` instead of
    /// deleting it. Used both for automatic promotion and for a user
    /// manually accepting a suggested candidate.
    @discardableResult
    func promoteOvernightCandidate(anchorID: UUID, for day: TripDay) -> Anchor? {
        guard let anchor = anchors.first(where: { $0.id == anchorID && $0.kind == .poi && $0.isOvernightCandidate }) else {
            return nil
        }
        anchor.kind = .lodging
        anchor.dwellDuration = 0
        day.endAnchorID = anchor.id
        day.timeUpPoint = nil
        updatedAt = .now
        markNeedsReview(after: .overnights)
        return anchor
    }
}
