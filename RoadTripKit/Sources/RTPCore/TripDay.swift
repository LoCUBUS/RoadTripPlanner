import Foundation
import SwiftData

/// One day of a Phase-3 itinerary: a travel-time budget, the anchor it
/// starts/ends at, and the point on the route where the budget ran out
/// (before a lodging was chosen). See docs/CONCEPT.md §2.6.
@Model
public final class TripDay {
    public var id: UUID = UUID()

    /// 0-based day index within the trip.
    public var index: Int = 0

    /// Driving time + POI dwell time the user wants to budget for this day.
    public var budget: TimeInterval = 0

    public var plannedDate: Date?

    public var startAnchorID: UUID?

    /// The lodging anchor that closes this day, or the destination anchor
    /// on the final day. Nil while the day is still open.
    public var endAnchorID: UUID?

    /// Where the budget was exhausted, before a lodging was picked.
    /// Interpolated at MKRoute.step granularity — an approximation, shown
    /// in the UI as "≈" (docs/CONCEPT.md §2.6).
    public var timeUpLatitude: Double?
    public var timeUpLongitude: Double?

    public var searchRadiusMeters: Double = 15_000

    public var trip: Trip?

    public init(
        id: UUID = UUID(),
        index: Int = 0,
        budget: TimeInterval = 0,
        plannedDate: Date? = nil,
        startAnchorID: UUID? = nil,
        endAnchorID: UUID? = nil,
        timeUpPoint: Coordinate? = nil,
        searchRadiusMeters: Double = 15_000
    ) {
        self.id = id
        self.index = index
        self.budget = budget
        self.plannedDate = plannedDate
        self.startAnchorID = startAnchorID
        self.endAnchorID = endAnchorID
        self.timeUpLatitude = timeUpPoint?.latitude
        self.timeUpLongitude = timeUpPoint?.longitude
        self.searchRadiusMeters = searchRadiusMeters
    }

    public var timeUpPoint: Coordinate? {
        get {
            guard let timeUpLatitude, let timeUpLongitude else { return nil }
            return Coordinate(latitude: timeUpLatitude, longitude: timeUpLongitude)
        }
        set {
            timeUpLatitude = newValue?.latitude
            timeUpLongitude = newValue?.longitude
        }
    }

    /// A day is closed once it has an end anchor (a chosen lodging, or the
    /// destination on the final day).
    public var isClosed: Bool { endAnchorID != nil }
}
