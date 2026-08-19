import Foundation
import Testing
@testable import RTPCore

@Suite("Trip day segmentation")
struct TripDaySegmentationTests {
    private let a = Coordinate(latitude: 48.0, longitude: 11.0)
    private let b = Coordinate(latitude: 49.0, longitude: 11.0)
    private let c = Coordinate(latitude: 50.0, longitude: 11.0)
    private let d = Coordinate(latitude: 51.0, longitude: 11.0)

    /// Builds Start(A) → POI(B, dwell) → Destination(D), with two 2h legs
    /// A→B and B→D (no intermediate C), each with 4 evenly spaced steps so
    /// step-level interpolation has something to chew on.
    private func tripWithOnePOI(dwell: TimeInterval) -> (trip: Trip, start: Anchor, poi: Anchor, destination: Anchor) {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Start", coordinate: a)
        let poi = trip.addPOI(title: "POI", coordinate: b, dwellDuration: dwell).poi
        let destination = trip.setDestination(title: "Destination", coordinate: d)

        addLeg(to: trip, from: start, to: poi, travelTime: 2 * 3600, distance: 200_000, stepCount: 4)
        addLeg(to: trip, from: poi, to: destination, travelTime: 2 * 3600, distance: 200_000, stepCount: 4)
        return (trip, start, poi, destination)
    }

    private func addLeg(to trip: Trip, from: Anchor, to: Anchor, travelTime: TimeInterval, distance: Double, stepCount: Int) {
        let leg = RouteLeg(fromAnchorID: from.id, toAnchorID: to.id, distanceMeters: distance, expectedTravelTime: travelTime, isStale: false)
        leg.polylineCoordinates = [from.coordinate, to.coordinate]
        let stepDistance = distance / Double(stepCount)
        leg.steps = (1...stepCount).map { index in
            let fraction = Double(index) / Double(stepCount)
            let lat = from.coordinate.latitude + (to.coordinate.latitude - from.coordinate.latitude) * fraction
            return RouteLegStep(distanceMeters: stepDistance, endCoordinate: Coordinate(latitude: lat, longitude: from.coordinate.longitude))
        }
        leg.trip = trip
        trip.legs.append(leg)
    }

    @Test("Budget exhausted mid-leg interpolates at step granularity")
    func reachesBudgetMidLegWithSteps() {
        let (trip, start, _, _) = tripWithOnePOI(dwell: 0)

        // 1 hour budget into a 2 hour leg → 50% of the way, i.e. step 2 of 4.
        let result = trip.segmentDay(startAnchorID: start.id, budget: 3600)

        guard case .reachedBudget(let point, let consumed) = result.outcome else {
            Issue.record("Expected .reachedBudget, got \(result.outcome)")
            return
        }
        #expect(consumed == 3600)
        #expect(abs(point.latitude - 48.5) < 0.01)
        #expect(result.containedAnchorIDs.isEmpty)
    }

    @Test("Budget smaller than the first leg still resolves without a contained stop")
    func budgetSmallerThanFirstLeg() {
        let (trip, start, _, _) = tripWithOnePOI(dwell: 0)

        let result = trip.segmentDay(startAnchorID: start.id, budget: 600) // 10 minutes into a 2h leg

        guard case .reachedBudget(_, let consumed) = result.outcome else {
            Issue.record("Expected .reachedBudget, got \(result.outcome)")
            return
        }
        #expect(consumed == 600)
        #expect(result.containedAnchorIDs.isEmpty)
    }

    @Test("Dwell time is added after the leg reaching the POI, contributing to the budget")
    func dwellTimeContributesToBudget() {
        let (trip, start, poi, _) = tripWithOnePOI(dwell: 30 * 60)

        // 2h drive + 30 min dwell = 2.5h consumed by the time we leave the POI.
        // Budget of 3h leaves 0.5h for the next 2h leg → 25% of the way.
        let result = trip.segmentDay(startAnchorID: start.id, budget: 3 * 3600)

        guard case .reachedBudget(_, let consumed) = result.outcome else {
            Issue.record("Expected .reachedBudget, got \(result.outcome)")
            return
        }
        #expect(consumed == 3 * 3600)
        #expect(result.containedAnchorIDs == [poi.id])
    }

    @Test("A POI's dwell time alone exceeding the budget raises dwellOverrun")
    func dwellOverrunIsRaised() {
        let (trip, start, poi, _) = tripWithOnePOI(dwell: 45 * 60)

        // Exactly the 2h drive as budget: arriving at the POI already
        // consumes the whole budget, so even the smallest extra dwell overruns.
        let result = trip.segmentDay(startAnchorID: start.id, budget: 2 * 3600)

        guard case .dwellOverrun(let anchorID, let title, let consumedBefore, let overshoot) = result.outcome else {
            Issue.record("Expected .dwellOverrun, got \(result.outcome)")
            return
        }
        #expect(anchorID == poi.id)
        #expect(title == "POI")
        #expect(consumedBefore == 2 * 3600)
        #expect(overshoot == 45 * 60)
        #expect(result.containedAnchorIDs.isEmpty)
    }

    @Test("Overshoot resolution (a) adds the full dwell and ends the day right after")
    func dwellOverrunOvershootResolution() {
        let (trip, start, poi, _) = tripWithOnePOI(dwell: 45 * 60)

        let result = trip.segmentDay(startAnchorID: start.id, budget: 2 * 3600, overshootAnchorIDs: [poi.id])

        // The POI is now contained; the day ends immediately (fraction ~0)
        // into the next leg since consumed already exceeds budget.
        #expect(result.containedAnchorIDs == [poi.id])
        guard case .reachedBudget(_, let consumed) = result.outcome else {
            Issue.record("Expected .reachedBudget, got \(result.outcome)")
            return
        }
        #expect(consumed == 2 * 3600 + 45 * 60)
    }

    @Test("Skip-dwell resolution (b) ends the day at the POI's own coordinate, excluding it")
    func dwellOverrunSkipResolution() {
        let (trip, start, poi, _) = tripWithOnePOI(dwell: 45 * 60)

        let result = trip.segmentDay(startAnchorID: start.id, budget: 2 * 3600, skipDwellAnchorIDs: [poi.id])

        guard case .reachedBudget(let point, let consumed) = result.outcome else {
            Issue.record("Expected .reachedBudget, got \(result.outcome)")
            return
        }
        #expect(consumed == 2 * 3600)
        #expect(point == poi.coordinate)
        #expect(result.containedAnchorIDs.isEmpty)
    }

    @Test("A day with enough budget for everything reaches the destination")
    func reachesDestinationWithNoBreak() {
        let (trip, start, poi, destination) = tripWithOnePOI(dwell: 30 * 60)

        let result = trip.segmentDay(startAnchorID: start.id, budget: 10 * 3600)

        guard case .reachedDestination(let consumed) = result.outcome else {
            Issue.record("Expected .reachedDestination, got \(result.outcome)")
            return
        }
        #expect(consumed == 4 * 3600 + 30 * 60) // 2h + 2h drive + 30 min dwell
        #expect(result.containedAnchorIDs == [poi.id, destination.id])
    }

    @Test("An unresolved leg is reported instead of guessed at")
    func legNotYetResolvedIsReported() {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Start", coordinate: a)
        _ = trip.setDestination(title: "Destination", coordinate: d)
        // No RouteLeg added at all — the leg from start to destination is unresolved.

        let result = trip.segmentDay(startAnchorID: start.id, budget: 3600)

        guard case .legNotYetResolved(let consumed) = result.outcome else {
            Issue.record("Expected .legNotYetResolved, got \(result.outcome)")
            return
        }
        #expect(consumed == 0)
    }

    @Test("Starting from the destination immediately reaches it with nothing consumed")
    func startingAtDestinationReachesItImmediately() {
        let (trip, _, _, destination) = tripWithOnePOI(dwell: 30 * 60)

        let result = trip.segmentDay(startAnchorID: destination.id, budget: 3600)

        guard case .reachedDestination(let consumed) = result.outcome else {
            Issue.record("Expected .reachedDestination, got \(result.outcome)")
            return
        }
        #expect(consumed == 0)
        #expect(result.containedAnchorIDs.isEmpty)
    }
}
