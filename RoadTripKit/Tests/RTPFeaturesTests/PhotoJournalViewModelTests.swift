import Foundation
import Testing
import RTPCore
import RTPProviders
@testable import RTPFeatures

@MainActor
@Suite("PhotoJournalViewModel")
struct PhotoJournalViewModelTests {
    private let munich = Coordinate(latitude: 48.0, longitude: 11.0)
    private let berlin = Coordinate(latitude: 50.0, longitude: 11.0)

    private func plannedTrip() -> Trip {
        let trip = Trip(name: "Test")
        _ = trip.setStart(title: "Munich", coordinate: munich)
        _ = trip.setDestination(title: "Berlin", coordinate: berlin)
        return trip
    }

    @Test("importPhotos resolves identifiers and adds a photo per result")
    func importPhotosAddsPhotos() async {
        let trip = plannedTrip()
        let resolver = StubPhotoAssetResolver()
        let captureDate = Date(timeIntervalSince1970: 1_700_000_000)
        resolver.metadataByIdentifier = [
            "asset-1": PhotoAssetMetadata(identifier: "asset-1", captureDate: captureDate, coordinate: Coordinate(latitude: 48.0001, longitude: 11.0001)),
            "asset-2": PhotoAssetMetadata(identifier: "asset-2", captureDate: captureDate, coordinate: nil),
        ]
        let viewModel = PhotoJournalViewModel(trip: trip, assetResolver: resolver)

        await viewModel.importPhotos(identifiers: ["asset-1", "asset-2"])

        #expect(viewModel.photos.count == 2)
        #expect(viewModel.pinnedPhotos.count == 1)
        #expect(viewModel.unpinnedPhotos.count == 1)
    }

    @Test("importPhotos skips identifiers already imported")
    func importPhotosSkipsDuplicates() async {
        let trip = plannedTrip()
        let resolver = StubPhotoAssetResolver()
        resolver.metadataByIdentifier = [
            "asset-1": PhotoAssetMetadata(identifier: "asset-1", captureDate: .now, coordinate: nil),
        ]
        let viewModel = PhotoJournalViewModel(trip: trip, assetResolver: resolver)

        await viewModel.importPhotos(identifiers: ["asset-1"])
        await viewModel.importPhotos(identifiers: ["asset-1"])

        #expect(viewModel.photos.count == 1)
    }

    @Test("importPhotos with an unresolvable identifier adds nothing")
    func importPhotosWithUnresolvableIdentifierAddsNothing() async {
        let trip = plannedTrip()
        let resolver = StubPhotoAssetResolver()
        let viewModel = PhotoJournalViewModel(trip: trip, assetResolver: resolver)

        await viewModel.importPhotos(identifiers: ["missing-asset"])

        #expect(viewModel.photos.isEmpty)
    }

    @Test("pinPhoto moves a photo from unpinned to pinned")
    func pinPhotoMovesPhotoToPinned() async {
        let trip = plannedTrip()
        let resolver = StubPhotoAssetResolver()
        resolver.metadataByIdentifier = [
            "asset-1": PhotoAssetMetadata(identifier: "asset-1", captureDate: .now, coordinate: nil),
        ]
        let viewModel = PhotoJournalViewModel(trip: trip, assetResolver: resolver)
        await viewModel.importPhotos(identifiers: ["asset-1"])
        let photo = try! #require(viewModel.unpinnedPhotos.first)

        viewModel.pinPhoto(photo, at: Coordinate(latitude: 48.0, longitude: 11.0))

        #expect(viewModel.unpinnedPhotos.isEmpty)
        #expect(viewModel.pinnedPhotos.count == 1)
    }

    @Test("removePhoto removes it from the trip")
    func removePhotoRemovesFromTrip() async {
        let trip = plannedTrip()
        let resolver = StubPhotoAssetResolver()
        resolver.metadataByIdentifier = [
            "asset-1": PhotoAssetMetadata(identifier: "asset-1", captureDate: .now, coordinate: nil),
        ]
        let viewModel = PhotoJournalViewModel(trip: trip, assetResolver: resolver)
        await viewModel.importPhotos(identifiers: ["asset-1"])
        let photo = try! #require(viewModel.photos.first)

        viewModel.removePhoto(photo)

        #expect(viewModel.photos.isEmpty)
    }

    @Test("setCaption updates the photo's caption")
    func setCaptionUpdatesCaption() async {
        let trip = plannedTrip()
        let resolver = StubPhotoAssetResolver()
        resolver.metadataByIdentifier = [
            "asset-1": PhotoAssetMetadata(identifier: "asset-1", captureDate: .now, coordinate: nil),
        ]
        let viewModel = PhotoJournalViewModel(trip: trip, assetResolver: resolver)
        await viewModel.importPhotos(identifiers: ["asset-1"])
        let photo = try! #require(viewModel.photos.first)

        viewModel.setCaption("Great view", for: photo)

        #expect(photo.caption == "Great view")
    }
}
