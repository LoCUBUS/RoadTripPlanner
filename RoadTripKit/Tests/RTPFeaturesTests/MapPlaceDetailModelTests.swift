import Foundation
import Testing
import RTPCore
import RTPProviders
@testable import RTPFeatures

@MainActor
@Suite("MapPlaceDetailModel")
struct MapPlaceDetailModelTests {
    private let coordinate = Coordinate(latitude: 49.4579, longitude: 11.0775)

    @Test("A nearby place hit is used directly, without falling back to reverse geocoding")
    func nearestPlaceHitIsUsed() async {
        let provider = StubMapProvider()
        provider.nearbyPlaces = [PlaceDetails(title: "Nuremberg Castle", coordinate: coordinate, category: .sight)]
        provider.reverseGeocodeResult = PlaceResult(id: "geo", title: "Should not be used", coordinate: coordinate)
        let model = MapPlaceDetailModel(mapProvider: provider)

        model.load(MapPlaceSelection(coordinate: coordinate), radiusMeters: 200)
        await waitUntilNotLoading(model)

        #expect(model.details?.title == "Nuremberg Castle")
        #expect(model.errorMessage == nil)
    }

    @Test("With no nearby place, the reverse-geocoded address is used")
    func fallsBackToReverseGeocode() async {
        let provider = StubMapProvider()
        provider.reverseGeocodeResult = PlaceResult(id: "geo", title: "Hauptmarkt 1", coordinate: coordinate)
        let model = MapPlaceDetailModel(mapProvider: provider)

        model.load(MapPlaceSelection(coordinate: coordinate), radiusMeters: 200)
        await waitUntilNotLoading(model)

        #expect(model.details?.title == "Hauptmarkt 1")
        #expect(model.errorMessage == nil)
    }

    @Test("When both lookups fail, the card still resolves usable details from the bare selection")
    func resolvedDetailsFallsBackToSelectionWhenNothingLoaded() async {
        let provider = StubMapProvider()
        let model = MapPlaceDetailModel(mapProvider: provider)
        let selection = MapPlaceSelection(coordinate: coordinate, fallbackTitle: "Dropped Pin")

        model.load(selection, radiusMeters: 200)
        await waitUntilNotLoading(model)

        #expect(model.details == nil)
        #expect(model.errorMessage != nil)
        let resolved = model.resolvedDetails(for: selection)
        #expect(resolved.title == "Dropped Pin")
        #expect(resolved.coordinate == coordinate)
    }

    @Test("A thrown nearest-place lookup surfaces an error message instead of crashing")
    func nearestPlaceFailureSurfacesError() async {
        let provider = StubMapProvider()
        provider.nearestPlaceShouldThrow = true
        let model = MapPlaceDetailModel(mapProvider: provider)

        model.load(MapPlaceSelection(coordinate: coordinate), radiusMeters: 200)
        await waitUntilNotLoading(model)

        #expect(model.details == nil)
        #expect(model.errorMessage != nil)
    }

    @Test("Presenting already-known details (a search-result pin) shows them immediately, without a lookup")
    func presentShowsKnownDetailsImmediately() {
        let provider = StubMapProvider()
        let model = MapPlaceDetailModel(mapProvider: provider)
        let known = PlaceDetails(title: "Known Hotel", coordinate: coordinate, category: .hotel)

        model.present(known)

        #expect(model.isLoading == false)
        #expect(model.details?.title == "Known Hotel")
    }

    @Test("Dismissing clears details, error, and loading state")
    func dismissClearsState() {
        let provider = StubMapProvider()
        let model = MapPlaceDetailModel(mapProvider: provider)
        model.present(PlaceDetails(title: "Known Hotel", coordinate: coordinate))

        model.dismiss()

        #expect(model.details == nil)
        #expect(model.errorMessage == nil)
        #expect(model.isLoading == false)
    }

    /// `load` kicks off a detached `Task`; give it a few run-loop turns to
    /// finish before asserting on its result.
    private func waitUntilNotLoading(_ model: MapPlaceDetailModel, timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while model.isLoading, ContinuousClock.now < deadline {
            await Task.yield()
        }
    }
}
