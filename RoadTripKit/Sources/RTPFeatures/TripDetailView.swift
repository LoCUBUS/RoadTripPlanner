import SwiftData
import SwiftUI
import RTPCore
import RTPProviders

/// Trip-level editing: rename, notes, and the current phase indicator.
/// The per-phase editors (corridor, POIs, overnights, summary, journal)
/// are built in their own work items and will replace the placeholder
/// section below. A read-only "Show on Map" sheet exercises the shared
/// `MapCanvasView` component ahead of that per-phase wiring.
public struct TripDetailView: View {
    @Bindable var trip: Trip
    @State private var showsMap = false
    private let mapProvider: any MapProvider = AppleMapsProvider()

    public init(trip: Trip) {
        self.trip = trip
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
                Button {
                    showsMap = true
                } label: {
                    Label("Show on Map", systemImage: "map")
                }
                Text("Corridor, POI, overnight, summary and journal editors land in their own work items.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(trip.name.isEmpty ? "Untitled Trip" : trip.name)
        .sheet(isPresented: $showsMap) {
            NavigationStack {
                MapCanvasView(
                    annotations: trip.anchors.sorted { $0.order < $1.order }.map(MapCanvasAnnotation.init(anchor:)),
                    searchRegion: mapRegion,
                    provider: mapProvider
                )
                .navigationTitle("Map")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showsMap = false }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 500)
            #endif
        }
    }

    /// A reasonable default region for the map sheet: centred on the first
    /// anchor if the trip has one, otherwise a wide view of central Europe.
    private var mapRegion: MapRegion {
        if let first = trip.anchors.sorted(by: { $0.order < $1.order }).first {
            return MapRegion(center: first.coordinate, latitudeDelta: 5, longitudeDelta: 5)
        }
        return MapRegion(center: Coordinate(latitude: 48.1351, longitude: 11.5820), latitudeDelta: 10, longitudeDelta: 10)
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
