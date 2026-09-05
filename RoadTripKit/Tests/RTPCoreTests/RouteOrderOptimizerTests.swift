import Foundation
import Testing
@testable import RTPCore

/// Verifies `RouteOrderOptimizer` in isolation: a pure utility with no
/// SwiftData/Trip dependency (docs/CONCEPT.md §2.2).
@Suite("RouteOrderOptimizer")
struct RouteOrderOptimizerTests {
    /// Coordinates along the equator so the great-circle distance between
    /// two points is (to a very close approximation) proportional to their
    /// longitude difference — this makes the "correct" visiting order
    /// obvious and lets assertions be about ordering, not float precision.
    private func point(_ longitude: Double) -> Coordinate {
        Coordinate(latitude: 0, longitude: longitude)
    }

    @Test("Empty waypoints are returned unchanged")
    func emptyWaypoints() {
        let result = RouteOrderOptimizer.optimize(start: point(0), destination: point(10), waypoints: [])
        #expect(result.isEmpty)
    }

    @Test("A single waypoint is returned unchanged")
    func singleWaypoint() {
        let id = UUID()
        let waypoint = RouteOrderOptimizer.Waypoint(id: id, coordinate: point(5))
        let result = RouteOrderOptimizer.optimize(start: point(0), destination: point(10), waypoints: [waypoint])
        #expect(result == [id])
    }

    @Test("Already-optimal input is returned unchanged")
    func alreadyOptimalInputUnchanged() {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()
        let waypoints = [
            RouteOrderOptimizer.Waypoint(id: idA, coordinate: point(2)),
            RouteOrderOptimizer.Waypoint(id: idB, coordinate: point(5)),
            RouteOrderOptimizer.Waypoint(id: idC, coordinate: point(8)),
        ]

        let result = RouteOrderOptimizer.optimize(start: point(0), destination: point(10), waypoints: waypoints)

        #expect(result == [idA, idB, idC])
    }

    @Test("A reversed, clearly suboptimal input is corrected")
    func suboptimalInputIsCorrected() {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()
        let idD = UUID()
        // Given in reverse geometric order relative to start (0) -> destination (10).
        let waypoints = [
            RouteOrderOptimizer.Waypoint(id: idA, coordinate: point(8)),
            RouteOrderOptimizer.Waypoint(id: idB, coordinate: point(6)),
            RouteOrderOptimizer.Waypoint(id: idC, coordinate: point(4)),
            RouteOrderOptimizer.Waypoint(id: idD, coordinate: point(2)),
        ]

        let result = RouteOrderOptimizer.optimize(start: point(0), destination: point(10), waypoints: waypoints)

        // Optimal order visits them along the line: 2, 4, 6, 8.
        #expect(result == [idD, idC, idB, idA])
    }

    @Test("Exhaustive search handles exactly the permutation limit (8 waypoints)")
    func exhaustiveHandlesLimit() {
        let ids = (0..<8).map { _ in UUID() }
        // Shuffle-like: given out of order, longitudes 14, 12, ..., 0 in steps of -2.
        let longitudes: [Double] = [14, 12, 10, 8, 6, 4, 2, 0]
        let waypoints = zip(ids, longitudes).map { RouteOrderOptimizer.Waypoint(id: $0, coordinate: point($1)) }

        let result = RouteOrderOptimizer.optimize(start: point(-2), destination: point(16), waypoints: waypoints)

        // Optimal order visits ascending longitude: 0, 2, 4, ..., 14 — i.e. ids reversed.
        #expect(result == ids.reversed())
    }

    @Test("Nearest-neighbour + 2-opt path (above the exhaustive limit) still finds the geometric order")
    func aboveLimitStillOrdersCorrectly() {
        let ids = (0..<9).map { _ in UUID() }
        let longitudes: [Double] = [16, 14, 12, 10, 8, 6, 4, 2, 0]
        let waypoints = zip(ids, longitudes).map { RouteOrderOptimizer.Waypoint(id: $0, coordinate: point($1)) }

        let result = RouteOrderOptimizer.optimize(start: point(-2), destination: point(18), waypoints: waypoints)

        #expect(result == ids.reversed())
    }

    @Test("Nearest-neighbour + 2-opt path is deterministic across repeated calls")
    func aboveLimitIsDeterministic() {
        let ids = (0..<12).map { _ in UUID() }
        // Not collinear, deliberately messy latitudes and longitudes.
        let coordinates: [Coordinate] = [
            Coordinate(latitude: 48.1, longitude: 11.6), Coordinate(latitude: 52.5, longitude: 13.4),
            Coordinate(latitude: 45.5, longitude: 9.2), Coordinate(latitude: 41.9, longitude: 12.5),
            Coordinate(latitude: 48.9, longitude: 2.4), Coordinate(latitude: 52.4, longitude: 4.9),
            Coordinate(latitude: 50.1, longitude: 14.4), Coordinate(latitude: 47.4, longitude: 8.5),
            Coordinate(latitude: 46.9, longitude: 7.4), Coordinate(latitude: 59.3, longitude: 18.1),
            Coordinate(latitude: 55.7, longitude: 12.6), Coordinate(latitude: 60.2, longitude: 24.9),
        ]
        let waypoints = zip(ids, coordinates).map { RouteOrderOptimizer.Waypoint(id: $0, coordinate: $1) }
        let start = Coordinate(latitude: 51.5, longitude: -0.1)
        let destination = Coordinate(latitude: 40.4, longitude: -3.7)

        let firstRun = RouteOrderOptimizer.optimize(start: start, destination: destination, waypoints: waypoints)
        let secondRun = RouteOrderOptimizer.optimize(start: start, destination: destination, waypoints: waypoints)

        #expect(firstRun == secondRun)
        #expect(Set(firstRun) == Set(ids)) // Same set of waypoints, just reordered.
    }

    @Test("Optimizing never drops or duplicates a waypoint")
    func optimizingPreservesSetOfWaypoints() {
        let ids = (0..<6).map { _ in UUID() }
        let longitudes: [Double] = [3, 9, 1, 7, 5, 2]
        let waypoints = zip(ids, longitudes).map { RouteOrderOptimizer.Waypoint(id: $0, coordinate: point($1)) }

        let result = RouteOrderOptimizer.optimize(start: point(0), destination: point(10), waypoints: waypoints)

        #expect(Set(result) == Set(ids))
        #expect(result.count == ids.count)
    }
}
