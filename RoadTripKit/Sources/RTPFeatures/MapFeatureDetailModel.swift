import Foundation
import Observation
import RTPCore
import RTPProviders

/// A tapped built-in Apple Maps point of interest, identified only by its
/// title and approximate coordinate — `MapFeature` itself isn't
/// `Hashable`/`Equatable` on macOS, so `MapCanvasView` never exposes it
/// directly (docs/CONCEPT.md §2.9 risks).
public struct MapFeatureTap: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var title: String
    public var coordinate: Coordinate

    public init(title: String, coordinate: Coordinate) {
        self.title = title
        self.coordinate = coordinate
    }
}

/// Loads enriched `PlaceDetails` for a tapped map feature, showing a loading
/// state while the fallback `MKLocalSearch` lookup runs and cancelling any
/// in-flight lookup if a new feature is tapped before it completes
/// (docs/CONCEPT.md §1.5 "Phase 2 — Points of interest", §2.5 "Selecting a
/// map POI").
@MainActor
@Observable
public final class MapFeatureDetailModel {
    private let mapProvider: any MapProvider
    private var loadTask: Task<Void, Never>?

    public private(set) var isLoading = false
    public private(set) var details: PlaceDetails?
    public private(set) var errorMessage: String?

    public init(mapProvider: any MapProvider) {
        self.mapProvider = mapProvider
    }

    public func load(_ tap: MapFeatureTap) {
        loadTask?.cancel()
        details = nil
        errorMessage = nil
        isLoading = true
        loadTask = Task {
            defer { isLoading = false }
            do {
                let result = try await mapProvider.details(forFeatureTitled: tap.title, near: tap.coordinate)
                guard !Task.isCancelled else { return }
                details = result
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Couldn't load details for this place."
            }
        }
    }

    public func dismiss() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        details = nil
        errorMessage = nil
    }

    /// The best available details to act on: the loaded result, or a
    /// minimal fallback built from the tap itself if the lookup hasn't
    /// finished or failed — so "Add as POI"/"Add as Overnight" always work.
    public func resolvedDetails(for tap: MapFeatureTap) -> PlaceDetails {
        details ?? PlaceDetails(title: tap.title, coordinate: tap.coordinate)
    }
}
