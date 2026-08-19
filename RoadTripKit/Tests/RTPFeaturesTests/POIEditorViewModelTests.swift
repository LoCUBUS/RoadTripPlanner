import Foundation
import Testing
import RTPCore
import RTPProviders
import RTPRouting
@testable import RTPFeatures

@MainActor
@Suite("POIEditorViewModel")
struct POIEditorViewModelTests {
    private let munich = Coordinate(latitude: 48.1351, longitude: 11.5820)
    private let nuremberg = Coordinate(latitude: 49.4579, longitude: 11.0775)
    private let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)

    private func fastConfiguration() -> RouteCoordinator.Configuration {
        RouteCoordinator.Configuration(requestDelayNanoseconds: 1_000, maxAttempts: 2, initialBackoffNanoseconds: 1_000)
    }

    private func corridorTrip() -> Trip {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        trip.addWaypoint(title: "Nuremberg", coordinate: nuremberg)
        trip.setDestination(title: "Berlin", coordinate: berlin)
        return trip
    }

    @Test("Adding a POI near a waypoint absorbs it and surfaces an undoable notice")
    func addPOIAbsorbsWaypointAndReportsNotice() {
        let trip = corridorTrip()
        let provider = StubMapProvider()
        let viewModel = POIEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))
        let nearNuremberg = Coordinate(latitude: nuremberg.latitude + 0.01, longitude: nuremberg.longitude)

        viewModel.addPOI(title: "Nuremberg Castle", coordinate: nearNuremberg, category: .sight)

        #expect(viewModel.orderedAnchors.map(\.title) == ["Munich", "Nuremberg Castle", "Berlin"])
        #expect(viewModel.lastAbsorption?.poiTitle == "Nuremberg Castle")
        #expect(viewModel.lastAbsorption?.waypointTitle == "Nuremberg")
    }

    @Test("undoLastAddition restores an absorbed waypoint and removes the POI")
    func undoRestoresAbsorbedWaypoint() {
        let trip = corridorTrip()
        let provider = StubMapProvider()
        let viewModel = POIEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))
        let nearNuremberg = Coordinate(latitude: nuremberg.latitude + 0.01, longitude: nuremberg.longitude)
        viewModel.addPOI(title: "Nuremberg Castle", coordinate: nearNuremberg, category: .sight)

        viewModel.undoLastAddition()

        #expect(viewModel.orderedAnchors.map(\.title) == ["Munich", "Nuremberg", "Berlin"])
        #expect(viewModel.lastAbsorption == nil)
    }

    @Test("A POI far from any waypoint does not report an absorption notice")
    func addPOIWithoutAbsorptionReportsNoNotice() {
        let trip = corridorTrip()
        let provider = StubMapProvider()
        let viewModel = POIEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))
        let farAway = Coordinate(latitude: 50.9, longitude: 12.0)

        viewModel.addPOI(title: "Motorway Viewpoint", coordinate: farAway, category: .viewpoint)

        #expect(viewModel.lastAbsorption == nil)
        #expect(viewModel.orderedAnchors.map(\.title) == ["Munich", "Nuremberg", "Motorway Viewpoint", "Berlin"])
    }

    @Test("setDwellDuration and setCategory update the anchor in place")
    func editingDwellAndCategory() {
        let trip = corridorTrip()
        let provider = StubMapProvider()
        let viewModel = POIEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))
        let poi = viewModel.addPOI(title: "Castle", coordinate: Coordinate(latitude: 50.9, longitude: 12.0), category: .sight)

        viewModel.setDwellDuration(90 * 60, for: poi)
        viewModel.setCategory(.museum, for: poi)

        #expect(poi.dwellDuration == 90 * 60)
        #expect(poi.category == .museum)
    }

    @Test("removePOI removes the anchor from the chain")
    func removePOIRemovesAnchor() {
        let trip = corridorTrip()
        let provider = StubMapProvider()
        let viewModel = POIEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))
        let poi = viewModel.addPOI(title: "Castle", coordinate: Coordinate(latitude: 50.9, longitude: 12.0), category: .sight)

        viewModel.removePOI(poi)

        #expect(!viewModel.orderedAnchors.contains { $0.id == poi.id })
    }

    @Test("recalculateRoute persists legs after adding a POI")
    func recalculateRouteAfterAddingPOI() async {
        let trip = corridorTrip()
        let provider = StubMapProvider()
        provider.defaultRoute = RouteResult(distanceMeters: 1000, expectedTravelTime: 60, polyline: [])
        let viewModel = POIEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))
        viewModel.addPOI(title: "Castle", coordinate: Coordinate(latitude: 50.9, longitude: 12.0), category: .sight)

        await viewModel.recalculateRoute()

        #expect(trip.legs.count == 3)
        #expect(!viewModel.hasStaleLegs)
    }
}
