import SwiftUI
import RTPCore
import RTPProviders

/// Persistent map and phase-inspector surface for the macOS three-column
/// workspace. The sidebar owns trip selection; this view owns the selected
/// trip's shared map/inspector state.
public struct TripWorkspaceView: View {
    @Bindable private var workspace: TripWorkspaceModel

    public init(workspace: TripWorkspaceModel) {
        self.workspace = workspace
    }

    public var body: some View {
        HSplitView {
            mapColumn
                .frame(minWidth: 520, idealWidth: 800)
            inspectorColumn
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
        }
        .navigationTitle(workspace.trip.name.isEmpty ? "Untitled Trip" : workspace.trip.name)
        .sheet(item: $workspace.pendingPOIPoint) { point in
            AddPOISheet(
                point: point,
                onAdd: { category, dwellMinutes in
                    workspace.poiViewModel.addPOI(
                        title: point.title,
                        coordinate: point.coordinate,
                        mapItemIdentifier: point.mapItemIdentifier,
                        category: category,
                        dwellDuration: TimeInterval(dwellMinutes * 60)
                    )
                    workspace.pendingPOIPoint = nil
                },
                onCancel: { workspace.pendingPOIPoint = nil }
            )
        }
        .sheet(item: $workspace.pendingLodgingPoint) { point in
            LodgingNameSheet(
                point: point,
                onAdd: { title in
                    guard
                        let day = workspace.dayPlannerViewModel.openDay,
                        let afterID = workspace.dayPlannerViewModel.lodgingInsertionAnchorID(for: day)
                    else {
                        workspace.pendingLodgingPoint = nil
                        return
                    }
                    workspace.dayPlannerViewModel.closeDay(
                        day,
                        afterAnchorID: afterID,
                        title: title,
                        coordinate: point.coordinate,
                        mapItemIdentifier: point.mapItemIdentifier
                    )
                    workspace.pendingLodgingPoint = nil
                },
                onCancel: { workspace.pendingLodgingPoint = nil }
            )
        }
    }

    private var mapColumn: some View {
        VStack(spacing: 0) {
            if !workspace.reviewBanners.isEmpty {
                reviewBanner
            }
            MapCanvasView(
                annotations: workspace.mapAnnotations,
                routePolylines: workspace.routePolylines,
                searchRegion: workspace.searchRegion,
                provider: workspace.mapProvider,
                onSelectSearchResult: workspace.handleSearchResult,
                onLongPress: workspace.handleLongPress
            )
        }
    }

    private var inspectorColumn: some View {
        List {
            phaseDisclosure(.corridor, icon: "map") {
                CorridorInspector(viewModel: workspace.corridorViewModel)
            }
            phaseDisclosure(.pointsOfInterest, icon: "star.circle") {
                POIInspector(viewModel: workspace.poiViewModel)
            }
            phaseDisclosure(.overnights, icon: "bed.double") {
                DayPlannerInspector(viewModel: workspace.dayPlannerViewModel)
            }
            phaseDisclosure(.summary, icon: "list.bullet.rectangle") {
                SummaryInspector(viewModel: workspace.summaryViewModel)
            }
            phaseDisclosure(.journal, icon: "photo.on.rectangle.angled") {
                JournalInspector(workspace: workspace)
            }
        }
        .listStyle(.sidebar)
    }

    private func phaseDisclosure<Content: View>(
        _ phase: Phase,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { workspace.expandedPhases.contains(phase) },
                set: { workspace.setExpanded($0, for: phase) }
            )
        ) {
            content()
        } label: {
            HStack {
                Label(phase.displayName, systemImage: icon)
                if workspace.activePhase == phase {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Active phase")
                }
            }
        }
    }

    private var reviewBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(workspace.reviewBanners, id: \.self) { phase in
                HStack {
                    Label("\(phase.displayName) may be out of date", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Recalculate") {
                        Task { await workspace.recalculate(phase) }
                    }
                    .disabled(workspace.recalculatingPhase != nil)
                    Button("Dismiss") {
                        workspace.trip.markReviewed(phase)
                    }
                    .disabled(workspace.recalculatingPhase != nil)
                }
            }
        }
        .font(.footnote)
        .padding(10)
        .background(.thinMaterial)
    }
}
