import Testing
import RTPCore
import RTPProviders
@testable import RTPFeatures

@MainActor
@Suite("TripWorkspaceModel")
struct TripWorkspaceModelTests {
    private func makeWorkspace() -> TripWorkspaceModel {
        TripWorkspaceModel(
            trip: Trip(),
            mapProvider: StubMapProvider(),
            photoAssetResolver: StubPhotoAssetResolver()
        )
    }

    @Test("Expanding a phase activates it while collapsing preserves the active phase")
    func phaseExpansionTracksActivePhase() {
        let workspace = makeWorkspace()

        workspace.setExpanded(true, for: .pointsOfInterest)
        #expect(workspace.activePhase == .pointsOfInterest)
        #expect(workspace.trip.currentPhase == .pointsOfInterest)

        workspace.setExpanded(false, for: .pointsOfInterest)
        #expect(workspace.activePhase == .pointsOfInterest)
        #expect(!workspace.expandedPhases.contains(.pointsOfInterest))
    }

    @Test("Corridor map selections fill start, destination, then waypoints")
    func corridorSelectionsRouteToEditor() {
        let workspace = makeWorkspace()

        workspace.handleLongPress(Coordinate(latitude: 48, longitude: 11))
        workspace.handleLongPress(Coordinate(latitude: 49, longitude: 12))
        workspace.handleLongPress(Coordinate(latitude: 50, longitude: 13))

        #expect(workspace.corridorViewModel.orderedAnchors.map(\.kind) == [.start, .waypoint, .destination])
    }

    @Test("POI map selections create a pending point without persisting prematurely")
    func poiSelectionCreatesPendingPoint() {
        let workspace = makeWorkspace()
        workspace.activate(.pointsOfInterest)

        workspace.handleLongPress(Coordinate(latitude: 48, longitude: 11))

        #expect(workspace.pendingPOIPoint?.title == "Dropped Pin")
        #expect(workspace.trip.anchors.isEmpty)
    }
}
