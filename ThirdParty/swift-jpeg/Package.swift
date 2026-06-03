// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-jpeg",
    products: [
        .library(name: "JPEG", targets: ["JPEG"]),
        .library(name: "JPEGSystem", targets: ["JPEGSystem"])
    ],
    targets: [
        .target(
            name: "JPEG",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "JPEGSystem",
            dependencies: ["JPEG"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
