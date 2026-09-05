import Foundation
import Observation
import RTPCore
import RTPProviders
import RTPRouting

/// A banner notice shown after `DayPlannerViewModel` automatically promotes
/// a Phase-2 overnight candidate to a day's lodging, so the view can offer
/// an undo (docs/CONCEPT.md §2.6 "Overnight candidates").
public struct AutoPromotedOvernightNotice: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let dayID: UUID
    public let anchorTitle: String
}

/// Drives Phase 3's day planner: opening/closing days against a per-day
/// travel-time budget, searching for lodging around the computed time-up
/// point, resolving dwell-time overruns, and keeping route legs in sync via
/// the shared `RouteRecalculator` (docs/CONCEPT.md §1.5 "Phase 3 —
/// Overnight stays", §2.6).
@MainActor
@Observable
public final class DayPlannerViewModel {
    public let trip: Trip
    private let routeCoordinator: RouteCoordinator
    private let mapProvider: any MapProvider

    public private(set) var isRecalculating = false
    public private(set) var recalculationError: String?
    public private(set) var isSearchingLodging = false
    public private(set) var lodgingResults: [PlaceResult] = []
    public private(set) var lodgingSearchError: String?
    /// True once a lodging search has completed at least once, so the view
    /// can distinguish "haven't searched yet" from "searched, found nothing".
    public private(set) var hasSearchedLodging = false

    /// The most recent `segmentDay` outcome for the currently open day, kept
    /// so the view can render the time-up marker, the dwell-overrun
    /// resolution sheet, or a "reached destination" state.
    public private(set) var lastSegmentation: DaySegmentationResult?

    /// Set whenever a day was just automatically closed with a Phase-2
    /// overnight candidate, so the view can show an undoable banner.
    /// Cleared by `dismissAutoPromotedOvernightNotice()`,
    /// `undoAutoPromotedOvernight()`, or the next day transition.
    public private(set) var lastAutoPromotedOvernight: AutoPromotedOvernightNotice?
    /// Overnight-candidate anchors the user has explicitly rejected for the
    /// currently open day (via undo), so re-segmenting that same day doesn't
    /// immediately re-promote them.
    private var rejectedOvernightCandidateAnchorIDs: Set<UUID> = []

    public var lodgingCategoryFilterEnabled = true

    public init(trip: Trip, routeCoordinator: RouteCoordinator, mapProvider: any MapProvider) {
        self.trip = trip
        self.routeCoordinator = routeCoordinator
        self.mapProvider = mapProvider
    }

    public var days: [TripDay] {
        trip.days.sorted { $0.index < $1.index }
    }

    public var closedDays: [TripDay] {
        days.filter(\.isClosed)
    }

    public var openDay: TripDay? {
        days.first { !$0.isClosed }
    }

    public var canStartNextDay: Bool {
        openDay == nil && trip.nextDayStartAnchorID != nil
    }

    /// The anchor a lodging choice for `day` should be inserted after: the
    /// last anchor the current segmentation run reported as contained, or
    /// the day's own start anchor if none were.
    public func lodgingInsertionAnchorID(for day: TripDay) -> UUID? {
        lastSegmentation?.containedAnchorIDs.last ?? day.startAnchorID
    }

    /// Opens the next day with `budget` and immediately segments it,
    /// automatically promoting a fitting Phase-2 overnight candidate if one
    /// exists.
    @discardableResult
    public func startNextDay(budget: TimeInterval) -> TripDay? {
        rejectedOvernightCandidateAnchorIDs = []
        lastAutoPromotedOvernight = nil
        guard let day = trip.openNextDay(budget: budget) else { return nil }
        lastSegmentation = recomputeAndCheckPromotion(for: day)
        return day
    }

    /// Updates a day's budget and re-segments it.
    public func updateBudget(day: TripDay, budget: TimeInterval) {
        trip.updateBudget(day: day, budget: budget)
        lastSegmentation = recomputeAndCheckPromotion(for: day)
    }

    /// Dwell-overrun resolution (a): approve overshooting the budget for
    /// `anchorID`'s full dwell time, then re-segment.
    public func resolveOvershoot(day: TripDay, anchorID: UUID) {
        lastSegmentation = recomputeAndCheckPromotion(for: day, overshootAnchorIDs: [anchorID])
    }

    /// Dwell-overrun resolution (b): end the day before `anchorID`, then
    /// re-segment.
    public func resolveEndDayBeforeAnchor(day: TripDay, anchorID: UUID) {
        lastSegmentation = recomputeAndCheckPromotion(for: day, skipDwellAnchorIDs: [anchorID])
    }

    /// Dwell-overrun resolution (c): shorten the POI's dwell duration to fit
    /// the remaining budget, then re-segment.
    public func resolveShortenDwell(day: TripDay, anchorID: UUID, newDwellDuration: TimeInterval) {
        guard let anchor = trip.anchors.first(where: { $0.id == anchorID }) else { return }
        anchor.dwellDuration = Swift.max(0, newDwellDuration)
        trip.updatedAt = .now
        lastSegmentation = recomputeAndCheckPromotion(for: day)
    }

    /// Widens the lodging search radius for `day`, clamped to
    /// `maxRadiusMeters` (docs/CONCEPT.md AC: "radius adjustable 5–50 km").
    public func setSearchRadius(_ radiusMeters: Double, for day: TripDay, minRadiusMeters: Double = 5_000, maxRadiusMeters: Double = 50_000) {
        day.searchRadiusMeters = Swift.min(maxRadiusMeters, Swift.max(minRadiusMeters, radiusMeters))
        trip.updatedAt = .now
    }

    /// Searches for lodging around `coordinate` (typically the day's
    /// `timeUpPoint`), filtered to lodging categories unless the filter is
    /// switched off.
    public func searchLodging(near coordinate: Coordinate, radiusMeters: Double) async {
        isSearchingLodging = true
        lodgingSearchError = nil
        defer { isSearchingLodging = false }

        let categories: [POICategory] = lodgingCategoryFilterEnabled
            ? [.hotel, .motel, .campground, .rvPark]
            : POICategory.allCases

        do {
            lodgingResults = try await mapProvider.search(categories: categories, near: coordinate, radiusMeters: radiusMeters)
        } catch {
            lodgingResults = []
            lodgingSearchError = "Couldn't search for lodging. Check your connection and try again."
        }
        hasSearchedLodging = true
    }

    /// Closes `day` with the chosen lodging, inserted right after
    /// `afterAnchorID` (see `lodgingInsertionAnchorID(for:)`), then
    /// recalculates the routes split by the new anchor.
    public func closeDay(
        _ day: TripDay,
        afterAnchorID: UUID,
        title: String,
        coordinate: Coordinate,
        mapItemIdentifier: String? = nil,
        category: POICategory? = .hotel
    ) {
        trip.closeDay(
            day,
            afterAnchorID: afterAnchorID,
            lodgingTitle: title,
            coordinate: coordinate,
            mapItemIdentifier: mapItemIdentifier,
            category: category
        )
        lodgingResults = []
        Task {
            await routeCoordinator.invalidate(anchorID: afterAnchorID)
            await recalculateRoute()
        }
    }

    public func reopenDay(_ day: TripDay) {
        rejectedOvernightCandidateAnchorIDs = []
        lastAutoPromotedOvernight = nil
        trip.reopenDay(day)
        lastSegmentation = nil
    }

    /// Removes `day`'s lodging, merging it with the following day, then
    /// recalculates and re-segments.
    public func removeLodging(for day: TripDay) {
        lastAutoPromotedOvernight = nil
        trip.removeLodging(for: day)
        Task { await recalculateRoute() }
    }

    /// Undoes an automatic overnight-candidate promotion: reverts the
    /// lodging anchor back to a `.poi` overnight candidate, reopens the day,
    /// excludes that candidate from future auto-matches on this day, and
    /// re-segments (which may auto-promote a different, less-close
    /// candidate if one exists).
    public func undoAutoPromotedOvernight() {
        guard let notice = lastAutoPromotedOvernight,
              let day = days.first(where: { $0.id == notice.dayID })
        else { return }
        if let lodgingID = day.endAnchorID {
            rejectedOvernightCandidateAnchorIDs.insert(lodgingID)
        }
        lastAutoPromotedOvernight = nil
        trip.removeLodging(for: day)
        lastSegmentation = recomputeAndCheckPromotion(for: day)
    }

    /// Dismisses the auto-promotion banner without undoing anything.
    public func dismissAutoPromotedOvernightNotice() {
        lastAutoPromotedOvernight = nil
    }

    /// Re-checks the currently open day for a fitting overnight candidate —
    /// call after changing `trip.overnightToleranceFraction` so a widened
    /// tolerance can immediately pick up a candidate that didn't qualify
    /// before.
    public func refreshOvernightPromotion() {
        guard let day = openDay else { return }
        lastSegmentation = recomputeAndCheckPromotion(for: day)
    }

    public func recalculateRoute() async {
        isRecalculating = true
        recalculationError = nil
        defer { isRecalculating = false }

        let outcome = await RouteRecalculator.recalculate(trip: trip, using: routeCoordinator)
        if outcome.hasStaleLegs {
            recalculationError = "Some legs could not be routed and use a straight-line estimate."
        }
        if let day = openDay {
            lastSegmentation = recomputeAndCheckPromotion(for: day)
        }
    }

    /// Re-segments `day` and, if the outcome is `.reachedBudget` (i.e. the
    /// day would otherwise ask the user to search for lodging), checks
    /// whether a Phase-2 overnight candidate already fits the budget's
    /// tolerance and — if so — automatically promotes it and closes the
    /// day there instead, surfacing an undoable notice.
    private func recomputeAndCheckPromotion(
        for day: TripDay,
        overshootAnchorIDs: Set<UUID> = [],
        skipDwellAnchorIDs: Set<UUID> = []
    ) -> DaySegmentationResult? {
        let result = trip.recomputeTimeUpPoint(for: day, overshootAnchorIDs: overshootAnchorIDs, skipDwellAnchorIDs: skipDwellAnchorIDs)
        guard case .reachedBudget = result?.outcome, day.endAnchorID == nil else { return result }
        guard let match = trip.bestOvernightCandidate(for: day, excludingAnchorIDs: rejectedOvernightCandidateAnchorIDs),
              let anchor = trip.promoteOvernightCandidate(anchorID: match.anchorID, for: day)
        else { return result }
        lastAutoPromotedOvernight = AutoPromotedOvernightNotice(dayID: day.id, anchorTitle: anchor.title)
        return result
    }
}
