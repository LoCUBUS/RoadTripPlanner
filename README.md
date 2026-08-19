# RoadTripPlanner

A road trip planning app for iOS and macOS. Plan a trip through five phases —
coarse corridor, points of interest, overnight stays, a day-by-day summary
with Apple Maps hand-off, and a travel photo journal — while being able to
freely revisit any earlier phase at any time.

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
  Sources/RTPProviders/    MapProvider protocol + AppleMapsProvider
  Sources/RTPFeatures/     SwiftUI views per phase + shared map canvas
  Tests/                   Unit tests (Swift Testing)
App/                     Thin app target: @main entry point, root view, resources
project.yml              XcodeGen project definition
```

## Building & testing

```sh
cd RoadTripKit && swift build && swift test   # core logic, fast, no Xcode project needed
xcodebuild -project RoadTripPlanner.xcodeproj -scheme RoadTripPlanner-macOS build
xcodebuild -project RoadTripPlanner.xcodeproj -scheme RoadTripPlanner-iOS \
  -destination 'platform=iOS Simulator,name=<a simulator you have installed>' build
```
