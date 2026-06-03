import Foundation
import JPEG
import JPEGSystem
import PNG
import WebP
@testable import InksteadWriter

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-swift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

func testJPEGData(width: Int, height: Int) throws -> Foundation.Data {
    let pixels = Array(repeating: JPEG.RGB(95, 201, 181), count: width * height)
    let layout: JPEG.Layout<JPEG.Common> = .init(
        format: .ycc8,
        process: .baseline,
        components: [
            1: (factor: (2, 2), qi: 0),
            2: (factor: (1, 1), qi: 1),
            3: (factor: (1, 1), qi: 1)
        ],
        scans: [
            .sequential((1, \.0, \.0), (2, \.1, \.1), (3, \.1, \.1))
        ]
    )
    let image: JPEG.Data.Rectangular<JPEG.Common> = .pack(
        size: (x: width, y: height),
        layout: layout,
        metadata: [.jfif(.init(version: .v1_2, density: (72, 72, .inches)))],
        pixels: pixels
    )
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-test-\(UUID().uuidString).jpg")
    defer { try? FileManager.default.removeItem(at: output) }
    try image.compress(path: output.path, quanta: [
        0: JPEG.CompressionLevel.luminance(0.2).quanta,
        1: JPEG.CompressionLevel.chrominance(0.2).quanta
    ])
    return try Foundation.Data(contentsOf: output)
}

func testPNGData(width: Int, height: Int) throws -> Foundation.Data {
    let pixels = Array(repeating: PNG.RGBA<UInt8>(95, 201, 181, 255), count: width * height)
    let image = PNG.Image(
        packing: pixels,
        size: (x: width, y: height),
        layout: PNG.Layout(format: .rgba8(palette: [], fill: nil))
    )
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("inkstead-writer-test-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: output) }
    try image.compress(path: output.path, level: 9)
    return try Foundation.Data(contentsOf: output)
}

func testWebPData(width: Int, height: Int) throws -> Foundation.Data {
    let rgba = (0..<(width * height)).flatMap { _ in [UInt8(95), UInt8(201), UInt8(181), UInt8(255)] }
    let image = WebP(width: width, height: height, rgba: rgba)
    return Foundation.Data(try image.encode(quality: 82))
}
