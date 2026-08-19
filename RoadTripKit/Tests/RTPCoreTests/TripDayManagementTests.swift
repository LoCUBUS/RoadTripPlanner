import Foundation
import Testing
@testable import RTPCore

@Suite("Trip day management")
struct TripDayManagementTests {
    private let a = Coordinate(latitude: 48.0, longitude: 11.0)
    private let b = Coordinate(latitude: 49.0, longitude: 11.0)
    private let c = Coordinate(latitude: 50.0, longitude: 11.0)

    /// Start(A) —2h— POI(B, no dwell) —2h— Destination(C).
    private func tripWithOnePOI() -> (trip: Trip, start: Anchor, poi: Anchor, destination: Anchor) {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Start", coordinate: a)
        let poi = trip.addPOI(title: "POI", coordinate: b, dwellDuration: 0).poi
        let destination = trip.setDestination(title: "Destination", coordinate: c)

        for (from, to) in [(start, poi), (poi, destination)] {
            addLeg(to: trip, from: from, to: to, travelTime: 2 * 3600)
        }
        return (trip, start, poi, destination)
    }

    /// Adds a cached leg — standing in for what `RouteRecalculator` would
    /// compute after a structural anchor-chain edit like `closeDay`.
    private func addLeg(to trip: Trip, from: Anchor, to: Anchor, travelTime: TimeInterval) {
        let leg = RouteLeg(fromAnchorID: from.id, toAnchorID: to.id, distanceMeters: 200_000, expectedTravelTime: travelTime, isStale: false)
        leg.polylineCoordinates = [from.coordinate, to.coordinate]
        leg.trip = trip
        trip.legs.append(leg)
    }

    @Test("Opening the first day starts at the trip's start anchor")
    func opensFirstDayAtStart() {
        let (trip, start, _, _) = tripWithOnePOI()

        let day = trip.openNextDay(budget: 3600)

        #expect(day?.startAnchorID == start.id)
        #expect(day?.index == 0)
        #expect(trip.days.count == 1)
    }

    @Test("Opening a day that reaches the destination auto-closes it there, needing no lodging")
    func autoClosesAtDestinationWhenBudgetSuffices() {
        let (trip, _, _, destination) = tripWithOnePOI()

        let day = trip.openNextDay(budget: 10 * 3600)

        #expect(day?.isClosed == true)
        #expect(day?.endAnchorID == destination.id)
        #expect(day?.timeUpPoint == nil)
    }

    @Test("Opening a day that runs out of budget mid-route sets a time-up point and stays open")
    func staysOpenWithTimeUpPointWhenBudgetRunsOut() {
        let (trip, _, _, _) = tripWithOnePOI()

        let day = trip.openNextDay(budget: 3600) // 1h into a 2h leg

        #expect(day?.isClosed == false)
        #expect(day?.timeUpPoint != nil)
    }

    @Test("Closing a day inserts a lodging anchor after the given anchor and closes the day")
    func closingDayInsertsLodgingAndCloses() {
        let (trip, start, poi, destination) = tripWithOnePOI()
        guard let day = trip.openNextDay(budget: 3600) else {
            Issue.record("Expected day to open")
            return
        }

        let lodgingCoordinate = Coordinate(latitude: 48.5, longitude: 11.0)
        let lodging = trip.closeDay(day, afterAnchorID: start.id, lodgingTitle: "Night 1 Inn", coordinate: lodgingCoordinate)

        #expect(day.isClosed)
        #expect(day.endAnchorID == lodging.id)
        #expect(day.timeUpPoint == nil)
        #expect(lodging.kind == .lodging)
        #expect(trip.orderedAnchors.map(\.title) == ["Start", "Night 1 Inn", "POI", "Destination"])
        _ = poi
        _ = destination
    }

    @Test("The second day starts at the first day's lodging")
    func secondDayStartsAtFirstLodging() {
        let (trip, start, poi, _) = tripWithOnePOI()
        guard let day1 = trip.openNextDay(budget: 3600) else {
            Issue.record("Expected day to open")
            return
        }
        let lodging = trip.closeDay(day1, afterAnchorID: start.id, lodgingTitle: "Night 1", coordinate: Coordinate(latitude: 48.5, longitude: 11.0))
        // Simulate RouteRecalculator re-resolving the legs split by the new lodging anchor.
        addLeg(to: trip, from: lodging, to: poi, travelTime: 3600)

        let day2 = trip.openNextDay(budget: 3600)

        #expect(day2?.startAnchorID == lodging.id)
        #expect(day2?.index == 1)
    }

    @Test("Reopening a day clears its end anchor but leaves the lodging anchor in the chain")
    func reopeningDayClearsEndAnchorOnly() {
        let (trip, start, _, _) = tripWithOnePOI()
        guard let day = trip.openNextDay(budget: 3600) else {
            Issue.record("Expected day to open")
            return
        }
        let lodging = trip.closeDay(day, afterAnchorID: start.id, lodgingTitle: "Night 1", coordinate: Coordinate(latitude: 48.5, longitude: 11.0))

        trip.reopenDay(day)

        #expect(day.isClosed == false)
        #expect(trip.anchors.contains { $0.id == lodging.id })
    }

    @Test("Replacing a lodging updates its title and coordinate without changing day boundaries")
    func replacingLodgingUpdatesInPlace() {
        let (trip, start, _, _) = tripWithOnePOI()
        guard let day = trip.openNextDay(budget: 3600) else {
            Issue.record("Expected day to open")
            return
        }
        let lodging = trip.closeDay(day, afterAnchorID: start.id, lodgingTitle: "Night 1", coordinate: Coordinate(latitude: 48.5, longitude: 11.0))

        let newCoordinate = Coordinate(latitude: 48.6, longitude: 11.1)
        trip.replaceLodging(anchorID: lodging.id, title: "Better Inn", coordinate: newCoordinate)

        #expect(lodging.title == "Better Inn")
        #expect(lodging.coordinate == newCoordinate)
        #expect(day.endAnchorID == lodging.id)
    }

    @Test("Removing a lodging merges the day with the following one, combining budgets")
    func removingLodgingMergesWithFollowingDay() {
        let (trip, start, poi, destination) = tripWithOnePOI()
        guard let day1 = trip.openNextDay(budget: 3600) else {
            Issue.record("Expected day to open")
            return
        }
        let lodging = trip.closeDay(day1, afterAnchorID: start.id, lodgingTitle: "Night 1", coordinate: Coordinate(latitude: 48.5, longitude: 11.0))
        addLeg(to: trip, from: lodging, to: poi, travelTime: 3600)

        guard let day2 = trip.openNextDay(budget: 5 * 3600) else {
            Issue.record("Expected second day to open")
            return
        }
        // Day 2 reaches the destination given enough budget.
        #expect(day2.endAnchorID == destination.id)

        trip.removeLodging(for: day1)

        #expect(!trip.anchors.contains { $0.id == lodging.id })
        #expect(day1.budget == 3600 + 5 * 3600)
        #expect(day1.endAnchorID == destination.id) // inherited from the merged day2
        #expect(trip.days.count == 1)
    }

    @Test("Removing a lodging from the last day simply reopens it")
    func removingLodgingFromLastDayReopens() {
        let (trip, start, _, _) = tripWithOnePOI()
        guard let day = trip.openNextDay(budget: 3600) else {
            Issue.record("Expected day to open")
            return
        }
        trip.closeDay(day, afterAnchorID: start.id, lodgingTitle: "Night 1", coordinate: Coordinate(latitude: 48.5, longitude: 11.0))

        trip.removeLodging(for: day)

        #expect(day.isClosed == false)
        #expect(trip.days.count == 1)
    }

    @Test("Updating a day's budget changes it without auto-recomputing the time-up point")
    func updatingBudgetDoesNotAutoRecompute() {
        let (trip, _, _, _) = tripWithOnePOI()
        guard let day = trip.openNextDay(budget: 3600) else {
            Issue.record("Expected day to open")
            return
        }
        let originalTimeUp = day.timeUpPoint

        trip.updateBudget(day: day, budget: 7200)

        #expect(day.budget == 7200)
        #expect(day.timeUpPoint == originalTimeUp) // unchanged until recomputeTimeUpPoint is called
    }
}
