import Foundation
import Observation
import RTPCore
import RTPProviders

/// A place the user is considering acting on: either a raw map click
/// (only a coordinate is known — `fallbackTitle` is a placeholder shown
/// until/unless a lookup resolves a real name) or a pin whose details are
/// already known (a search/lodging result). `MapCanvasView` never exposes
/// MapKit's own `MapFeature` type directly — it isn't available on macOS at
/// all (docs/CONCEPT.md §2.9 risks) — so every map interaction funnels
/// through this provider-agnostic shape instead.
public struct MapPlaceSelection: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var coordinate: Coordinate
    public var fallbackTitle: String
    public var mapItemIdentifier: String?

    public init(coordinate: Coordinate, fallbackTitle: String = "Dropped Pin", mapItemIdentifier: String? = nil) {
        self.coordinate = coordinate
        self.fallbackTitle = fallbackTitle
        self.mapItemIdentifier = mapItemIdentifier
    }
}

/// Loads enriched `PlaceDetails` for a map click, showing a loading state
/// while the lookup runs and cancelling any in-flight lookup if a new place
/// is picked before it completes (docs/CONCEPT.md §1.5 "Phase 2 — Points of
/// interest", §2.5 "Selecting a map place").
///
/// Since macOS cannot resolve which built-in Apple Maps POI icon was
/// tapped (see `docs/CONCEPT.md` §2.9), a click is resolved with a
/// best-effort heuristic: search for the nearest real place within a
/// zoom-scaled radius, falling back to a reverse geocode (a plain address),
/// and finally to the bare coordinate — so the card always has *something*
/// to show and "Add..." always works.
@MainActor
@Observable
public final class MapPlaceDetailModel {
    private let mapProvider: any MapProvider
    private var loadTask: Task<Void, Never>?

    public private(set) var isLoading = false
    public private(set) var details: PlaceDetails?
    public private(set) var errorMessage: String?

    public init(mapProvider: any MapProvider) {
        self.mapProvider = mapProvider
    }

    /// Resolves a raw map click: nearest real place within `radiusMeters`,
    /// then a reverse geocode, then gives up silently (the bare coordinate
    /// via `resolvedDetails(for:)` still lets "Add..." work).
    public func load(_ selection: MapPlaceSelection, radiusMeters: Double) {
        loadTask?.cancel()
        details = nil
        errorMessage = nil
        isLoading = true
        loadTask = Task {
            defer { isLoading = false }
            do {
                if let nearest = try await mapProvider.nearestPlace(to: selection.coordinate, radiusMeters: radiusMeters) {
                    guard !Task.isCancelled else { return }
                    details = nearest
                    return
                }
                let reverseGeocoded = try await mapProvider.reverseGeocode(selection.coordinate)
                guard !Task.isCancelled else { return }
                details = PlaceDetails(
                    title: reverseGeocoded.title,
                    coordinate: reverseGeocoded.coordinate,
                    category: reverseGeocoded.category,
                    mapItemIdentifier: reverseGeocoded.mapItemIdentifier
                )
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Couldn't load details for this place."
            }
        }
    }

    /// Shows already-known details immediately — for a search/lodging
    /// result pin, where a lookup would just re-fetch what's already known.
    public func present(_ details: PlaceDetails) {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        errorMessage = nil
        self.details = details
    }

    public func dismiss() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        details = nil
        errorMessage = nil
    }

    /// The best available details to act on: the loaded/presented result, or
    /// a minimal fallback built from the selection itself if the lookup
    /// hasn't finished or failed — so "Add as POI"/"Add as Overnight" always
    /// work.
    public func resolvedDetails(for selection: MapPlaceSelection) -> PlaceDetails {
        details ?? PlaceDetails(title: selection.fallbackTitle, coordinate: selection.coordinate, mapItemIdentifier: selection.mapItemIdentifier)
    }
}
