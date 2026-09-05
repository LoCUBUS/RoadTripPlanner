import Foundation
import SwiftData

/// A single road trip: the root of the anchor chain, its cached route legs,
/// day segmentation and photo journal. See docs/CONCEPT.md §2.2.
@Model
public final class Trip {
    public var id: UUID = UUID()
    public var name: String = "New Trip"
    public var notes: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public var currentPhaseRawValue: Int = Phase.corridor.rawValue

    /// Encoded `[Int: RevisionStamp]` keyed by `Phase.rawValue`. Stored as
    /// `Data` rather than a native SwiftData relationship/dictionary so the
    /// schema stays simple and CloudKit-compatible; see `phaseStatus` below
    /// for the ergonomic accessor.
    public var phaseRevisionData: Data = Data()

    @Relationship(deleteRule: .cascade, inverse: \Anchor.trip)
    public var anchors: [Anchor] = []

    @Relationship(deleteRule: .cascade, inverse: \RouteLeg.trip)
    public var legs: [RouteLeg] = []

    @Relationship(deleteRule: .cascade, inverse: \TripDay.trip)
    public var days: [TripDay] = []

    @Relationship(deleteRule: .cascade, inverse: \TripPhoto.trip)
    public var photos: [TripPhoto] = []

    public init(
        id: UUID = UUID(),
        name: String = "New Trip",
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        currentPhase: Phase = .corridor
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.currentPhaseRawValue = currentPhase.rawValue
    }

    public var currentPhase: Phase {
        get { Phase(rawValue: currentPhaseRawValue) ?? .corridor }
        set { currentPhaseRawValue = newValue.rawValue }
    }

    /// Per-phase revision tracking (docs/CONCEPT.md §1.6, principle P2).
    /// Editing an earlier phase should mark every later phase `needsReview`
    /// via `markNeedsReview(after:)` — never delete downstream data.
    public var phaseStatus: [Phase: RevisionStamp] {
        get {
            guard !phaseRevisionData.isEmpty,
                  let decoded = try? JSONDecoder().decode([Int: RevisionStamp].self, from: phaseRevisionData)
            else { return [:] }
            return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                Phase(rawValue: key).map { ($0, value) }
            })
        }
        set {
            let encodable = Dictionary(uniqueKeysWithValues: newValue.map { ($0.rawValue, $1) })
            phaseRevisionData = (try? JSONEncoder().encode(encodable)) ?? Data()
        }
    }

    /// Whether `phase` holds any data of its own that an upstream edit could
    /// actually invalidate:
    ///
    /// | Phase | Has content when |
    /// |---|---|
    /// | `.corridor` | any anchor exists |
    /// | `.pointsOfInterest` | any anchor is a POI |
    /// | `.overnights` | any day exists, or any anchor is a lodging |
    /// | `.summary` | any anchor carries visited/comment/rating state |
    /// | `.journal` | any photo exists |
    ///
    /// An empty phase cannot go out of date, so flagging it for review would
    /// only produce a banner about data that does not exist yet.
    public func hasReviewableContent(_ phase: Phase) -> Bool {
        switch phase {
        case .corridor:
            !anchors.isEmpty
        case .pointsOfInterest:
            anchors.contains { $0.kind == .poi }
        case .overnights:
            !days.isEmpty || anchors.contains { $0.kind == .lodging }
        case .summary:
            anchors.contains { $0.isVisited || !($0.comment ?? "").isEmpty || $0.rating != nil }
        case .journal:
            !photos.isEmpty
        }
    }

    /// Marks every phase strictly after `phase` as needing review, without
    /// touching any of their underlying data (principle P2).
    ///
    /// Phases that hold no data of their own are skipped — see
    /// `hasReviewableContent(_:)`. Without that guard the very first edit to a
    /// brand-new trip raises a review banner for all four later phases even
    /// though none of them contain anything yet.
    public func markNeedsReview(after phase: Phase) {
        var status = phaseStatus
        for later in Phase.allCases where later > phase && hasReviewableContent(later) {
            status[later] = RevisionStamp(needsReview: true, lastRecalculatedAt: status[later]?.lastRecalculatedAt)
        }
        phaseStatus = status
        updatedAt = .now
    }

    /// Clears the review flag for `phase` after it has been recalculated.
    public func markReviewed(_ phase: Phase, at date: Date = .now) {
        var status = phaseStatus
        status[phase] = RevisionStamp(needsReview: false, lastRecalculatedAt: date)
        phaseStatus = status
        updatedAt = .now
    }
}
