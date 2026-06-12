import Foundation
import XCTest
@testable import InksteadWriter

final class BuildSupportTests: XCTestCase {
    func testRelativePathReturnsEmptyStringForRootItself() {
        let root = URL(fileURLWithPath: "/tmp/a/b")

        XCTAssertEqual(FileTreeSupport.relativePath(of: URL(fileURLWithPath: "/tmp/a/b"), under: root), "")
    }

    func testRelativePathKeepsRepeatedRootComponents() {
        let root = URL(fileURLWithPath: "/tmp/a/b")
        let item = URL(fileURLWithPath: "/tmp/a/b/x/a/b/f")

        XCTAssertEqual(FileTreeSupport.relativePath(of: item, under: root), "x/a/b/f")
    }

    func testRelativePathKeepsRepeatedAbsoluteRootPath() {
        let root = URL(fileURLWithPath: "/tmp/a/b")
        let item = URL(fileURLWithPath: "/tmp/a/b/nested/tmp/a/b/f")

        XCTAssertEqual(FileTreeSupport.relativePath(of: item, under: root), "nested/tmp/a/b/f")
    }

    func testRelativePathHandlesSpaces() {
        let root = URL(fileURLWithPath: "/tmp/My Site/media")
        let item = URL(fileURLWithPath: "/tmp/My Site/media/photo album/img 1.jpg")

        XCTAssertEqual(FileTreeSupport.relativePath(of: item, under: root), "photo album/img 1.jpg")
    }

    func testRelativePathReturnsNilOutsideRoot() {
        let root = URL(fileURLWithPath: "/tmp/a/b")

        XCTAssertNil(FileTreeSupport.relativePath(of: URL(fileURLWithPath: "/tmp/a/c/f"), under: root))
    }

    func testRelativePathDoesNotMatchSiblingPrefix() {
        let root = URL(fileURLWithPath: "/tmp/ab")

        XCTAssertNil(FileTreeSupport.relativePath(of: URL(fileURLWithPath: "/tmp/abc/f"), under: root))
    }

    func testFilesHaveSameContentsComparesBytes() throws {
        let root = try TemporaryDirectory()
        let first = root.url.appendingPathComponent("a.txt")
        let second = root.url.appendingPathComponent("b.txt")
        let third = root.url.appendingPathComponent("c.txt")
        try Data("same".utf8).write(to: first)
        try Data("same".utf8).write(to: second)
        try Data("diff".utf8).write(to: third)

        XCTAssertTrue(try FileTreeSupport.filesHaveSameContents(first, second))
        XCTAssertFalse(try FileTreeSupport.filesHaveSameContents(first, third))
    }

    func testEnvFileParseHandlesQuotesExportAndWhitespace() {
        let parsed = EnvFile.parse("""
        # comment line
        PLAIN=value
        export EXPORTED = "quoted value"
        SINGLE='single quoted'
          SPACED   =   spaced value
        MALFORMED LINE
        =missing-key
        URL=https://example.com/?a=b
        """)

        XCTAssertEqual(parsed["PLAIN"], "value")
        XCTAssertEqual(parsed["EXPORTED"], "quoted value")
        XCTAssertEqual(parsed["SINGLE"], "single quoted")
        XCTAssertEqual(parsed["SPACED"], "spaced value")
        XCTAssertEqual(parsed["URL"], "https://example.com/?a=b")
        XCTAssertNil(parsed["MALFORMED LINE"])
        XCTAssertNil(parsed[""])
        XCTAssertNil(parsed["# comment line"])
    }

    func testEnvFileReadReturnsEmptyForMissingFile() throws {
        let root = try TemporaryDirectory()
        XCTAssertEqual(EnvFile.read(root: root.url), [:])
    }

    func testFormatDurationUsesFinerPrecisionUnderTenSeconds() {
        XCTAssertTrue(BuildFormatting.formatDuration(since: Date()).hasSuffix("s"))
        XCTAssertTrue(BuildFormatting.formatDuration(since: Date(timeIntervalSinceNow: -2)).hasPrefix("2.0"))
        XCTAssertTrue(BuildFormatting.formatDuration(since: Date(timeIntervalSinceNow: -15)).hasPrefix("15."))
    }
}
