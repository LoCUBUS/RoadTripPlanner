import Foundation
import SwiftData

/// A Phase-5 journal entry. Only a reference to the Photos library asset is
/// stored — never image data — so the trip stays lightweight and in sync
/// with the user's actual photo library (docs/CONCEPT.md §1.5, §2.9).
@Model
public final class TripPhoto {
    public var id: UUID = UUID()

    /// `PHAsset.localIdentifier`. The asset itself may later be deleted from
    /// the library; callers should render a placeholder tile when it can no
    /// longer be resolved rather than losing the caption/coordinate.
    public var assetLocalIdentifier: String = ""

    public var captureDate: Date = Date.distantPast

    /// Nil when the asset had no location metadata and hasn't been pinned
    /// manually yet.
    public var latitude: Double?
    public var longitude: Double?

    public var caption: String = ""

    public var associatedDayIndex: Int?
    public var associatedAnchorID: UUID?

    public var trip: Trip?

    public init(
        id: UUID = UUID(),
        assetLocalIdentifier: String,
        captureDate: Date = .distantPast,
        coordinate: Coordinate? = nil,
        caption: String = "",
        associatedDayIndex: Int? = nil,
        associatedAnchorID: UUID? = nil
    ) {
        self.id = id
        self.assetLocalIdentifier = assetLocalIdentifier
        self.captureDate = captureDate
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.caption = caption
        self.associatedDayIndex = associatedDayIndex
        self.associatedAnchorID = associatedAnchorID
    }

    public var coordinate: Coordinate? {
        get {
            guard let latitude, let longitude else { return nil }
            return Coordinate(latitude: latitude, longitude: longitude)
        }
        set {
            latitude = newValue?.latitude
            longitude = newValue?.longitude
        }
    }
}
