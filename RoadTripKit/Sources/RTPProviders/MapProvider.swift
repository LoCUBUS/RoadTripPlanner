import Foundation
import RTPCore

/// A rectangular map region, expressed without any MapKit dependency so
/// `RTPRouting` can depend on this protocol without importing MapKit
/// (docs/CONCEPT.md §2.3, principle P5).
public struct MapRegion: Sendable, Equatable {
    public var center: Coordinate
    public var latitudeDelta: Double
    public var longitudeDelta: Double

    public init(center: Coordinate, latitudeDelta: Double, longitudeDelta: Double) {
        self.center = center
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}

/// A single search/geocode result, provider-agnostic.
public struct PlaceResult: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var coordinate: Coordinate
    public var category: POICategory?
    public var mapItemIdentifier: String?

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        coordinate: Coordinate,
        category: POICategory? = nil,
        mapItemIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.category = category
        self.mapItemIdentifier = mapItemIdentifier
    }
}

/// Enriched information about a place tapped directly on the map (a
/// built-in Apple Maps point of interest). Provider-agnostic, kept separate
/// from `PlaceResult` since it's resolved from a map tap rather than a text
/// search (docs/CONCEPT.md §2.3, §2.5 "Selecting a map POI").
public struct PlaceDetails: Sendable, Equatable {
    public var title: String
    public var coordinate: Coordinate
    public var category: POICategory?
    public var address: String?
    public var phoneNumber: String?
    public var url: URL?
    public var mapItemIdentifier: String?

    public init(
        title: String,
        coordinate: Coordinate,
        category: POICategory? = nil,
        address: String? = nil,
        phoneNumber: String? = nil,
        url: URL? = nil,
        mapItemIdentifier: String? = nil
    ) {
        self.title = title
        self.coordinate = coordinate
        self.category = category
        self.address = address
        self.phoneNumber = phoneNumber
        self.url = url
        self.mapItemIdentifier = mapItemIdentifier
    }
}

/// One leg of a driving step, used only to distribute travel time along a
/// route by distance share (docs/CONCEPT.md §2.6) — MKRoute exposes no
/// per-step duration, only per-step distance.
public struct RouteStep: Sendable, Equatable {
    public var distanceMeters: Double
    public var endCoordinate: Coordinate

    public init(distanceMeters: Double, endCoordinate: Coordinate) {
        self.distanceMeters = distanceMeters
        self.endCoordinate = endCoordinate
    }
}

/// The result of a directions request between two points.
public struct RouteResult: Sendable, Equatable {
    public var distanceMeters: Double
    public var expectedTravelTime: TimeInterval
    public var polyline: [Coordinate]
    public var steps: [RouteStep]

    public init(
        distanceMeters: Double,
        expectedTravelTime: TimeInterval,
        polyline: [Coordinate],
        steps: [RouteStep] = []
    ) {
        self.distanceMeters = distanceMeters
        self.expectedTravelTime = expectedTravelTime
        self.polyline = polyline
        self.steps = steps
    }
}

public enum MapProviderError: Error, Sendable, Equatable {
    case noResults
    case requestFailed(String)
}

/// Abstraction over a map/search/directions backend. `AppleMapsProvider` is
/// the only v1 implementation; adding Google Maps/OSM later means a new
/// conformance here, not a change to `RTPRouting` or `RTPFeatures`
/// (docs/CONCEPT.md §2.3, principle P5).
public protocol MapProvider: Sendable {
    func search(query: String, near region: MapRegion) async throws -> [PlaceResult]
    func search(categories: [POICategory], near coordinate: Coordinate, radiusMeters: Double) async throws -> [PlaceResult]
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult
    func directions(from: Coordinate, to: Coordinate) async throws -> RouteResult
    func externalNavigationURL(for anchors: [Anchor]) -> URL
    /// Resolves a tapped built-in map feature (identified only by its title
    /// and approximate coordinate — macOS exposes no direct feature→map-item
    /// API, see docs/CONCEPT.md §2.9 risks) into richer place info by
    /// searching near that point and matching the closest result.
    func details(forFeatureTitled title: String, near coordinate: Coordinate) async throws -> PlaceDetails
}
