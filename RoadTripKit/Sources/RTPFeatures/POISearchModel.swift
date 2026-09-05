import Foundation
import Observation
import RTPCore
import RTPProviders

/// Drives the single search field in the Phase 2 (POI) inspector, mirroring
/// `CorridorSearchModel`'s per-field pattern (docs/CONCEPT.md §1.5
/// "Phase 2 — Points of interest"). Kept as its own small model — rather
/// than adding a fourth field to `CorridorSearchModel` — since it belongs to
/// a different phase and inspector.
@MainActor
@Observable
public final class POISearchModel {
    public let search: MapSearchViewModel
    public var query: String = ""

    private var searchRegionClosure: (() -> MapRegion)?

    public init(mapProvider: any MapProvider) {
        self.search = MapSearchViewModel(provider: mapProvider)
    }

    public func setSearchRegion(_ closure: @escaping () -> MapRegion) {
        searchRegionClosure = closure
    }

    public func updateQuery(_ text: String) {
        query = text
        if let region = searchRegionClosure?() {
            search.updateQuery(text, region: region)
        }
    }

    public func resetAfterPick() {
        query = ""
        search.clear()
    }
}
