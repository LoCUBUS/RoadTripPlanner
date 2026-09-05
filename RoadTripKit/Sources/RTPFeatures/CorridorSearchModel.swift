import Foundation
import Observation
import RTPCore
import RTPProviders

/// Drives three independent search fields in the Corridor inspector:
/// start point, destination, and waypoint-adding. Each field owns its own
/// query text, results, and loading state via a dedicated `MapSearchViewModel`.
/// Resets query and results after a pick so the user can add the next point.
@MainActor
@Observable
public final class CorridorSearchModel {
    public let startSearch: MapSearchViewModel
    public let destinationSearch: MapSearchViewModel
    public let waypointSearch: MapSearchViewModel

    public var startQuery: String = ""
    public var destinationQuery: String = ""
    public var waypointQuery: String = ""

    private let mapProvider: any MapProvider
    private var searchRegionClosure: (() -> MapRegion)?
    private var tripClosure: (() -> Trip)?

    public init(mapProvider: any MapProvider) {
        self.mapProvider = mapProvider

        self.startSearch = MapSearchViewModel(provider: mapProvider)
        self.destinationSearch = MapSearchViewModel(provider: mapProvider)
        self.waypointSearch = MapSearchViewModel(provider: mapProvider)
    }

    public func setSearchRegion(_ closure: @escaping () -> MapRegion) {
        searchRegionClosure = closure
    }

    public func setTrip(_ closure: @escaping () -> Trip) {
        tripClosure = closure
    }

    /// Returns true when both start and destination anchors exist in the trip,
    /// enabling waypoint input. Without this constraint, users could add
    /// waypoints before the route endpoints are defined.
    public var isWaypointInputEnabled: Bool {
        guard let trip = tripClosure?() else { return false }
        let hasStart = !trip.orderedAnchors.filter { $0.kind == .start }.isEmpty
        let hasDestination = !trip.orderedAnchors.filter { $0.kind == .destination }.isEmpty
        return hasStart && hasDestination
    }

    public func updateStartQuery(_ text: String) {
        startQuery = text
        if let region = searchRegionClosure?() {
            startSearch.updateQuery(text, region: region)
        }
    }

    public func updateDestinationQuery(_ text: String) {
        destinationQuery = text
        if let region = searchRegionClosure?() {
            destinationSearch.updateQuery(text, region: region)
        }
    }

    public func updateWaypointQuery(_ text: String) {
        waypointQuery = text
        if let region = searchRegionClosure?() {
            waypointSearch.updateQuery(text, region: region)
        }
    }

    public func resetStartAfterPick() {
        startQuery = ""
        startSearch.clear()
    }

    public func resetDestinationAfterPick() {
        destinationQuery = ""
        destinationSearch.clear()
    }

    public func resetWaypointAfterPick() {
        waypointQuery = ""
        waypointSearch.clear()
    }
}
