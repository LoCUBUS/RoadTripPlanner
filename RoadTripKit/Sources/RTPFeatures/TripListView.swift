import SwiftData
import SwiftUI
import RTPCore

/// The trip management shell: list, create, rename (in the detail view),
/// duplicate and delete (docs/CONCEPT.md §1.5 "Trip management"). Adapts to
/// a `NavigationSplitView` on iPad/Mac and a stacked navigation on iPhone
/// automatically, since `NavigationSplitView` collapses on compact width
/// classes.
public struct TripListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.updatedAt, order: .reverse) private var trips: [Trip]

    @State private var selection: Trip?
    @State private var tripPendingDeletion: Trip?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(trips) { trip in
                    NavigationLink(value: trip) {
                        TripRow(trip: trip)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            tripPendingDeletion = trip
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            duplicate(trip)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            tripPendingDeletion = trip
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView(
                        "No Trips Yet",
                        systemImage: "map",
                        description: Text("Tap + to plan your first road trip.")
                    )
                }
            }
            .toolbar {
                ToolbarItem {
                    Button(action: createTrip) {
                        Label("New Trip", systemImage: "plus")
                    }
                }
            }
            .confirmationDialog(
                "Delete Trip",
                isPresented: Binding(
                    get: { tripPendingDeletion != nil },
                    set: { isPresented in if !isPresented { tripPendingDeletion = nil } }
                ),
                presenting: tripPendingDeletion
            ) { trip in
                Button("Delete \u{201C}\(trip.name)\u{201D}", role: .destructive) {
                    delete(trip)
                }
                Button("Cancel", role: .cancel) {}
            } message: { trip in
                Text("This removes all stops, days and photos in \u{201C}\(trip.name)\u{201D}. This can't be undone.")
            }
        } detail: {
            if let selection {
                TripDetailView(trip: selection)
            } else {
                ContentUnavailableView("Select a Trip", systemImage: "map")
            }
        }
    }

    private func createTrip() {
        let trip = Trip()
        modelContext.insert(trip)
        selection = trip
    }

    private func duplicate(_ trip: Trip) {
        let copy = trip.duplicate()
        modelContext.insert(copy)
        selection = copy
    }

    private func delete(_ trip: Trip) {
        if selection?.persistentModelID == trip.persistentModelID {
            selection = nil
        }
        modelContext.delete(trip)
        tripPendingDeletion = nil
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.name.isEmpty ? "Untitled Trip" : trip.name)
                .font(.headline)
            Text("\(trip.currentPhase.displayName) \u{00B7} \(trip.anchors.count) stops")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    TripListView()
        .modelContainer(try! RTPSchema.makeContainer(inMemory: true))
}
