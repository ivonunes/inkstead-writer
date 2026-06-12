import Foundation
import XCTest

final class PortabilityTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testURLNetworkingSourcesImportFoundationNetworkingForLinux() throws {
        let sources = swiftFiles(in: root.appendingPathComponent("Sources"))
        let networkingTokens = ["URLRequest", "URLSession", "HTTPURLResponse"]
        let offenders = try sources.compactMap { file -> String? in
            let text = try String(contentsOf: file, encoding: .utf8)
            guard networkingTokens.contains(where: text.contains) else { return nil }
            let importCount = text.components(separatedBy: "import FoundationNetworking").count - 1
            let hasConditionalImport = text.contains("#if canImport(FoundationNetworking)") && importCount == 1
            return hasConditionalImport ? nil : relativePath(file, from: root)
        }

        XCTAssertEqual(offenders, [])
    }

    func testSwiftPackageStaysSingleBinaryWithoutNpmRuntimeDependencies() throws {
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        XCTAssertTrue(manifest.contains(#".executable(name: "inkstead-writer""#))
        XCTAssertTrue(manifest.contains(#".library(name: "InksteadWriter""#))
        XCTAssertTrue(manifest.contains("libjpeg-turbo"))
        XCTAssertTrue(manifest.contains("libspng"))
        XCTAssertTrue(manifest.contains("libwebp"))
        XCTAssertFalse(manifest.contains("resources:"))
    }

    func testCIExercisesLinuxAndMacReleaseBuildsWithoutNpm() throws {
        let testWorkflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/test.yml"), encoding: .utf8)
        let releaseWorkflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
        let workflows = testWorkflow + "\n" + releaseWorkflow

        XCTAssertTrue(testWorkflow.contains("container:"))
        XCTAssertTrue(testWorkflow.contains("image: swift:6.3"))
        XCTAssertFalse(workflows.contains("image: swift:latest"))
        XCTAssertTrue(testWorkflow.contains("swift test"))
        XCTAssertTrue(testWorkflow.contains("swift build -c release --static-swift-stdlib"))
        XCTAssertTrue(testWorkflow.contains("runs-on: macos-latest"))
        XCTAssertTrue(testWorkflow.contains("pull_request:"))
        XCTAssertFalse(testWorkflow.contains("push:"))
        XCTAssertTrue(testWorkflow.contains("actions/cache"))
        XCTAssertTrue(releaseWorkflow.contains("image: swift:6.3"))
        XCTAssertTrue(releaseWorkflow.contains("runner: macos-latest"))
        XCTAssertTrue(releaseWorkflow.contains("runner: macos-26-intel"))
        XCTAssertTrue(releaseWorkflow.contains("arch: x86_64"))
        XCTAssertTrue(releaseWorkflow.contains("arch: aarch64"))
        XCTAssertTrue(releaseWorkflow.contains("arch: arm64"))
        XCTAssertTrue(releaseWorkflow.contains("swift test"))
        XCTAssertTrue(releaseWorkflow.contains("needs:"))
        XCTAssertTrue(releaseWorkflow.contains("- linux"))
        XCTAssertTrue(releaseWorkflow.contains("- macos"))
        XCTAssertTrue(releaseWorkflow.contains("inkstead-writer-${GITHUB_REF_NAME}-linux-${{ matrix.arch }}.tar.gz"))
        XCTAssertTrue(releaseWorkflow.contains("inkstead-writer-${GITHUB_REF_NAME}-macos-${{ matrix.arch }}.tar.gz"))
        XCTAssertTrue(releaseWorkflow.contains("Smoke test archive"))
        XCTAssertTrue(releaseWorkflow.contains("inkstead-writer-${GITHUB_REF_NAME}-SHA256SUMS"))
        XCTAssertTrue(releaseWorkflow.contains("sha256sum -c \"inkstead-writer-${GITHUB_REF_NAME}-SHA256SUMS\""))
        XCTAssertFalse(releaseWorkflow.contains("actions/configure-pages"))
        XCTAssertFalse(releaseWorkflow.contains("actions/upload-pages-artifact"))
        XCTAssertFalse(releaseWorkflow.contains("actions/deploy-pages"))
        XCTAssertFalse(releaseWorkflow.contains("deploy-docs"))
        XCTAssertFalse(workflows.contains("Checkout Plume"))
        XCTAssertFalse(workflows.contains("../plume"))
        XCTAssertFalse(workflows.contains("npm"))
        XCTAssertFalse(workflows.contains("npx"))
    }

    private func swiftFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && url.pathExtension == "swift" ? url : nil
        }.sorted { $0.path < $1.path }
    }

    private func relativePath(_ url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return path }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
