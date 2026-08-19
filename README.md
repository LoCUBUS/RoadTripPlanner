# RoadTripPlanner

A road trip planning app for iOS and macOS. Plan a trip through five phases —
coarse corridor, points of interest, overnight stays, a day-by-day summary
with Apple Maps hand-off, and a travel photo journal — while being able to
freely revisit any earlier phase at any time.

See [`docs/CONCEPT.md`](docs/CONCEPT.md) for the full product concept
(problem statement, user stories/acceptance criteria, domain model, and
algorithms for absorption, day segmentation, and Apple Maps hand-off).

## The five phases

1. **Corridor** — set a start, a destination, and coarse waypoints in between.
2. **Points of interest** — add fixed stops with a dwell duration; POIs added
   within 10 km of a coarse waypoint absorb it.
3. **Overnights** — state a daily travel-time budget; the app marks where
   it's exhausted and helps you find lodging nearby.
4. **Summary** — a day-by-day itinerary with Apple Maps hand-off, a visited
   toggle, and a comment/rating per stop.
5. **Journal** — import photos from the Photos library, see them pinned
   where they were taken, and caption them.

Editing an earlier phase never deletes downstream data — it flags later
phases with a dismissible "may be out of date — Recalculate" banner.

v1 uses **Apple Maps only** as the map/routing provider (MapKit); the
domain layer is provider-agnostic (`MapProvider` protocol) so Google Maps/
OpenStreetMap support can be added later without touching the core model.
UI language is English-only in v1, routed through a String Catalog so
localization is a follow-up, not a rewrite.

## Requirements

- Xcode 26 (Swift 6.2 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```sh
./scripts/generate-project.sh   # generates RoadTripPlanner.xcodeproj from project.yml
open RoadTripPlanner.xcodeproj
```

The `.xcodeproj` and the derived `App/Info-*.plist` files are generated and
**not** committed — `project.yml` is the source of truth. Regenerate after
pulling changes to `project.yml`.

## Project structure

```
RoadTripKit/            Local Swift package with the shared, testable core
  Sources/RTPCore/         Domain model (SwiftData), phases, revision tracking
  Sources/RTPRouting/      Leg caching, absorption rule, day segmentation (MapKit-free)
  Sources/RTPProviders/    MapProvider/PhotoAssetResolver protocols + Apple/Photos implementations
  Sources/RTPFeatures/     SwiftUI views per phase + shared map canvas
  Tests/                   Unit tests (Swift Testing)
App/                     Thin app target: @main entry point, root view, resources, app icon
project.yml              XcodeGen project definition
docs/CONCEPT.md          Product concept: Define/Refine, domain model, algorithms
```

## Building & testing

```sh
cd RoadTripKit && swift build && swift test   # core logic, fast, no Xcode project needed
xcodebuild -project RoadTripPlanner.xcodeproj -scheme RoadTripPlanner-macOS build
xcodebuild -project RoadTripPlanner.xcodeproj -scheme RoadTripPlanner-iOS \
  -destination 'platform=iOS Simulator,name=<a simulator you have installed>' build
```

`RoadTripKit`'s test suite (`swift test`) covers the domain layer end to
end with `StubMapProvider`/`StubPhotoAssetResolver` — no MapKit, network, or
Photos-library access required — including the absorption rule, day
segmentation (dwell overrun, final-day detection), leg-cache invalidation,
trip duplication, and phase-revision propagation.

## Accessibility & polish notes

- Map pins expose a VoiceOver label combining their kind (start, POI,
  lodging, time-up point, photo, …) and title.
- Every list-based screen (trips, corridor, POIs, days, summary, journal)
  has an explicit empty state, and network-backed actions (route
  recalculation, lodging search) surface a visible error message instead of
  failing silently.
- SwiftUI `Form`/`List` are used throughout, which pick up Dynamic Type and
  macOS keyboard navigation automatically.

