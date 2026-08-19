import Foundation
import Observation
import RTPCore
import RTPProviders

/// Drives the search field of `MapCanvasView`: debounces keystrokes, cancels
/// superseded requests, and turns provider results into a simple published
/// state. Kept independent of SwiftUI/MapKit rendering so it is unit
/// testable with `StubMapProvider` (docs/CONCEPT.md §2.3, §2.8).
@MainActor
@Observable
public final class MapSearchViewModel {
    public private(set) var results: [PlaceResult] = []
    public private(set) var isSearching = false
    public private(set) var errorMessage: String?

    private let provider: any MapProvider
    private let debounceNanoseconds: UInt64
    private var searchTask: Task<Void, Never>?

    public init(provider: any MapProvider, debounceNanoseconds: UInt64 = 300_000_000) {
        self.provider = provider
        self.debounceNanoseconds = debounceNanoseconds
    }

    /// Call on every keystroke. Cancels any in-flight search, waits out the
    /// debounce window, then searches near `region` unless superseded.
    public func updateQuery(_ text: String, region: MapRegion) {
        searchTask?.cancel()

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        searchTask = Task { [debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.performSearch(query: text, region: region)
        }
    }

    private func performSearch(query: String, region: MapRegion) async {
        isSearching = true
        do {
            let results = try await provider.search(query: query, near: region)
            guard !Task.isCancelled else { return }
            self.results = results
            self.errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.results = []
            self.errorMessage = "Search failed. Please try again."
        }
        isSearching = false
    }

    public func clear() {
        searchTask?.cancel()
        results = []
        errorMessage = nil
        isSearching = false
    }

    /// Awaits the currently in-flight debounce+search task, if any — for
    /// deterministic unit tests only.
    public func waitForPendingSearch() async {
        await searchTask?.value
    }
}
