import Foundation
import Testing
import RTPCore
import RTPProviders
@testable import RTPFeatures

@MainActor
@Suite("SummaryViewModel")
struct SummaryViewModelTests {
    private let munich = Coordinate(latitude: 48.0, longitude: 11.0)
    private let castle = Coordinate(latitude: 48.5, longitude: 11.0)
    private let berlin = Coordinate(latitude: 50.0, longitude: 11.0)

    private func plannedTrip() -> (trip: Trip, poi: Anchor, day: TripDay) {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Munich", coordinate: munich)
        let poi = trip.addPOI(title: "Castle", coordinate: castle, dwellDuration: 30 * 60).poi
        let destination = trip.setDestination(title: "Berlin", coordinate: berlin)

        for (from, to) in [(start, poi), (poi, destination)] {
            let leg = RouteLeg(fromAnchorID: from.id, toAnchorID: to.id, distanceMeters: 100_000, expectedTravelTime: 3600, isStale: false)
            leg.trip = trip
            trip.legs.append(leg)
        }

        let day = TripDay(index: 0, budget: 3 * 3600, startAnchorID: start.id, endAnchorID: destination.id)
        day.trip = trip
        trip.days.append(day)

        return (trip, poi, day)
    }

    @Test("toggleVisited flips the anchor's visited flag")
    func toggleVisitedFlipsFlag() {
        let (trip, poi, _) = plannedTrip()
        let viewModel = SummaryViewModel(trip: trip, mapProvider: StubMapProvider())

        viewModel.toggleVisited(poi)
        #expect(poi.isVisited)
        viewModel.toggleVisited(poi)
        #expect(!poi.isVisited)
    }

    @Test("setComment stores a comment and clears it when set to empty")
    func setCommentStoresAndClears() {
        let (trip, poi, _) = plannedTrip()
        let viewModel = SummaryViewModel(trip: trip, mapProvider: StubMapProvider())

        viewModel.setComment("Beautiful view", for: poi)
        #expect(poi.comment == "Beautiful view")

        viewModel.setComment("", for: poi)
        #expect(poi.comment == nil)
    }

    @Test("setRating stores a 0-5 rating or clears it")
    func setRatingStoresOrClears() {
        let (trip, poi, _) = plannedTrip()
        let viewModel = SummaryViewModel(trip: trip, mapProvider: StubMapProvider())

        viewModel.setRating(4, for: poi)
        #expect(poi.rating == 4)

        viewModel.setRating(nil, for: poi)
        #expect(poi.rating == nil)
    }

    @Test("navigationURL(for: anchor) delegates to the map provider")
    func navigationURLForAnchorDelegatesToProvider() {
        let (trip, poi, _) = plannedTrip()
        let viewModel = SummaryViewModel(trip: trip, mapProvider: StubMapProvider())

        let url = viewModel.navigationURL(for: poi)

        #expect(url == URL(string: "maps://stub")!)
    }

    @Test("navigationURL(for: day) returns nil for a day with no contained stops")
    func navigationURLForEmptyDayIsNil() {
        let trip = Trip(name: "Test")
        let start = trip.setStart(title: "Munich", coordinate: munich)
        trip.setDestination(title: "Berlin", coordinate: berlin)
        let day = TripDay(index: 0, budget: 3600, startAnchorID: start.id)
        let viewModel = SummaryViewModel(trip: trip, mapProvider: StubMapProvider())

        #expect(viewModel.navigationURL(for: day) == nil)
    }

    @Test("days lists TripDay entries sorted by index")
    func daysListedInOrder() {
        let (trip, _, day1) = plannedTrip()
        let day2 = TripDay(index: 1, budget: 3600)
        day2.trip = trip
        trip.days.insert(day2, at: 0) // deliberately out of order in the array
        let viewModel = SummaryViewModel(trip: trip, mapProvider: StubMapProvider())

        #expect(viewModel.days.map(\.id) == [day1.id, day2.id])
    }
}
