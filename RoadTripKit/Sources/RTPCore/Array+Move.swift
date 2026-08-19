import Foundation

/// A minimal re-implementation of `RangeReplaceableCollection.move(fromOffsets:toOffset:)`
/// (normally provided by SwiftUI/Foundation for `List.onMove`) so `RTPCore`
/// can reorder anchors without importing SwiftUI — the domain layer stays
/// UI-framework-free (docs/CONCEPT.md §2.8).
extension Array {
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let elementsToMove = source.map { self[$0] }
        var remaining = self
        for index in source.sorted(by: >) {
            remaining.remove(at: index)
        }
        // Recompute the insertion point after removal: every source index
        // strictly before `destination` shifts the target left by one.
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let adjustedDestination = Swift.max(0, Swift.min(remaining.count, destination - removedBeforeDestination))
        remaining.insert(contentsOf: elementsToMove, at: adjustedDestination)
        self = remaining
    }
}
