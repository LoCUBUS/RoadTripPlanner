import SwiftUI
import RTPCore

/// Placeholder root view. Replaced by the trip list / trip detail
/// NavigationSplitView shell in the `trip-crud` work item.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("RoadTripPlanner")
                .font(.title)
            Text("Phase \(Phase.corridor.rawValue) of \(Phase.allCases.count): Corridor")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
