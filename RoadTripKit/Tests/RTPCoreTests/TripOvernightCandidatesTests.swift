import Foundation
import Testing
@testable import RTPCore

@Suite("Trip overnight candidates")
struct TripOvernightCandidatesTests {
    private let a = Coordinate(latitude: 48.0, longitude: 11.0)
    private let b = Coordinate(latitude: 49.0, longitude: 11.0)
    private let c = Coordinate(latitude: 50.0, longitude: 11.0)
    private let d = Coordinate(latitude: 51.0, longitude: 11.0)

    /// Start(A) —2h— Candidate(B, overnight candidate, no dwell) —2h— Destination(C).
    private func tripWithOneCandidate() -> (trip: Trip, start: Anchor, candidate: Anchor, destination: Anchor) {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Start", coordinate: a)
        let candidate = trip.addPOI(title: "Lakeside Inn", coordinate: b, category: .hotel, dwellDuration: 0, isOvernightCandidate: true).poi
        let destination = trip.setDestination(title: "Destination", coordinate: c)

        for (from, to) in [(start, candidate), (candidate, destination)] {
            addLeg(to: trip, from: from, to: to, travelTime: 2 * 3600)
        }
        return (trip, start, candidate, destination)
    }

    private func addLeg(to trip: Trip, from: Anchor, to: Anchor, travelTime: TimeInterval) {
        let leg = RouteLeg(fromAnchorID: from.id, toAnchorID: to.id, distanceMeters: 200_000, expectedTravelTime: travelTime, isStale: false)
        leg.polylineCoordinates = [from.coordinate, to.coordinate]
        leg.trip = trip
        trip.legs.append(leg)
    }

    @Test("A candidate reached exactly at the budget is an exact-deviation match")
    func candidateAtExactBudgetMatches() {
        let (trip, start, candidate, _) = tripWithOneCandidate()

        let matches = trip.overnightCandidates(startAnchorID: start.id, budget: 2 * 3600, toleranceFraction: 0.2)

        #expect(matches.count == 1)
        #expect(matches[0].anchorID == candidate.id)
        #expect(matches[0].deviation == 0)
    }

    @Test("A candidate just within tolerance is matched by bestOvernightCandidate")
    func candidateWithinToleranceMatches() {
        let (trip, _, candidate, _) = tripWithOneCandidate()
        let day = trip.openNextDay(budget: 1.8 * 3600) // candidate at +2h is +11% over budget

        let match = trip.bestOvernightCandidate(for: day!, toleranceFraction: 0.2)

        #expect(match?.anchorID == candidate.id)
    }

    @Test("A candidate outside tolerance is not matched")
    func candidateOutsideToleranceDoesNotMatch() {
        let (trip, _, _, _) = tripWithOneCandidate()
        let day = trip.openNextDay(budget: 1.0 * 3600) // candidate at +2h is +100% over budget

        let match = trip.bestOvernightCandidate(for: day!, toleranceFraction: 0.2)

        #expect(match == nil)
    }

    @Test("Among several candidates, the one closest to the budget wins")
    func bestCandidateIsClosestToBudget() {
        let trip = Trip(name: "Test")
        // Set start and destination first so `addPOI`'s projection logic has
        // a real leg to insert each candidate into, landing them in the
        // intended chain order Start → Near → Far → Destination.
        let start = trip.setStart(title: "Start", coordinate: a)
        let destination = trip.setDestination(title: "Destination", coordinate: d)
        let near = trip.addPOI(title: "Near Inn", coordinate: b, category: .hotel, dwellDuration: 0, isOvernightCandidate: true).poi
        let far = trip.addPOI(title: "Far Inn", coordinate: c, category: .hotel, dwellDuration: 0, isOvernightCandidate: true).poi

        #expect(trip.orderedAnchors.map(\.id) == [start.id, near.id, far.id, destination.id])

        addLeg(to: trip, from: start, to: near, travelTime: 1.9 * 3600)
        addLeg(to: trip, from: near, to: far, travelTime: 0.3 * 3600) // far reached at 2.2h
        addLeg(to: trip, from: far, to: destination, travelTime: 2 * 3600)

        let day = trip.openNextDay(budget: 2 * 3600)
        let match = trip.bestOvernightCandidate(for: day!, toleranceFraction: 0.2)

        #expect(match?.anchorID == near.id) // |1.9-2| = 0.1h beats |2.2-2| = 0.2h
    }

    @Test("excludingAnchorIDs omits a candidate that would otherwise match")
    func excludingAnchorIDsOmitsCandidate() {
        let (trip, _, candidate, _) = tripWithOneCandidate()
        let day = trip.openNextDay(budget: 2 * 3600)

        let match = trip.bestOvernightCandidate(for: day!, excludingAnchorIDs: [candidate.id], toleranceFraction: 0.2)

        #expect(match == nil)
    }

    @Test("A non-candidate POI is never matched, even within budget")
    func nonCandidatePOIIsNeverMatched() {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Start", coordinate: a)
        let poi = trip.addPOI(title: "Museum", coordinate: b, dwellDuration: 0, isOvernightCandidate: false).poi
        let destination = trip.setDestination(title: "Destination", coordinate: c)
        addLeg(to: trip, from: start, to: poi, travelTime: 2 * 3600)
        addLeg(to: trip, from: poi, to: destination, travelTime: 2 * 3600)

        let day = trip.openNextDay(budget: 2 * 3600)
        let match = trip.bestOvernightCandidate(for: day!, toleranceFraction: 0.2)

        #expect(match == nil)
    }

    @Test("promoteOvernightCandidate converts the anchor to lodging in place and closes the day")
    func promoteConvertsAnchorInPlace() {
        let (trip, start, candidate, _) = tripWithOneCandidate()
        let day = trip.openNextDay(budget: 2 * 3600)!
        let originalOrder = candidate.order

        let promoted = trip.promoteOvernightCandidate(anchorID: candidate.id, for: day)

        #expect(promoted?.id == candidate.id)
        #expect(candidate.kind == .lodging)
        #expect(candidate.isOvernightCandidate) // flag stays set so removeLodging can revert it
        #expect(candidate.order == originalOrder) // kept its position, not re-inserted
        #expect(day.endAnchorID == candidate.id)
        #expect(day.timeUpPoint == nil)
        _ = start
    }

    @Test("promoteOvernightCandidate refuses a non-candidate or already-non-POI anchor")
    func promoteRefusesInvalidAnchor() {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Start", coordinate: a)
        let poi = trip.addPOI(title: "Museum", coordinate: b, dwellDuration: 0, isOvernightCandidate: false).poi
        let destination = trip.setDestination(title: "Destination", coordinate: c)
        let day = trip.openNextDay(budget: 3600)!

        let promoted = trip.promoteOvernightCandidate(anchorID: poi.id, for: day)

        #expect(promoted == nil)
        #expect(poi.kind == .poi)
        _ = start
        _ = destination
    }

    @Test("removeLodging reverts a promoted overnight candidate back to .poi instead of deleting it")
    func removeLodgingRevertsCandidateToPOI() {
        let (trip, start, candidate, destination) = tripWithOneCandidate()
        let day = trip.openNextDay(budget: 2 * 3600)!
        trip.promoteOvernightCandidate(anchorID: candidate.id, for: day)

        trip.removeLodging(for: day)

        #expect(trip.anchors.contains { $0.id == candidate.id })
        #expect(candidate.kind == .poi)
        #expect(candidate.isOvernightCandidate)
        #expect(day.endAnchorID == nil)
        _ = start
        _ = destination
    }

    @Test("removeLodging still deletes a plain, non-candidate lodging anchor")
    func removeLodgingDeletesPlainLodging() {
        let (trip, start, _, _) = tripWithOneCandidate()
        let day = trip.openNextDay(budget: 3600)! // candidate too far, stays open with a time-up point
        let lodging = trip.closeDay(day, afterAnchorID: start.id, lodgingTitle: "Manual Choice", coordinate: Coordinate(latitude: 48.5, longitude: 11.0))

        trip.removeLodging(for: day)

        #expect(!trip.anchors.contains { $0.id == lodging.id })
    }

    @Test("The trip's default overnight tolerance fraction is 20%")
    func defaultToleranceIsTwentyPercent() {
        let trip = Trip(name: "Test")
        #expect(trip.overnightToleranceFraction == 0.2)
        #expect(Trip.defaultOvernightToleranceFraction == 0.2)
    }

    @Test("A per-trip tolerance override is respected when no explicit fraction is passed")
    func perTripToleranceOverrideIsRespected() {
        let (trip, _, candidate, _) = tripWithOneCandidate()
        trip.overnightToleranceFraction = 0.5
        let day = trip.openNextDay(budget: 1.4 * 3600) // candidate at +2h is +43% over budget

        let match = trip.bestOvernightCandidate(for: day!)

        #expect(match?.anchorID == candidate.id)
    }
}
