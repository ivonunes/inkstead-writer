// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InksteadWriter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "InksteadWriter", targets: ["InksteadWriter"]),
        .executable(name: "inkstead-writer", targets: ["InksteadWriterCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/ivonunes/plume.git", from: "1.0.0"),
        .package(path: "ThirdParty/swift-jpeg"),
        .package(path: "ThirdParty/swift-png"),
        .package(path: "ThirdParty/libwebp")
    ],
    targets: [
        .target(
            name: "InksteadWriter",
            dependencies: [
                .product(name: "Plume", package: "plume"),
                .product(name: "JPEG", package: "swift-jpeg"),
                .product(name: "JPEGSystem", package: "swift-jpeg"),
                .product(name: "PNG", package: "swift-png"),
                .product(name: "WebP", package: "libwebp")
            ],
            exclude: [
                "Templates/DefaultTheme"
            ],
            plugins: [
                .plugin(name: "InksteadWriterAssetsPlugin")
            ]
        ),
        .executableTarget(name: "InksteadWriterCLI", dependencies: [
            "InksteadWriter",
            .product(name: "Plume", package: "plume")
        ]),
        .executableTarget(name: "InksteadWriterAssets"),
        .plugin(
            name: "InksteadWriterAssetsPlugin",
            capability: .buildTool(),
            dependencies: ["InksteadWriterAssets"]
        ),
        .testTarget(name: "InksteadWriterTests", dependencies: [
            "InksteadWriter",
            .product(name: "Plume", package: "plume"),
            .product(name: "JPEG", package: "swift-jpeg"),
            .product(name: "JPEGSystem", package: "swift-jpeg"),
            .product(name: "PNG", package: "swift-png"),
            .product(name: "WebP", package: "libwebp")
        ])
    ]
)
