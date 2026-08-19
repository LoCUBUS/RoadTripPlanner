import Foundation
import Observation
import RTPCore
import RTPProviders

/// Drives Phase 4's summary screen: the day-by-day itinerary derived from
/// the already-planned anchor chain, per-stop Apple Maps hand-off, the
/// visited toggle, and the comment/rating fields (docs/CONCEPT.md §1.5
/// "Phase 4 — Summary", §2.7). Purely a read/annotate layer over data the
/// earlier phases already produced — it never mutates the anchor chain
/// itself.
@MainActor
@Observable
public final class SummaryViewModel {
    public let trip: Trip
    private let mapProvider: any MapProvider

    public init(trip: Trip, mapProvider: any MapProvider) {
        self.trip = trip
        self.mapProvider = mapProvider
    }

    public var days: [TripDay] {
        trip.days.sorted { $0.index < $1.index }
    }

    public func anchors(in day: TripDay) -> [Anchor] {
        trip.anchors(in: day)
    }

    public func drivingTime(in day: TripDay) -> TimeInterval {
        trip.drivingTime(in: day)
    }

    public func distanceMeters(in day: TripDay) -> Double {
        trip.distanceMeters(in: day)
    }

    public func dwellTime(in day: TripDay) -> TimeInterval {
        trip.dwellTime(in: day)
    }

    public func toggleVisited(_ anchor: Anchor) {
        anchor.isVisited.toggle()
        trip.updatedAt = .now
    }

    public func setComment(_ comment: String, for anchor: Anchor) {
        anchor.comment = comment.isEmpty ? nil : comment
        trip.updatedAt = .now
    }

    public func setRating(_ rating: Int?, for anchor: Anchor) {
        anchor.rating = rating
        trip.updatedAt = .now
    }

    /// A stable, shareable `maps://` link to navigate to a single stop.
    public func navigationURL(for anchor: Anchor) -> URL {
        mapProvider.externalNavigationURL(for: [anchor])
    }

    /// A multi-stop `maps://` hand-off for every anchor in `day`, in route
    /// order (docs/CONCEPT.md §2.7 "Apple Maps supports multi-item
    /// hand-off").
    public func navigationURL(for day: TripDay) -> URL? {
        let stops = anchors(in: day)
        guard !stops.isEmpty else { return nil }
        return mapProvider.externalNavigationURL(for: stops)
    }
}
