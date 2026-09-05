import SwiftData
import SwiftUI
import RTPCore
import RTPProviders

/// The macOS trip-management sidebar and persistent three-column workspace.
public struct TripListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.updatedAt, order: .reverse) private var trips: [Trip]

    @State private var selection: Trip?
    @State private var workspace: TripWorkspaceModel?
    @State private var tripPendingDeletion: Trip?
    @State private var tripPendingRename: Trip?
    @State private var renameText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            if let workspace {
                TripWorkspaceView(workspace: workspace)
            } else {
                ContentUnavailableView("Select a Trip", systemImage: "map")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { selectInitialTrip() }
        .onChange(of: selection?.persistentModelID) { _, _ in
            updateWorkspace()
        }
        .sheet(item: $tripPendingRename) { trip in
            RenameTripSheet(
                name: Binding(
                    get: { trip.name },
                    set: { trip.name = $0 }
                ),
                onCancel: { tripPendingRename = nil },
                onSave: {
                    trip.updatedAt = .now
                    tripPendingRename = nil
                }
            )
        }
        .confirmationDialog(
            "Delete Trip",
            isPresented: Binding(
                get: { tripPendingDeletion != nil },
                set: { if !$0 { tripPendingDeletion = nil } }
            ),
            presenting: tripPendingDeletion
        ) { trip in
            Button("Delete \"\(trip.name.isEmpty ? "Untitled Trip" : trip.name)\"", role: .destructive) {
                delete(trip)
            }
            Button("Cancel", role: .cancel) {}
        } message: { trip in
            Text("This removes all stops, days and photos in this trip. This can't be undone.")
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(trips) { trip in
                TripRow(trip: trip)
                    .tag(trip)
                    .contextMenu {
                        Button { rename(trip) } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button { duplicate(trip) } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) { tripPendingDeletion = trip } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Trips")
        .overlay {
            if trips.isEmpty {
                ContentUnavailableView("No Trips Yet", systemImage: "map", description: Text("Create a trip to get started."))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: createTrip) {
                    Label("New Trip", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                if selection != nil {
                    Button { duplicate(selection!) } label: {
                        Label("Duplicate Trip", systemImage: "plus.square.on.square")
                    }
                    .keyboardShortcut("d", modifiers: .command)
                }
            }
        }
    }

    private func selectInitialTrip() {
        if selection == nil {
            selection = trips.first
        }
        updateWorkspace()
    }

    private func updateWorkspace() {
        guard let trip = selection else {
            workspace = nil
            return
        }
        if workspace?.trip.persistentModelID != trip.persistentModelID {
            workspace = TripWorkspaceModel(
                trip: trip,
                mapProvider: AppleMapsProvider(),
                photoAssetResolver: PHPhotoAssetResolver()
            )
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

    private func rename(_ trip: Trip) {
        renameText = trip.name
        tripPendingRename = trip
    }

    private func delete(_ trip: Trip) {
        if selection?.persistentModelID == trip.persistentModelID {
            selection = trips.first(where: { $0.persistentModelID != trip.persistentModelID })
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
            Text("\(trip.currentPhase.displayName) · \(trip.anchors.count) stops")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct RenameTripSheet: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Trip").font(.headline)
            TextField("Trip name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
