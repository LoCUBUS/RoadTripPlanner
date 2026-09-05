import SwiftUI
import SwiftData
import RTPCore
import RTPFeatures

@main
struct RoadTripPlannerApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try RTPSchema.makeContainer()
        } catch {
            fatalError("Failed to create the SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TripListView()
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Trip") {
                    NotificationCenter.default.post(name: .newTripRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
