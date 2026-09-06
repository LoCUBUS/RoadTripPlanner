import Testing
import RTPCore
import RTPProviders
@testable import RTPFeatures

@MainActor
@Suite("TripWorkspaceModel")
struct TripWorkspaceModelTests {
    private func makeWorkspace(provider: StubMapProvider = StubMapProvider()) -> TripWorkspaceModel {
        TripWorkspaceModel(
            trip: Trip(),
            mapProvider: provider,
            photoAssetResolver: StubPhotoAssetResolver()
        )
    }

    private let details = PlaceDetails(title: "Test Place", coordinate: Coordinate(latitude: 48, longitude: 11), category: .sight, mapItemIdentifier: "abc")

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

    @Test("Corridor place actions offer Set as Start, then Destination, then Waypoint in order")
    func corridorPlaceActionsProgressThroughSlots() {
        let workspace = makeWorkspace()
        workspace.activate(.corridor)

        #expect(workspace.placeActions().map(\.title) == ["Set as Start"])
        workspace.placeActions()[0].handler(details)
        #expect(workspace.corridorViewModel.orderedAnchors.map(\.kind) == [.start])

        #expect(workspace.placeActions().map(\.title) == ["Set as Destination"])
        workspace.placeActions()[0].handler(PlaceDetails(title: "Dest", coordinate: Coordinate(latitude: 49, longitude: 12)))
        #expect(workspace.corridorViewModel.orderedAnchors.map(\.kind) == [.start, .destination])

        #expect(workspace.placeActions().map(\.title) == ["Add as Waypoint"])
        workspace.placeActions()[0].handler(PlaceDetails(title: "Way", coordinate: Coordinate(latitude: 48.5, longitude: 11.5)))
        #expect(workspace.corridorViewModel.orderedAnchors.map(\.kind) == [.start, .waypoint, .destination])
    }

    @Test("POI place actions open a prefilled pending point or add an overnight candidate directly")
    func poiPlaceActionsOfferAddAsPOIAndOvernightCandidate() {
        let workspace = makeWorkspace()
        workspace.activate(.pointsOfInterest)

        let actions = workspace.placeActions()
        #expect(actions.map(\.title) == ["Add as POI\u{2026}", "Add as Overnight Candidate"])
        #expect(workspace.placeFootnote() == nil)

        actions[0].handler(details)
        #expect(workspace.pendingPOIPoint?.title == "Test Place")
        #expect(workspace.pendingPOIPoint?.category == .sight)
        #expect(workspace.trip.anchors.isEmpty)

        actions[1].handler(details)
        #expect(workspace.trip.anchors.contains { $0.title == "Test Place" && $0.isOvernightCandidate })
    }

    @Test("Overnight place actions fall back to adding a candidate when no day is open, with an explanatory footnote")
    func overnightPlaceActionsFallBackWithoutOpenDay() {
        let workspace = makeWorkspace()
        workspace.activate(.overnights)

        let actions = workspace.placeActions()
        #expect(actions.map(\.title) == ["Add as Overnight Candidate"])
        #expect(workspace.placeFootnote() != nil)

        actions[0].handler(details)
        #expect(workspace.trip.anchors.contains { $0.title == "Test Place" && $0.isOvernightCandidate })
    }

    @Test("Overnight place actions close the open day with the resolved place when a day is open")
    func overnightPlaceActionsCloseOpenDay() async {
        let munich = Coordinate(latitude: 48.1351, longitude: 11.5820)
        let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)
        let provider = StubMapProvider()
        provider.defaultRoute = RouteResult(
            distanceMeters: 500_000,
            expectedTravelTime: 5 * 3600,
            polyline: [munich, berlin],
            steps: [RouteStep(distanceMeters: 500_000, endCoordinate: berlin)]
        )
        let workspace = makeWorkspace(provider: provider)
        workspace.corridorViewModel.setStart(title: "Munich", coordinate: munich)
        workspace.corridorViewModel.setDestination(title: "Berlin", coordinate: berlin)
        await workspace.poiViewModel.recalculateRoute()

        workspace.activate(.overnights)
        _ = workspace.dayPlannerViewModel.startNextDay(budget: 3 * 3600)
        #expect(workspace.dayPlannerViewModel.openDay != nil)

        let actions = workspace.placeActions()
        #expect(actions.map(\.title) == ["Use as Tonight's Overnight"])
        #expect(workspace.placeFootnote() == nil)

        actions[0].handler(details)
        #expect(workspace.dayPlannerViewModel.openDay == nil)
        #expect(workspace.trip.anchors.contains { $0.title == "Test Place" && $0.kind == .lodging })
    }

    @Test("Place selection is disabled in Journal unless a photo is armed for pinning")
    func placeSelectionDisabledInJournalUnlessPhotoArmed() {
        let workspace = makeWorkspace()
        workspace.activate(.journal)

        #expect(!workspace.isPlaceSelectionEnabled)
        #expect(workspace.placeActions().isEmpty)
    }
}
