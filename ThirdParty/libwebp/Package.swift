// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "libwebp",
    products: [
        .library(name: "WebP", targets: ["WebP"])
    ],
    targets: [
        .target(
            name: "libwebp",
            path: "libwebp/src",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../.")
            ]
        ),
        .target(
            name: "sharpyuv",
            dependencies: [
                .target(name: "libwebp")
            ],
            path: "libwebp/sharpyuv",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../.")
            ]
        ),
        .target(
            name: "WebP",
            dependencies: [
                .target(name: "libwebp"),
                .target(name: "sharpyuv")
            ]
        )
    ]
)
