import SwiftUI
import RTPCore
import RTPProviders
import RTPRouting

/// Phase 1 editor: set start/destination, add/reorder/remove coarse
/// waypoints on the shared map canvas, and see a live route summary
/// (docs/CONCEPT.md §1.5 "Phase 1 — Coarse route"). Reachable at any time,
/// per principle P1 — nothing here is gated behind `trip.currentPhase`.
public struct CorridorEditorView: View {
    @State private var viewModel: CorridorEditorViewModel
    private let provider: any MapProvider

    public init(trip: Trip, routeCoordinator: RouteCoordinator, provider: any MapProvider) {
        _viewModel = State(initialValue: CorridorEditorViewModel(trip: trip, routeCoordinator: routeCoordinator))
        self.provider = provider
    }

    public var body: some View {
        VStack(spacing: 0) {
            MapCanvasView(
                annotations: viewModel.orderedAnchors.map(MapCanvasAnnotation.init(anchor:)),
                routePolylines: viewModel.trip.legs.map(\.polylineCoordinates),
                searchRegion: searchRegion,
                provider: provider,
                onSelectSearchResult: { result in
                    handleNewPoint(title: result.title, coordinate: result.coordinate, mapItemIdentifier: result.mapItemIdentifier)
                },
                onLongPress: { coordinate in
                    handleNewPoint(title: "Dropped Pin", coordinate: coordinate, mapItemIdentifier: nil)
                }
            )
            .frame(minHeight: 260)

            List {
                Section("Route") {
                    if let start = viewModel.orderedAnchors.first(where: { $0.kind == .start }) {
                        Label(start.title, systemImage: "flag.checkered.circle.fill")
                    } else {
                        Text("Search or long-press the map to set a start")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.orderedMiddleAnchors) { anchor in
                        Label(anchor.title, systemImage: "mappin.circle.fill")
                    }
                    .onMove { offsets, destination in
                        viewModel.moveMiddleAnchors(fromOffsets: offsets, toOffset: destination)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            viewModel.removeAnchor(viewModel.orderedMiddleAnchors[index])
                        }
                    }

                    if let destination = viewModel.orderedAnchors.first(where: { $0.kind == .destination }) {
                        Label(destination.title, systemImage: "checkered.flag.circle.fill")
                    } else {
                        Text("Search or long-press the map to set a destination")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Summary") {
                    if viewModel.trip.legs.isEmpty {
                        Text("Add a start and destination, then recalculate the route.")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Distance", value: distanceText)
                        LabeledContent("Driving time", value: durationText)
                        if viewModel.hasStaleLegs {
                            Label("One or more legs use a straight-line estimate", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }

                    Button {
                        Task { await viewModel.recalculateRoute() }
                    } label: {
                        if viewModel.isRecalculating {
                            ProgressView()
                        } else {
                            Label("Recalculate Route", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(viewModel.isRecalculating || viewModel.orderedAnchors.count < 2)
                }
            }
            #if os(iOS)
            .toolbar { EditButton() }
            #endif
        }
        .navigationTitle("Corridor")
    }

    /// The next tapped/searched/long-pressed point becomes the start if it
    /// is not yet set, then the destination if that is not yet set, and a
    /// waypoint otherwise — this mirrors the natural order a user plans a
    /// trip in without requiring a mode switch.
    private func handleNewPoint(title: String, coordinate: Coordinate, mapItemIdentifier: String?) {
        if viewModel.orderedAnchors.first(where: { $0.kind == .start }) == nil {
            viewModel.setStart(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        } else if viewModel.orderedAnchors.first(where: { $0.kind == .destination }) == nil {
            viewModel.setDestination(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        } else {
            viewModel.addWaypoint(title: title, coordinate: coordinate, mapItemIdentifier: mapItemIdentifier)
        }
    }

    private var searchRegion: MapRegion {
        if let first = viewModel.orderedAnchors.first {
            return MapRegion(center: first.coordinate, latitudeDelta: 5, longitudeDelta: 5)
        }
        return MapRegion(center: Coordinate(latitude: 48.1351, longitude: 11.5820), latitudeDelta: 10, longitudeDelta: 10)
    }

    private var distanceText: String {
        let kilometers = viewModel.totalDistanceMeters / 1000
        return String(format: "%.0f km", kilometers)
    }

    private var durationText: String {
        let hours = Int(viewModel.totalTravelTime) / 3600
        let minutes = (Int(viewModel.totalTravelTime) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
