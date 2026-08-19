import Foundation
import Testing
import RTPCore
import RTPProviders
import RTPRouting
@testable import RTPFeatures

@MainActor
@Suite("CorridorEditorViewModel")
struct CorridorEditorViewModelTests {
    private let munich = Coordinate(latitude: 48.1351, longitude: 11.5820)
    private let nuremberg = Coordinate(latitude: 49.4579, longitude: 11.0775)
    private let lisbon = Coordinate(latitude: 38.7223, longitude: -9.1393)

    private func fastConfiguration() -> RouteCoordinator.Configuration {
        RouteCoordinator.Configuration(requestDelayNanoseconds: 1_000, maxAttempts: 2, initialBackoffNanoseconds: 1_000)
    }

    @Test("Setting start/destination and adding a waypoint updates the ordered chain")
    func editsAnchorChain() {
        let trip = Trip(name: "Test")
        let provider = StubMapProvider()
        let viewModel = CorridorEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))

        viewModel.setStart(title: "Munich", coordinate: munich)
        viewModel.setDestination(title: "Lisbon", coordinate: lisbon)
        viewModel.addWaypoint(title: "Nuremberg", coordinate: nuremberg)

        #expect(viewModel.orderedAnchors.map(\.title) == ["Munich", "Nuremberg", "Lisbon"])
        #expect(viewModel.orderedMiddleAnchors.map(\.title) == ["Nuremberg"])
    }

    @Test("recalculateRoute persists legs and computes totals")
    func recalculateRoutePersistsLegs() async {
        let trip = Trip(name: "Test")
        let provider = StubMapProvider()
        provider.defaultRoute = RouteResult(
            distanceMeters: 170_000,
            expectedTravelTime: 6300,
            polyline: [munich, nuremberg]
        )
        let viewModel = CorridorEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))

        viewModel.setStart(title: "Munich", coordinate: munich)
        viewModel.setDestination(title: "Lisbon", coordinate: lisbon)

        await viewModel.recalculateRoute()

        #expect(trip.legs.count == 1)
        #expect(viewModel.totalDistanceMeters == 170_000)
        #expect(viewModel.totalTravelTime == 6300)
        #expect(!viewModel.hasStaleLegs)
        #expect(trip.legs[0].polylineCoordinates == [munich, nuremberg])
    }

    @Test("Removing an anchor prunes legs that touched it")
    func removingAnchorPrunesLegs() async {
        let trip = Trip(name: "Test")
        let provider = StubMapProvider()
        provider.defaultRoute = RouteResult(distanceMeters: 1000, expectedTravelTime: 60, polyline: [])
        let viewModel = CorridorEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))

        viewModel.setStart(title: "Munich", coordinate: munich)
        viewModel.addWaypoint(title: "Nuremberg", coordinate: nuremberg)
        viewModel.setDestination(title: "Lisbon", coordinate: lisbon)
        await viewModel.recalculateRoute()
        #expect(trip.legs.count == 2)

        let waypoint = viewModel.orderedMiddleAnchors[0]
        viewModel.removeAnchor(waypoint)

        #expect(trip.legs.isEmpty)
        #expect(viewModel.orderedAnchors.map(\.title) == ["Munich", "Lisbon"])
    }

    @Test("A chain shorter than two anchors clears any cached legs")
    func shortChainClearsLegs() async {
        let trip = Trip(name: "Test")
        let provider = StubMapProvider()
        let viewModel = CorridorEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))

        viewModel.setStart(title: "Munich", coordinate: munich)
        await viewModel.recalculateRoute()

        #expect(trip.legs.isEmpty)
    }

    @Test("A permanently failing leg is flagged via recalculationError and hasStaleLegs")
    func permanentFailureSetsError() async {
        let trip = Trip(name: "Test")
        let provider = StubMapProvider()
        provider.directionsFailuresRemaining = 10
        let viewModel = CorridorEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))

        viewModel.setStart(title: "Munich", coordinate: munich)
        viewModel.setDestination(title: "Lisbon", coordinate: lisbon)
        await viewModel.recalculateRoute()

        #expect(viewModel.hasStaleLegs)
        #expect(viewModel.recalculationError != nil)
    }

    @Test("moveMiddleAnchors reorders waypoints")
    func moveMiddleAnchorsReorders() {
        let trip = Trip(name: "Test")
        let provider = StubMapProvider()
        let viewModel = CorridorEditorViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()))

        viewModel.setStart(title: "Munich", coordinate: munich)
        viewModel.setDestination(title: "Lisbon", coordinate: lisbon)
        viewModel.addWaypoint(title: "Nuremberg", coordinate: nuremberg)
        viewModel.addWaypoint(title: "Berlin", coordinate: Coordinate(latitude: 52.5200, longitude: 13.4050))

        viewModel.moveMiddleAnchors(fromOffsets: [1], toOffset: 0)

        #expect(viewModel.orderedMiddleAnchors.map(\.title) == ["Berlin", "Nuremberg"])
    }
}
