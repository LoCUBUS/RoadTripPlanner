import Foundation
import Photos
import RTPCore

/// The v1 `PhotoAssetResolver`: resolves `PhotosPicker`-selected item
/// identifiers to their `PHAsset` capture date and location via
/// `PHAsset.fetchAssets(withLocalIdentifiers:options:)`
/// (docs/CONCEPT.md §1.5 "Phase 5 — Journal").
public final class PHPhotoAssetResolver: PhotoAssetResolver, @unchecked Sendable {
    public init() {}

    public func metadata(for identifiers: [String]) async -> [PhotoAssetMetadata] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var metadata: [PhotoAssetMetadata] = []
        result.enumerateObjects { asset, _, _ in
            metadata.append(
                PhotoAssetMetadata(
                    identifier: asset.localIdentifier,
                    captureDate: asset.creationDate ?? .distantPast,
                    coordinate: asset.location.map { Coordinate($0.coordinate) }
                )
            )
        }
        return metadata
    }
}
