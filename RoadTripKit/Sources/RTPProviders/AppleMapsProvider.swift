import Foundation
import MapKit
import RTPCore

public extension Coordinate {
    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension MKPolyline {
    /// Extracts every coordinate of the polyline, since `MKPolyline` only
    /// exposes them through the C-style `getCoordinates(_:range:)` API.
    var coordinates: [Coordinate] {
        var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&points, range: NSRange(location: 0, length: pointCount))
        return points.map(Coordinate.init)
    }
}

/// The v1, and only, `MapProvider` implementation: MapKit backed by
/// `MKLocalSearch`, `MKDirections` and `CLGeocoder`, with `MKMapItem.openMaps`
/// as the hand-off mechanism for Phase 4 (docs/CONCEPT.md §2.3, §2.7).
public final class AppleMapsProvider: MapProvider, @unchecked Sendable {
    public init() {}

    public func search(query: String, near region: MapRegion) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: region.center.clLocationCoordinate2D,
            span: MKCoordinateSpan(latitudeDelta: region.latitudeDelta, longitudeDelta: region.longitudeDelta)
        )
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.map(Self.placeResult(from:))
        } catch {
            throw MapProviderError.requestFailed(error.localizedDescription)
        }
    }

    public func search(categories: [POICategory], near coordinate: Coordinate, radiusMeters: Double) async throws -> [PlaceResult] {
        let mkCategories = categories.compactMap(Self.mkCategory(for:))
        let request = MKLocalPointsOfInterestRequest(center: coordinate.clLocationCoordinate2D, radius: radiusMeters)
        if !mkCategories.isEmpty {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: mkCategories)
        }
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.map(Self.placeResult(from:))
        } catch {
            throw MapProviderError.requestFailed(error.localizedDescription)
        }
    }

    public func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw MapProviderError.requestFailed("Invalid location for reverse geocoding")
        }
        do {
            guard let mapItem = try await request.mapItems.first else { throw MapProviderError.noResults }
            return Self.placeResult(from: mapItem)
        } catch let error as MapProviderError {
            throw error
        } catch {
            throw MapProviderError.requestFailed(error.localizedDescription)
        }
    }

    public func directions(from: Coordinate, to: Coordinate) async throws -> RouteResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .automobile
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else { throw MapProviderError.noResults }
            var cumulativeDistance = 0.0
            let steps: [RouteStep] = route.steps.compactMap { step in
                guard step.distance > 0 else { return nil }
                cumulativeDistance += step.distance
                let endCoordinate = step.polyline.coordinates.last ?? Coordinate(step.polyline.coordinate)
                return RouteStep(distanceMeters: step.distance, endCoordinate: endCoordinate)
            }
            return RouteResult(
                distanceMeters: route.distance,
                expectedTravelTime: route.expectedTravelTime,
                polyline: route.polyline.coordinates,
                steps: steps
            )
        } catch let error as MapProviderError {
            throw error
        } catch {
            throw MapProviderError.requestFailed(error.localizedDescription)
        }
    }

    /// Resolves a tapped built-in map feature into richer place info by
    /// running an `MKLocalSearch` for `title` in a tight region around
    /// `coordinate` and matching the closest result — macOS exposes no
    /// direct feature→map-item API (`MKMapItemRequest`/`MKMapItemIdentifier`
    /// are unavailable on macOS; see docs/CONCEPT.md §2.9 risks).
    public func details(forFeatureTitled title: String, near coordinate: Coordinate) async throws -> PlaceDetails {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = title
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: coordinate.clLocationCoordinate2D,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let match = Self.closestMapItem(to: coordinate, in: response.mapItems) else {
                throw MapProviderError.noResults
            }
            return Self.placeDetails(from: match)
        } catch let error as MapProviderError {
            throw error
        } catch {
            throw MapProviderError.requestFailed(error.localizedDescription)
        }
    }

    private static func closestMapItem(to coordinate: Coordinate, in items: [MKMapItem]) -> MKMapItem? {
        items.min { lhs, rhs in
            Coordinate(lhs.location.coordinate).distance(to: coordinate) < Coordinate(rhs.location.coordinate).distance(to: coordinate)
        }
    }

    private static func placeDetails(from mapItem: MKMapItem) -> PlaceDetails {
        PlaceDetails(
            title: mapItem.name ?? "",
            coordinate: Coordinate(mapItem.location.coordinate),
            category: mapItem.pointOfInterestCategory.flatMap(poiCategory(for:)),
            address: mapItem.address?.fullAddress ?? mapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true),
            phoneNumber: mapItem.phoneNumber,
            url: mapItem.url,
            mapItemIdentifier: mapItem.identifier?.rawValue
        )
    }

    /// Builds a stable `maps://` hand-off URL. A single anchor opens driving
    /// directions to that point; multiple anchors chain via Apple Maps'
    /// `daddr=...+to:...` multi-stop syntax (docs/CONCEPT.md §2.7).
    public func externalNavigationURL(for anchors: [Anchor]) -> URL {
        var components = URLComponents()
        components.scheme = "maps"
        components.host = ""
        let stops = anchors.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" }
        let destination = stops.joined(separator: "+to:")
        components.queryItems = [
            URLQueryItem(name: "daddr", value: destination),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        return components.url ?? URL(string: "maps://")!
    }

    private static func placeResult(from mapItem: MKMapItem) -> PlaceResult {
        let identifier = mapItem.identifier?.rawValue
        return PlaceResult(
            id: identifier ?? UUID().uuidString,
            title: mapItem.name ?? "",
            subtitle: mapItem.addressRepresentations?.cityWithContext ?? "",
            coordinate: Coordinate(mapItem.location.coordinate),
            category: mapItem.pointOfInterestCategory.flatMap(poiCategory(for:)),
            mapItemIdentifier: identifier
        )
    }

    private static func mkCategory(for category: POICategory) -> MKPointOfInterestCategory? {
        switch category {
        case .sight: .landmark
        case .viewpoint: .nationalPark
        case .nature: .park
        case .museum: .museum
        case .restaurant: .restaurant
        case .hotel: .hotel
        case .motel: .hotel
        case .campground: .campground
        case .rvPark: .rvPark
        case .other: nil
        }
    }

    private static func poiCategory(for mkCategory: MKPointOfInterestCategory) -> POICategory? {
        switch mkCategory {
        case .hotel: .hotel
        case .campground: .campground
        case .rvPark: .rvPark
        case .museum: .museum
        case .restaurant: .restaurant
        case .park, .nationalPark: .nature
        case .landmark: .sight
        default: .other
        }
    }
}
