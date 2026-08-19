import SwiftUI
import RTPCore
import RTPProviders
import RTPRouting

/// Phase 2 editor: add fixed POIs with a dwell duration and category, and
/// see the 10 km absorption rule apply to nearby Phase 1 waypoints
/// (docs/CONCEPT.md §1.5 "Phase 2 — Points of interest", §2.5). Reachable
/// at any time (P1) — nothing here is gated behind `trip.currentPhase`.
public struct POIEditorView: View {
    @State private var viewModel: POIEditorViewModel
    private let provider: any MapProvider
    @State private var pendingPoint: PendingPOIPoint?

    public init(trip: Trip, routeCoordinator: RouteCoordinator, provider: any MapProvider) {
        _viewModel = State(initialValue: POIEditorViewModel(trip: trip, routeCoordinator: routeCoordinator))
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
                    pendingPoint = PendingPOIPoint(
                        title: result.title,
                        coordinate: result.coordinate,
                        mapItemIdentifier: result.mapItemIdentifier
                    )
                },
                onLongPress: { coordinate in
                    pendingPoint = PendingPOIPoint(title: "Dropped Pin", coordinate: coordinate, mapItemIdentifier: nil)
                }
            )
            .frame(minHeight: 260)

            List {
                if let absorption = viewModel.lastAbsorption {
                    Section {
                        HStack {
                            Label(
                                "Replaced \u{201C}\(absorption.waypointTitle)\u{201D} with \u{201C}\(absorption.poiTitle)\u{201D}",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            Spacer()
                            Button("Undo") { viewModel.undoLastAddition() }
                        }
                    }
                }

                Section("Stops") {
                    if viewModel.orderedMiddleAnchors.isEmpty {
                        Text("Search or long-press the map to add a POI.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.orderedMiddleAnchors) { anchor in
                        if anchor.kind == .poi {
                            POIRow(anchor: anchor, viewModel: viewModel)
                        } else {
                            Label(anchor.title, systemImage: MapCanvasAnnotation.Style.waypoint.systemImage)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onMove { offsets, destination in
                        viewModel.moveMiddleAnchors(fromOffsets: offsets, toOffset: destination)
                    }
                    .onDelete { offsets in
                        let anchors = viewModel.orderedMiddleAnchors
                        for index in offsets where anchors[index].kind == .poi {
                            viewModel.removePOI(anchors[index])
                        }
                    }
                }

                Section("Summary") {
                    if viewModel.trip.legs.isEmpty {
                        Text("Add a start and destination in the corridor editor, then recalculate the route.")
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
        .navigationTitle("Points of Interest")
        .sheet(item: $pendingPoint) { point in
            AddPOISheet(
                point: point,
                onAdd: { category, dwellMinutes in
                    viewModel.addPOI(
                        title: point.title,
                        coordinate: point.coordinate,
                        mapItemIdentifier: point.mapItemIdentifier,
                        category: category,
                        dwellDuration: TimeInterval(dwellMinutes * 60)
                    )
                    pendingPoint = nil
                },
                onCancel: { pendingPoint = nil }
            )
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

/// A point picked by search or long-press, awaiting category/dwell-duration
/// input before it becomes a persisted POI.
private struct PendingPOIPoint: Identifiable {
    let id = UUID()
    let title: String
    let coordinate: Coordinate
    let mapItemIdentifier: String?
}

/// One POI row: title plus inline category and dwell-duration controls.
private struct POIRow: View {
    let anchor: RTPCore.Anchor
    let viewModel: POIEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(anchor.title, systemImage: MapCanvasAnnotation.Style.poi.systemImage)

            HStack {
                Picker(
                    "Category",
                    selection: Binding(
                        get: { anchor.category ?? .other },
                        set: { viewModel.setCategory($0, for: anchor) }
                    )
                ) {
                    ForEach(POICategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()

                Stepper(
                    "\(Int(anchor.dwellDuration / 60)) min",
                    value: Binding(
                        get: { Int(anchor.dwellDuration / 60) },
                        set: { viewModel.setDwellDuration(TimeInterval($0 * 60), for: anchor) }
                    ),
                    in: 0...480,
                    step: 15
                )
            }
            .font(.subheadline)
        }
    }
}

/// A short form to set a category and dwell duration before a picked point
/// becomes a persisted POI.
private struct AddPOISheet: View {
    let point: PendingPOIPoint
    let onAdd: (POICategory?, Int) -> Void
    let onCancel: () -> Void

    @State private var category: POICategory = .sight
    @State private var dwellMinutes: Int = 45

    var body: some View {
        NavigationStack {
            Form {
                Section("Point") {
                    Text(point.title)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(POICategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
                Section("Dwell Time") {
                    Stepper("\(dwellMinutes) min", value: $dwellMinutes, in: 0...480, step: 15)
                }
            }
            .navigationTitle("Add POI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(category, dwellMinutes) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
    }
}
