// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InksteadWriter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "InksteadWriter", targets: ["InksteadWriter"]),
        .executable(name: "inkstead-writer", targets: ["InksteadWriterCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/ivonunes/plumekit.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-cmark.git", from: "0.8.0"),
        .package(path: "ThirdParty/libjpeg-turbo"),
        .package(path: "ThirdParty/libspng"),
        .package(path: "ThirdParty/libwebp")
    ],
    targets: [
        .target(
            name: "InksteadWriter",
            dependencies: [
                .product(name: "Plume", package: "plumekit"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "JPEGTurbo", package: "libjpeg-turbo"),
                .product(name: "PNGCodec", package: "libspng"),
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
            .product(name: "Plume", package: "plumekit")
        ]),
        .executableTarget(name: "InksteadWriterAssets"),
        .plugin(
            name: "InksteadWriterAssetsPlugin",
            capability: .buildTool(),
            dependencies: ["InksteadWriterAssets"]
        ),
        .testTarget(name: "InksteadWriterTests", dependencies: [
            "InksteadWriter",
            .product(name: "Plume", package: "plumekit"),
            .product(name: "JPEGTurbo", package: "libjpeg-turbo"),
            .product(name: "PNGCodec", package: "libspng"),
            .product(name: "WebP", package: "libwebp")
        ])
    ]
)
