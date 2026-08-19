import Foundation

/// Marker type confirming the RTPRouting module compiles independently of MapKit.
/// Real content (RouteCoordinator, absorption rule, day segmentation) lands in
/// the `routing-engine`, `phase2-pois` and `phase3-days` work items.
public enum RTPRouting {
    public static let moduleName = "RTPRouting"
}
