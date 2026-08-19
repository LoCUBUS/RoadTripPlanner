import Foundation

/// Marker type for the SwiftUI feature layer (per-phase views + shared map
/// canvas). Real views land starting with the `map-canvas` work item.
public enum RTPFeatures {
    public static let moduleName = "RTPFeatures"
}
