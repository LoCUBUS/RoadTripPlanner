import Foundation

/// The five planning phases of a trip. Phases are lenses on the same anchor
/// chain, not a forced linear wizard — any phase can be revisited at any time.
public enum Phase: Int, CaseIterable, Codable, Sendable, Comparable {
    case corridor = 1
    case pointsOfInterest = 2
    case overnights = 3
    case summary = 4
    case journal = 5

    public static func < (lhs: Phase, rhs: Phase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Tracks whether the data produced by a phase is still consistent with any
/// upstream edits. Never triggers deletion — only surfaces a review banner.
public struct RevisionStamp: Codable, Sendable, Equatable {
    public var needsReview: Bool
    public var lastRecalculatedAt: Date?

    public init(needsReview: Bool = false, lastRecalculatedAt: Date? = nil) {
        self.needsReview = needsReview
        self.lastRecalculatedAt = lastRecalculatedAt
    }
}
