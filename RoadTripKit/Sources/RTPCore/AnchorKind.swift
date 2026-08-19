import Foundation

/// The role an anchor plays in the trip's anchor chain
/// (see docs/CONCEPT.md §2.1 "the itinerary anchor chain").
public enum AnchorKind: Int, Codable, Sendable, CaseIterable {
    case start = 0
    case waypoint = 1
    case poi = 2
    case lodging = 3
    case destination = 4

    /// Only coarse Phase-1 waypoints can be absorbed by a nearby Phase-2 POI.
    /// Start and destination are permanent; POIs and lodging are already fixed.
    public var isAbsorbable: Bool { self == .waypoint }

    /// Whether this anchor kind can carry a Phase-2 dwell duration.
    public var contributesDwellTime: Bool { self == .poi }
}

/// Broad category used both to tag a POI and to drive the Phase 3 lodging
/// map filter. Kept as an open string-backed enum so `AppleMapsProvider` can
/// map additional MKPointOfInterestCategory values without a schema change.
public enum POICategory: String, Codable, Sendable, CaseIterable {
    case sight
    case viewpoint
    case nature
    case museum
    case restaurant
    case hotel
    case motel
    case campground
    case rvPark
    case other

    public var isLodging: Bool {
        switch self {
        case .hotel, .motel, .campground, .rvPark: true
        default: false
        }
    }

    public var displayName: String {
        switch self {
        case .sight: "Sight"
        case .viewpoint: "Viewpoint"
        case .nature: "Nature"
        case .museum: "Museum"
        case .restaurant: "Restaurant"
        case .hotel: "Hotel"
        case .motel: "Motel"
        case .campground: "Campground"
        case .rvPark: "RV Park"
        case .other: "Other"
        }
    }
}
