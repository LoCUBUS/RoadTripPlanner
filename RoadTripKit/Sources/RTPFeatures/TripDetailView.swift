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
                        Label("\(phase.displayName) may be out of date \u{2014} Recalculate", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
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
