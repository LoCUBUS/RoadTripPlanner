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

    /// When > 0, `directions(from:to:)` throws `.requestFailed` and
    /// decrements this counter instead of returning a route — lets tests
    /// script transient failures to exercise retry/backoff/fallback logic
    /// (e.g. in `RouteCoordinator`).
    public var directionsFailuresRemaining: Int = 0
    /// Total number of `directions(from:to:)` calls observed, so tests can
    /// assert on cache hits vs. re-requests.
    public private(set) var directionsCallCount: Int = 0
    /// When true, `search(categories:near:radius:)` throws `.requestFailed`,
    /// letting tests script a lodging-search failure (e.g. offline).
    public var categorySearchShouldThrow = false

    /// Scripted result for `details(forFeatureTitled:near:)`, keyed by the
    /// tapped feature's title.
    public var featureDetailsByTitle: [String: PlaceDetails] = [:]
    public var featureDetailsShouldThrow = false

    public init() {}

    public static func routeKey(from: Coordinate, to: Coordinate) -> String {
        "\(from.latitude),\(from.longitude)->\(to.latitude),\(to.longitude)"
    }

    public func search(query: String, near region: MapRegion) async throws -> [PlaceResult] {
        searchResultsByQuery[query] ?? []
    }

    public func search(categories: [POICategory], near coordinate: Coordinate, radiusMeters: Double) async throws -> [PlaceResult] {
        if categorySearchShouldThrow {
            throw MapProviderError.requestFailed("stubbed failure")
        }
        return categorySearchResults.filter { result in
            guard let category = result.category else { return false }
            return categories.contains(category) && coordinate.distance(to: result.coordinate) <= radiusMeters
        }
    }

    public func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        guard let reverseGeocodeResult else { throw MapProviderError.noResults }
        return reverseGeocodeResult
    }

    public func directions(from: Coordinate, to: Coordinate) async throws -> RouteResult {
        directionsCallCount += 1
        if directionsFailuresRemaining > 0 {
            directionsFailuresRemaining -= 1
            throw MapProviderError.requestFailed("stubbed failure")
        }
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

    public func details(forFeatureTitled title: String, near coordinate: Coordinate) async throws -> PlaceDetails {
        if featureDetailsShouldThrow {
            throw MapProviderError.requestFailed("stubbed failure")
        }
        guard let details = featureDetailsByTitle[title] else { throw MapProviderError.noResults }
        return details
    }
}
