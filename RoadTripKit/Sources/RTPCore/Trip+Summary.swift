import Foundation

/// Phase 4 summary helpers: which anchors fall into which day, and each
/// day's/trip's aggregate driving distance, driving time and dwell time
/// (docs/CONCEPT.md §1.5 "Phase 4 — Summary").
public extension Trip {
    /// The anchors visited during `day`, in route order, from just after
    /// its start anchor through its end anchor (inclusive). Empty if the
    /// day isn't closed yet, or its start/end anchors can't be found in the
    /// current chain (e.g. stale after an upstream edit).
    func anchors(in day: TripDay) -> [Anchor] {
        let chain = orderedAnchors
        guard let startAnchorID = day.startAnchorID,
              let endAnchorID = day.endAnchorID,
              let startIndex = chain.firstIndex(where: { $0.id == startAnchorID }),
              let endIndex = chain.firstIndex(where: { $0.id == endAnchorID }),
              endIndex > startIndex
        else { return [] }
        return Array(chain[(startIndex + 1)...endIndex])
    }

    /// Total driving time between `day`'s start and end anchor, summed from
    /// the cached legs along that stretch of the chain.
    func drivingTime(in day: TripDay) -> TimeInterval {
        legSlice(in: day).reduce(0) { $0 + $1.expectedTravelTime }
    }

    /// Total driving distance between `day`'s start and end anchor.
    func distanceMeters(in day: TripDay) -> Double {
        legSlice(in: day).reduce(0) { $0 + $1.distanceMeters }
    }

    /// Total POI dwell time consumed during `day`.
    func dwellTime(in day: TripDay) -> TimeInterval {
        anchors(in: day).reduce(0) { $0 + $1.dwellDuration }
    }

    /// The cached legs strictly between `day`'s start and end anchor, in
    /// route order (whichever of them have already been resolved).
    private func legSlice(in day: TripDay) -> [RouteLeg] {
        let chain = orderedAnchors
        guard let startAnchorID = day.startAnchorID,
              let endAnchorID = day.endAnchorID,
              let startIndex = chain.firstIndex(where: { $0.id == startAnchorID }),
              let endIndex = chain.firstIndex(where: { $0.id == endAnchorID }),
              endIndex > startIndex
        else { return [] }

        var result: [RouteLeg] = []
        for index in startIndex..<endIndex {
            if let leg = legs.first(where: { $0.fromAnchorID == chain[index].id && $0.toAnchorID == chain[index + 1].id }) {
                result.append(leg)
            }
        }
        return result
    }
}
