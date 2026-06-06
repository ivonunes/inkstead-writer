// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "libjpeg-turbo",
    products: [
        .library(name: "JPEGTurbo", targets: ["JPEGTurbo"])
    ],
    targets: [
        .target(
            name: "CTurboJPEG",
            path: "libjpeg-turbo",
            sources: [
                "src/jcapimin.c",
                "src/wrapper/jcapistd-8.c", "src/wrapper/jcapistd-12.c", "src/wrapper/jcapistd-16.c",
                "src/wrapper/jccoefct-8.c", "src/wrapper/jccoefct-12.c",
                "src/wrapper/jccolor-8.c", "src/wrapper/jccolor-12.c", "src/wrapper/jccolor-16.c",
                "src/wrapper/jcdctmgr-8.c", "src/wrapper/jcdctmgr-12.c",
                "src/wrapper/jcdiffct-8.c", "src/wrapper/jcdiffct-12.c", "src/wrapper/jcdiffct-16.c",
                "src/jchuff.c", "src/jcicc.c", "src/jcinit.c", "src/jclhuff.c",
                "src/wrapper/jclossls-8.c", "src/wrapper/jclossls-12.c", "src/wrapper/jclossls-16.c",
                "src/wrapper/jcmainct-8.c", "src/wrapper/jcmainct-12.c", "src/wrapper/jcmainct-16.c",
                "src/jcmarker.c", "src/jcmaster.c", "src/jcomapi.c", "src/jcparam.c", "src/jcphuff.c",
                "src/wrapper/jcprepct-8.c", "src/wrapper/jcprepct-12.c", "src/wrapper/jcprepct-16.c",
                "src/wrapper/jcsample-8.c", "src/wrapper/jcsample-12.c", "src/wrapper/jcsample-16.c",
                "src/jctrans.c", "src/jdapimin.c",
                "src/wrapper/jdapistd-8.c", "src/wrapper/jdapistd-12.c", "src/wrapper/jdapistd-16.c",
                "src/jdatadst.c", "src/jdatasrc.c",
                "src/wrapper/jdcoefct-8.c", "src/wrapper/jdcoefct-12.c",
                "src/wrapper/jdcolor-8.c", "src/wrapper/jdcolor-12.c", "src/wrapper/jdcolor-16.c",
                "src/wrapper/jddctmgr-8.c", "src/wrapper/jddctmgr-12.c",
                "src/wrapper/jddiffct-8.c", "src/wrapper/jddiffct-12.c", "src/wrapper/jddiffct-16.c",
                "src/jdhuff.c", "src/jdicc.c", "src/jdinput.c", "src/jdlhuff.c",
                "src/wrapper/jdlossls-8.c", "src/wrapper/jdlossls-12.c", "src/wrapper/jdlossls-16.c",
                "src/wrapper/jdmainct-8.c", "src/wrapper/jdmainct-12.c", "src/wrapper/jdmainct-16.c",
                "src/jdmarker.c", "src/jdmaster.c",
                "src/wrapper/jdmerge-8.c", "src/wrapper/jdmerge-12.c",
                "src/jdphuff.c",
                "src/wrapper/jdpostct-8.c", "src/wrapper/jdpostct-12.c", "src/wrapper/jdpostct-16.c",
                "src/wrapper/jdsample-8.c", "src/wrapper/jdsample-12.c", "src/wrapper/jdsample-16.c",
                "src/jdtrans.c", "src/jerror.c", "src/jfdctflt.c",
                "src/wrapper/jfdctfst-8.c", "src/wrapper/jfdctfst-12.c",
                "src/wrapper/jfdctint-8.c", "src/wrapper/jfdctint-12.c",
                "src/wrapper/jidctflt-8.c", "src/wrapper/jidctflt-12.c",
                "src/wrapper/jidctfst-8.c", "src/wrapper/jidctfst-12.c",
                "src/wrapper/jidctint-8.c", "src/wrapper/jidctint-12.c",
                "src/wrapper/jidctred-8.c", "src/wrapper/jidctred-12.c",
                "src/jmemmgr.c", "src/jmemnobs.c", "src/jpeg_nbits.c",
                "src/wrapper/jquant1-8.c", "src/wrapper/jquant1-12.c",
                "src/wrapper/jquant2-8.c", "src/wrapper/jquant2-12.c",
                "src/wrapper/jutils-8.c", "src/wrapper/jutils-12.c", "src/wrapper/jutils-16.c",
                "src/jaricom.c", "src/jcarith.c", "src/jdarith.c",
                "src/turbojpeg.c", "src/transupp.c", "src/jdatadst-tj.c", "src/jdatasrc-tj.c",
                "src/rdbmp.c", "src/wrapper/rdppm-8.c", "src/wrapper/rdppm-12.c", "src/wrapper/rdppm-16.c",
                "src/wrbmp.c", "src/wrapper/wrppm-8.c", "src/wrapper/wrppm-12.c", "src/wrapper/wrppm-16.c"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("BMP_SUPPORTED"),
                .define("PPM_SUPPORTED"),
                .headerSearchPath("src")
            ]
        ),
        .target(
            name: "JPEGTurbo",
            dependencies: [
                .target(name: "CTurboJPEG")
            ]
        )
    ]
)
