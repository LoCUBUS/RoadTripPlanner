import SwiftUI
import RTPCore
import RTPRouting

/// Phase 3 inspector: set a daily travel-time budget, see the time-up point
/// where it runs out, search for lodging there (or drop a pin manually via
/// the map), and resolve a dwell-time overrun (docs/CONCEPT.md §1.5
/// "Phase 3 — Overnight stays", §2.6). Map long-presses are routed through
/// `TripWorkspaceModel`, which raises `pendingLodgingPoint` for the
/// workspace shell to present `LodgingNameSheet` for. Reachable at any time
/// (P1).
public struct DayPlannerInspector: View {
    @Bindable var viewModel: DayPlannerViewModel

    @State private var budgetHours: Double = 5
    @State private var shortenDwellMinutes: Int = 30

    public init(viewModel: DayPlannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if let day = viewModel.openDay {
                openDaySections(day)
            } else if viewModel.canStartNextDay {
                startDaySection
            } else {
                Text("All days are planned — the trip reaches its destination.")
                    .foregroundStyle(.secondary)
            }

            if !viewModel.closedDays.isEmpty {
                Divider()
                Text("Planned Days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.closedDays) { day in
                    DaySummaryRow(day: day)
                }
            }

            if let error = viewModel.recalculationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Sections

    private var startDaySection: some View {
        Group {
            Stepper("Budget: \(String(format: "%.1f", budgetHours)) h", value: $budgetHours, in: 1...16, step: 0.5)
            Button("Start Day \(viewModel.days.count + 1)") {
                viewModel.startNextDay(budget: budgetHours * 3600)
            }
        }
    }

    @ViewBuilder
    private func openDaySections(_ day: TripDay) -> some View {
        Text("Day \(day.index + 1)")
            .font(.headline)
        Stepper(
            "Budget: \(String(format: "%.1f", day.budget / 3600)) h",
            value: Binding(
                get: { day.budget / 3600 },
                set: { viewModel.updateBudget(day: day, budget: $0 * 3600) }
            ),
            in: 1...16,
            step: 0.5
        )

        if viewModel.isRecalculating {
            ProgressView("Recalculating route…")
        }

        if let outcome = viewModel.lastSegmentation?.outcome {
            switch outcome {
            case .reachedBudget:
                lodgingSearchSection(day)
            case .dwellOverrun(let anchorID, let anchorTitle, _, let overshoot):
                dwellOverrunSection(day: day, anchorID: anchorID, anchorTitle: anchorTitle, overshoot: overshoot)
            case .legNotYetResolved:
                Text("Some legs haven't been routed yet.")
                    .foregroundStyle(.secondary)
                Button {
                    Task { await viewModel.recalculateRoute() }
                } label: {
                    Label("Recalculate Route", systemImage: "arrow.triangle.2.circlepath")
                }
            case .reachedDestination:
                EmptyView() // openNextDay/recomputeTimeUpPoint auto-closes this case.
            }
        }
    }

    private func lodgingSearchSection(_ day: TripDay) -> some View {
        Group {
            Divider()
            Text("Overnight Near Time-Up Point")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Lodging categories only", isOn: $viewModel.lodgingCategoryFilterEnabled)

            Stepper(
                "Search radius: \(Int(day.searchRadiusMeters / 1000)) km",
                value: Binding(
                    get: { day.searchRadiusMeters / 1000 },
                    set: { viewModel.setSearchRadius($0 * 1000, for: day) }
                ),
                in: 5...50,
                step: 5
            )

            Button {
                guard let point = day.timeUpPoint else { return }
                Task { await viewModel.searchLodging(near: point, radiusMeters: day.searchRadiusMeters) }
            } label: {
                if viewModel.isSearchingLodging {
                    ProgressView()
                } else {
                    Label("Search Lodging", systemImage: "magnifyingglass")
                }
            }
            .disabled(day.timeUpPoint == nil || viewModel.isSearchingLodging)

            if let error = viewModel.lodgingSearchError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            } else if viewModel.hasSearchedLodging && viewModel.lodgingResults.isEmpty && !viewModel.isSearchingLodging {
                Text("No lodging found nearby. Try widening the search radius or long-press the map to drop a pin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.lodgingResults) { result in
                Button {
                    guard let afterID = viewModel.lodgingInsertionAnchorID(for: day) else { return }
                    viewModel.closeDay(day, afterAnchorID: afterID, title: result.title, coordinate: result.coordinate, mapItemIdentifier: result.mapItemIdentifier, category: result.category)
                } label: {
                    VStack(alignment: .leading) {
                        Text(result.title)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("Long-press the map to drop a pin instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func dwellOverrunSection(day: TripDay, anchorID: UUID, anchorTitle: String, overshoot: TimeInterval) -> some View {
        Group {
            Divider()
            Text("\u{201C}\(anchorTitle)\u{201D} Doesn't Fit Today's Budget")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Staying the full dwell time would overshoot the budget by \(Int(overshoot / 60)) min.")
                .foregroundStyle(.secondary)

            Button("Overshoot the budget") {
                viewModel.resolveOvershoot(day: day, anchorID: anchorID)
            }
            Button("End the day before this stop") {
                viewModel.resolveEndDayBeforeAnchor(day: day, anchorID: anchorID)
            }

            Stepper("Shorten dwell to \(shortenDwellMinutes) min", value: $shortenDwellMinutes, in: 0...480, step: 15)
            Button("Shorten dwell time") {
                viewModel.resolveShortenDwell(day: day, anchorID: anchorID, newDwellDuration: TimeInterval(shortenDwellMinutes * 60))
            }
        }
    }
}

/// A short form to name a manually dropped lodging pin. Presented by the
/// workspace shell as a sheet bound to `TripWorkspaceModel.pendingLodgingPoint`.
struct LodgingNameSheet: View {
    let point: PendingMapPoint
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Lodging name", text: $title)
            }
            .navigationTitle("Add Lodging")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(title.isEmpty ? point.title : title) }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }
}

/// One row per closed day: its budget, driving distance/time, and lodging.
private struct DaySummaryRow: View {
    let day: TripDay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Day \(day.index + 1)")
                .font(.headline)
            Text("Budget: \(String(format: "%.1f", day.budget / 3600)) h")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
