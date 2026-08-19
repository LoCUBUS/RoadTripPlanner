import Foundation

/// Phase 5 journal editing: importing a photo (already resolved to an
/// asset identifier/capture date/coordinate by the caller), captioning it,
/// manually pinning one without location metadata, and auto-associating it
/// with the nearest anchor/day (docs/CONCEPT.md §1.5 "Phase 5 — Journal").
public extension Trip {
    @discardableResult
    func addPhoto(
        assetLocalIdentifier: String,
        captureDate: Date,
        coordinate: Coordinate?,
        caption: String = ""
    ) -> TripPhoto {
        let photo = TripPhoto(
            assetLocalIdentifier: assetLocalIdentifier,
            captureDate: captureDate,
            coordinate: coordinate,
            caption: caption
        )
        associate(photo)
        photo.trip = self
        photos.append(photo)
        updatedAt = .now
        return photo
    }

    func removePhoto(_ photo: TripPhoto) {
        photos.removeAll { $0.id == photo.id }
        updatedAt = .now
    }

    func setCaption(_ caption: String, for photo: TripPhoto) {
        photo.caption = caption
        updatedAt = .now
    }

    /// Manually pins a photo that had no location metadata (or re-pins an
    /// existing one) to `coordinate`, re-running its nearest-day/stop
    /// association.
    func pinPhoto(_ photo: TripPhoto, at coordinate: Coordinate) {
        photo.coordinate = coordinate
        associate(photo)
        updatedAt = .now
    }

    /// Associates `photo` with the nearest anchor (great-circle distance)
    /// and, if that anchor falls within a closed day's span, that day's
    /// index. Clears both if the photo has no coordinate or the trip has no
    /// anchors yet.
    private func associate(_ photo: TripPhoto) {
        guard let coordinate = photo.coordinate,
              let nearest = anchors.min(by: { $0.coordinate.distance(to: coordinate) < $1.coordinate.distance(to: coordinate) })
        else {
            photo.associatedAnchorID = nil
            photo.associatedDayIndex = nil
            return
        }
        photo.associatedAnchorID = nearest.id
        photo.associatedDayIndex = days.first { day in
            anchors(in: day).contains { $0.id == nearest.id }
        }?.index
    }
}
