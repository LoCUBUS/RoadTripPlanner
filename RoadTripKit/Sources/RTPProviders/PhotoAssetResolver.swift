import Foundation
import RTPCore

/// Metadata extracted from a Photos library asset: just enough to create a
/// `TripPhoto` without ever copying the image itself (docs/CONCEPT.md §1.5
/// "Phase 5 — Journal": "only an asset identifier + capture date +
/// coordinate are stored").
public struct PhotoAssetMetadata: Sendable, Equatable {
    public var identifier: String
    public var captureDate: Date
    public var coordinate: Coordinate?

    public init(identifier: String, captureDate: Date, coordinate: Coordinate?) {
        self.identifier = identifier
        self.captureDate = captureDate
        self.coordinate = coordinate
    }
}

/// Abstraction over resolving `PhotosPicker`-selected item identifiers to
/// their capture date/location, kept separate from `MapProvider` (it isn't
/// map-related) but alongside it as the other platform-facing provider
/// abstraction (docs/CONCEPT.md §2.3, principle P5).
public protocol PhotoAssetResolver: Sendable {
    func metadata(for identifiers: [String]) async -> [PhotoAssetMetadata]
}
