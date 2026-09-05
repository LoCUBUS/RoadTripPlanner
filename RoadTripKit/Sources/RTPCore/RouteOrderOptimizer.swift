import Foundation

/// Computes a geometrically efficient visiting order for waypoints between
/// a fixed start and destination — an open-path TSP with fixed endpoints
/// (docs/CONCEPT.md §2.2, §1.5 "Phase 1 — Coarse route").
///
/// Uses great-circle distance (`Coordinate.distance(to:)`) as its metric.
/// This is deliberately cheaper than routing through the map provider's
/// directions API, which would need O(n²) requests per edit; the waypoint
/// order it produces is typically identical to a road-distance-based
/// ordering at corridor-planning scale. Callers who want it to reflect road
/// distances instead can swap the metric behind this same API.
public enum RouteOrderOptimizer {
    /// A point to be ordered, identified so the optimized permutation can be
    /// mapped back onto the caller's own model objects without this utility
    /// depending on `Anchor`/SwiftData.
    public struct Waypoint: Sendable, Equatable {
        public var id: UUID
        public var coordinate: Coordinate

        public init(id: UUID, coordinate: Coordinate) {
            self.id = id
            self.coordinate = coordinate
        }
    }

    /// Above this many waypoints, exhaustive permutation is replaced by a
    /// nearest-neighbour construction plus 2-opt refinement so a single edit
    /// never blocks the UI (8! = 40,320 permutations is the practical
    /// ceiling for an exhaustive search within one debounce window).
    static let exhaustiveLimit = 8

    /// Returns `waypoints.map(\.id)` reordered so the total great-circle
    /// distance start → waypoints… → destination is minimized (or nearly so
    /// above `exhaustiveLimit`). Order is unchanged when already optimal.
    /// Empty or single-element input is returned unchanged, since there is
    /// nothing to reorder.
    public static func optimize(
        start: Coordinate,
        destination: Coordinate,
        waypoints: [Waypoint]
    ) -> [UUID] {
        guard waypoints.count > 1 else {
            return waypoints.map(\.id)
        }

        let order: [Int]
        if waypoints.count <= exhaustiveLimit {
            order = exhaustiveOrder(start: start, destination: destination, waypoints: waypoints)
        } else {
            order = nearestNeighborThenTwoOpt(start: start, destination: destination, waypoints: waypoints)
        }
        return order.map { waypoints[$0].id }
    }

    // MARK: - Exhaustive search (n <= exhaustiveLimit)

    private static func exhaustiveOrder(
        start: Coordinate,
        destination: Coordinate,
        waypoints: [Waypoint]
    ) -> [Int] {
        var bestOrder = Array(0..<waypoints.count)
        var bestDistance = totalDistance(start: start, destination: destination, waypoints: waypoints, order: bestOrder)

        var indices = Array(0..<waypoints.count)
        permute(&indices, 0) { candidate in
            let distance = totalDistance(start: start, destination: destination, waypoints: waypoints, order: candidate)
            if distance < bestDistance {
                bestDistance = distance
                bestOrder = candidate
            }
        }
        return bestOrder
    }

    /// Heap's algorithm — generates every permutation of `array` in place,
    /// invoking `visit` with each complete arrangement.
    private static func permute(_ array: inout [Int], _ k: Int, visit: ([Int]) -> Void) {
        if k == array.count {
            visit(array)
            return
        }
        for i in k..<array.count {
            array.swapAt(k, i)
            permute(&array, k + 1, visit: visit)
            array.swapAt(k, i)
        }
    }

    // MARK: - Nearest-neighbour + 2-opt (n > exhaustiveLimit)

    private static func nearestNeighborThenTwoOpt(
        start: Coordinate,
        destination: Coordinate,
        waypoints: [Waypoint]
    ) -> [Int] {
        let constructed = nearestNeighborOrder(start: start, waypoints: waypoints)
        return twoOptImprove(start: start, destination: destination, waypoints: waypoints, order: constructed)
    }

    /// Greedily visits whichever remaining waypoint is closest to the
    /// current position, starting from `start`. Deterministic: ties are
    /// broken by the lower original index, since `min(by:)` keeps the first
    /// minimal element it encounters.
    private static func nearestNeighborOrder(start: Coordinate, waypoints: [Waypoint]) -> [Int] {
        var remaining = Array(0..<waypoints.count)
        var order: [Int] = []
        order.reserveCapacity(waypoints.count)
        var current = start

        while !remaining.isEmpty {
            let nextPosition = remaining.indices.min { lhs, rhs in
                waypoints[remaining[lhs]].coordinate.distance(to: current)
                    < waypoints[remaining[rhs]].coordinate.distance(to: current)
            }!
            let next = remaining.remove(at: nextPosition)
            order.append(next)
            current = waypoints[next].coordinate
        }
        return order
    }

    /// Iterative 2-opt: repeatedly reverses sub-segments of the route when
    /// doing so shortens the total distance, until a full pass makes no
    /// improvement or `maxIterations` is reached. Deterministic: segments
    /// are always tried in the same (i, j) order.
    private static func twoOptImprove(
        start: Coordinate,
        destination: Coordinate,
        waypoints: [Waypoint],
        order initialOrder: [Int]
    ) -> [Int] {
        var order = initialOrder
        guard order.count > 2 else { return order }

        let maxIterations = 200
        var iterations = 0
        var improved = true

        while improved && iterations < maxIterations {
            improved = false
            iterations += 1
            let currentDistance = totalDistance(start: start, destination: destination, waypoints: waypoints, order: order)
            var bestDistance = currentDistance
            var bestOrder = order

            for i in 0..<(order.count - 1) {
                for j in (i + 1)..<order.count {
                    var candidate = order
                    candidate[i...j].reverse()
                    let candidateDistance = totalDistance(start: start, destination: destination, waypoints: waypoints, order: candidate)
                    if candidateDistance < bestDistance {
                        bestDistance = candidateDistance
                        bestOrder = candidate
                    }
                }
            }

            if bestDistance < currentDistance {
                order = bestOrder
                improved = true
            }
        }
        return order
    }

    // MARK: - Shared distance calculation

    private static func totalDistance(
        start: Coordinate,
        destination: Coordinate,
        waypoints: [Waypoint],
        order: [Int]
    ) -> Double {
        guard !order.isEmpty else {
            return start.distance(to: destination)
        }
        var total = 0.0
        var current = start
        for index in order {
            let next = waypoints[index].coordinate
            total += current.distance(to: next)
            current = next
        }
        total += current.distance(to: destination)
        return total
    }
}
