import XCTest
@testable import InksteadWriter

final class RequirementsDoctorTests: XCTestCase {
    func testRendersAdapterRequirements() {
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            deploy: DeployConfig(provider: .netlify),
            syndication: SyndicationConfig(providers: [.mastodon])
        )

        let requirements = RequirementsRenderer.render(config)
        XCTAssertTrue(requirements.contains("NETLIFY_SITE_ID"))
        XCTAssertTrue(requirements.contains("NETLIFY_AUTH_TOKEN"))
        XCTAssertTrue(requirements.contains("MASTODON_ACCESS_TOKEN"))
        XCTAssertTrue(requirements.contains("./inkstead-writer doctor"))
    }

    func testDoctorReportsCoreEnvironmentContentAndWorkflowDrift() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "content": { "posts": "content/posts", "pages": "content/pages", "media": "content/media" },
          "ci": { "provider": "github-actions" },
          "deploy": { "provider": "cloudflare-workers", "projectName": "my-website" },
          "syndication": { "providers": ["mastodon"] }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent(".github/workflows"), withIntermediateDirectories: true)
        try "name: Old workflow\n".write(to: root.url.appendingPathComponent(".github/workflows/publish.yml"), atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(root: root.url)
        let result = Doctor.run(root: root.url, config: config, env: [:])

        XCTAssertTrue(result.output.contains("inkstead.json found"))
        XCTAssertTrue(result.output.contains("CLOUDFLARE_API_TOKEN is missing"))
        XCTAssertTrue(result.output.contains("MASTODON_ACCESS_TOKEN is missing"))
        XCTAssertTrue(result.output.contains("differs from Inkstead Writer's current template"))
        XCTAssertFalse(result.output.contains("Agent Context"))
        XCTAssertGreaterThan(result.issues, 0)

        let plan = try MigrationPlanner.plan(root: root.url, config: config)
        XCTAssertTrue(plan.actions.contains {
            if case .write(".github/workflows/publish.yml", _, "refresh generated workflow") = $0 { return true }
            return false
        })
    }

    func testDoctorReportsLauncherDrift() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent(".github/workflows"), withIntermediateDirectories: true)
        try """
        {
          "inkstead": { "version": "2.0.0" },
          "site": { "title": "My Website", "url": "https://example.com", "author": "Your Name" },
          "ci": { "provider": "github-actions" }
        }
        """.write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        try "old launcher\n".write(to: root.url.appendingPathComponent("inkstead-writer"), atomically: true, encoding: .utf8)
        try "dist\n".write(to: root.url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try """
        name: Publish
        jobs:
          publish:
            steps:
              - run: inkstead-writer publish
        """.write(to: root.url.appendingPathComponent(".github/workflows/publish.yml"), atomically: true, encoding: .utf8)

        let result = Doctor.run(root: root.url, config: try ConfigLoader.load(root: root.url), env: [:])

        XCTAssertTrue(result.output.contains("inkstead-writer is not executable"))
        XCTAssertTrue(result.output.contains("inkstead-writer wrapper differs from Inkstead Writer's current template"))
        XCTAssertTrue(result.output.contains(".github/workflows/publish.yml runs global inkstead-writer"))
    }
}
