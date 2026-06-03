import Foundation
import XCTest
@testable import InksteadWriter

final class SiteWrapperTests: XCTestCase {
    func testGlobalLauncherFindsSiteRootAndExecsCachedSiteVersion() throws {
        #if os(Windows)
        throw XCTSkip("The generated launcher is a POSIX shell script.")
        #else
        let temp = try TemporaryDirectory()
        let bin = temp.url.appendingPathComponent("bin")
        let site = temp.url.appendingPathComponent("site")
        let nested = site.appendingPathComponent("content/posts")
        let cache = temp.url.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try """
        {
          "version": "2.0.0",
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" }
        }
        """.write(to: site.appendingPathComponent("inkstead-writer.json"), atomically: true, encoding: .utf8)

        let launcher = bin.appendingPathComponent("inkstead-writer")
        try SiteWrapper.script.write(to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        let platform = try InksteadWriterReleaseResolver.currentPlatform()
        let cached = InksteadWriterReleaseResolver.cachedBinary(cacheRoot: cache, version: "2.0.0", platform: platform)
        try FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        #!/bin/sh
        printf 'cwd=%s\\n' "$PWD"
        printf 'args=%s\\n' "$*"
        """.write(to: cached, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cached.path)

        let output = try runLauncher(launcher, arguments: ["build", "--verbose"], cwd: nested, environment: [
            "INKSTEAD_WRITER_CACHE_DIR": cache.path
        ])

        XCTAssertEqual(output.status, 0)
        let cwdLine = try XCTUnwrap(output.stdout.components(separatedBy: .newlines).first { $0.hasPrefix("cwd=") })
        let launchedCWD = URL(fileURLWithPath: String(cwdLine.dropFirst(4))).standardizedFileURL.resolvingSymlinksInPath()
        XCTAssertEqual(launchedCWD.path, site.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertTrue(output.stdout.contains("args=build --verbose"))
        XCTAssertEqual(output.stderr, "")
        #endif
    }

    func testGlobalLauncherExplainsNonSiteCommandsOutsideASite() throws {
        #if os(Windows)
        throw XCTSkip("The generated launcher is a POSIX shell script.")
        #else
        let temp = try TemporaryDirectory()
        let launcher = temp.url.appendingPathComponent("inkstead-writer")
        let cwd = temp.url.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try SiteWrapper.script.write(to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        let output = try runLauncher(launcher, arguments: ["build"], cwd: cwd, environment: [
            "INKSTEAD_WRITER_CACHE_DIR": temp.url.appendingPathComponent("cache").path
        ])

        XCTAssertNotEqual(output.status, 0)
        XCTAssertTrue(output.stderr.contains("not inside an Inkstead Writer site"))
        XCTAssertTrue(output.stderr.contains("inkstead-writer init my-site"))
        XCTAssertEqual(output.stdout, "")
        #endif
    }

    private func runLauncher(
        _ launcher: URL,
        arguments: [String],
        cwd: URL,
        environment: [String: String]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.currentDirectoryURL = cwd
        process.executableURL = launcher
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}
