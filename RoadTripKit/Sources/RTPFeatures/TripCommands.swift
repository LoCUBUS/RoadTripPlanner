import Foundation

/// Cross-cutting "create a new trip" signal, so the app's File menu command
/// (defined at the `App` scene level, which has no access to
/// `TripListView`'s own `@State`/`modelContext`) can trigger the same
/// creation path `TripListView` itself uses for its sidebar footer button
/// and list context menu — one place decides what "new trip" means
/// (insert + select), regardless of which affordance triggered it.
public extension Notification.Name {
    static let newTripRequested = Notification.Name("RTPNewTripRequested")
}
