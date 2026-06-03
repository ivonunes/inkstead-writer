import Foundation
import XCTest
@testable import InksteadWriter

final class DocumentationTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func testReferencedDocsAssetsExist() throws {
        let docsRoot = root.appendingPathComponent("docs")
        var missing: [String] = []
        for file in markdownFiles(in: docsRoot) {
            let markdown = try String(contentsOf: file, encoding: .utf8)
            for asset in matches(in: markdown, pattern: #"!\[[^\]]*]\((/assets/[^)]+)\)"#) {
                let path = String(asset.dropFirst())
                let assetURL = docsRoot.appendingPathComponent(path)
                if !FileManager.default.fileExists(atPath: assetURL.path) {
                    missing.append("\(relativePath(file, from: docsRoot)) -> \(asset)")
                }
            }
        }
        XCTAssertEqual(missing, [])
    }

    func testPublicStyleSurfacesSupportExpectedColorSchemes() throws {
        let source = root.appendingPathComponent("Sources/InksteadWriter/Templates/DefaultTheme/components/SiteStyles.plume")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertTrue(text.contains("color-scheme: light dark"), source.path)
        XCTAssertTrue(text.contains("@media (prefers-color-scheme: dark)"), source.path)
    }

    func testDocsUseSingleBinaryWorkflowTerminology() throws {
        let docsRoot = root.appendingPathComponent("docs")
        let files = [root.appendingPathComponent("README.md")] + markdownFiles(in: docsRoot)
        let stale = try files.compactMap { file -> String? in
            let markdown = try String(contentsOf: file, encoding: .utf8)
            return hasMatch(in: markdown, pattern: #"\b(npm|npx|site\.config\.ts|defineConfig|\.liquid)\b"#)
                ? relativePath(file, from: root)
                : nil
        }
        XCTAssertEqual(stale, [])
    }

    func testPublishedLauncherScriptMatchesGeneratedSiteWrapper() throws {
        let launcher = try String(contentsOf: root.appendingPathComponent("support/inkstead-writer"), encoding: .utf8)
        XCTAssertEqual(
            launcher.trimmingCharacters(in: .newlines),
            SiteWrapper.script.trimmingCharacters(in: .newlines)
        )
    }

    func testInstallScriptIsExecutableAndDocumented() throws {
        let installScript = root.appendingPathComponent("support/install.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installScript.path))

        let script = try String(contentsOf: installScript, encoding: .utf8)
        XCTAssertTrue(script.contains("INKSTEAD_WRITER_INSTALL_DIR"))
        XCTAssertTrue(script.contains("SHA256SUMS"))
        XCTAssertTrue(script.contains("/usr/local/bin"))

        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let gettingStarted = try String(contentsOf: root.appendingPathComponent("docs/getting-started.md"), encoding: .utf8)
        for markdown in [readme, gettingStarted] {
            XCTAssertTrue(markdown.contains("curl -fsSL https://install.inkstead.dev/writer | sh"))
            XCTAssertTrue(markdown.contains("brew tap ivonunes/tap"))
            XCTAssertTrue(markdown.contains("brew install inkstead-writer"))
        }
    }

    func testInstallScriptCanInstallLatestOrPinnedLauncherSafely() throws {
        let script = try String(contentsOf: root.appendingPathComponent("support/install.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("https://api.github.com/repos/$REPOSITORY/releases/latest"))
        XCTAssertTrue(script.contains(#"VERSION="${1#v}""#))
        XCTAssertTrue(script.contains("https://github.com/$REPOSITORY/releases/download/v$VERSION/$ASSET"))
        XCTAssertTrue(script.contains("https://github.com/$REPOSITORY/releases/download/v$VERSION/inkstead-writer-v$VERSION-SHA256SUMS"))
        XCTAssertTrue(script.contains(#"verify_checksum "$LAUNCHER" "$(checksum_for_asset "$VERSION" "$ASSET")""#))
        XCTAssertTrue(script.contains("sudo install -m 755"))
        XCTAssertTrue(script.contains("trap cleanup 0 1 2 15"))
    }

    func testLauncherCanBootstrapLegacySitesForMigrationCommands() throws {
        XCTAssertTrue(SiteWrapper.script.contains("site.config.ts"))
        XCTAssertTrue(SiteWrapper.script.contains("migrate|update"))
        XCTAssertTrue(SiteWrapper.script.contains("does not record an Inkstead Writer version yet"))
        XCTAssertTrue(SiteWrapper.script.contains("build        Build the current site"))
        XCTAssertFalse(SiteWrapper.script.contains("project context"))
    }

    func testRepositoryDoesNotShipLegacyNpmProjectFiles() throws {
        let forbidden = [
            "package.json",
            "package-lock.json",
            "tsconfig.json",
            "vite.writer.config.ts",
            "vitest.config.ts",
            "scripts/build-docs.mjs",
            "scripts/copy-template-assets.mjs"
        ]
        let present = forbidden.filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
        XCTAssertEqual(present, [])

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("src").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("tests/content-build.test.ts").path))
    }

    private func markdownFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && url.pathExtension == "md" ? url : nil
        }.sorted { $0.path < $1.path }
    }

    private func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 1, let range = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func hasMatch(in text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private func relativePath(_ url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return path }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
