import Foundation
import Testing
@testable import RTPCore

@Suite("Trip journal")
struct TripJournalTests {
    private let munich = Coordinate(latitude: 48.0, longitude: 11.0)
    private let castle = Coordinate(latitude: 48.5, longitude: 11.0)
    private let lodging = Coordinate(latitude: 49.0, longitude: 11.0)
    private let berlin = Coordinate(latitude: 50.0, longitude: 11.0)

    /// Start(Munich) → POI(Castle) → Lodging(Night 1) → Destination(Berlin),
    /// with a closed day spanning start...lodging.
    private func plannedTrip() -> (trip: Trip, poi: Anchor, lodgingAnchor: Anchor, day: TripDay) {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Munich", coordinate: munich)
        let poi = trip.addPOI(title: "Castle", coordinate: castle, dwellDuration: 30 * 60).poi
        let destination = trip.setDestination(title: "Berlin", coordinate: berlin)
        let lodgingAnchor = Anchor(kind: .lodging, title: "Night 1", coordinate: lodging)
        lodgingAnchor.trip = trip
        lodgingAnchor.order = poi.order + 1
        trip.anchors.append(lodgingAnchor)
        trip.reindexOrder()

        let day = TripDay(index: 0, budget: 3 * 3600, startAnchorID: start.id, endAnchorID: lodgingAnchor.id)
        day.trip = trip
        trip.days.append(day)

        _ = destination
        return (trip, poi, lodgingAnchor, day)
    }

    @Test("adding a photo with a coordinate associates it with the nearest anchor and its day")
    func addPhotoWithCoordinateAssociates() {
        let (trip, poi, _, day) = plannedTrip()

        // Very close to the castle POI.
        let near = Coordinate(latitude: 48.5001, longitude: 11.0001)
        let photo = trip.addPhoto(assetLocalIdentifier: "asset-1", captureDate: .now, coordinate: near)

        #expect(photo.associatedAnchorID == poi.id)
        #expect(photo.associatedDayIndex == day.index)
        #expect(trip.photos.contains { $0.id == photo.id })
    }

    @Test("adding a photo with no coordinate leaves both associations nil")
    func addPhotoWithoutCoordinateLeavesAssociationsNil() {
        let (trip, _, _, _) = plannedTrip()

        let photo = trip.addPhoto(assetLocalIdentifier: "asset-2", captureDate: .now, coordinate: nil)

        #expect(photo.associatedAnchorID == nil)
        #expect(photo.associatedDayIndex == nil)
        #expect(photo.coordinate == nil)
    }

    @Test("pinPhoto sets the coordinate and re-runs association")
    func pinPhotoReassociates() {
        let (trip, _, lodgingAnchor, day) = plannedTrip()
        let photo = trip.addPhoto(assetLocalIdentifier: "asset-3", captureDate: .now, coordinate: nil)
        #expect(photo.associatedAnchorID == nil)

        // Very close to the lodging anchor.
        trip.pinPhoto(photo, at: Coordinate(latitude: 49.0001, longitude: 11.0001))

        #expect(photo.coordinate != nil)
        #expect(photo.associatedAnchorID == lodgingAnchor.id)
        #expect(photo.associatedDayIndex == day.index)
    }

    @Test("removePhoto removes it from the trip")
    func removePhotoRemoves() {
        let (trip, _, _, _) = plannedTrip()
        let photo = trip.addPhoto(assetLocalIdentifier: "asset-4", captureDate: .now, coordinate: nil)
        #expect(trip.photos.count == 1)

        trip.removePhoto(photo)

        #expect(trip.photos.isEmpty)
    }

    @Test("setCaption updates the photo's caption in place")
    func setCaptionUpdates() {
        let (trip, _, _, _) = plannedTrip()
        let photo = trip.addPhoto(assetLocalIdentifier: "asset-5", captureDate: .now, coordinate: nil, caption: "")

        trip.setCaption("Beautiful sunset", for: photo)

        #expect(photo.caption == "Beautiful sunset")
    }
}
