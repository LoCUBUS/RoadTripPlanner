# RoadTripPlanner — Concept & Implementation Plan

Single-platform SwiftUI app (macOS 26) for planning road trips in five phases,
built on Apple Maps (MapKit) as the only provider in v1, English-only UI.

---

# PART 1 — DEFINE

## 1.1 Problem statement

Planning a multi-day road trip today means juggling a maps app, a notes app and a hotel
site. None of them understand that *time spent at a viewpoint is time not spent driving*.
Users cannot answer the central question: **"Given that I want to drive ~5 hours today and
stop at these three places, where do I realistically sleep tonight?"**

RoadTripPlanner answers exactly that, by making the trip a progressive refinement:
coarse corridor → fixed stops with dwell times → day segmentation with overnight stays →
executable day-by-day itinerary → travel journal.

## 1.2 Target user

- Plans trips of 3–21 days by car, alone or as a couple/family.
- Already inside the Apple ecosystem (Apple Maps for navigation, Photos for memories).
- Wants control, not an automatic "AI itinerary" — the app computes, the user decides.

## 1.3 Product principles

| # | Principle | Consequence |
|---|---|---|
| P1 | **Phases are lenses, not a wizard** | Any phase reachable at any time; no forced linear flow. |
| P2 | **Never silently destroy user work** | Upstream edits mark downstream data `needsReview`, never delete it. |
| P3 | **The map is the primary input** | Every POI, waypoint and lodging can be picked interactively on the map. |
| P4 | **Time is the currency** | Every entity contributes either travel time or dwell time. |
| P5 | **Provider-agnostic core** | Domain layer knows nothing about MapKit; Apple Maps is one implementation. |
| P6 | **Offline-tolerant** | Routes/legs are cached in the model; a planned trip is readable without network. |

## 1.4 Scope

### In scope (v1)

- Trip CRUD: create, edit, **duplicate as new trip**, delete.
- Phase 1 — Corridor: start, destination, ordered coarse waypoints (cities/places).
- Phase 2 — POIs: fixed stops with **dwell duration**; 10 km absorption rule.
- Phase 3 — Overnights: per-day travel-time budget, computed "time-up" point on the route,
  lodging search with map filter, day closure, repeat until destination.
- Phase 4 — Summary: day list, per-stop "Open in Apple Maps", visited checkbox, comment/rating.
- Phase 5 — Journal: import photos via PhotosPicker, place them on the map by EXIF location,
  add a caption per photo.
- English-only UI, but fully localizable (all strings via String Catalog from day one).

### Explicitly out of scope (v1)

- Google Maps / OpenStreetMap / other providers (architecture prepared, not implemented).
- CloudKit sync (model designed to be CloudKit-compatible, sync switched off).
- Booking or price lookup for accommodation.
- Ferries/tolls/EV-charging optimisation, multi-vehicle, collaborative editing.
- Turn-by-turn navigation inside the app (we hand off to Apple Maps).
- Localization beyond English.

## 1.5 User stories & acceptance criteria

**Trip management**
- *As a user I can create, rename, duplicate and delete a trip.*
  - AC: Duplicating copies all phases including POIs, days, lodging; photos and
    "visited"/comment state are **not** copied (a duplicate is a fresh trip).
  - AC: Deleting asks for confirmation and cascades to all child entities.

**Phase 1 — Coarse route**
- *As a user I set a start and a destination and add coarse waypoints in between.*
  - AC: Start and destination are set via text search fields in the right inspector (addresses, POIs, landmarks); searches are region-biased toward existing anchors.
  - AC: Waypoint field is only active once start and destination are set; can be added via search or long-press on the map.
  - AC: Waypoints are reorderable via drag & drop; the route auto-updates after each edit (debounced 500ms).
  - AC: Distance and driving time update live after each change (start, destination, waypoint add/remove/reorder).
  - AC: Result is a driving route Start → W₁ … Wₙ → Destination with total distance/duration.
  - AC: Phase 1 is complete when start + destination are set and a route was computed.
  - AC: Manual "Recalculate Route" button remains as a fallback for stale legs.

**Phase 2 — Points of interest**
- *As a user I add POIs to refine the route and say how long I want to stay.*
  - AC: A POI carries name, coordinate, category, and a **dwell duration** (default 45 min).
  - AC: **Absorption rule** — when a POI is added within 10 km (great-circle) of an existing
    *intermediate* Phase-1 waypoint, that waypoint is removed and the POI inherits its
    position in the order. Start and destination are never absorbed.
  - AC: Absorption is announced ("Replaced *Nuremberg* with *Nuremberg Castle*") and undoable.
  - AC: If a POI is within 10 km of several waypoints, only the nearest one is absorbed.
  - AC: POIs are reorderable; the route recomputes.

**Phase 3 — Overnight stays**
- *As a user I state how long I want to drive on day N and get a suggested area to sleep in.*
  - AC: The daily budget is **travel time**, defined as driving time + dwell time of POIs
    visited that day (configurable per day, default carried over from previous day).
  - AC: The app marks the point on the route where the budget is exhausted.
  - AC: A lodging filter (hotel / motel / campground / RV park) can be toggled on the map,
    searching around that point (default radius 15 km, adjustable 5–50 km).
  - AC: Choosing a lodging closes the day; the next day starts at that lodging.
  - AC: If a POI's dwell time alone exceeds the remaining budget, the app offers to
    (a) overshoot the budget, (b) end the day before that POI, or (c) shorten the dwell time.
  - AC: The last day ends at the destination; no lodging is requested there (opt-in if desired).
  - AC: A day can be reopened, its budget changed, or its lodging replaced/removed.

**Phase 4 — Summary**
- *As a user I get a day-by-day list I can execute while travelling.*
  - AC: Each day shows: date/index, driving distance & time, dwell time, ordered stops, lodging.
  - AC: Every stop has an **Open in Apple Maps** action (navigation from current location).
  - AC: Every stop has a **visited** toggle and a free-text comment + 0–5 star rating.
  - AC: A whole day can be opened in Apple Maps as a multi-stop route where supported.

**Phase 5 — Journal**
- *As a user I import photos and see them where they were taken.*
  - AC: Photos are selected with PhotosPicker; only an asset identifier + capture date +
    coordinate are stored (no image copies in the database).
  - AC: Photos without location metadata are still importable and can be pinned manually.
  - AC: Each photo has an editable caption and is auto-associated with the nearest day/stop.
  - AC: Photos render as thumbnail annotations on the trip map with a clustered gallery.

## 1.6 Cross-cutting requirements

- **Phase re-entry (P2)**: a `RevisionStamp` per phase. Editing phase *n* sets
  `needsReview` on all phases > *n*; the UI shows a non-blocking banner
  "Days may be out of date — Recalculate / Dismiss". Nothing is auto-deleted.
- **Privacy**: location permission is *when in use* and optional (only for "navigate from
  here" and map centring). Photos access is limited to picker-selected assets.
- **Accessibility**: Dynamic Type, VoiceOver labels on all map annotations, contrast-safe
  route colours, full keyboard navigation on macOS.
- **Performance budget**: trip with 60 stops must render and recompute in < 2 s; route legs
  are cached and only invalidated legs are re-requested.

---

# PART 2 — REFINE

## 2.1 Core abstraction: the itinerary anchor chain

Everything reduces to one ordered list of **anchors**:

```
[ Start ] → [ anchor ] → [ anchor ] → … → [ Destination ]
```

An anchor is a coordinate that the route must pass through. Three concrete kinds:

| Kind | Created in | Absorbable | Contributes dwell |
|---|---|---|---|
| `.waypoint` (coarse place) | Phase 1 | yes | no |
| `.poi` (fixed stop) | Phase 2 | no | yes (`dwellDuration`) |
| `.lodging` (overnight) | Phase 3 | no | ends a day |

The **route** is the concatenation of `RouteLeg`s between consecutive anchors. This single
model makes phases 1–3 the *same* data structure viewed through different editors, which is
what makes free navigation between phases (P1) cheap.

```mermaid
graph LR
  S[Start] -->|leg| W1[Waypoint: Nuremberg]
  W1 -->|leg| P1[POI: Castle · 1h30]
  P1 -->|leg| L1[Lodging: Night 1]
  L1 -->|leg| P2[POI: Viewpoint · 0h45]
  P2 -->|leg| D[Destination]
```

## 2.2 Domain model (SwiftData)

```
Trip
  id, name, notes, createdAt, updatedAt
  startAnchor, destinationAnchor
  anchors: [Anchor]            // ordered, includes start & destination
  legs: [RouteLeg]             // cached, keyed by (fromAnchorID, toAnchorID)
  days: [TripDay]
  photos: [TripPhoto]
  phaseStatus: [Phase: RevisionStamp]   // .ok / .needsReview
  currentPhase: Phase

Anchor
  id, order, kind (.start/.waypoint/.poi/.lodging/.destination)
  title, subtitle, latitude, longitude
  mapItemIdentifier: String?   // MKMapItem.Identifier for reliable re-resolution
  category: POICategory?
  dwellDuration: TimeInterval  // 0 for non-POI
  isVisited: Bool, comment: String?, rating: Int?   // Phase 4 state

RouteLeg
  fromAnchorID, toAnchorID
  distanceMeters, expectedTravelTime
  encodedPolyline: Data        // compressed coordinates for offline redraw
  computedAt, isStale: Bool

TripDay
  index, budget: TimeInterval, plannedDate: Date?
  startAnchorID, endAnchorID      // endAnchorID == lodging (or destination on last day)
  timeUpPoint: Coordinate?        // where the budget ran out, before lodging was chosen
  searchRadiusMeters
  derived: drivingTime, dwellTime, distance, containedAnchorIDs

TripPhoto
  assetLocalIdentifier, captureDate, latitude?, longitude?
  caption, associatedDayIndex?, associatedAnchorID?
```

*CloudKit-readiness*: no unique constraints, no `.deny` delete rules, all non-optional
properties have defaults, relationships are optional and inverse-paired — so enabling
`.automatic` CloudKit later is a configuration change, not a migration.

## 2.3 Provider abstraction (P5)

```swift
protocol MapProvider {
    func search(query: String, near: MKCoordinateRegion) async throws -> [PlaceResult]
    func search(categories: [POICategory], near: Coordinate, radius: CLLocationDistance)
        async throws -> [PlaceResult]
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult
    func directions(from: Coordinate, to: Coordinate) async throws -> RouteResult
    func externalNavigationURL(for: [Anchor]) -> URL
}
```

`AppleMapsProvider` is the only v1 implementation (MKLocalSearch, MKDirections,
`MKMapItem.openMaps(with:)`). Adding Google/OSM later means one new conformance plus a
provider picker in settings — no domain changes.

## 2.4 Routing engine

MKDirections computes **one leg per request** (no native multi-waypoint). Therefore:

- `RouteCoordinator` maintains the leg cache and recomputes **only invalidated legs**.
  Inserting an anchor between A and B invalidates leg A→B and creates A→X, X→B — 2 requests,
  not N.
- Requests are serialised through an actor with a small delay and retry-with-backoff, because
  MKDirections is aggressively throttled; failures degrade to a straight-line estimate marked
  `isStale` and are retried in the background.
- Polylines are stored encoded so the planned trip renders offline.

## 2.5 Phase 2 — Absorption algorithm

```
onAdd(poi):
  candidates = anchors.filter { $0.kind == .waypoint }          // never start/destination
                      .filter { haversine($0, poi) <= 10_000 }
  if let victim = candidates.min(by: distance) {
      poi.order = victim.order
      remove(victim); insert(poi)
      invalidate(legs touching victim)
      present undoable notice
  } else {
      insert(poi) at nearest position along the existing polyline
  }
```

Insertion position for a non-absorbing POI is chosen by projecting the POI onto the current
route polyline and inserting it into the leg whose projection is nearest — so the user does
not have to reorder manually in the common case. The order remains fully user-editable.

## 2.6 Phase 3 — Day segmentation algorithm

```
cursor = day.startAnchor ; consumed = 0 ; budget = day.budget
for each leg forward from cursor:
    if consumed + leg.travelTime > budget:
        remaining = budget - consumed
        fraction  = remaining / leg.travelTime
        timeUpPoint = interpolate(leg.polyline, byDistanceFraction: fraction)   // ⚠ approximation
        break
    consumed += leg.travelTime
    nextAnchor = leg.destination
    if nextAnchor.dwellDuration > 0:
        if consumed + nextAnchor.dwellDuration > budget:
            raise .dwellOverrun(anchor: nextAnchor, overshoot: …)   // user chooses a/b/c
        consumed += nextAnchor.dwellDuration
if no break occurred: this is the final day → ends at destination
```

**Known approximation**: time is interpolated along a leg proportionally to *distance*,
because MKRoute exposes no per-step time distribution beyond `MKRoute.Step`. Refinement:
walk `MKRoute.steps` and use each step's `distance` share of the leg to place the marker at
step granularity — accurate to a few minutes on motorway legs. This is the implementation we
ship; a documented ±10 % tolerance is shown in the UI as "≈".

Edge cases handled explicitly:
- Budget smaller than the first leg → time-up point inside leg 1, day may contain no stop.
- No lodging results in radius → offer radius expansion, then manual pin drop.
- User picks a lodging *before* the time-up point → allowed, day simply ends earlier.
- Deleting a lodging merges the day with the following one and re-runs segmentation.

## 2.7 Phase 4 — Apple Maps hand-off

- Single stop: `MKMapItem(placemark:).openInMaps(launchOptions: directionsModeDriving)`.
- Whole day: `MKMapItem.openMaps(with: [stops], launchOptions:)` — Apple Maps supports
  multi-item hand-off; on macOS it opens the Maps app equally.
- A stable `maps://?daddr=lat,lng` URL is stored per stop as the shareable link.

## 2.8 Architecture

Modular Swift package `RoadTripKit` + thin app target:

```
RoadTripKit/
  Sources/RTPCore/         domain models (SwiftData), value types, no MapKit import
  Sources/RTPRouting/      RouteCoordinator, day segmentation, absorption rules  (pure, testable)
  Sources/RTPProviders/    MapProvider protocol + AppleMapsProvider
  Sources/RTPFeatures/     SwiftUI views per phase + shared MapCanvas
  Tests/                   unit tests for routing/segmentation with stub provider
App/                       @main app, SwiftData container, navigation shell, String Catalog
```

`RTPRouting` is deliberately free of MapKit so the segmentation logic is unit-testable with
synthetic legs — this is the highest-risk logic in the product.

UI shell: a persistent three-column `NavigationSplitView` — a collapsible trip
list/management sidebar, the map canvas (largest column), and a phase-segmented
inspector on the right. macOS-only for v1; no iPhone/iPad adaptation.

**Project generation**: commit an XcodeGen `project.yml` so the `.xcodeproj` is reproducible
and reviewable from the CLI instead of a hand-edited `project.pbxproj`.

## 2.9 Risks

| Risk | Impact | Mitigation |
|---|---|---|
| MKDirections throttling on large trips | route recompute stalls | leg cache, serialised actor, incremental invalidation, stale fallback |
| Time-along-polyline approximation | wrong overnight suggestion | step-level interpolation, "≈" labelling, user can drag the marker |
| MKMapItem identifiers not resolvable later | stale POIs | always persist coordinate + name as source of truth, identifier only as bonus |
| SwiftData relationship churn on reorder | data corruption | explicit integer `order` field, never rely on array index |
| Photos assets deleted from library | broken journal entries | store caption/coordinate independently, render a placeholder tile |

## 2.10 Definition of Done (v1)

A trip Munich → Lisbon can be planned end-to-end: 4 coarse waypoints, 12 POIs with dwell
times, 6 days with individually chosen budgets and lodgings, a summary that opens each stop
in Apple Maps, 20 imported photos with captions on the map — and the whole trip survives an
app relaunch and can be duplicated and deleted.

