// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "h",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(name: "CRC", targets: ["CRC"])
    ],
    targets: [
        .target(
            name: "BaseDigits",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "Base16",
            dependencies: [
                .target(name: "BaseDigits")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "CRC",
            dependencies: [
                .target(name: "Base16")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ]
)
