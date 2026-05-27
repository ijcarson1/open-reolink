// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "OpenRingPackage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenRingFeature", targets: ["OpenRingFeature"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "ReolinkClient", targets: ["ReolinkClient"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "VisionProviders", targets: ["VisionProviders"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat.git", from: "0.49.0"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: []
        ),

        .binaryTarget(
            name: "VLCKit",
            path: "Frameworks/VLCKit.xcframework"
        ),

        .target(
            name: "ReolinkClient",
            dependencies: ["VLCKit"]
        ),

        .target(
            name: "Storage",
            dependencies: [
                "ReolinkClient",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        .target(
            name: "VisionProviders",
            dependencies: []
        ),

        .target(
            name: "OpenRingFeature",
            dependencies: [
                "DesignSystem",
                "ReolinkClient",
                "Storage",
                "VisionProviders",
            ]
        ),

        .testTarget(
            name: "ReolinkClientTests",
            dependencies: ["ReolinkClient"],
            resources: [.copy("Fixtures")]
        ),

        .testTarget(
            name: "StorageTests",
            dependencies: ["Storage", "ReolinkClient"]
        ),

        .testTarget(
            name: "VisionProvidersTests",
            dependencies: ["VisionProviders"],
            resources: [.copy("Fixtures")]
        ),

        .testTarget(
            name: "OpenRingFeatureTests",
            dependencies: ["OpenRingFeature"]
        ),
    ]
)
