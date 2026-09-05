import Foundation
import SwiftData

/// A single stop in the trip's ordered anchor chain: the start, a coarse
/// Phase-1 waypoint, a fixed Phase-2 POI, a Phase-3 lodging, or the
/// destination. See docs/CONCEPT.md §2.1–2.2.
///
/// All properties have defaults and the relationship to `Trip` is optional,
/// so the schema stays CloudKit-compatible even though CloudKit sync is off
/// in v1.
@Model
public final class Anchor {
    public var id: UUID = UUID()

    /// Explicit ordering key — never rely on array index, since SwiftData/
    /// CloudKit relationship arrays are not guaranteed to preserve order.
    public var order: Int = 0

    public var kindRawValue: Int = AnchorKind.waypoint.rawValue

    public var title: String = ""
    public var subtitle: String = ""

    public var latitude: Double = 0
    public var longitude: Double = 0

    /// `MKMapItem.Identifier.rawValue`, kept only as a resolution shortcut.
    /// The coordinate + title above remain the source of truth so a stale
    /// identifier never breaks the trip (see docs/CONCEPT.md §2.9 risks).
    public var mapItemIdentifier: String?

    public var categoryRawValue: String?

    /// How long the user plans to stay (Phase 2). Zero for non-POI anchors.
    public var dwellDuration: TimeInterval = 0

    /// Marks a Phase-2 `.poi` anchor as a candidate the user has already
    /// picked for an overnight stay (docs/CONCEPT.md §1.5 "Phase 2 — Points
    /// of interest"). Phase 3 automatically promotes it to `.lodging` (in
    /// place, keeping its position in the chain) if it falls within the
    /// trip's overnight tolerance of a day's time budget — see
    /// `Trip.bestOvernightCandidate(for:)`. Left `true` even after
    /// promotion, so `Trip.removeLodging(for:)` knows to revert the anchor
    /// back to `.poi` rather than deleting it outright.
    public var isOvernightCandidate: Bool = false

    // Phase 4 state
    public var isVisited: Bool = false
    public var comment: String?
    public var rating: Int?

    public var trip: Trip?

    public init(
        id: UUID = UUID(),
        order: Int = 0,
        kind: AnchorKind = .waypoint,
        title: String = "",
        subtitle: String = "",
        coordinate: Coordinate = Coordinate(),
        mapItemIdentifier: String? = nil,
        category: POICategory? = nil,
        dwellDuration: TimeInterval = 0,
        isOvernightCandidate: Bool = false
    ) {
        self.id = id
        self.order = order
        self.kindRawValue = kind.rawValue
        self.title = title
        self.subtitle = subtitle
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.mapItemIdentifier = mapItemIdentifier
        self.categoryRawValue = category?.rawValue
        self.dwellDuration = dwellDuration
        self.isOvernightCandidate = isOvernightCandidate
    }

    public var kind: AnchorKind {
        get { AnchorKind(rawValue: kindRawValue) ?? .waypoint }
        set { kindRawValue = newValue.rawValue }
    }

    public var coordinate: Coordinate {
        get { Coordinate(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }

    public var category: POICategory? {
        get { categoryRawValue.flatMap(POICategory.init(rawValue:)) }
        set { categoryRawValue = newValue?.rawValue }
    }
}
