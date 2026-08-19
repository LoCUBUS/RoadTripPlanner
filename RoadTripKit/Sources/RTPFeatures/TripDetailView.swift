import SwiftData
import SwiftUI
import RTPCore

/// Trip-level editing: rename, notes, and the current phase indicator.
/// The per-phase editors (corridor, POIs, overnights, summary, journal)
/// are built in their own work items and will replace the placeholder
/// section below.
public struct TripDetailView: View {
    @Bindable var trip: Trip

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
                Text("Corridor, POI, overnight, summary and journal editors land in their own work items.")
                    .foregroundStyle(.secondary)
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
