import Foundation
import RTPCore
import RTPProviders

/// A resolved leg between two consecutive anchors, ready to be persisted as
/// a SwiftData `RouteLeg` by the caller. `isStale` mirrors `RouteLeg.isStale`:
/// true means directions could not be fetched and this is a straight-line
/// fallback estimate that should be retried later (docs/CONCEPT.md §2.4, §2.9).
public struct RouteLegResult: Sendable, Equatable {
    public var fromAnchorID: UUID
    public var toAnchorID: UUID
    public var route: RouteResult
    public var isStale: Bool
    public var computedAt: Date

    public init(fromAnchorID: UUID, toAnchorID: UUID, route: RouteResult, isStale: Bool, computedAt: Date = .now) {
        self.fromAnchorID = fromAnchorID
        self.toAnchorID = toAnchorID
        self.route = route
        self.isStale = isStale
        self.computedAt = computedAt
    }
}

/// Maintains the leg cache for a trip's anchor chain and recomputes only the
/// legs invalidated by an edit — never the whole route (docs/CONCEPT.md §2.4).
///
/// Requests are serialised on this actor with a small delay between them and
/// a retry-with-backoff, because `MKDirections` is aggressively throttled by
/// Apple. A leg that still fails after all retries degrades to a straight-line
/// distance/time estimate marked `isStale`, so the UI can keep working and
/// retry later rather than blocking on the network.
public actor RouteCoordinator {
    public struct Configuration: Sendable {
        /// Delay observed between consecutive directions requests to avoid
        /// MKDirections throttling.
        public var requestDelayNanoseconds: UInt64
        /// Total attempts (including the first) before falling back to a
        /// straight-line estimate.
        public var maxAttempts: Int
        /// Delay before the first retry; doubles (by `backoffMultiplier`)
        /// after each subsequent failure.
        public var initialBackoffNanoseconds: UInt64
        public var backoffMultiplier: Double
        /// Assumed average driving speed (m/s) used for the straight-line
        /// fallback's estimated travel time.
        public var fallbackSpeedMetersPerSecond: Double

        public init(
            requestDelayNanoseconds: UInt64 = 200_000_000,
            maxAttempts: Int = 3,
            initialBackoffNanoseconds: UInt64 = 300_000_000,
            backoffMultiplier: Double = 2.0,
            fallbackSpeedMetersPerSecond: Double = 80_000.0 / 3600.0
        ) {
            self.requestDelayNanoseconds = requestDelayNanoseconds
            self.maxAttempts = maxAttempts
            self.initialBackoffNanoseconds = initialBackoffNanoseconds
            self.backoffMultiplier = backoffMultiplier
            self.fallbackSpeedMetersPerSecond = fallbackSpeedMetersPerSecond
        }

        public static let `default` = Configuration()
    }

    public struct LegKey: Hashable, Sendable {
        public var from: UUID
        public var to: UUID

        public init(from: UUID, to: UUID) {
            self.from = from
            self.to = to
        }
    }

    private let provider: any MapProvider
    private let configuration: Configuration
    private var cache: [LegKey: RouteLegResult] = [:]

    public init(provider: any MapProvider, configuration: Configuration = .default) {
        self.provider = provider
        self.configuration = configuration
    }

    /// Removes every cached leg touching `anchorID` (as either endpoint), so
    /// the next `resolveLegs` call re-requests them. Inserting an anchor
    /// between A and B therefore costs 2 requests (A→X, X→B), not a full
    /// route recompute.
    public func invalidate(anchorID: UUID) {
        cache = cache.filter { $0.key.from != anchorID && $0.key.to != anchorID }
    }

    /// Removes a single cached leg by its endpoints, if present.
    public func invalidateLeg(from: UUID, to: UUID) {
        cache.removeValue(forKey: LegKey(from: from, to: to))
    }

    public func invalidateAll() {
        cache.removeAll()
    }

    /// Marks every cached leg touching `anchorID` as stale without removing
    /// it, so the previous (possibly good) result is still available to the
    /// UI while a fresh request is in flight or pending retry.
    public func markStale(anchorID: UUID) {
        for (key, value) in cache where key.from == anchorID || key.to == anchorID {
            var updated = value
            updated.isStale = true
            cache[key] = updated
        }
    }

    public var cachedLegCount: Int {
        cache.count
    }

    /// Resolves the full ordered leg chain for `anchors`, reusing cached,
    /// non-stale legs and requesting only the missing or invalidated ones.
    @discardableResult
    public func resolveLegs(for anchors: [AnchorPoint]) async -> [RouteLegResult] {
        guard anchors.count >= 2 else { return [] }

        var results: [RouteLegResult] = []
        results.reserveCapacity(anchors.count - 1)

        for index in 0..<(anchors.count - 1) {
            let from = anchors[index]
            let to = anchors[index + 1]
            let key = LegKey(from: from.id, to: to.id)

            if let cached = cache[key], !cached.isStale {
                results.append(cached)
                continue
            }

            if index > 0 {
                try? await Task.sleep(nanoseconds: configuration.requestDelayNanoseconds)
            }

            let result = await requestLeg(from: from, to: to)
            cache[key] = result
            results.append(result)
        }

        return results
    }

    private func requestLeg(from: AnchorPoint, to: AnchorPoint) async -> RouteLegResult {
        var attempt = 0
        var backoff = configuration.initialBackoffNanoseconds

        while attempt < configuration.maxAttempts {
            do {
                let route = try await provider.directions(from: from.coordinate, to: to.coordinate)
                return RouteLegResult(fromAnchorID: from.id, toAnchorID: to.id, route: route, isStale: false)
            } catch {
                attempt += 1
                guard attempt < configuration.maxAttempts else { break }
                try? await Task.sleep(nanoseconds: backoff)
                backoff = UInt64(Double(backoff) * configuration.backoffMultiplier)
            }
        }

        return fallbackLeg(from: from, to: to)
    }

    private func fallbackLeg(from: AnchorPoint, to: AnchorPoint) -> RouteLegResult {
        let distance = from.coordinate.distance(to: to.coordinate)
        let travelTime = distance / configuration.fallbackSpeedMetersPerSecond
        let route = RouteResult(
            distanceMeters: distance,
            expectedTravelTime: travelTime,
            polyline: [from.coordinate, to.coordinate],
            steps: [RouteStep(distanceMeters: distance, endCoordinate: to.coordinate)]
        )
        return RouteLegResult(fromAnchorID: from.id, toAnchorID: to.id, route: route, isStale: true)
    }
}
