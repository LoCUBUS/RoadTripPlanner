import SwiftUI
import RTPCore
import RTPProviders
import RTPRouting

/// Phase 2 inspector: add fixed POIs with a dwell duration and category, and
/// see the 10 km absorption rule apply to nearby Phase 1 waypoints
/// (docs/CONCEPT.md §1.5 "Phase 2 — Points of interest", §2.5). Mirrors the
/// Corridor inspector's own search field (rather than relying on the map's,
/// which was removed as redundant) — picking a result raises
/// `workspace.pendingPOIPoint`, the same path a map long-press uses, so the
/// category/dwell-duration sheet still appears before it becomes a POI.
/// Reachable at any time (P1) — nothing here is gated behind
/// `trip.currentPhase`.
public struct POIInspector: View {
    var workspace: TripWorkspaceModel
    @Bindable var poiSearchModel: POISearchModel
    var viewModel: POIEditorViewModel { workspace.poiViewModel }

    public init(workspace: TripWorkspaceModel) {
        self.workspace = workspace
        self.poiSearchModel = workspace.poiSearchModel
    }

    public var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Search for a POI, hotel, or address...", text: $poiSearchModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: poiSearchModel.query) { _, newValue in
                        poiSearchModel.updateQuery(newValue)
                    }

                if !poiSearchModel.search.results.isEmpty {
                    ForEach(poiSearchModel.search.results, id: \.id) { result in
                        SearchResultRow(result: result) {
                            selectSearchResult(result)
                        }
                    }
                }

                if poiSearchModel.search.isSearching {
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

            Divider()

            if let absorption = viewModel.lastAbsorption {
                HStack {
                    Label(
                        "Replaced \u{201C}\(absorption.waypointTitle)\u{201D} with \u{201C}\(absorption.poiTitle)\u{201D}",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    Spacer()
                    Button("Undo") { viewModel.undoLastAddition() }
                }
            }

            if viewModel.orderedMiddleAnchors.isEmpty {
                Text("Search above or long-press the map to add a POI.")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.orderedMiddleAnchors) { anchor in
                if anchor.kind == .poi {
                    POIRow(anchor: anchor, viewModel: viewModel)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.removePOI(anchor)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                } else {
                    Label(anchor.title, systemImage: MapCanvasAnnotation.Style.waypoint.systemImage)
                        .foregroundStyle(.secondary)
                }
            }
            .onMove { offsets, destination in
                viewModel.moveMiddleAnchors(fromOffsets: offsets, toOffset: destination)
            }

            Divider()

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

    // MARK: - Selection Handler

    /// Routes a search pick through the same path as a map long-press
    /// (`TripWorkspaceModel.handleSearchResult`), which raises
    /// `pendingPOIPoint` for the workspace shell's `AddPOISheet` — the
    /// active phase is already `.pointsOfInterest` whenever this inspector's
    /// search field is visible, so it applies the 10 km absorption rule the
    /// same way any other POI addition does.
    private func selectSearchResult(_ result: PlaceResult) {
        workspace.handleSearchResult(result)
        poiSearchModel.resetAfterPick()
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
/// becomes a persisted POI. Presented by the workspace shell as a sheet
/// bound to `TripWorkspaceModel.pendingPOIPoint`.
struct AddPOISheet: View {
    let point: PendingMapPoint
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
        .frame(minWidth: 360, minHeight: 320)
    }
}
