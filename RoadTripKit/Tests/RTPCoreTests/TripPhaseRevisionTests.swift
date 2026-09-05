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

    @Test("setStart on empty trip flags nothing (no downstream content yet)")
    func setStartFlagsLaterPhases() {
        let trip = Trip(name: "Test")

        _ = trip.setStart(title: "Munich", coordinate: munich)

        // New trip: no phases 2-5 have content yet, so nothing is flagged
        // per hasReviewableContent filtering.
        #expect(trip.phaseStatus[.corridor]?.needsReview != true)
        #expect(trip.phaseStatus[.pointsOfInterest]?.needsReview != true)
        #expect(trip.phaseStatus[.overnights]?.needsReview != true)
        #expect(trip.phaseStatus[.summary]?.needsReview != true)
        #expect(trip.phaseStatus[.journal]?.needsReview != true)
    }

    @Test("setStart with downstream content flags those phases")
    func setStartFlagsDownstreamPhases() {
        let trip = Trip(name: "Test")
        
        // Seed overnights and journal with content so they can go out of date
        let day = TripDay(index: 0, budget: 3600, startAnchorID: UUID())
        day.trip = trip
        trip.days.append(day)
        
        let photo = TripPhoto(assetLocalIdentifier: "test-asset", caption: "Test")
        photo.trip = trip
        trip.photos.append(photo)
        
        _ = trip.setStart(title: "Munich", coordinate: munich)

        // Now overnights and journal have content, so they should be flagged
        #expect(trip.phaseStatus[.overnights]?.needsReview == true)
        #expect(trip.phaseStatus[.journal]?.needsReview == true)
    }

    @Test("addWaypoint flags later phases only if they have content")
    func addWaypointFlagsAndCanBeReviewed() {
        let trip = Trip(name: "Test")
        _ = trip.setStart(title: "Munich", coordinate: munich)
        trip.markReviewed(.corridor)
        for phase in Phase.allCases {
            trip.markReviewed(phase)
        }

        // Seed pointsOfInterest with a POI so it can go out of date
        let poi = Anchor(
            order: 1,
            kind: .poi,
            title: "Museum",
            coordinate: castle,
            category: .sight,
            dwellDuration: 3600
        )
        poi.trip = trip
        trip.anchors.append(poi)

        _ = trip.addWaypoint(title: "Nuremberg", coordinate: nuremberg)

        // Now pointsOfInterest has content and should be flagged
        #expect(trip.phaseStatus[.pointsOfInterest]?.needsReview == true)
        // overnights/summary/journal are empty, so not flagged
        #expect(trip.phaseStatus[.overnights]?.needsReview != true)
        #expect(trip.phaseStatus[.summary]?.needsReview != true)
        #expect(trip.phaseStatus[.journal]?.needsReview != true)

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

        // Seed overnights with a day so it has content to be flagged
        let day = TripDay(index: 0, budget: 3600, startAnchorID: trip.orderedAnchors[0].id)
        day.trip = trip
        trip.days.append(day)

        _ = trip.addPOI(title: "Castle", coordinate: castle)

        // overnights now has content, so it gets flagged
        #expect(trip.phaseStatus[.overnights]?.needsReview == true)
        // summary/journal are empty, so not flagged
        #expect(trip.phaseStatus[.summary]?.needsReview != true)
        #expect(trip.phaseStatus[.journal]?.needsReview != true)
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

        // Seed summary with a visited anchor so it has content to be flagged
        if let startAnchor = trip.anchors.first(where: { $0.kind == .start }) {
            startAnchor.isVisited = true
        }

        trip.updateBudget(day: day, budget: 7200)

        // summary now has content and should be flagged
        #expect(trip.phaseStatus[.summary]?.needsReview == true)
        // journal is empty, so not flagged
        #expect(trip.phaseStatus[.journal]?.needsReview != true)
        // updateBudget precedes overnights itself, so overnights (phase 3)
        // is not flagged by its own edit.
        #expect(trip.phaseStatus[.overnights]?.needsReview != true)
    }
}
