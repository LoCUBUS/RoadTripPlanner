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
        optimizeWaypointOrder()
        reindexOrder()
        updatedAt = .now
        markNeedsReview(after: .corridor)
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
        optimizeWaypointOrder()
        reindexOrder()
        updatedAt = .now
        markNeedsReview(after: .corridor)
        return anchor
    }

    /// Adds a new coarse Phase 1 waypoint.
    ///
    /// If the middle section is still pure waypoints, the whole section is
    /// re-sorted into a geometrically efficient visiting order via
    /// `optimizeWaypointOrder()` — the user never has to manually reorder a
    /// route made only of coarse stops. If a later phase has already added
    /// a POI or lodging anchor, re-sorting would undo that work, so the new
    /// waypoint is instead inserted at whichever position its coordinate
    /// projects closest to, mirroring Phase 2's own insertion rule
    /// (principle P2). Either way, the user can still reorder manually
    /// afterwards via `reorderMiddleAnchors`.
    @discardableResult
    func addWaypoint(title: String, coordinate: Coordinate, mapItemIdentifier: String? = nil) -> Anchor {
        let anchor = Anchor(kind: .waypoint, title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)

        if middleSectionContainsFixedAnchors {
            insertByProjection(anchor)
            anchor.trip = self
        } else {
            let maxMiddleOrder = orderedMiddleAnchors.map(\.order).max() ?? 0
            anchor.order = maxMiddleOrder + 1
            anchor.trip = self
            anchors.append(anchor)
            optimizeWaypointOrder()
        }

        reindexOrder()
        updatedAt = .now
        markNeedsReview(after: .corridor)
        return anchor
    }

    /// Removes any anchor (start/destination included) by id.
    func removeAnchor(id: UUID) {
        anchors.removeAll { $0.id == id }
        reindexOrder()
        updatedAt = .now
        markNeedsReview(after: .corridor)
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
        markNeedsReview(after: .corridor)
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

    /// Re-sorts every Phase 1 waypoint into a geometrically efficient
    /// visiting order between start and destination, via
    /// `RouteOrderOptimizer` (docs/CONCEPT.md §2.2). No-op when:
    /// - fewer than two waypoints exist (nothing to reorder),
    /// - start or destination is not yet set (nothing to optimize against),
    /// - the middle section contains a POI or lodging anchor — re-sorting
    ///   those would silently undo positioning work done in a later phase,
    ///   which principle P2 forbids. In that case callers insert new
    ///   waypoints by projection instead (see `addWaypoint`).
    ///
    /// Exposed as `public` (rather than called only internally) so the
    /// Corridor inspector's explicit "Optimize Order" action can re-run it
    /// on demand after a manual `reorderMiddleAnchors` call, which never
    /// triggers it automatically.
    func optimizeWaypointOrder() {
        guard !middleSectionContainsFixedAnchors else { return }
        let waypoints = orderedMiddleAnchors.filter { $0.kind == .waypoint }
        guard waypoints.count > 1 else { return }
        guard let start = anchors.first(where: { $0.kind == .start })?.coordinate,
              let destination = anchors.first(where: { $0.kind == .destination })?.coordinate
        else { return }

        let optimizerWaypoints = waypoints.map { RouteOrderOptimizer.Waypoint(id: $0.id, coordinate: $0.coordinate) }
        let orderedIDs = RouteOrderOptimizer.optimize(start: start, destination: destination, waypoints: optimizerWaypoints)

        let anchorsByID = Dictionary(uniqueKeysWithValues: waypoints.map { ($0.id, $0) })
        var nextOrder = waypoints.map(\.order).min() ?? 0
        for id in orderedIDs {
            anchorsByID[id]?.order = nextOrder
            nextOrder += 1
        }
    }

    /// Whether the middle section already contains a fixed Phase 2/3
    /// anchor (POI or lodging) that `optimizeWaypointOrder()` must not
    /// disturb.
    private var middleSectionContainsFixedAnchors: Bool {
        orderedMiddleAnchors.contains { $0.kind == .poi || $0.kind == .lodging }
    }
}
