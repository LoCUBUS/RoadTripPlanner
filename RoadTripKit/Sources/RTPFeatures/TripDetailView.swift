import SwiftData
import SwiftUI
import RTPCore
import RTPProviders
import RTPRouting

/// Trip-level editing: rename, notes, and the current phase indicator.
/// The Phase 1 corridor editor is wired in below; POI/overnight/summary/
/// journal editors land in their own work items.
public struct TripDetailView: View {
    @Bindable var trip: Trip
    private let mapProvider: any MapProvider = AppleMapsProvider()
    private let photoAssetResolver: any PhotoAssetResolver = PHPhotoAssetResolver()
    private let routeCoordinator: RouteCoordinator

    @State private var recalculatingPhase: Phase?

    public init(trip: Trip) {
        self.trip = trip
        self.routeCoordinator = RouteCoordinator(provider: AppleMapsProvider())
    }

    public var body: some View {
        Form {
            Section("Trip") {
                TextField("Name", text: $trip.name)
                    .onSubmit { trip.updatedAt = .now }
                TextField("Notes", text: $trip.notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Phase") {
                Picker("Current Phase", selection: $trip.currentPhase) {
                    ForEach(Phase.allCases, id: \.self) { phase in
                        Text(phase.displayName).tag(phase)
                    }
                }
                .pickerStyle(.segmented)

                if let reviewedPhases = reviewBanners, !reviewedPhases.isEmpty {
                    ForEach(reviewedPhases, id: \.self) { phase in
                        VStack(alignment: .leading, spacing: 4) {
                            Label("\(phase.displayName) may be out of date", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            HStack {
                                Button {
                                    Task { await recalculate(phase) }
                                } label: {
                                    if recalculatingPhase == phase {
                                        ProgressView()
                                    } else {
                                        Text("Recalculate")
                                    }
                                }
                                .disabled(recalculatingPhase != nil)
                                Button("Dismiss") {
                                    trip.markReviewed(phase)
                                }
                                .disabled(recalculatingPhase != nil)
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    CorridorEditorView(trip: trip, routeCoordinator: routeCoordinator, provider: mapProvider)
                } label: {
                    Label("Edit Corridor", systemImage: "map")
                }
                NavigationLink {
                    POIEditorView(trip: trip, routeCoordinator: routeCoordinator, provider: mapProvider)
                } label: {
                    Label("Edit Points of Interest", systemImage: "star.circle")
                }
                NavigationLink {
                    DayPlannerView(trip: trip, routeCoordinator: routeCoordinator, provider: mapProvider)
                } label: {
                    Label("Plan Overnights", systemImage: "bed.double")
                }
                NavigationLink {
                    SummaryView(trip: trip, mapProvider: mapProvider)
                } label: {
                    Label("View Summary", systemImage: "list.bullet.rectangle")
                }
                NavigationLink {
                    PhotoJournalView(trip: trip, assetResolver: photoAssetResolver, mapProvider: mapProvider)
                } label: {
                    Label("Journal", systemImage: "photo.on.rectangle.angled")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(trip.name.isEmpty ? "Untitled Trip" : trip.name)
    }

    private var reviewBanners: [Phase]? {
        let flagged = trip.phaseStatus.filter { $0.value.needsReview }.keys.sorted()
        return flagged.isEmpty ? nil : flagged
    }

    /// Recalculates the data a flagged phase depends on, then clears its
    /// review flag — never deleting anything (docs/CONCEPT.md §1.6,
    /// principle P2). Corridor/POI edits invalidate cached route legs, so
    /// those two phases re-run `RouteRecalculator`. Overnights re-segments
    /// its currently open day, if any. Summary and journal hold user-entered
    /// state (visited/comment/rating/captions) that upstream edits never
    /// invalidate directly, so dismissing simply clears the flag.
    private func recalculate(_ phase: Phase) async {
        recalculatingPhase = phase
        defer { recalculatingPhase = nil }

        switch phase {
        case .corridor, .pointsOfInterest:
            _ = await RouteRecalculator.recalculate(trip: trip, using: routeCoordinator)
        case .overnights:
            if let openDay = trip.days.sorted(by: { $0.index < $1.index }).first(where: { $0.endAnchorID == nil }) {
                trip.recomputeTimeUpPoint(for: openDay)
            }
        case .summary, .journal:
            break
        }
        trip.markReviewed(phase)
    }
}

#Preview {
    let container = try! RTPSchema.makeContainer(inMemory: true)
    let trip = Trip(name: "Munich to Lisbon")
    container.mainContext.insert(trip)
    return NavigationStack {
        TripDetailView(trip: trip)
    }
    .modelContainer(container)
}
