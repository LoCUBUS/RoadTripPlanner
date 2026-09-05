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

    @Test("Feature details returns the scripted result for the tapped title")
    func featureDetailsScripted() async throws {
        let provider = StubMapProvider()
        let expected = PlaceDetails(
            title: "Nuremberg Castle",
            coordinate: Coordinate(latitude: 49.4579, longitude: 11.0775),
            category: .sight,
            address: "Auf der Burg 13, 90403 N\u{00fc}rnberg",
            phoneNumber: "+49 911 2446590",
            url: URL(string: "https://www.kaiserburg-nuernberg.de")
        )
        provider.featureDetailsByTitle["Nuremberg Castle"] = expected

        let result = try await provider.details(forFeatureTitled: "Nuremberg Castle", near: expected.coordinate)
        #expect(result == expected)
    }

    @Test("Feature details without a scripted result throws noResults")
    func featureDetailsMissing() async {
        let provider = StubMapProvider()
        await #expect(throws: MapProviderError.noResults) {
            _ = try await provider.details(forFeatureTitled: "Unknown Place", near: Coordinate())
        }
    }

    @Test("Feature details can be scripted to throw, e.g. to simulate being offline")
    func featureDetailsScriptedFailure() async {
        let provider = StubMapProvider()
        provider.featureDetailsShouldThrow = true
        await #expect(throws: MapProviderError.requestFailed("stubbed failure")) {
            _ = try await provider.details(forFeatureTitled: "Anything", near: Coordinate())
        }
    }
}
