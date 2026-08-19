// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoadTripKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "RTPCore", targets: ["RTPCore"]),
        .library(name: "RTPRouting", targets: ["RTPRouting"]),
        .library(name: "RTPProviders", targets: ["RTPProviders"]),
        .library(name: "RTPFeatures", targets: ["RTPFeatures"])
    ],
    targets: [
        // RTPCore: SwiftData domain model. No MapKit import — pure data + value types.
        .target(
            name: "RTPCore"
        ),

        // RTPRouting: leg caching, absorption rule, day segmentation. MapKit-free and
        // therefore unit-testable with synthetic data via RTPProviders' MapProvider protocol.
        .target(
            name: "RTPRouting",
            dependencies: ["RTPCore"]
        ),

        // RTPProviders: MapProvider protocol + AppleMapsProvider (MapKit-backed) + StubProvider.
        .target(
            name: "RTPProviders",
            dependencies: ["RTPCore"]
        ),

        // RTPFeatures: SwiftUI views per phase + shared MapCanvas. Depends on everything.
        .target(
            name: "RTPFeatures",
            dependencies: ["RTPCore", "RTPRouting", "RTPProviders"]
        ),

        .testTarget(
            name: "RTPCoreTests",
            dependencies: ["RTPCore"]
        ),
        .testTarget(
            name: "RTPRoutingTests",
            dependencies: ["RTPRouting", "RTPProviders"]
        )
    ]
)
