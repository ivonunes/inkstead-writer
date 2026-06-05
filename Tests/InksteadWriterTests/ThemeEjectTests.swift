import XCTest
@testable import InksteadWriter

final class ThemeEjectTests: XCTestCase {
    func testCopiesDefaultPlumeTemplatesWithoutOverwritingExistingFiles() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme/pages"), withIntermediateDirectories: true)
        try "Custom home".write(to: root.url.appendingPathComponent("theme/pages/home.plume"), atomically: true, encoding: .utf8)

        let result = try ThemeEjector.eject(root: root.url)

        XCTAssertTrue(result.copied.contains("theme/layouts/default.plume"))
        XCTAssertTrue(result.copied.contains("theme/pages/feed.xml.plume"))
        XCTAssertTrue(result.copied.contains("theme/pages/feed.json.plume"))
        XCTAssertTrue(result.copied.contains("theme/pages/post.plume"))
        XCTAssertTrue(result.copied.contains("theme/pages/404.plume"))
        XCTAssertTrue(result.skipped.contains("theme/pages/home.plume"))
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("theme/pages/home.plume"), encoding: .utf8), "Custom home")

        let forced = try ThemeEjector.eject(root: root.url, force: true)
        XCTAssertTrue(forced.copied.contains("theme/pages/home.plume"))
        XCTAssertTrue(forced.copied.contains("theme/components/PostList.plume"))
        XCTAssertTrue(try String(contentsOf: root.url.appendingPathComponent("theme/components/PostList.plume"), encoding: .utf8).contains("post-list"))
    }

    func testEjectDoesNotShadowExistingFlatTemplates() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("theme"), withIntermediateDirectories: true)
        try "Flat custom home".write(to: root.url.appendingPathComponent("theme/home.plume"), atomically: true, encoding: .utf8)

        let result = try ThemeEjector.eject(root: root.url)

        XCTAssertTrue(result.skipped.contains("theme/pages/home.plume"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("theme/pages/home.plume").path))
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("theme/home.plume"), encoding: .utf8), "Flat custom home")
    }

    func testCanEjectIntoConfiguredThemePath() throws {
        let root = try TemporaryDirectory()

        let result = try ThemeEjector.eject(root: root.url, themePath: "custom-theme")

        XCTAssertTrue(result.copied.contains("custom-theme/layouts/default.plume"))
        XCTAssertTrue(result.copied.contains("custom-theme/components/SiteStyles.plume"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("custom-theme/layouts/default.plume").path))
    }
}
