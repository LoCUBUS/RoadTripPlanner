import Foundation
import Observation
import RTPCore
import RTPProviders
import RTPRouting

/// A point picked by map search or long-press, awaiting further input (a
/// category/dwell duration, a lodging name, ...) before it becomes a
/// persisted anchor. Shared across phases so the workspace only needs one
/// "point awaiting a sheet" shape.
public struct PendingMapPoint: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let coordinate: Coordinate
    public let mapItemIdentifier: String?

    public init(title: String, coordinate: Coordinate, mapItemIdentifier: String? = nil) {
        self.title = title
        self.coordinate = coordinate
        self.mapItemIdentifier = mapItemIdentifier
    }
}

/// The single owner of state shared between the always-visible map column
/// and the phase inspector column in the three-column macOS workspace. Holds
/// one instance of each phase's existing view model — their own logic and
/// tests are untouched — and adds the glue that only makes sense once map
/// and inspector are separate views: which phase is "active" (and therefore
/// receives map interactions), what the map should currently render, and the
/// phase-revision Recalculate/Dismiss actions (previously on
/// `TripDetailView`, which this model replaces together with the five
/// map-owning phase views).
@MainActor
@Observable
public final class TripWorkspaceModel {
    public let trip: Trip
    public let mapProvider: any MapProvider
    public let photoAssetResolver: any PhotoAssetResolver
    public let routeCoordinator: RouteCoordinator

    public let corridorViewModel: CorridorEditorViewModel
    public let poiViewModel: POIEditorViewModel
    public let dayPlannerViewModel: DayPlannerViewModel
    public let summaryViewModel: SummaryViewModel
    public let journalViewModel: PhotoJournalViewModel
    public let corridorSearchModel: CorridorSearchModel

    /// The phase whose inspector last changed the map's content and
    /// interaction routing. Expanding any disclosure group activates it;
    /// several groups may stay expanded at once, but only one is active.
    public private(set) var activePhase: Phase
    public var expandedPhases: Set<Phase>

    /// A point picked while `.pointsOfInterest` is active, awaiting a
    /// category/dwell-duration sheet before it becomes a POI.
    public var pendingPOIPoint: PendingMapPoint?
    /// A point picked while `.overnights` is active, awaiting a lodging-name
    /// sheet before it closes the open day.
    public var pendingLodgingPoint: PendingMapPoint?
    /// A photo armed for manual pinning while `.journal` is active; the next
    /// map long-press (or search-result pick) places it.
    public var photoAwaitingPin: TripPhoto?

    public private(set) var recalculatingPhase: Phase?

    public init(
        trip: Trip,
        mapProvider: any MapProvider,
        photoAssetResolver: any PhotoAssetResolver
    ) {
        self.trip = trip
        self.mapProvider = mapProvider
        self.photoAssetResolver = photoAssetResolver

        let coordinator = RouteCoordinator(provider: mapProvider)
        self.routeCoordinator = coordinator
        self.corridorViewModel = CorridorEditorViewModel(trip: trip, routeCoordinator: coordinator)
        self.poiViewModel = POIEditorViewModel(trip: trip, routeCoordinator: coordinator)
        self.dayPlannerViewModel = DayPlannerViewModel(trip: trip, routeCoordinator: coordinator, mapProvider: mapProvider)
        self.summaryViewModel = SummaryViewModel(trip: trip, mapProvider: mapProvider)
        self.journalViewModel = PhotoJournalViewModel(trip: trip, assetResolver: photoAssetResolver)
        self.corridorSearchModel = CorridorSearchModel(mapProvider: mapProvider)

        self.activePhase = trip.currentPhase
        self.expandedPhases = [trip.currentPhase]

        corridorSearchModel.setSearchRegion { self.searchRegion }
        corridorSearchModel.setTrip { trip }
    }

    // MARK: - Disclosure group expansion

    /// Called from each phase's `DisclosureGroup` binding. Expanding a group
    /// activates its phase; collapsing one never changes the active phase,
    /// even if it was the one collapsed — the map keeps routing interactions
    /// there until another group is expanded or `activate(_:)` is called
    /// directly (e.g. clicking an already-expanded header).
    public func setExpanded(_ isExpanded: Bool, for phase: Phase) {
        if isExpanded {
            expandedPhases.insert(phase)
            activate(phase)
        } else {
            expandedPhases.remove(phase)
        }
    }

    public func activate(_ phase: Phase) {
        activePhase = phase
        trip.currentPhase = phase
    }

    // MARK: - Map content for the active phase

    public var mapAnnotations: [MapCanvasAnnotation] {
        switch activePhase {
        case .corridor:
            corridorViewModel.orderedAnchors.map(MapCanvasAnnotation.init(anchor:))
        case .pointsOfInterest:
            poiViewModel.orderedAnchors.map(MapCanvasAnnotation.init(anchor:))
        case .overnights:
            overnightsAnnotations
        case .summary:
            trip.orderedAnchors.map(MapCanvasAnnotation.init(anchor:))
        case .journal:
            journalAnnotations
        }
    }

    private var overnightsAnnotations: [MapCanvasAnnotation] {
        var annotations = trip.orderedAnchors.map(MapCanvasAnnotation.init(anchor:))
        if let day = dayPlannerViewModel.openDay, let timeUpPoint = day.timeUpPoint {
            annotations.append(MapCanvasAnnotation(coordinate: timeUpPoint, title: "Time's Up \u{2248}", style: .timeUp))
        }
        return annotations
    }

    private var journalAnnotations: [MapCanvasAnnotation] {
        trip.orderedAnchors.map(MapCanvasAnnotation.init(anchor:)) +
            journalViewModel.pinnedPhotos.compactMap { photo in
                guard let coordinate = photo.coordinate else { return nil }
                return MapCanvasAnnotation(id: photo.id, coordinate: coordinate, title: photo.caption.isEmpty ? "Photo" : photo.caption, style: .photo)
            }
    }

    /// The route legs drawn on the map — shown regardless of the active
    /// phase, since the map is now a persistent, shared column rather than
    /// something each phase gets its own copy of.
    public var routePolylines: [[Coordinate]] {
        trip.legs.map(\.polylineCoordinates)
    }

    public var searchRegion: MapRegion {
        if activePhase == .overnights, let day = dayPlannerViewModel.openDay, let point = day.timeUpPoint {
            return MapRegion(center: point, latitudeDelta: 2, longitudeDelta: 2)
        }
        if let first = trip.orderedAnchors.first {
            return MapRegion(center: first.coordinate, latitudeDelta: 5, longitudeDelta: 5)
        }
        return MapRegion(center: Coordinate(latitude: 48.1351, longitude: 11.5820), latitudeDelta: 10, longitudeDelta: 10)
    }

    // MARK: - Map interaction routing

    /// Routes a map search-result pick to whatever the active phase means by
    /// "a point was chosen": the next corridor stop, a pending POI/lodging
    /// sheet, or (in the journal) pinning an armed photo. No-op in Summary,
    /// which is read-only.
    public func handleSearchResult(_ result: PlaceResult) {
        handleNewPoint(title: result.title, coordinate: result.coordinate, mapItemIdentifier: result.mapItemIdentifier)
    }

    /// Routes a map long-press the same way as a search-result pick, using a
    /// generic "Dropped Pin" title.
    public func handleLongPress(_ coordinate: Coordinate) {
        handleNewPoint(title: "Dropped Pin", coordinate: coordinate, mapItemIdentifier: nil)
    }

    private func handleNewPoint(title: String, coordinate: Coordinate, mapItemIdentifier: String?) {
        switch activePhase {
        case .corridor:
            handleCorridorPoint(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        case .pointsOfInterest:
            pendingPOIPoint = PendingMapPoint(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        case .overnights:
            guard dayPlannerViewModel.openDay != nil else { return }
            pendingLodgingPoint = PendingMapPoint(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        case .summary:
            break
        case .journal:
            guard let photo = photoAwaitingPin else { return }
            journalViewModel.pinPhoto(photo, at: coordinate)
            photoAwaitingPin = nil
        }
    }

    /// The next tapped/searched/long-pressed point becomes the start if it
    /// is not yet set, then the destination if that is not yet set, and a
    /// waypoint otherwise — mirrors the natural order a user plans a trip in
    /// without requiring a mode switch.
    private func handleCorridorPoint(title: String, coordinate: Coordinate, mapItemIdentifier: String?) {
        if corridorViewModel.orderedAnchors.first(where: { $0.kind == .start }) == nil {
            corridorViewModel.setStart(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        } else if corridorViewModel.orderedAnchors.first(where: { $0.kind == .destination }) == nil {
            corridorViewModel.setDestination(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        } else {
            corridorViewModel.addWaypoint(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        }
    }

    // MARK: - Phase revision banner

    /// Phases currently flagged as possibly out of date by an upstream edit
    /// (docs/CONCEPT.md §1.6, principle P2), sorted so earlier phases show
    /// first.
    ///
    /// Filtered by `hasReviewableContent` as well as the flag itself, so a
    /// phase that was emptied *after* being flagged (e.g. its last POI was
    /// removed) stops showing a banner about data it no longer has.
    public var reviewBanners: [Phase] {
        trip.phaseStatus
            .filter { $0.value.needsReview && trip.hasReviewableContent($0.key) }
            .keys
            .sorted()
    }

    /// Runs `recalculate(_:)` for every currently flagged phase, in phase
    /// order, so the consolidated banner can be cleared with one action.
    public func recalculateFlaggedPhases() async {
        for phase in reviewBanners {
            await recalculate(phase)
        }
    }

    /// Clears every review flag without recalculating anything — the
    /// "I know, that's fine" escape hatch. Deletes no data (principle P2).
    public func dismissReviewBanners() {
        for phase in reviewBanners {
            trip.markReviewed(phase)
        }
    }

    /// Recalculates the data a flagged phase depends on, then clears its
    /// review flag — never deleting anything. Corridor/POI edits invalidate
    /// cached route legs, so those two phases re-run their own view model's
    /// `recalculateRoute()` (which uses the same shared `routeCoordinator`).
    /// Overnights re-segments its currently open day via the day planner
    /// view model's `recalculateRoute()`. Summary and journal hold
    /// user-entered state (visited/comment/rating/captions) that upstream
    /// edits never invalidate directly, so dismissing simply clears the
    /// flag.
    public func recalculate(_ phase: Phase) async {
        recalculatingPhase = phase
        defer { recalculatingPhase = nil }

        switch phase {
        case .corridor:
            await corridorViewModel.recalculateRoute()
        case .pointsOfInterest:
            await poiViewModel.recalculateRoute()
        case .overnights:
            await dayPlannerViewModel.recalculateRoute()
        case .summary, .journal:
            break
        }
        trip.markReviewed(phase)
    }
}
