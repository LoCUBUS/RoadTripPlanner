import Foundation
import RTPCore

/// A minimal, `Sendable` stand-in for `RTPCore.Anchor`'s identity and
/// position. `RouteCoordinator` is an actor and only ever needs an anchor's
/// id and coordinate, so it works against this plain value type instead of
/// the SwiftData `Anchor` class — keeping `RTPRouting` easy to unit test
/// with synthetic data (docs/CONCEPT.md §2.4/§2.8).
public struct AnchorPoint: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var coordinate: Coordinate

    public init(id: UUID, coordinate: Coordinate) {
        self.id = id
        self.coordinate = coordinate
    }
}

public extension AnchorPoint {
    init(anchor: Anchor) {
        self.init(id: anchor.id, coordinate: anchor.coordinate)
    }
}
