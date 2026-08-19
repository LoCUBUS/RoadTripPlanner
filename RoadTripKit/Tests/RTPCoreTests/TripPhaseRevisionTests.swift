import Foundation
import Testing
@testable import RTPCore

/// Verifies that structural anchor/day mutations propagate `needsReview`
/// downstream per docs/CONCEPT.md §1.6 (principle P2): editing phase *n*
/// flags every phase *after* it, never deleting data. `TripModelTests`
/// already covers `markNeedsReview`/`markReviewed` in isolation — these
/// tests cover the call sites that trigger it.
@Suite("Phase revision propagation")
struct TripPhaseRevisionTests {
    private let munich = Coordinate(latitude: 48.0, longitude: 11.0)
    private let nuremberg = Coordinate(latitude: 48.5, longitude: 11.2)
    private let castle = Coordinate(latitude: 48.5001, longitude: 11.2001)
    private let berlin = Coordinate(latitude: 52.0, longitude: 13.0)

    @Test("setStart flags Phases 2-5 as needing review")
    func setStartFlagsLaterPhases() {
        let trip = Trip(name: "Test")

        _ = trip.setStart(title: "Munich", coordinate: munich)

        let flagged = Phase.allCases.filter { $0 != .corridor }
        for phase in flagged {
            #expect(trip.phaseStatus[phase]?.needsReview == true)
        }
        #expect(trip.phaseStatus[.corridor]?.needsReview != true)
    }

    @Test("addWaypoint flags later phases; markReviewed(.corridor) clears only that phase")
    func addWaypointFlagsAndCanBeReviewed() {
        let trip = Trip(name: "Test")
        _ = trip.setStart(title: "Munich", coordinate: munich)
        trip.markReviewed(.corridor)
        for phase in Phase.allCases {
            trip.markReviewed(phase)
        }

        _ = trip.addWaypoint(title: "Nuremberg", coordinate: nuremberg)

        #expect(trip.phaseStatus[.pointsOfInterest]?.needsReview == true)
        #expect(trip.phaseStatus[.overnights]?.needsReview == true)
        #expect(trip.phaseStatus[.summary]?.needsReview == true)
        #expect(trip.phaseStatus[.journal]?.needsReview == true)

        trip.markReviewed(.corridor)
        #expect(trip.phaseStatus[.corridor]?.needsReview == false)
        // Other phases are untouched by markReviewed(.corridor) — nothing deleted.
        #expect(trip.phaseStatus[.pointsOfInterest]?.needsReview == true)
    }

    @Test("addPOI flags Phases 3-5 as needing review")
    func addPOIFlagsOvernightsSummaryJournal() {
        let trip = Trip(name: "Test")
        _ = trip.setStart(title: "Munich", coordinate: munich)
        _ = trip.setDestination(title: "Berlin", coordinate: berlin)
        for phase in Phase.allCases {
            trip.markReviewed(phase)
        }

        _ = trip.addPOI(title: "Castle", coordinate: castle)

        #expect(trip.phaseStatus[.overnights]?.needsReview == true)
        #expect(trip.phaseStatus[.summary]?.needsReview == true)
        #expect(trip.phaseStatus[.journal]?.needsReview == true)
    }

    @Test("updateBudget flags Phases 4-5 as needing review")
    func updateBudgetFlagsSummaryAndJournal() {
        let trip = Trip(name: "Test")
        _ = trip.setStart(title: "Munich", coordinate: munich)
        _ = trip.setDestination(title: "Berlin", coordinate: berlin)
        let day = TripDay(index: 0, budget: 3600, startAnchorID: trip.orderedAnchors[0].id)
        day.trip = trip
        trip.days.append(day)
        for phase in Phase.allCases {
            trip.markReviewed(phase)
        }

        trip.updateBudget(day: day, budget: 7200)

        #expect(trip.phaseStatus[.summary]?.needsReview == true)
        #expect(trip.phaseStatus[.journal]?.needsReview == true)
        // updateBudget precedes overnights itself, so overnights (phase 3)
        // is not flagged by its own edit.
        #expect(trip.phaseStatus[.overnights]?.needsReview != true)
    }
}
