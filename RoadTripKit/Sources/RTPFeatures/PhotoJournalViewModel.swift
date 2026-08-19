import Foundation
import Observation
import RTPCore
import RTPProviders

/// Drives Phase 5's travel journal: importing `PhotosPicker`-selected
/// assets (resolved to capture date/coordinate by a `PhotoAssetResolver`,
/// never copying image data), captioning them, and manually pinning photos
/// that had no location metadata (docs/CONCEPT.md §1.5 "Phase 5 —
/// Journal").
@MainActor
@Observable
public final class PhotoJournalViewModel {
    public let trip: Trip
    private let assetResolver: any PhotoAssetResolver

    public private(set) var isImporting = false

    public init(trip: Trip, assetResolver: any PhotoAssetResolver) {
        self.trip = trip
        self.assetResolver = assetResolver
    }

    /// All journal photos, oldest capture first.
    public var photos: [TripPhoto] {
        trip.photos.sorted { $0.captureDate < $1.captureDate }
    }

    /// Photos with a coordinate — rendered as map pins.
    public var pinnedPhotos: [TripPhoto] {
        photos.filter { $0.coordinate != nil }
    }

    /// Photos without a coordinate yet — need a manual pin.
    public var unpinnedPhotos: [TripPhoto] {
        photos.filter { $0.coordinate == nil }
    }

    /// Resolves `identifiers` (from `PhotosPickerItem.itemIdentifier`) and
    /// adds a `TripPhoto` for each, auto-associated with the nearest
    /// day/stop. Duplicate imports of an already-added asset are skipped.
    public func importPhotos(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        let existingIdentifiers = Set(trip.photos.map(\.assetLocalIdentifier))
        let newIdentifiers = identifiers.filter { !existingIdentifiers.contains($0) }
        guard !newIdentifiers.isEmpty else { return }

        let metadata = await assetResolver.metadata(for: newIdentifiers)
        for item in metadata {
            trip.addPhoto(assetLocalIdentifier: item.identifier, captureDate: item.captureDate, coordinate: item.coordinate)
        }
    }

    public func removePhoto(_ photo: TripPhoto) {
        trip.removePhoto(photo)
    }

    public func setCaption(_ caption: String, for photo: TripPhoto) {
        trip.setCaption(caption, for: photo)
    }

    /// Manually pins a photo (typically one with no EXIF location) at a
    /// map point the user long-pressed.
    public func pinPhoto(_ photo: TripPhoto, at coordinate: Coordinate) {
        trip.pinPhoto(photo, at: coordinate)
    }
}
