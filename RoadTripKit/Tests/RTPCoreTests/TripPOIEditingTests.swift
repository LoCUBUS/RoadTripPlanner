import Foundation
import Testing
@testable import RTPCore

@Suite("Trip POI editing")
struct TripPOIEditingTests {
    private let munich = Coordinate(latitude: 48.1351, longitude: 11.5820)
    private let nuremberg = Coordinate(latitude: 49.4579, longitude: 11.0775)
    private let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)

    /// ~1.1 km north of Nuremberg — well inside the 10 km absorption radius.
    private var nearNuremberg: Coordinate {
        Coordinate(latitude: nuremberg.latitude + 0.01, longitude: nuremberg.longitude)
    }

    private func corridorTrip() -> Trip {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        trip.addWaypoint(title: "Nuremberg", coordinate: nuremberg)
        trip.setDestination(title: "Berlin", coordinate: berlin)
        return trip
    }

    @Test("A POI within 10 km absorbs the nearest waypoint and takes its position")
    func absorbsNearbyWaypoint() {
        let trip = corridorTrip()

        let result = trip.addPOI(title: "Nuremberg Castle", coordinate: nearNuremberg, category: .sight)

        #expect(result.absorbedWaypoint?.title == "Nuremberg")
        #expect(trip.orderedAnchors.map(\.title) == ["Munich", "Nuremberg Castle", "Berlin"])
        #expect(trip.orderedAnchors.filter { $0.kind == .waypoint }.isEmpty)
    }

    @Test("Start and destination are never absorbed even when a POI is added right on top of them")
    func neverAbsorbsStartOrDestination() {
        let trip = corridorTrip()

        let result = trip.addPOI(title: "Munich Museum", coordinate: munich, category: .museum)

        #expect(result.absorbedWaypoint == nil)
        #expect(trip.orderedAnchors.contains { $0.kind == .start && $0.title == "Munich" })
        #expect(trip.orderedAnchors.contains { $0.title == "Munich Museum" })
    }

    @Test("Only the nearest of several candidate waypoints is absorbed")
    func absorbsOnlyNearestCandidate() {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        trip.addWaypoint(title: "Nuremberg", coordinate: nuremberg)
        // A second waypoint even closer to the POI than Nuremberg is.
        let veryClose = Coordinate(latitude: nuremberg.latitude + 0.001, longitude: nuremberg.longitude)
        trip.addWaypoint(title: "Nuremberg Suburb", coordinate: veryClose)
        trip.setDestination(title: "Berlin", coordinate: berlin)

        let result = trip.addPOI(title: "Nuremberg Castle", coordinate: nearNuremberg, category: .sight)

        #expect(result.absorbedWaypoint?.title == "Nuremberg Suburb")
        #expect(trip.orderedAnchors.contains { $0.title == "Nuremberg" })
        #expect(!trip.orderedAnchors.contains { $0.title == "Nuremberg Suburb" })
    }

    @Test("A POI far from any waypoint is inserted, not absorbed")
    func insertsWithoutAbsorbing() {
        let trip = corridorTrip()
        let farAway = Coordinate(latitude: 50.9, longitude: 12.0) // between Nuremberg and Berlin, far from either

        let result = trip.addPOI(title: "Motorway Viewpoint", coordinate: farAway, category: .viewpoint)

        #expect(result.absorbedWaypoint == nil)
        #expect(trip.orderedAnchors.contains { $0.kind == .waypoint && $0.title == "Nuremberg" })
        // Inserted between Nuremberg and Berlin: the segment its coordinate projects closest to.
        #expect(trip.orderedAnchors.map(\.title) == ["Munich", "Nuremberg", "Motorway Viewpoint", "Berlin"])
    }

    @Test("A POI near the start of the route projects into the first leg")
    func insertsIntoFirstLeg() {
        let trip = corridorTrip()
        let nearStart = Coordinate(latitude: 48.6, longitude: 11.4) // between Munich and Nuremberg

        trip.addPOI(title: "Roadside Stop", coordinate: nearStart, category: .other)

        #expect(trip.orderedAnchors.map(\.title) == ["Munich", "Roadside Stop", "Nuremberg", "Berlin"])
    }

    @Test("Undoing an absorbing addition restores the waypoint and removes the POI")
    func undoRestoresAbsorbedWaypoint() {
        let trip = corridorTrip()
        let result = trip.addPOI(title: "Nuremberg Castle", coordinate: nearNuremberg, category: .sight)

        trip.undoPOIAddition(result)

        #expect(trip.orderedAnchors.map(\.title) == ["Munich", "Nuremberg", "Berlin"])
        #expect(!trip.orderedAnchors.contains { $0.title == "Nuremberg Castle" })
    }

    @Test("Undoing a non-absorbing addition simply removes the POI")
    func undoRemovesInsertedPOI() {
        let trip = corridorTrip()
        let farAway = Coordinate(latitude: 50.9, longitude: 12.0)
        let result = trip.addPOI(title: "Motorway Viewpoint", coordinate: farAway, category: .viewpoint)

        trip.undoPOIAddition(result)

        #expect(trip.orderedAnchors.map(\.title) == ["Munich", "Nuremberg", "Berlin"])
    }

    @Test("A POI defaults to a 45 minute dwell duration and carries its category")
    func poiCarriesDwellAndCategory() {
        let trip = corridorTrip()
        let result = trip.addPOI(title: "Nuremberg Castle", coordinate: nearNuremberg, category: .sight)

        #expect(result.poi.dwellDuration == 45 * 60)
        #expect(result.poi.category == .sight)
        #expect(result.poi.kind == .poi)
    }
}
