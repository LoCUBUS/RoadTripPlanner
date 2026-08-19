import Foundation
import SwiftData
import Testing
@testable import RTPCore

@Suite("Coordinate")
struct CoordinateTests {
    @Test("Distance between identical coordinates is zero")
    func zeroDistance() {
        let munich = Coordinate(latitude: 48.1351, longitude: 11.5820)
        #expect(munich.distance(to: munich) == 0)
    }

    @Test("Distance between Munich and Nuremberg is roughly 150 km")
    func knownDistance() {
        let munich = Coordinate(latitude: 48.1351, longitude: 11.5820)
        let nuremberg = Coordinate(latitude: 49.4521, longitude: 11.0767)
        let distance = munich.distance(to: nuremberg)
        #expect(distance > 140_000 && distance < 160_000)
    }
}

@Suite("RouteLeg")
struct RouteLegTests {
    @Test("polylineCoordinates round-trips through the encoded Data storage")
    func polylineRoundTrips() {
        let leg = RouteLeg(fromAnchorID: UUID(), toAnchorID: UUID())
        let coordinates = [
            Coordinate(latitude: 48.1351, longitude: 11.5820),
            Coordinate(latitude: 49.4579, longitude: 11.0775)
        ]
        leg.polylineCoordinates = coordinates
        #expect(leg.polylineCoordinates == coordinates)
        #expect(!leg.encodedPolyline.isEmpty)
    }

    @Test("An empty encodedPolyline decodes to an empty array")
    func emptyPolylineDecodesEmpty() {
        let leg = RouteLeg(fromAnchorID: UUID(), toAnchorID: UUID())
        #expect(leg.polylineCoordinates.isEmpty)
    }
}

@Suite("Trip model", .serialized)
struct TripModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try RTPSchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("A new trip defaults to Phase 1 with no anchors")
    func newTripDefaults() throws {
        let context = try makeContext()
        let trip = Trip(name: "Munich to Lisbon")
        context.insert(trip)

        #expect(trip.currentPhase == .corridor)
        #expect(trip.anchors.isEmpty)
        #expect(trip.phaseStatus.isEmpty)
    }

    @Test("Anchors persist with their order and are reachable from the trip")
    func anchorsPersist() throws {
        let context = try makeContext()
        let trip = Trip(name: "Munich to Lisbon")
        let start = Anchor(order: 0, kind: .start, title: "Munich", coordinate: Coordinate(latitude: 48.1351, longitude: 11.5820))
        let destination = Anchor(order: 1, kind: .destination, title: "Lisbon", coordinate: Coordinate(latitude: 38.7223, longitude: -9.1393))
        trip.anchors = [start, destination]
        context.insert(trip)
        try context.save()

        #expect(trip.anchors.count == 2)
        #expect(trip.anchors.first?.trip === trip)
        #expect(start.kind == .start)
        #expect(destination.kind == .destination)
    }

    @Test("markNeedsReview flags only later phases and preserves nothing to delete")
    func revisionTracking() throws {
        let context = try makeContext()
        let trip = Trip(name: "Munich to Lisbon")
        context.insert(trip)

        trip.markNeedsReview(after: .pointsOfInterest)

        #expect(trip.phaseStatus[.corridor] == nil)
        #expect(trip.phaseStatus[.pointsOfInterest] == nil)
        #expect(trip.phaseStatus[.overnights]?.needsReview == true)
        #expect(trip.phaseStatus[.summary]?.needsReview == true)
        #expect(trip.phaseStatus[.journal]?.needsReview == true)

        trip.markReviewed(.overnights)
        #expect(trip.phaseStatus[.overnights]?.needsReview == false)
        #expect(trip.phaseStatus[.summary]?.needsReview == true)
    }

    @Test("A POI anchor stores dwell duration and category")
    func poiAnchor() throws {
        let poi = Anchor(
            order: 1,
            kind: .poi,
            title: "Nuremberg Castle",
            coordinate: Coordinate(latitude: 49.4579, longitude: 11.0775),
            category: .sight,
            dwellDuration: 90 * 60
        )
        #expect(poi.kind.contributesDwellTime)
        #expect(poi.category == .sight)
        #expect(poi.dwellDuration == 5400)
        #expect(poi.kind.isAbsorbable == false)
    }

    @Test("Only waypoints are absorbable")
    func absorbability() {
        #expect(AnchorKind.waypoint.isAbsorbable)
        #expect(AnchorKind.start.isAbsorbable == false)
        #expect(AnchorKind.destination.isAbsorbable == false)
        #expect(AnchorKind.poi.isAbsorbable == false)
        #expect(AnchorKind.lodging.isAbsorbable == false)
    }

    @Test("TripDay closes only once it has an end anchor")
    func tripDayClosure() {
        let day = TripDay(index: 0, budget: 5 * 3600, startAnchorID: UUID())
        #expect(day.isClosed == false)

        day.endAnchorID = UUID()
        #expect(day.isClosed)
    }

    @Test("TripDay round-trips its time-up point")
    func tripDayTimeUpPoint() {
        let point = Coordinate(latitude: 49.0, longitude: 11.0)
        let day = TripDay(index: 0, budget: 3600, timeUpPoint: point)
        #expect(day.timeUpPoint == point)
    }

    @Test("TripPhoto round-trips its optional coordinate")
    func tripPhotoCoordinate() {
        let photo = TripPhoto(assetLocalIdentifier: "abc123", caption: "Sunset")
        #expect(photo.coordinate == nil)

        photo.coordinate = Coordinate(latitude: 1, longitude: 2)
        #expect(photo.coordinate == Coordinate(latitude: 1, longitude: 2))
    }

    @Test("Deleting a trip cascades to its anchors")
    func cascadeDelete() throws {
        let context = try makeContext()
        let trip = Trip(name: "To delete")
        let anchor = Anchor(order: 0, kind: .start, title: "Start")
        trip.anchors = [anchor]
        context.insert(trip)
        try context.save()

        context.delete(trip)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Anchor>())
        #expect(remaining.isEmpty)
    }
}
