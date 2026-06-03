import XCTest
@testable import InksteadWriter

final class AppConnectionTests: XCTestCase {
    func testPublicConfigUsesConnectionOverrides() throws {
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            content: ContentConfig(),
            connection: AppConnectionConfig(
                provider: .github,
                repository: "me/site",
                branch: "main",
                categories: ["Photography", "Essays"]
            ),
            syndication: SyndicationConfig(providers: [.mastodon, .bluesky])
        )

        let publicConfig = AppConnectionSupport.publicConfig(config, environment: [:])

        XCTAssertEqual(publicConfig.version, InksteadWriterMetadata.currentVersion)
        XCTAssertEqual(publicConfig.siteName, "My Website")
        XCTAssertEqual(publicConfig.provider, .github)
        XCTAssertEqual(publicConfig.owner, "me")
        XCTAssertEqual(publicConfig.repo, "site")
        XCTAssertEqual(publicConfig.branch, "main")
        XCTAssertEqual(publicConfig.postsPath, "content/posts")
        XCTAssertEqual(publicConfig.mediaPath, "content/media")
        XCTAssertEqual(publicConfig.syndicationProviders, [.mastodon, .bluesky])
        XCTAssertEqual(publicConfig.categories, ["Photography", "Essays"])
    }

    func testPublicConfigFallsBackToConfiguredCiProvider() throws {
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            connection: AppConnectionConfig(repository: "group/site"),
            ci: CiConfig(provider: .gitlabCi)
        )

        let publicConfig = AppConnectionSupport.publicConfig(config, environment: [:])

        XCTAssertEqual(publicConfig.version, InksteadWriterMetadata.currentVersion)
        XCTAssertEqual(publicConfig.provider, .gitlab)
        XCTAssertEqual(publicConfig.owner, "group")
        XCTAssertEqual(publicConfig.repo, "site")
    }

    func testPublicConfigPrefersDetectedEnvironmentOverConfiguredCiProvider() throws {
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            connection: AppConnectionConfig(),
            ci: CiConfig(provider: .githubActions)
        )

        let publicConfig = AppConnectionSupport.publicConfig(config, environment: [
            "CI_PROJECT_PATH": "group/site",
            "CI_COMMIT_BRANCH": "main",
            "CI_SERVER_URL": "https://gitlab.example.com"
        ])

        XCTAssertEqual(publicConfig.provider, .gitlab)
        XCTAssertEqual(publicConfig.owner, "group")
        XCTAssertEqual(publicConfig.repo, "site")
        XCTAssertEqual(publicConfig.branch, "main")
        XCTAssertEqual(publicConfig.instanceUrl, "https://gitlab.example.com")
    }

    func testBuildWritesPublicConfigAtSiteRoot() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/posts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/pages"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("content/media"), withIntermediateDirectories: true)
        try """
        ---
        title: Visible
        date: 2026-05-10T18:30:00+01:00
        ---

        Body.
        """.write(to: root.url.appendingPathComponent("content/posts/2026-05-10-visible.md"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            content: ContentConfig(),
            connection: AppConnectionConfig(provider: .github, repository: "example/site", branch: "main")
        )

        try SiteBuilder.build(root: root.url, config: config)

        let dist = root.url.appendingPathComponent("dist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dist.appendingPathComponent("writer").path))

        let publicConfig = try JSONDecoder().decode(
            PublicAppConnectionConfig.self,
            from: Data(contentsOf: dist.appendingPathComponent("inkstead-writer.json"))
        )
        XCTAssertEqual(publicConfig.version, InksteadWriterMetadata.currentVersion)
        XCTAssertEqual(publicConfig.siteName, "My Website")
        XCTAssertEqual(publicConfig.provider, .github)
        XCTAssertEqual(publicConfig.owner, "example")
        XCTAssertEqual(publicConfig.repo, "site")
        XCTAssertEqual(publicConfig.branch, "main")
        XCTAssertEqual(publicConfig.postsPath, "content/posts")
        XCTAssertEqual(publicConfig.mediaPath, "content/media")
    }
}
