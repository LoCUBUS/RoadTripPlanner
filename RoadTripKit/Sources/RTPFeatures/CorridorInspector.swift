import SwiftUI
import RTPCore
import RTPRouting

/// Phase 1 inspector: set start/destination, add/reorder/remove coarse
/// waypoints, and see a live route summary (docs/CONCEPT.md §1.5
/// "Phase 1 — Coarse route"). Map interaction (search/long-press) is routed
/// through `TripWorkspaceModel`, not owned here — this view only renders the
/// list of rows that make up the phase's disclosure group content in the
/// three-column workspace's inspector column. Reachable at any time, per
/// principle P1 — nothing here is gated behind `trip.currentPhase`.
public struct CorridorInspector: View {
    var viewModel: CorridorEditorViewModel

    public init(viewModel: CorridorEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if let start = viewModel.orderedAnchors.first(where: { $0.kind == .start }) {
                Label(start.title, systemImage: "flag.checkered.circle.fill")
            } else {
                Text("Search or long-press the map to set a start")
                    .foregroundStyle(.secondary)
            }

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

            if let destination = viewModel.orderedAnchors.first(where: { $0.kind == .destination }) {
                Label(destination.title, systemImage: "checkered.flag.circle.fill")
            } else {
                Text("Search or long-press the map to set a destination")
                    .foregroundStyle(.secondary)
            }

            Divider()

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
