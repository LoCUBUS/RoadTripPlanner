import SwiftUI
import RTPCore
import RTPRouting
import RTPProviders

/// Phase 1 inspector: set start/destination via search fields, add/reorder/remove
/// coarse waypoints, and see live route summary (docs/CONCEPT.md §1.5
/// "Phase 1 — Coarse route"). Map interaction (search/long-press) is routed
/// through `TripWorkspaceModel`, not owned here — this view only renders the
/// list of rows that make up the phase's disclosure group content in the
/// three-column workspace's inspector column. Reachable at any time, per
/// principle P1 — nothing here is gated behind `trip.currentPhase`.
public struct CorridorInspector: View {
    var viewModel: CorridorEditorViewModel
    @Bindable var corridorSearchModel: CorridorSearchModel

    public init(
        viewModel: CorridorEditorViewModel,
        corridorSearchModel: CorridorSearchModel
    ) {
        self.viewModel = viewModel
        self.corridorSearchModel = corridorSearchModel
    }

    public var body: some View {
        Group {
            // MARK: - Start Point Search
            VStack(alignment: .leading, spacing: 4) {
                Text("Start")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let start = viewModel.orderedAnchors.first(where: { $0.kind == .start }) {
                    HStack {
                        Label(start.title, systemImage: "flag.checkered.circle.fill")
                        Spacer()
                        Button(action: { clearStart() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                } else {
                    TextField("Search start location...", text: $corridorSearchModel.startQuery)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: corridorSearchModel.startQuery) { oldValue, newValue in
                            corridorSearchModel.updateStartQuery(newValue)
                        }
                    
                    if !corridorSearchModel.startSearch.results.isEmpty {
                        ForEach(corridorSearchModel.startSearch.results, id: \.id) { result in
                            SearchResultRow(result: result) {
                                selectStart(result: result)
                            }
                        }
                    }
                    
                    if corridorSearchModel.startSearch.isSearching {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Searching...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Divider()

            // MARK: - Destination Search
            VStack(alignment: .leading, spacing: 4) {
                Text("Destination")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let destination = viewModel.orderedAnchors.first(where: { $0.kind == .destination }) {
                    HStack {
                        Label(destination.title, systemImage: "checkered.flag.circle.fill")
                        Spacer()
                        Button(action: { clearDestination() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                } else {
                    TextField("Search destination...", text: $corridorSearchModel.destinationQuery)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: corridorSearchModel.destinationQuery) { oldValue, newValue in
                            corridorSearchModel.updateDestinationQuery(newValue)
                        }
                    
                    if !corridorSearchModel.destinationSearch.results.isEmpty {
                        ForEach(corridorSearchModel.destinationSearch.results, id: \.id) { result in
                            SearchResultRow(result: result) {
                                selectDestination(result: result)
                            }
                        }
                    }
                    
                    if corridorSearchModel.destinationSearch.isSearching {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Searching...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Divider()

            // MARK: - Waypoints
            VStack(alignment: .leading, spacing: 4) {
                Text("Waypoints")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                let hasStartAndDestination = viewModel.orderedAnchors.contains { $0.kind == .start } &&
                                           viewModel.orderedAnchors.contains { $0.kind == .destination }
                
                if hasStartAndDestination {
                    TextField("Search waypoint location...", text: $corridorSearchModel.waypointQuery)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: corridorSearchModel.waypointQuery) { oldValue, newValue in
                            corridorSearchModel.updateWaypointQuery(newValue)
                        }
                    
                    if !corridorSearchModel.waypointSearch.results.isEmpty {
                        ForEach(corridorSearchModel.waypointSearch.results, id: \.id) { result in
                            SearchResultRow(result: result) {
                                selectWaypoint(result: result)
                            }
                        }
                    }
                    
                    if corridorSearchModel.waypointSearch.isSearching {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Searching...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Text("Add start and destination first")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.vertical, 4)
                }
                
                if !viewModel.orderedMiddleAnchors.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    
                    ForEach(viewModel.orderedMiddleAnchors) { anchor in
                        Label(anchor.title, systemImage: "mappin.circle.fill")
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.removeAnchor(anchor)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                    .onMove { offsets, destination in
                        viewModel.moveMiddleAnchors(fromOffsets: offsets, toOffset: destination)
                    }
                }
            }

            Divider()

            // MARK: - Route Summary
            if viewModel.trip.legs.isEmpty {
                Text("Add start, destination, and waypoints to calculate the route")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                LabeledContent("Distance", value: distanceText)
                LabeledContent("Driving time", value: durationText)
                
                if viewModel.hasStaleLegs {
                    Label("One or more legs use a straight-line estimate", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                
                if viewModel.isRecalculating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Updating route...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

    // MARK: - Selection Handlers
    
    private func selectStart(result: PlaceResult) {
        viewModel.setStart(
            title: result.title,
            coordinate: result.coordinate,
            mapItemIdentifier: result.mapItemIdentifier
        )
        corridorSearchModel.resetStartAfterPick()
    }

    private func selectDestination(result: PlaceResult) {
        viewModel.setDestination(
            title: result.title,
            coordinate: result.coordinate,
            mapItemIdentifier: result.mapItemIdentifier
        )
        corridorSearchModel.resetDestinationAfterPick()
    }

    private func selectWaypoint(result: PlaceResult) {
        viewModel.addWaypoint(
            title: result.title,
            coordinate: result.coordinate,
            mapItemIdentifier: result.mapItemIdentifier
        )
        corridorSearchModel.resetWaypointAfterPick()
    }

    private func clearStart() {
        if let start = viewModel.orderedAnchors.first(where: { $0.kind == .start }) {
            viewModel.removeAnchor(start)
        }
    }

    private func clearDestination() {
        if let destination = viewModel.orderedAnchors.first(where: { $0.kind == .destination }) {
            viewModel.removeAnchor(destination)
        }
    }

    // MARK: - Formatting

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

// MARK: - Search Result Row Helper

struct SearchResultRow: View {
    let result: PlaceResult
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}
