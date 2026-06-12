import Foundation
import XCTest
@testable import InksteadWriter

final class ImageOptimizationTests: XCTestCase {
    func testUnsupportedImageDataDoesNotFailBuildOptimization() throws {
        let root = try TemporaryDirectory()
        let image = root.url.appendingPathComponent("unsupported.jpg")
        let bytes = Data("not actually a jpeg".utf8)
        try bytes.write(to: image)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            media: MediaConfig(optimize: true, maxWidth: 100, maxHeight: 100, quality: 82)
        )

        XCTAssertNoThrow(try ImageOptimizer.optimizeBuiltImages(root: root.url, config: config))
        XCTAssertEqual(try Data(contentsOf: image), bytes)
    }

    func testUnsupportedImageDataReturnsNoDimensions() throws {
        let root = try TemporaryDirectory()
        let image = root.url.appendingPathComponent("unsupported.jpg")
        try Data("not actually a jpeg".utf8).write(to: image)

        XCTAssertNil(try ImageOptimizer.dimensions(of: image))
    }

    func testTruncatedJPEGStillReportsHeaderDimensions() throws {
        let root = try TemporaryDirectory()
        let image = root.url.appendingPathComponent("truncated.jpg")
        try entropyTruncatedJPEGData(width: 320, height: 180).write(to: image)

        XCTAssertEqual(try ImageOptimizer.dimensions(of: image), ImageDimensions(width: 320, height: 180))
    }

    func testTruncatedJPEGCanBeOptimizedWithTurboDecoderRecovery() throws {
        let root = try TemporaryDirectory()
        let image = root.url.appendingPathComponent("truncated.jpg")
        try entropyTruncatedJPEGData(width: 320, height: 180).write(to: image)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            media: MediaConfig(optimize: true, maxWidth: 100, maxHeight: 100, quality: 82)
        )

        XCTAssertNoThrow(try ImageOptimizer.optimizeBuiltImages(root: root.url, config: config))
        XCTAssertEqual(try ImageOptimizer.dimensions(of: image), ImageDimensions(width: 100, height: 56))
    }

    func testOptimizedImagesAreReusedFromCache() throws {
        let root = try TemporaryDirectory()
        let cache = root.url.appendingPathComponent("cache")
        let sourceMedia = root.url.appendingPathComponent("content/media")
        let outputMedia = root.url.appendingPathComponent("dist/media")
        let sourceImage = sourceMedia.appendingPathComponent("photo.jpg")
        let outputImage = outputMedia.appendingPathComponent("photo.jpg")
        try FileManager.default.createDirectory(at: sourceMedia, withIntermediateDirectories: true)
        let original = try testJPEGData(width: 320, height: 180)
        try original.write(to: sourceImage)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            media: MediaConfig(optimize: true, maxWidth: 100, maxHeight: 100, quality: 82)
        )

        try ImageOptimizer.copyOptimizedMedia(from: sourceMedia, to: outputMedia, config: config, cacheRoot: cache)
        let cachedFiles = try regularFiles(in: cache)
        XCTAssertEqual(cachedFiles.count, 1)

        let sentinel = Data("cached optimized image".utf8)
        try sentinel.write(to: cachedFiles[0], options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 4_102_444_800)],
            ofItemAtPath: sourceImage.path
        )
        try FileManager.default.removeItem(at: outputMedia)

        try ImageOptimizer.copyOptimizedMedia(from: sourceMedia, to: outputMedia, config: config, cacheRoot: cache)

        XCTAssertEqual(try Data(contentsOf: outputImage), sentinel)
    }

    func testUndecodableSupportedImageEmitsWarningInsteadOfSilentCopy() throws {
        let root = try TemporaryDirectory()
        let cache = root.url.appendingPathComponent("cache")
        let sourceMedia = root.url.appendingPathComponent("content/media")
        let outputMedia = root.url.appendingPathComponent("dist/media")
        try FileManager.default.createDirectory(at: sourceMedia, withIntermediateDirectories: true)
        let bytes = Data("not actually a jpeg".utf8)
        let sourceImage = sourceMedia.appendingPathComponent("broken.jpg")
        try bytes.write(to: sourceImage)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            media: MediaConfig(optimize: true, maxWidth: 100, maxHeight: 100, quality: 82)
        )

        var warnings: [String] = []
        try ImageOptimizer.copyOptimizedMedia(from: sourceMedia, to: outputMedia, config: config, cacheRoot: cache) { warnings.append($0) }

        XCTAssertEqual(try Data(contentsOf: outputMedia.appendingPathComponent("broken.jpg")), bytes)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("could not optimize"))
        XCTAssertTrue(warnings[0].contains(sourceImage.path))
    }

    func testSuccessfulOptimizationEmitsNoWarning() throws {
        let root = try TemporaryDirectory()
        let cache = root.url.appendingPathComponent("cache")
        let sourceMedia = root.url.appendingPathComponent("content/media")
        let outputMedia = root.url.appendingPathComponent("dist/media")
        try FileManager.default.createDirectory(at: sourceMedia, withIntermediateDirectories: true)
        try testJPEGData(width: 320, height: 180).write(to: sourceMedia.appendingPathComponent("photo.jpg"))
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "Test", url: "https://example.com", author: "Test"),
            media: MediaConfig(optimize: true, maxWidth: 100, maxHeight: 100, quality: 82)
        )

        var warnings: [String] = []
        try ImageOptimizer.copyOptimizedMedia(from: sourceMedia, to: outputMedia, config: config, cacheRoot: cache) { warnings.append($0) }

        XCTAssertEqual(warnings, [])
    }

    func testContentHashCacheMemoizesUntilFileChanges() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("photo.jpg")
        let original = Data("original contents".utf8)
        try original.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: file.path)

        let before = FileContentHashCache.shared.computedHashCount
        let first = try FileContentHashCache.shared.hash(of: file)
        let second = try FileContentHashCache.shared.hash(of: file)
        XCTAssertEqual(first, SHA256.hex(original))
        XCTAssertEqual(second, first)
        XCTAssertEqual(FileContentHashCache.shared.computedHashCount - before, 1)

        let updated = Data("updated contents!".utf8)
        try updated.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)], ofItemAtPath: file.path)
        let third = try FileContentHashCache.shared.hash(of: file)
        XCTAssertEqual(third, SHA256.hex(updated))
        XCTAssertNotEqual(third, first)
        XCTAssertEqual(FileContentHashCache.shared.computedHashCount - before, 2)
    }

    func testOptimizationKeepsOriginalWhenEncodedImageWouldBeLarger() throws {
        let root = try TemporaryDirectory()
        let image = root.url.appendingPathComponent("tiny.jpg")
        let original = try testJPEGData(width: 1, height: 1)
        try original.write(to: image)

        try ImageEncoder.optimizeImage(at: image, options: ImageOptimizationOptions(enabled: true, maxWidth: 100, maxHeight: 100, quality: 100))

        XCTAssertLessThanOrEqual(try Data(contentsOf: image).count, original.count)
    }

    private func entropyTruncatedJPEGData(width: Int, height: Int) throws -> Data {
        let bytes = [UInt8](try testJPEGData(width: width, height: height))
        let endOfImage = stride(from: bytes.count - 2, through: 0, by: -1)
            .first { bytes[$0] == 0xFF && bytes[$0 + 1] == 0xD9 }
        guard let endOfImage else {
            XCTFail("Generated test JPEG should contain an EOI marker")
            return Data(bytes)
        }

        let cutStart = max(0, endOfImage - 128)
        var data = Data()
        data.append(contentsOf: bytes[..<cutStart])
        data.append(contentsOf: bytes[endOfImage...])
        return data
    }

    private func regularFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return try enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
                return nil
            }
            return url
        }
    }
}
