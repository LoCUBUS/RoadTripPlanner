import Foundation
import Testing
@testable import RTPCore

@Suite("Trip summary")
struct TripSummaryTests {
    private let munich = Coordinate(latitude: 48.0, longitude: 11.0)
    private let castle = Coordinate(latitude: 48.5, longitude: 11.0)
    private let lodging = Coordinate(latitude: 49.0, longitude: 11.0)
    private let berlin = Coordinate(latitude: 50.0, longitude: 11.0)

    /// Start(Munich) → POI(Castle, 30 min dwell) → Lodging(Night 1) → Destination(Berlin),
    /// with three 1h legs.
    private func plannedTrip() -> (trip: Trip, poi: Anchor, day: TripDay) {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Munich", coordinate: munich)
        let poi = trip.addPOI(title: "Castle", coordinate: castle, dwellDuration: 30 * 60).poi
        let destination = trip.setDestination(title: "Berlin", coordinate: berlin)
        let lodgingAnchor = Anchor(kind: .lodging, title: "Night 1", coordinate: lodging)
        lodgingAnchor.trip = trip
        lodgingAnchor.order = poi.order + 1
        trip.anchors.append(lodgingAnchor)
        trip.reindexOrder()

        for (from, to) in [(start, poi), (poi, lodgingAnchor), (lodgingAnchor, destination)] {
            let leg = RouteLeg(fromAnchorID: from.id, toAnchorID: to.id, distanceMeters: 100_000, expectedTravelTime: 3600, isStale: false)
            leg.trip = trip
            trip.legs.append(leg)
        }

        let day = TripDay(index: 0, budget: 3 * 3600, startAnchorID: start.id, endAnchorID: lodgingAnchor.id)
        day.trip = trip
        trip.days.append(day)

        return (trip, poi, day)
    }

    @Test("anchors(in:) returns the POI and lodging between a day's start and end")
    func anchorsInDayReturnsContainedStops() {
        let (trip, poi, day) = plannedTrip()

        let anchors = trip.anchors(in: day)

        #expect(anchors.map(\.title) == ["Castle", "Night 1"])
        #expect(anchors.first?.id == poi.id)
    }

    @Test("drivingTime and distance sum only the legs within the day")
    func drivingTimeAndDistanceSumWithinDay() {
        let (trip, _, day) = plannedTrip()

        #expect(trip.drivingTime(in: day) == 2 * 3600) // Munich→Castle, Castle→Night 1
        #expect(trip.distanceMeters(in: day) == 200_000)
    }

    @Test("dwellTime sums only POI dwell durations within the day")
    func dwellTimeSumsPOIsWithinDay() {
        let (trip, _, day) = plannedTrip()

        #expect(trip.dwellTime(in: day) == 30 * 60)
    }

    @Test("An open day (no end anchor) has no contained anchors")
    func openDayHasNoContainedAnchors() {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Munich", coordinate: munich)
        trip.setDestination(title: "Berlin", coordinate: berlin)
        let day = TripDay(index: 0, budget: 3600, startAnchorID: start.id)

        #expect(trip.anchors(in: day).isEmpty)
        #expect(trip.drivingTime(in: day) == 0)
    }
}
