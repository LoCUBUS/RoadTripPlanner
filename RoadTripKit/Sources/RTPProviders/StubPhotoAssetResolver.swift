import Foundation
import RTPCore

/// A deterministic, in-memory `PhotoAssetResolver` used by unit tests
/// (docs/CONCEPT.md §2.3, §2.8) — mirrors `StubMapProvider`.
public final class StubPhotoAssetResolver: PhotoAssetResolver, @unchecked Sendable {
    public var metadataByIdentifier: [String: PhotoAssetMetadata] = [:]

    public init() {}

    public func metadata(for identifiers: [String]) async -> [PhotoAssetMetadata] {
        identifiers.compactMap { metadataByIdentifier[$0] }
    }
}
