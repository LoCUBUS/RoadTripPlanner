import Foundation
import Testing
import RTPCore
import RTPProviders
@testable import RTPRouting

@Suite("RouteCoordinator")
struct RouteCoordinatorTests {
    private let munich = Coordinate(latitude: 48.1351, longitude: 11.5820)
    private let nuremberg = Coordinate(latitude: 49.4579, longitude: 11.0775)
    private let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)

    private func fastConfiguration() -> RouteCoordinator.Configuration {
        RouteCoordinator.Configuration(
            requestDelayNanoseconds: 1_000,
            maxAttempts: 3,
            initialBackoffNanoseconds: 1_000,
            backoffMultiplier: 2.0
        )
    }

    @Test("Resolves one leg per consecutive anchor pair")
    func resolvesLegsForChain() async {
        let provider = StubMapProvider()
        provider.defaultRoute = RouteResult(distanceMeters: 1000, expectedTravelTime: 60, polyline: [])
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())

        let anchors = [
            AnchorPoint(id: UUID(), coordinate: munich),
            AnchorPoint(id: UUID(), coordinate: nuremberg),
            AnchorPoint(id: UUID(), coordinate: berlin)
        ]

        let legs = await coordinator.resolveLegs(for: anchors)

        #expect(legs.count == 2)
        #expect(legs[0].fromAnchorID == anchors[0].id)
        #expect(legs[0].toAnchorID == anchors[1].id)
        #expect(legs[1].fromAnchorID == anchors[1].id)
        #expect(legs[1].toAnchorID == anchors[2].id)
        #expect(legs.allSatisfy { !$0.isStale })
    }

    @Test("A fewer-than-two anchor chain resolves no legs")
    func emptyChain() async {
        let provider = StubMapProvider()
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())
        let legs = await coordinator.resolveLegs(for: [AnchorPoint(id: UUID(), coordinate: munich)])
        #expect(legs.isEmpty)
    }

    @Test("Re-resolving an unchanged chain reuses the cache instead of re-requesting")
    func reusesCache() async {
        let provider = StubMapProvider()
        provider.defaultRoute = RouteResult(distanceMeters: 1000, expectedTravelTime: 60, polyline: [])
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())

        let anchors = [
            AnchorPoint(id: UUID(), coordinate: munich),
            AnchorPoint(id: UUID(), coordinate: nuremberg)
        ]

        _ = await coordinator.resolveLegs(for: anchors)
        #expect(provider.directionsCallCount == 1)

        _ = await coordinator.resolveLegs(for: anchors)
        #expect(provider.directionsCallCount == 1, "second resolve should hit the cache, not the provider")
    }

    @Test("Invalidating an anchor forces its touching legs to be re-requested")
    func invalidationForcesRerequest() async {
        let provider = StubMapProvider()
        provider.defaultRoute = RouteResult(distanceMeters: 1000, expectedTravelTime: 60, polyline: [])
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())

        let a = AnchorPoint(id: UUID(), coordinate: munich)
        let b = AnchorPoint(id: UUID(), coordinate: nuremberg)
        let c = AnchorPoint(id: UUID(), coordinate: berlin)

        _ = await coordinator.resolveLegs(for: [a, b, c])
        #expect(provider.directionsCallCount == 2)

        // Inserting/editing anchor b invalidates only the legs touching it
        // (a->b and b->c) — not a full recompute (docs/CONCEPT.md §2.4).
        await coordinator.invalidate(anchorID: b.id)
        _ = await coordinator.resolveLegs(for: [a, b, c])
        #expect(provider.directionsCallCount == 4)
    }

    @Test("A leg that keeps failing falls back to a straight-line stale estimate")
    func fallsBackAfterRepeatedFailure() async {
        let provider = StubMapProvider()
        provider.directionsFailuresRemaining = 10 // more than maxAttempts
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())

        let a = AnchorPoint(id: UUID(), coordinate: munich)
        let b = AnchorPoint(id: UUID(), coordinate: nuremberg)

        let legs = await coordinator.resolveLegs(for: [a, b])

        #expect(legs.count == 1)
        #expect(legs[0].isStale)
        let expectedDistance = munich.distance(to: nuremberg)
        #expect(abs(legs[0].route.distanceMeters - expectedDistance) < 1)
        #expect(legs[0].route.expectedTravelTime > 0)
        // maxAttempts = 3, so exactly 3 calls should have been made before falling back.
        #expect(provider.directionsCallCount == 3)
    }

    @Test("A transient failure recovers once the provider stops throwing")
    func recoversAfterTransientFailure() async {
        let provider = StubMapProvider()
        provider.directionsFailuresRemaining = 1
        provider.defaultRoute = RouteResult(distanceMeters: 5000, expectedTravelTime: 300, polyline: [])
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())

        let a = AnchorPoint(id: UUID(), coordinate: munich)
        let b = AnchorPoint(id: UUID(), coordinate: nuremberg)

        let legs = await coordinator.resolveLegs(for: [a, b])

        #expect(legs.count == 1)
        #expect(!legs[0].isStale)
        #expect(legs[0].route.distanceMeters == 5000)
        #expect(provider.directionsCallCount == 2)
    }

    @Test("invalidateAll clears the entire cache")
    func invalidateAllClearsCache() async {
        let provider = StubMapProvider()
        provider.defaultRoute = RouteResult(distanceMeters: 1000, expectedTravelTime: 60, polyline: [])
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())

        let anchors = [
            AnchorPoint(id: UUID(), coordinate: munich),
            AnchorPoint(id: UUID(), coordinate: nuremberg)
        ]

        _ = await coordinator.resolveLegs(for: anchors)
        #expect(await coordinator.cachedLegCount == 1)

        await coordinator.invalidateAll()
        #expect(await coordinator.cachedLegCount == 0)

        _ = await coordinator.resolveLegs(for: anchors)
        #expect(provider.directionsCallCount == 2)
    }

    @Test("markStale keeps the previous result available while flagging it for retry")
    func markStaleKeepsPreviousResult() async {
        let provider = StubMapProvider()
        provider.defaultRoute = RouteResult(distanceMeters: 1000, expectedTravelTime: 60, polyline: [])
        let coordinator = RouteCoordinator(provider: provider, configuration: fastConfiguration())

        let a = AnchorPoint(id: UUID(), coordinate: munich)
        let b = AnchorPoint(id: UUID(), coordinate: nuremberg)

        _ = await coordinator.resolveLegs(for: [a, b])
        await coordinator.markStale(anchorID: a.id)

        // A stale cache entry must still trigger a re-request on next resolve.
        _ = await coordinator.resolveLegs(for: [a, b])
        #expect(provider.directionsCallCount == 2)
    }
}
