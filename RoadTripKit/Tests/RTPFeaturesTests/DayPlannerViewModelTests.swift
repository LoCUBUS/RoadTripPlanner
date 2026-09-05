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

    /// A Munich → Overnight candidate (2h away, flagged) → Berlin corridor
    /// with legs already resolved, for exercising Phase 2→3 auto-promotion.
    private func corridorTripWithOvernightCandidate(provider: StubMapProvider) async -> (trip: Trip, candidate: Anchor) {
        let trip = Trip(name: "Test")
        trip.setStart(title: "Munich", coordinate: munich)
        let candidateCoordinate = Coordinate(latitude: 49.0, longitude: 11.6)
        let candidate = trip.addPOI(title: "Lakeside Inn", coordinate: candidateCoordinate, category: .hotel, dwellDuration: 0, isOvernightCandidate: true).poi
        trip.setDestination(title: "Berlin", coordinate: berlin)
        provider.routesByKey[StubMapProvider.routeKey(from: munich, to: candidateCoordinate)] = RouteResult(distanceMeters: 200_000, expectedTravelTime: 2 * 3600, polyline: [munich, candidateCoordinate])
        provider.routesByKey[StubMapProvider.routeKey(from: candidateCoordinate, to: berlin)] = RouteResult(distanceMeters: 300_000, expectedTravelTime: 3 * 3600, polyline: [candidateCoordinate, berlin])
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())
        _ = await RTPFeaturesTestSupport.recalculate(trip: trip, using: coordinator)
        return (trip, candidate)
    }

    @Test("Starting a day auto-promotes a Phase-2 overnight candidate within tolerance and surfaces a notice")
    func startNextDayAutoPromotesOvernightCandidate() async {
        let provider = StubMapProvider()
        let (trip, candidate) = await corridorTripWithOvernightCandidate(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)

        // Candidate is reached at 2h; a 1.9h budget is within the default ±20% tolerance.
        let day = viewModel.startNextDay(budget: 1.9 * 3600)

        #expect(day?.isClosed == true)
        #expect(day?.endAnchorID == candidate.id)
        #expect(candidate.kind == .lodging)
        #expect(viewModel.lastAutoPromotedOvernight?.anchorTitle == "Lakeside Inn")
        #expect(viewModel.lastAutoPromotedOvernight?.dayID == day?.id)
    }

    @Test("Starting a day does not promote a candidate outside tolerance")
    func startNextDayDoesNotPromoteOutOfToleranceCandidate() async {
        let provider = StubMapProvider()
        let (trip, candidate) = await corridorTripWithOvernightCandidate(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)

        // Candidate reached at 2h; a 1h budget puts it far outside tolerance.
        let day = viewModel.startNextDay(budget: 1 * 3600)

        #expect(day?.isClosed == false)
        #expect(candidate.kind == .poi)
        #expect(viewModel.lastAutoPromotedOvernight == nil)
    }

    @Test("Undoing an auto-promoted overnight reverts the anchor and excludes it from re-matching")
    func undoAutoPromotedOvernightRevertsAndExcludes() async {
        let provider = StubMapProvider()
        let (trip, candidate) = await corridorTripWithOvernightCandidate(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)
        guard let day = viewModel.startNextDay(budget: 1.9 * 3600) else {
            Issue.record("Expected an open day")
            return
        }
        #expect(viewModel.lastAutoPromotedOvernight != nil)

        viewModel.undoAutoPromotedOvernight()

        #expect(viewModel.lastAutoPromotedOvernight == nil)
        #expect(candidate.kind == .poi)
        #expect(trip.anchors.contains { $0.id == candidate.id })
        #expect(day.isClosed == false) // re-segmenting finds no other candidate to promote
    }

    @Test("Dismissing the auto-promotion notice keeps the promotion but clears the banner")
    func dismissAutoPromotedOvernightNoticeKeepsPromotion() async {
        let provider = StubMapProvider()
        let (trip, candidate) = await corridorTripWithOvernightCandidate(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)
        guard let day = viewModel.startNextDay(budget: 1.9 * 3600) else {
            Issue.record("Expected an open day")
            return
        }

        viewModel.dismissAutoPromotedOvernightNotice()

        #expect(viewModel.lastAutoPromotedOvernight == nil)
        #expect(candidate.kind == .lodging)
        #expect(day.isClosed == true)
    }

    @Test("Widening the trip's overnight tolerance and refreshing promotes a previously out-of-range candidate")
    func refreshOvernightPromotionPicksUpWidenedTolerance() async {
        let provider = StubMapProvider()
        let (trip, candidate) = await corridorTripWithOvernightCandidate(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)
        // 1.4h budget vs. a 2h candidate is +43% over — outside the default ±20% tolerance.
        guard let day = viewModel.startNextDay(budget: 1.4 * 3600) else {
            Issue.record("Expected an open day")
            return
        }
        #expect(viewModel.lastAutoPromotedOvernight == nil)
        #expect(candidate.kind == .poi)

        trip.overnightToleranceFraction = 0.5
        viewModel.refreshOvernightPromotion()

        #expect(candidate.kind == .lodging)
        #expect(day.endAnchorID == candidate.id)
        #expect(viewModel.lastAutoPromotedOvernight?.anchorTitle == "Lakeside Inn")
    }

    @Test("Reopening a day clears the auto-promotion notice and rejection set")
    func reopeningDayClearsNoticeAndRejections() async {
        let provider = StubMapProvider()
        let (trip, candidate) = await corridorTripWithOvernightCandidate(provider: provider)
        let viewModel = DayPlannerViewModel(trip: trip, routeCoordinator: RouteCoordinator(provider: provider, configuration: fastConfiguration()), mapProvider: provider)
        guard let day = viewModel.startNextDay(budget: 1.9 * 3600) else {
            Issue.record("Expected an open day")
            return
        }
        viewModel.undoAutoPromotedOvernight() // rejects the candidate for this day

        viewModel.reopenDay(day)
        viewModel.refreshOvernightPromotion()

        // After reopening, the rejection set was cleared, so the same candidate can be re-promoted.
        #expect(candidate.kind == .lodging)
        #expect(viewModel.lastAutoPromotedOvernight?.anchorTitle == "Lakeside Inn")
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
