import Foundation

/// Pure anchor-chain editing operations shared by the Phase 1 corridor
/// editor (and, later, Phase 2/3 anchor insertion). Kept as plain methods on
/// `Trip` with no SwiftUI/MapKit dependency so the ordering logic is
/// unit-testable in isolation (docs/CONCEPT.md §2.1, §2.2).
public extension Trip {
    /// All anchors sorted by their explicit `order` field. Never rely on
    /// the `anchors` array's own element order — SwiftData/CloudKit
    /// relationship arrays are not guaranteed to preserve insertion order.
    var orderedAnchors: [Anchor] {
        anchors.sorted { $0.order < $1.order }
    }

    /// Every anchor that is neither the start nor the destination, i.e. the
    /// part of the chain a phase editor actually reorders/mutates.
    var orderedMiddleAnchors: [Anchor] {
        anchors.filter { $0.kind != .start && $0.kind != .destination }.sorted { $0.order < $1.order }
    }

    /// Creates or updates the trip's single start anchor.
    @discardableResult
    func setStart(title: String, coordinate: Coordinate, mapItemIdentifier: String? = nil) -> Anchor {
        let anchor = anchors.first { $0.kind == .start } ?? {
            let created = Anchor(kind: .start)
            created.trip = self
            anchors.append(created)
            return created
        }()
        anchor.title = title
        anchor.coordinate = coordinate
        anchor.mapItemIdentifier = mapItemIdentifier
        reindexOrder()
        updatedAt = .now
        return anchor
    }

    /// Creates or updates the trip's single destination anchor.
    @discardableResult
    func setDestination(title: String, coordinate: Coordinate, mapItemIdentifier: String? = nil) -> Anchor {
        let anchor = anchors.first { $0.kind == .destination } ?? {
            let created = Anchor(kind: .destination)
            created.trip = self
            anchors.append(created)
            return created
        }()
        anchor.title = title
        anchor.coordinate = coordinate
        anchor.mapItemIdentifier = mapItemIdentifier
        reindexOrder()
        updatedAt = .now
        return anchor
    }

    /// Appends a new coarse Phase 1 waypoint just before the destination
    /// (or at the end if there is no destination yet). The user can freely
    /// reorder it afterwards via `reorderMiddleAnchors`.
    @discardableResult
    func addWaypoint(title: String, coordinate: Coordinate, mapItemIdentifier: String? = nil) -> Anchor {
        let maxMiddleOrder = orderedMiddleAnchors.map(\.order).max() ?? 0
        let anchor = Anchor(kind: .waypoint, title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        anchor.order = maxMiddleOrder + 1
        anchor.trip = self
        anchors.append(anchor)
        reindexOrder()
        updatedAt = .now
        return anchor
    }

    /// Removes any anchor (start/destination included) by id.
    func removeAnchor(id: UUID) {
        anchors.removeAll { $0.id == id }
        reindexOrder()
        updatedAt = .now
    }

    /// Reorders the middle section (waypoints/POIs/lodging) in place, using
    /// `IndexSet`/offset semantics compatible with SwiftUI's `List.onMove`.
    func reorderMiddleAnchors(fromOffsets: IndexSet, toOffset: Int) {
        var middle = orderedMiddleAnchors
        middle.moveElements(fromOffsets: fromOffsets, toOffset: toOffset)
        for (index, anchor) in middle.enumerated() {
            anchor.order = index
        }
        reindexOrder()
        updatedAt = .now
    }

    /// Recomputes every anchor's `order` from scratch: start is always 0,
    /// the middle section keeps its current relative sequence, and the
    /// destination is always last. Called after every structural edit so
    /// `order` values stay dense and consistent.
    func reindexOrder() {
        var nextOrder = 0
        if let start = anchors.first(where: { $0.kind == .start }) {
            start.order = nextOrder
            nextOrder += 1
        }
        for anchor in orderedMiddleAnchors {
            anchor.order = nextOrder
            nextOrder += 1
        }
        if let destination = anchors.first(where: { $0.kind == .destination }) {
            destination.order = nextOrder
        }
    }
}
