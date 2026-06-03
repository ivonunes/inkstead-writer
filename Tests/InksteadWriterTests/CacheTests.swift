import XCTest
@testable import InksteadWriter

final class CacheTests: XCTestCase {
    func testListsCachedBinariesAndMarksCurrentPlatform() throws {
        let root = try TemporaryDirectory()
        let cache = root.url.appendingPathComponent("cache")
        try writeCachedBinary(cache: cache, version: "2.0.0", platform: "macos-arm64", contents: "current")
        try writeCachedBinary(cache: cache, version: "1.9.0", platform: "linux-x86_64", contents: "old")
        try FileManager.default.createDirectory(
            at: cache.appendingPathComponent("v2.0.0/macos-arm64.lock"),
            withIntermediateDirectories: true
        )

        let entries = try CacheManager.list(
            cacheRoot: cache,
            currentVersion: "2.0.0",
            currentPlatform: InksteadWriterReleasePlatform(os: "macos", arch: "arm64")
        )

        XCTAssertEqual(entries.map(\.version), ["1.9.0", "2.0.0"])
        XCTAssertEqual(entries.map(\.platform), ["linux-x86_64", "macos-arm64"])
        XCTAssertFalse(entries[0].isCurrent)
        XCTAssertTrue(entries[1].isCurrent)
        XCTAssertEqual(entries[1].relativePath, "v2.0.0/macos-arm64")
        XCTAssertTrue(entries.allSatisfy(\.isExecutable))
        XCTAssertTrue(entries.allSatisfy { $0.sizeBytes > 0 })
    }

    func testCleanRemovesStaleVersionsAndKeepsCurrentVersionByDefault() throws {
        let root = try TemporaryDirectory()
        let cache = root.url.appendingPathComponent("cache")
        try writeCachedBinary(cache: cache, version: "2.0.0", platform: "macos-arm64", contents: "current")
        try writeCachedBinary(cache: cache, version: "1.9.0", platform: "macos-arm64", contents: "old")

        let result = try CacheManager.clean(cacheRoot: cache, keepVersion: "2.0.0")

        XCTAssertEqual(result.removedPaths, ["v1.9.0"])
        XCTAssertGreaterThan(result.freedBytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.appendingPathComponent("v1.9.0").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.appendingPathComponent("v2.0.0").path))
    }

    func testCleanDryRunDoesNotRemoveCaches() throws {
        let root = try TemporaryDirectory()
        let cache = root.url.appendingPathComponent("cache")
        try writeCachedBinary(cache: cache, version: "1.9.0", platform: "macos-arm64", contents: "old")

        let result = try CacheManager.clean(cacheRoot: cache, keepVersion: "2.0.0", dryRun: true)

        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.removedPaths, ["v1.9.0"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.appendingPathComponent("v1.9.0").path))
    }

    func testCleanSpecificVersionAcceptsLeadingV() throws {
        let root = try TemporaryDirectory()
        let cache = root.url.appendingPathComponent("cache")
        try writeCachedBinary(cache: cache, version: "2.0.0", platform: "macos-arm64", contents: "current")
        try writeCachedBinary(cache: cache, version: "1.9.0", platform: "macos-arm64", contents: "old")

        let result = try CacheManager.clean(cacheRoot: cache, keepVersion: "2.0.0", version: "v2.0.0")

        XCTAssertEqual(result.removedPaths, ["v2.0.0"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.appendingPathComponent("v2.0.0").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.appendingPathComponent("v1.9.0").path))
    }

    func testCleanAllRemovesEveryCacheItem() throws {
        let root = try TemporaryDirectory()
        let cache = root.url.appendingPathComponent("cache")
        try writeCachedBinary(cache: cache, version: "2.0.0", platform: "macos-arm64", contents: "current")
        try writeCachedBinary(cache: cache, version: "1.9.0", platform: "linux-x86_64", contents: "old")
        try "note".write(to: cache.appendingPathComponent("README"), atomically: true, encoding: .utf8)

        let result = try CacheManager.clean(cacheRoot: cache, keepVersion: "2.0.0", all: true)

        XCTAssertEqual(Set(result.removedPaths), ["README", "v1.9.0", "v2.0.0"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path), [])
    }

    private func writeCachedBinary(cache: URL, version: String, platform: String, contents: String) throws {
        let binary = cache
            .appendingPathComponent("v\(version)")
            .appendingPathComponent(platform)
            .appendingPathComponent("inkstead-writer")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }
}
