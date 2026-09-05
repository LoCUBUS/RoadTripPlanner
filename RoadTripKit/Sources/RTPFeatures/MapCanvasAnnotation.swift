import Foundation
import RTPCore

/// A pin rendered on `MapCanvasView`, decoupled from `RTPCore.Anchor` so the
/// map component can also render search results and provider POIs, not just
/// persisted anchors.
public struct MapCanvasAnnotation: Identifiable, Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case start
        case destination
        case waypoint
        case poi
        case lodging
        case searchResult
        case timeUp
        case photo
    }

    public var id: UUID
    public var coordinate: Coordinate
    public var title: String
    public var style: Style

    public init(id: UUID = UUID(), coordinate: Coordinate, title: String, style: Style) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
        self.style = style
    }
}

public extension MapCanvasAnnotation {
    init(anchor: Anchor) {
        let style: Style
        switch anchor.kind {
        case .start: style = .start
        case .destination: style = .destination
        case .waypoint: style = .waypoint
        case .poi: style = .poi
        case .lodging: style = .lodging
        }
        self.init(id: anchor.id, coordinate: anchor.coordinate, title: anchor.title, style: style)
    }
}

public extension MapCanvasAnnotation.Style {
    /// SF Symbol shown on the map pin for this annotation kind.
    var systemImage: String {
        switch self {
        case .start: "play.circle.fill"
        case .destination: "flag.fill"
        case .waypoint: "mappin.circle"
        case .poi: "star.circle.fill"
        case .lodging: "bed.double.circle.fill"
        case .searchResult: "magnifyingglass.circle.fill"
        case .timeUp: "clock.badge.exclamationmark.fill"
        case .photo: "photo.circle.fill"
        }
    }

    /// A VoiceOver-friendly description of this annotation kind, combined
    /// with the pin's title to form the full accessibility label
    /// (docs/CONCEPT.md §1.6 "Accessibility").
    var accessibilityDescription: String {
        switch self {
        case .start: "Start"
        case .destination: "Destination"
        case .waypoint: "Waypoint"
        case .poi: "Point of interest"
        case .lodging: "Lodging"
        case .searchResult: "Search result"
        case .timeUp: "Time-up point"
        case .photo: "Photo"
        }
    }
}
