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
                onAdd: { category, dwellMinutes, isOvernightCandidate in
                    workspace.poiViewModel.addPOI(
                        title: point.title,
                        coordinate: point.coordinate,
                        mapItemIdentifier: point.mapItemIdentifier,
                        category: category,
                        dwellDuration: TimeInterval(dwellMinutes * 60),
                        isOvernightCandidate: isOvernightCandidate
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
            if let notice = workspace.dayPlannerViewModel.lastAutoPromotedOvernight {
                autoPromotedOvernightBanner(notice)
            }
            MapCanvasView(
                annotations: workspace.mapAnnotations,
                routePolylines: workspace.routePolylines,
                searchRegion: workspace.searchRegion,
                mapProvider: workspace.mapProvider,
                featureSelectionEnabled: workspace.activePhase == .pointsOfInterest,
                onLongPress: workspace.handleLongPress,
                onAddFeatureAsPOI: { details in
                    workspace.poiViewModel.addPOI(
                        title: details.title,
                        coordinate: details.coordinate,
                        mapItemIdentifier: details.mapItemIdentifier,
                        category: details.category,
                        dwellDuration: 45 * 60,
                        isOvernightCandidate: false
                    )
                },
                onAddFeatureAsOvernight: { details in
                    workspace.poiViewModel.addPOI(
                        title: details.title,
                        coordinate: details.coordinate,
                        mapItemIdentifier: details.mapItemIdentifier,
                        category: details.category?.isLodging == true ? details.category : .hotel,
                        dwellDuration: 0,
                        isOvernightCandidate: true
                    )
                }
            )
        }
    }

    private var inspectorColumn: some View {
        List {
            phaseDisclosure(.corridor, icon: "map") {
                CorridorInspector(viewModel: workspace.corridorViewModel, corridorSearchModel: workspace.corridorSearchModel)
            }
            phaseDisclosure(.pointsOfInterest, icon: "star.circle") {
                POIInspector(workspace: workspace)
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

    /// Shown after `DayPlannerViewModel` automatically closes a day with a
    /// Phase-2 overnight candidate that fit the time budget's tolerance
    /// (docs/CONCEPT.md §2.6 "Overnight candidates") — undoable, since the
    /// promotion happens without an explicit user action.
    private func autoPromotedOvernightBanner(_ notice: AutoPromotedOvernightNotice) -> some View {
        HStack(spacing: 8) {
            Label("\u{201C}\(notice.anchorTitle)\u{201D} was automatically used as tonight's overnight stay", systemImage: "bed.double.fill")
                .foregroundStyle(.blue)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Undo") {
                workspace.dayPlannerViewModel.undoAutoPromotedOvernight()
            }
            Button("Dismiss") {
                workspace.dayPlannerViewModel.dismissAutoPromotedOvernightNotice()
            }
        }
        .font(.footnote)
        .padding(10)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
    }

    /// A single compact row rather than one banner per flagged phase: an
    /// upstream edit typically flags several phases at once, and stacking a
    /// full-width row with its own buttons for each of them buries the map.
    private var reviewBanner: some View {
        let phases = workspace.reviewBanners
        let message = "\(phases.map(\.displayName).formatted(.list(type: .and))) may be out of date"

        return HStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Recalculate") {
                Task { await workspace.recalculateFlaggedPhases() }
            }
            .disabled(workspace.recalculatingPhase != nil)
            Button("Dismiss") {
                workspace.dismissReviewBanners()
            }
            .disabled(workspace.recalculatingPhase != nil)
        }
        .font(.footnote)
        .padding(10)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }
}
