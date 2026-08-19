import Foundation
import SwiftData
import Testing
@testable import RTPCore

@Suite("Trip duplication", .serialized)
struct TripDuplicationTests {
    private func makeContext() throws -> ModelContext {
        let container = try RTPSchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    private func makeSampleTrip() -> Trip {
        let trip = Trip(name: "Munich to Lisbon", notes: "Summer trip", currentPhase: .overnights)

        let start = Anchor(order: 0, kind: .start, title: "Munich", coordinate: Coordinate(latitude: 48.1351, longitude: 11.5820))
        let poi = Anchor(order: 1, kind: .poi, title: "Nuremberg Castle", coordinate: Coordinate(latitude: 49.4579, longitude: 11.0775), category: .sight, dwellDuration: 5400)
        poi.isVisited = true
        poi.comment = "Beautiful view"
        poi.rating = 5
        let destination = Anchor(order: 2, kind: .destination, title: "Lisbon", coordinate: Coordinate(latitude: 38.7223, longitude: -9.1393))
        trip.anchors = [start, poi, destination]

        let leg = RouteLeg(fromAnchorID: start.id, toAnchorID: poi.id, distanceMeters: 170_000, expectedTravelTime: 6300, isStale: false)
        trip.legs = [leg]

        let day = TripDay(index: 0, budget: 5 * 3600, startAnchorID: start.id, endAnchorID: poi.id)
        trip.days = [day]

        trip.markNeedsReview(after: .pointsOfInterest)

        let photo = TripPhoto(assetLocalIdentifier: "asset-1", caption: "A photo")
        trip.photos = [photo]

        return trip
    }

    @Test("Duplicate copies the anchor chain but not visited/comment/rating")
    func duplicateCopiesAnchors() {
        let original = makeSampleTrip()
        let copy = original.duplicate()

        #expect(copy.name == "Munich to Lisbon Copy")
        #expect(copy.notes == original.notes)
        #expect(copy.currentPhase == .overnights)
        #expect(copy.anchors.count == original.anchors.count)

        let copiedPOI = copy.anchors.first { $0.kind == .poi }
        #expect(copiedPOI?.title == "Nuremberg Castle")
        #expect(copiedPOI?.dwellDuration == 5400)
        #expect(copiedPOI?.isVisited == false)
        #expect(copiedPOI?.comment == nil)
        #expect(copiedPOI?.rating == nil)
    }

    @Test("Duplicate assigns fresh anchor identities and remaps legs/days accordingly")
    func duplicateRemapsIdentities() {
        let original = makeSampleTrip()
        let copy = original.duplicate()

        let originalAnchorIDs = Set(original.anchors.map(\.id))
        let copiedAnchorIDs = Set(copy.anchors.map(\.id))
        #expect(originalAnchorIDs.isDisjoint(with: copiedAnchorIDs))

        #expect(copy.legs.count == 1)
        let copiedLeg = copy.legs[0]
        #expect(copiedAnchorIDs.contains(copiedLeg.fromAnchorID))
        #expect(copiedAnchorIDs.contains(copiedLeg.toAnchorID))
        #expect(copiedLeg.distanceMeters == 170_000)

        #expect(copy.days.count == 1)
        let copiedDay = copy.days[0]
        #expect(copiedAnchorIDs.contains(copiedDay.startAnchorID ?? UUID()))
        #expect(copiedAnchorIDs.contains(copiedDay.endAnchorID ?? UUID()))
    }

    @Test("Duplicate does not copy photos or phase review status")
    func duplicateExcludesPhotosAndReviewStatus() {
        let original = makeSampleTrip()
        #expect(original.photos.count == 1)
        #expect(original.phaseStatus.isEmpty == false)

        let copy = original.duplicate()
        #expect(copy.photos.isEmpty)
        #expect(copy.phaseStatus.isEmpty)
    }

    @Test("A duplicated trip can be inserted and saved independently of the original")
    func duplicatePersistsIndependently() throws {
        let context = try makeContext()
        let original = makeSampleTrip()
        context.insert(original)
        try context.save()

        let copy = original.duplicate(name: "New Adventure")
        context.insert(copy)
        try context.save()

        let allTrips = try context.fetch(FetchDescriptor<Trip>())
        #expect(allTrips.count == 2)
        #expect(allTrips.contains { $0.name == "New Adventure" })

        // Deleting the copy must not affect the original's anchors.
        context.delete(copy)
        try context.save()
        #expect(original.anchors.count == 3)
    }
}
