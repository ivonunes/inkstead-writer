import Foundation
import JPEGTurbo
import PNGCodec
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
    let rgb = (0..<(width * height)).flatMap { _ in [UInt8(95), UInt8(201), UInt8(181)] }
    return Foundation.Data(try JPEGTurbo.encodeRGB(width: width, height: height, rgb: rgb, quality: 82))
}

func testPNGData(width: Int, height: Int) throws -> Foundation.Data {
    let rgba = (0..<(width * height)).flatMap { _ in [UInt8(95), UInt8(201), UInt8(181), UInt8(255)] }
    return Foundation.Data(try PNGCodec.encodeRGBA(width: width, height: height, rgba: rgba))
}

func testWebPData(width: Int, height: Int) throws -> Foundation.Data {
    let rgba = (0..<(width * height)).flatMap { _ in [UInt8(95), UInt8(201), UInt8(181), UInt8(255)] }
    let image = WebP(width: width, height: height, rgba: rgba)
    return Foundation.Data(try image.encode(quality: 82))
}
