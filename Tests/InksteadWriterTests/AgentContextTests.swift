import XCTest
@testable import InksteadWriter

final class AgentContextTests: XCTestCase {
    func testRendererIncludesProjectSpecificPlumeGuidance() throws {
        let root = try TemporaryDirectory()
        try "{}".write(to: root.url.appendingPathComponent("inkstead-writer.json"), atomically: true, encoding: .utf8)

        let config = InksteadWriterConfig(
            version: "2.0.0",
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Ivo"),
            content: ContentConfig(
                posts: "content/notes",
                pages: "content/pages",
                media: "content/media",
                collections: "content/collections"
            ),
            build: BuildConfig(output: "public"),
            assets: AssetsConfig(passthrough: [PassthroughAsset(from: "public/assets", to: "assets")]),
            theme: ThemeConfig(path: "custom-theme", showPoweredBy: false),
            data: ["repos": DataSourceConfig(file: "data/repos.json")],
            connection: AppConnectionConfig(provider: .github, repository: "me/site", branch: "main"),
            ci: CiConfig(provider: .githubActions),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "site"),
            syndication: SyndicationConfig(providers: [.mastodon])
        )

        let output = AgentContextRenderer.render(root: root.url, config: config)

        XCTAssertTrue(output.contains("# Inkstead Writer Agent Context"))
        XCTAssertTrue(output.contains("Site title: My Website"))
        XCTAssertTrue(output.contains("Config: inkstead-writer.json"))
        XCTAssertTrue(output.contains("`custom-theme/**/*.plume`"))
        XCTAssertTrue(output.contains("Data sources: `data.repos`"))
        XCTAssertTrue(output.contains("App connection repository: `me/site`"))
        XCTAssertTrue(output.contains("`@script { ... }`"))
        XCTAssertTrue(output.contains("`@script(language: \"javascript\")`"))
        XCTAssertTrue(output.contains("@navigation(root: \"main\", viewTransitions: true)"))
        XCTAssertTrue(output.contains("page.measure(event.target"))
        XCTAssertTrue(output.contains("Do not write Liquid syntax"))
        XCTAssertTrue(output.contains("Run `./inkstead-writer theme check` after template changes."))
        XCTAssertTrue(output.contains("Run `./inkstead-writer build` when changing rendering"))
    }

    func testRendererFallsBackToLegacyConfigNameWhenNeeded() throws {
        let root = try TemporaryDirectory()
        try "{}".write(to: root.url.appendingPathComponent("inkstead.json"), atomically: true, encoding: .utf8)
        let config = InksteadWriterConfig(site: SiteConfig(title: "Legacy", url: "https://example.com", author: "Ivo"))

        let output = AgentContextRenderer.render(root: root.url, config: config)

        XCTAssertTrue(output.contains("Config: inkstead.json"))
    }

    func testWritesAgentsMarkdownForInitializedSite() throws {
        let parent = try TemporaryDirectory()
        let site = parent.url.appendingPathComponent("site")
        _ = try SiteInitializer.initSite(at: site, options: InitSiteOptions(ci: nil, deploy: nil))

        let path = try SiteInitializer.writeAgentContext(at: site)
        let output = try String(contentsOf: site.appendingPathComponent(path), encoding: .utf8)

        XCTAssertEqual(path, "AGENTS.md")
        XCTAssertTrue(output.contains("# Inkstead Writer Agent Context"))
        XCTAssertTrue(output.contains("Config: inkstead-writer.json"))
        XCTAssertTrue(output.contains("Run `./inkstead-writer build` when changing rendering"))
    }
}
