import Foundation
import RTPCore

/// A deterministic, in-memory `MapProvider` used by unit tests (and
/// available to any test target that needs synthetic routing data without
/// touching MapKit/network — docs/CONCEPT.md §2.3, §2.8).
public final class StubMapProvider: MapProvider, @unchecked Sendable {
    public var searchResultsByQuery: [String: [PlaceResult]] = [:]
    public var categorySearchResults: [PlaceResult] = []
    public var reverseGeocodeResult: PlaceResult?
    /// Keyed by "fromLat,fromLng->toLat,toLng" so tests can script specific legs.
    public var routesByKey: [String: RouteResult] = [:]
    /// Used when no specific route was scripted for a from/to pair.
    public var defaultRoute: RouteResult?

    public init() {}

    public static func routeKey(from: Coordinate, to: Coordinate) -> String {
        "\(from.latitude),\(from.longitude)->\(to.latitude),\(to.longitude)"
    }

    public func search(query: String, near region: MapRegion) async throws -> [PlaceResult] {
        searchResultsByQuery[query] ?? []
    }

    public func search(categories: [POICategory], near coordinate: Coordinate, radiusMeters: Double) async throws -> [PlaceResult] {
        categorySearchResults.filter { result in
            guard let category = result.category else { return false }
            return categories.contains(category) && coordinate.distance(to: result.coordinate) <= radiusMeters
        }
    }

    public func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        guard let reverseGeocodeResult else { throw MapProviderError.noResults }
        return reverseGeocodeResult
    }

    public func directions(from: Coordinate, to: Coordinate) async throws -> RouteResult {
        if let scripted = routesByKey[Self.routeKey(from: from, to: to)] {
            return scripted
        }
        if let defaultRoute {
            return defaultRoute
        }
        // Fall back to a straight-line estimate at 80 km/h, mirroring the
        // stale-leg fallback `RouteCoordinator` uses when MKDirections fails.
        let distance = from.distance(to: to)
        return RouteResult(
            distanceMeters: distance,
            expectedTravelTime: distance / (80_000 / 3600),
            polyline: [from, to],
            steps: [RouteStep(distanceMeters: distance, endCoordinate: to)]
        )
    }

    public func externalNavigationURL(for anchors: [Anchor]) -> URL {
        URL(string: "maps://stub")!
    }
}
