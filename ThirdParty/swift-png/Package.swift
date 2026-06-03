// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-png",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(name: "PNG", targets: ["PNG"])
    ],
    dependencies: [
        .package(path: "../h")
    ],
    targets: [
        .target(
            name: "LZ77",
            dependencies: [
                .product(name: "CRC", package: "h")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "PNG",
            dependencies: [
                .target(name: "LZ77")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
