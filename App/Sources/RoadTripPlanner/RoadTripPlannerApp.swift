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
        .modelContainer(container)
    }
}
