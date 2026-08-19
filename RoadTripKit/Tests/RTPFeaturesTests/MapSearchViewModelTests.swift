import Foundation
import Testing
import RTPCore
import RTPProviders
@testable import RTPFeatures

@MainActor
@Suite("MapSearchViewModel")
struct MapSearchViewModelTests {
    private let region = MapRegion(center: Coordinate(latitude: 48.1351, longitude: 11.5820), latitudeDelta: 0.5, longitudeDelta: 0.5)

    @Test("An empty query clears results without calling the provider")
    func emptyQueryClears() async {
        let provider = StubMapProvider()
        provider.searchResultsByQuery["Castle"] = [
            PlaceResult(id: "1", title: "Nuremberg Castle", coordinate: Coordinate(latitude: 49.4579, longitude: 11.0775))
        ]
        let viewModel = MapSearchViewModel(provider: provider, debounceNanoseconds: 1_000)

        viewModel.updateQuery("Castle", region: region)
        await viewModel.waitForPendingSearch()
        #expect(viewModel.results.count == 1)

        viewModel.updateQuery("", region: region)
        #expect(viewModel.results.isEmpty)
        #expect(!viewModel.isSearching)
    }

    @Test("A query returns the provider's scripted results")
    func queryReturnsResults() async {
        let provider = StubMapProvider()
        provider.searchResultsByQuery["Castle"] = [
            PlaceResult(id: "1", title: "Nuremberg Castle", coordinate: Coordinate(latitude: 49.4579, longitude: 11.0775))
        ]
        let viewModel = MapSearchViewModel(provider: provider, debounceNanoseconds: 1_000)

        viewModel.updateQuery("Castle", region: region)
        await viewModel.waitForPendingSearch()

        #expect(viewModel.results.map(\.title) == ["Nuremberg Castle"])
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isSearching)
    }

    @Test("Rapid keystrokes cancel superseded searches, only the last query's results survive")
    func debounceCancelsSuperseded() async {
        let provider = StubMapProvider()
        provider.searchResultsByQuery["Ca"] = [PlaceResult(id: "partial", title: "Wrong result", coordinate: Coordinate())]
        provider.searchResultsByQuery["Castle"] = [PlaceResult(id: "1", title: "Nuremberg Castle", coordinate: Coordinate())]
        let viewModel = MapSearchViewModel(provider: provider, debounceNanoseconds: 30_000_000)

        viewModel.updateQuery("Ca", region: region)
        viewModel.updateQuery("Cas", region: region)
        viewModel.updateQuery("Castle", region: region)
        await viewModel.waitForPendingSearch()

        #expect(viewModel.results.map(\.title) == ["Nuremberg Castle"])
    }

    @Test("clear() resets query state")
    func clearResetsState() async {
        let provider = StubMapProvider()
        provider.searchResultsByQuery["Castle"] = [PlaceResult(id: "1", title: "Nuremberg Castle", coordinate: Coordinate())]
        let viewModel = MapSearchViewModel(provider: provider, debounceNanoseconds: 1_000)

        viewModel.updateQuery("Castle", region: region)
        await viewModel.waitForPendingSearch()
        #expect(!viewModel.results.isEmpty)

        viewModel.clear()
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isSearching)
    }
}
