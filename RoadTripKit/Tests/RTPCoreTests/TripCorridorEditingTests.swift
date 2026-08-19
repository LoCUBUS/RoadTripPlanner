import Foundation
import Testing
@testable import RTPCore

@Suite("Trip corridor editing")
struct TripCorridorEditingTests {
    private let munich = Coordinate(latitude: 48.1351, longitude: 11.5820)
    private let nuremberg = Coordinate(latitude: 49.4579, longitude: 11.0775)
    private let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)
    private let lisbon = Coordinate(latitude: 38.7223, longitude: -9.1393)

    @Test("setStart/setDestination create anchors with order 0 and last")
    func setStartAndDestination() {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        trip.setDestination(title: "Lisbon", coordinate: lisbon)

        #expect(trip.orderedAnchors.map(\.title) == ["Munich", "Lisbon"])
        #expect(trip.orderedAnchors.first?.order == 0)
        #expect(trip.orderedAnchors.last?.order == 1)
        #expect(trip.orderedAnchors.first?.kind == .start)
        #expect(trip.orderedAnchors.last?.kind == .destination)
    }

    @Test("setStart called twice updates the existing start anchor instead of creating a second one")
    func setStartIsIdempotent() {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        trip.setStart(title: "Munich Central", coordinate: munich)

        #expect(trip.anchors.filter { $0.kind == .start }.count == 1)
        #expect(trip.orderedAnchors.first?.title == "Munich Central")
    }

    @Test("Waypoints are appended before the destination, in insertion order")
    func addWaypointOrdering() {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        trip.setDestination(title: "Lisbon", coordinate: lisbon)
        trip.addWaypoint(title: "Nuremberg", coordinate: nuremberg)
        trip.addWaypoint(title: "Berlin", coordinate: berlin)

        let titles = trip.orderedAnchors.map(\.title)
        #expect(titles == ["Munich", "Nuremberg", "Berlin", "Lisbon"])
    }

    @Test("Waypoints can be appended before start/destination are set")
    func addWaypointWithoutStartOrDestination() {
        let trip = Trip(name: "Test")
        trip.addWaypoint(title: "Nuremberg", coordinate: nuremberg)
        #expect(trip.orderedAnchors.map(\.title) == ["Nuremberg"])
    }

    @Test("removeAnchor removes a waypoint and reindexes the remaining chain")
    func removeAnchorReindexes() {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        trip.setDestination(title: "Lisbon", coordinate: lisbon)
        let nurembergAnchor = trip.addWaypoint(title: "Nuremberg", coordinate: nuremberg)
        trip.addWaypoint(title: "Berlin", coordinate: berlin)

        trip.removeAnchor(id: nurembergAnchor.id)

        let titles = trip.orderedAnchors.map(\.title)
        #expect(titles == ["Munich", "Berlin", "Lisbon"])
        #expect(trip.orderedAnchors.map(\.order) == [0, 1, 2])
    }

    @Test("reorderMiddleAnchors moves a waypoint while keeping start first and destination last")
    func reorderMiddleAnchorsMovesWaypoint() {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        trip.setDestination(title: "Lisbon", coordinate: lisbon)
        trip.addWaypoint(title: "Nuremberg", coordinate: nuremberg)
        trip.addWaypoint(title: "Berlin", coordinate: berlin)

        // Move "Berlin" (index 1 within the middle section) before "Nuremberg" (index 0).
        trip.reorderMiddleAnchors(fromOffsets: [1], toOffset: 0)

        let titles = trip.orderedAnchors.map(\.title)
        #expect(titles == ["Munich", "Berlin", "Nuremberg", "Lisbon"])
        #expect(trip.orderedAnchors.first?.kind == .start)
        #expect(trip.orderedAnchors.last?.kind == .destination)
    }

    @Test("orderedAnchors does not depend on the underlying array's insertion order")
    func orderedAnchorsIgnoresArrayOrder() {
        let trip = Trip(name: "Test")
        let destination = Anchor(order: 2, kind: .destination, title: "Lisbon", coordinate: lisbon)
        let start = Anchor(order: 0, kind: .start, title: "Munich", coordinate: munich)
        let waypoint = Anchor(order: 1, kind: .waypoint, title: "Nuremberg", coordinate: nuremberg)
        // Deliberately append out of order.
        trip.anchors = [destination, waypoint, start]

        #expect(trip.orderedAnchors.map(\.title) == ["Munich", "Nuremberg", "Lisbon"])
    }
}
