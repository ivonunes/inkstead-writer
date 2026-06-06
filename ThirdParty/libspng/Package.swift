// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "libspng",
    products: [
        .library(name: "PNGCodec", targets: ["PNGCodec"])
    ],
    targets: [
        .target(
            name: "CSPNG",
            path: "libspng",
            sources: [
                "spng/spng.c",
                "miniz/miniz.c",
                "miniz/miniz_tdef.c",
                "miniz/miniz_tinfl.c"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("SPNG_STATIC"),
                .define("SPNG_USE_MINIZ"),
                .define("MINIZ_NO_ARCHIVE_APIS"),
                .define("MINIZ_NO_ARCHIVE_WRITING_APIS"),
                .define("MINIZ_NO_STDIO"),
                .define("MINIZ_NO_TIME"),
                .headerSearchPath("spng"),
                .headerSearchPath("miniz")
            ]
        ),
        .target(
            name: "PNGCodec",
            dependencies: [
                .target(name: "CSPNG")
            ]
        )
    ]
)
