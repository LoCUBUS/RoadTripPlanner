import Foundation
import Testing
@testable import RTPCore
@testable import RTPProviders

@Suite("StubMapProvider")
struct StubMapProviderTests {
    @Test("Query search returns scripted results")
    func querySearch() async throws {
        let provider = StubMapProvider()
        let expected = PlaceResult(id: "1", title: "Nuremberg Castle", coordinate: Coordinate(latitude: 49.4579, longitude: 11.0775))
        provider.searchResultsByQuery["castle"] = [expected]

        let results = try await provider.search(query: "castle", near: MapRegion(center: expected.coordinate, latitudeDelta: 0.1, longitudeDelta: 0.1))
        #expect(results == [expected])
    }

    @Test("Category search filters by category and radius")
    func categorySearch() async throws {
        let provider = StubMapProvider()
        let near = PlaceResult(id: "1", title: "Nearby Hotel", coordinate: Coordinate(latitude: 49.0, longitude: 11.0), category: .hotel)
        let far = PlaceResult(id: "2", title: "Far Museum", coordinate: Coordinate(latitude: 60.0, longitude: 30.0), category: .museum)
        provider.categorySearchResults = [near, far]

        let results = try await provider.search(categories: [.hotel, .motel], near: Coordinate(latitude: 49.0, longitude: 11.0), radiusMeters: 15_000)
        #expect(results == [near])
    }

    @Test("Directions returns a scripted route when available")
    func scriptedRoute() async throws {
        let provider = StubMapProvider()
        let from = Coordinate(latitude: 48.1351, longitude: 11.5820)
        let to = Coordinate(latitude: 49.4521, longitude: 11.0767)
        let scripted = RouteResult(distanceMeters: 170_000, expectedTravelTime: 6300, polyline: [from, to])
        provider.routesByKey[StubMapProvider.routeKey(from: from, to: to)] = scripted

        let result = try await provider.directions(from: from, to: to)
        #expect(result == scripted)
    }

    @Test("Directions falls back to a straight-line estimate when nothing is scripted")
    func fallbackRoute() async throws {
        let provider = StubMapProvider()
        let from = Coordinate(latitude: 0, longitude: 0)
        let to = Coordinate(latitude: 0, longitude: 1)

        let result = try await provider.directions(from: from, to: to)
        #expect(result.distanceMeters > 0)
        #expect(result.expectedTravelTime > 0)
        #expect(result.polyline == [from, to])
    }

    @Test("Reverse geocode without a scripted result throws noResults")
    func reverseGeocodeMissing() async {
        let provider = StubMapProvider()
        await #expect(throws: MapProviderError.noResults) {
            _ = try await provider.reverseGeocode(Coordinate())
        }
    }

    @Test("Nearest place returns the closest scripted candidate within radius")
    func nearestPlaceScripted() async throws {
        let provider = StubMapProvider()
        let clickPoint = Coordinate(latitude: 49.4579, longitude: 11.0775)
        let near = PlaceDetails(
            title: "Nuremberg Castle",
            coordinate: Coordinate(latitude: 49.4580, longitude: 11.0776),
            category: .sight,
            address: "Auf der Burg 13, 90403 N\u{00fc}rnberg",
            phoneNumber: "+49 911 2446590",
            url: URL(string: "https://www.kaiserburg-nuernberg.de")
        )
        let far = PlaceDetails(title: "Far Away Museum", coordinate: Coordinate(latitude: 60.0, longitude: 30.0))
        provider.nearbyPlaces = [far, near]

        let result = try await provider.nearestPlace(to: clickPoint, radiusMeters: 500)
        #expect(result == near)
    }

    @Test("Nearest place returns nil when nothing is within radius")
    func nearestPlaceOutOfRange() async throws {
        let provider = StubMapProvider()
        provider.nearbyPlaces = [PlaceDetails(title: "Far Away Museum", coordinate: Coordinate(latitude: 60.0, longitude: 30.0))]

        let result = try await provider.nearestPlace(to: Coordinate(), radiusMeters: 500)
        #expect(result == nil)
    }

    @Test("Nearest place can be scripted to throw, e.g. to simulate being offline")
    func nearestPlaceScriptedFailure() async {
        let provider = StubMapProvider()
        provider.nearestPlaceShouldThrow = true
        await #expect(throws: MapProviderError.requestFailed("stubbed failure")) {
            _ = try await provider.nearestPlace(to: Coordinate(), radiusMeters: 500)
        }
    }
}
