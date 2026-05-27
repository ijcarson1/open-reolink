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

        .target(
            name: "ReolinkClient",
            dependencies: []
        ),

        .target(
            name: "Storage",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),

        .target(
            name: "OpenRingFeature",
            dependencies: [
                "DesignSystem",
                "ReolinkClient",
                "Storage",
            ]
        ),

        .testTarget(
            name: "ReolinkClientTests",
            dependencies: ["ReolinkClient"]
        ),

        .testTarget(
            name: "OpenRingFeatureTests",
            dependencies: ["OpenRingFeature"]
        ),
    ]
)
