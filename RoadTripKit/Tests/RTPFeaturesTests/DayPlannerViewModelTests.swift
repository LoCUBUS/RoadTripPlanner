import Foundation
import Testing
import RTPCore
import RTPProviders
import RTPRouting
@testable import RTPFeatures

@MainActor
@Suite("DayPlannerViewModel")
struct DayPlannerViewModelTests {
    private let munich = Coordinate(latitude: 48.1351, longitude: 11.5820)
    private let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)

    private func fastConfiguration() -> RouteCoordinator.Configuration {
        RouteCoordinator.Configuration(requestDelayNanoseconds: 1_000, maxAttempts: 2, initialBackoffNanoseconds: 1_000)
    }

    /// A 5-hour, 500 km corridor Munich → Berlin with legs already resolved.
    private func corridorTrip(provider: StubMapProvider) async -> Trip {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        trip.setDestination(title: "Berlin", coordinate: berlin)
        provider.defaultRoute = RouteResult(
            distanceMeters: 500_000,
            expectedTravelTime: 5 * 3600,
            polyline: [munich, berlin],
            steps: [RouteStep(distanceMeters: 500_000, endCoordinate: berlin)]
        )
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())
        let outcome = await RTPFeaturesTestSupport.recalculate(trip: trip, using: coordinator)
        #expect(!outcome.hasStaleLegs)
        return trip
    }

    @Test("Starting the next day segments immediately against the existing legs")
    func startNextDaySegments() async {
        let provider = StubMapProvider()
        let trip = await corridorTrip(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)

        let day = viewModel.startNextDay(budget: 3 * 3600)

        #expect(day != nil)
        #expect(viewModel.openDay?.id == day?.id)
        guard case .reachedBudget = viewModel.lastSegmentation?.outcome else {
            Issue.record("Expected .reachedBudget, got \(String(describing: viewModel.lastSegmentation?.outcome))")
            return
        }
        #expect(day?.timeUpPoint != nil)
    }

    @Test("A day with enough budget to reach the destination auto-closes and disables starting another")
    func dayReachingDestinationAutoCloses() async {
        let provider = StubMapProvider()
        let trip = await corridorTrip(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)

        viewModel.startNextDay(budget: 10 * 3600)

        #expect(viewModel.openDay == nil)
        #expect(viewModel.closedDays.count == 1)
        #expect(viewModel.canStartNextDay == false)
    }

    @Test("closeDay inserts a lodging and closes the open day")
    func closeDayInsertsLodging() async {
        let provider = StubMapProvider()
        let trip = await corridorTrip(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)
        guard let day = viewModel.startNextDay(budget: 3 * 3600), let afterID = viewModel.lodgingInsertionAnchorID(for: day) else {
            Issue.record("Expected an open day with an insertion anchor")
            return
        }

        viewModel.closeDay(day, afterAnchorID: afterID, title: "Night 1 Inn", coordinate: Coordinate(latitude: 49.0, longitude: 11.6))

        #expect(day.isClosed)
        #expect(trip.orderedAnchors.contains { $0.title == "Night 1 Inn" })
    }

    @Test("Lodging search filters by category and radius through the stub provider")
    func lodgingSearchFiltersByCategoryAndRadius() async {
        let provider = StubMapProvider()
        let trip = await corridorTrip(provider: provider)
        let nearPoint = Coordinate(latitude: 49.0, longitude: 11.6)
        provider.categorySearchResults = [
            PlaceResult(id: "1", title: "Hotel Nearby", coordinate: Coordinate(latitude: 49.01, longitude: 11.6), category: .hotel),
            PlaceResult(id: "2", title: "Restaurant Nearby", coordinate: Coordinate(latitude: 49.01, longitude: 11.6), category: .restaurant),
            PlaceResult(id: "3", title: "Hotel Far Away", coordinate: Coordinate(latitude: 60.0, longitude: 11.6), category: .hotel)
        ]
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)

        await viewModel.searchLodging(near: nearPoint, radiusMeters: 15_000)

        #expect(viewModel.lodgingResults.map(\.title) == ["Hotel Nearby"])
        #expect(viewModel.hasSearchedLodging)
        #expect(viewModel.lodgingSearchError == nil)
    }

    @Test("A failing lodging search surfaces an error message instead of silently returning nothing")
    func lodgingSearchFailureSurfacesError() async {
        let provider = StubMapProvider()
        let trip = await corridorTrip(provider: provider)
        provider.categorySearchShouldThrow = true
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)

        await viewModel.searchLodging(near: Coordinate(latitude: 49.0, longitude: 11.6), radiusMeters: 15_000)

        #expect(viewModel.lodgingResults.isEmpty)
        #expect(viewModel.lodgingSearchError != nil)
        #expect(viewModel.hasSearchedLodging)
    }

    @Test("Dwell overrun overshoot resolution re-segments past the overrun anchor")
    func dwellOverrunOvershootResolvesSegmentation() async {
        let provider = StubMapProvider()
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Munich", coordinate: munich)
        let poi = trip.addPOI(title: "Museum", coordinate: Coordinate(latitude: 49.0, longitude: 11.6), dwellDuration: 45 * 60).poi
        trip.setDestination(title: "Berlin", coordinate: berlin)
        provider.routesByKey[StubMapProvider.routeKey(from: munich, to: poi.coordinate)] = RouteResult(distanceMeters: 100_000, expectedTravelTime: 2 * 3600, polyline: [munich, poi.coordinate])
        provider.routesByKey[StubMapProvider.routeKey(from: poi.coordinate, to: berlin)] = RouteResult(distanceMeters: 100_000, expectedTravelTime: 2 * 3600, polyline: [poi.coordinate, berlin])
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())
        _ = await RTPFeaturesTestSupport.recalculate(trip: trip, using: coordinator)

        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: coordinator, mapProvider: provider)
        guard let day = viewModel.startNextDay(budget: 2 * 3600) else {
            Issue.record("Expected an open day")
            return
        }
        guard case .dwellOverrun(let anchorID, _, _, _) = viewModel.lastSegmentation?.outcome else {
            Issue.record("Expected .dwellOverrun, got \(String(describing: viewModel.lastSegmentation?.outcome))")
            return
        }

        viewModel.resolveOvershoot(day: day, anchorID: anchorID)

        #expect(viewModel.lastSegmentation?.containedAnchorIDs == [poi.id])
        _ = start
    }

    @Test("removeLodging merges the day with the following one and clears the lodging anchor")
    func removeLodgingMergesDays() async {
        let provider = StubMapProvider()
        let trip = await corridorTrip(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)
        guard let day1 = viewModel.startNextDay(budget: 2 * 3600), let afterID = viewModel.lodgingInsertionAnchorID(for: day1) else {
            Issue.record("Expected an open day")
            return
        }
        let lodgingCoordinate = Coordinate(latitude: 49.5, longitude: 12.0)
        provider.routesByKey[StubMapProvider.routeKey(from: munich, to: lodgingCoordinate)] = RouteResult(distanceMeters: 200_000, expectedTravelTime: 2 * 3600, polyline: [munich, lodgingCoordinate])
        provider.routesByKey[StubMapProvider.routeKey(from: lodgingCoordinate, to: berlin)] = RouteResult(distanceMeters: 300_000, expectedTravelTime: 3 * 3600, polyline: [lodgingCoordinate, berlin])
        viewModel.closeDay(day1, afterAnchorID: afterID, title: "Night 1", coordinate: lodgingCoordinate)
        await viewModel.recalculateRoute()

        let lodgingID = day1.endAnchorID
        viewModel.removeLodging(for: day1)
        await viewModel.recalculateRoute()

        #expect(!trip.anchors.contains { $0.id == lodgingID })
        #expect(trip.days.count == 1)
    }
}

/// Exposes `RouteRecalculator.recalculate` (internal to RTPFeatures) to this
/// test target via `@testable import`.
enum RTPFeaturesTestSupport {
    @MainActor
    static func recalculate(trip: Trip, using routeCoordinator: RouteCoordinator) async -> RouteRecalculator.Outcome {
        await RouteRecalculator.recalculate(trip: trip, using: routeCoordinator)
    }
}
