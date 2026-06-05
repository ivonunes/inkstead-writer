import XCTest
@testable import InksteadWriter

final class InitAndPostTests: XCTestCase {
    func testInitializesNpmFreeSiteWithVersionedConfig() throws {
        let parent = try TemporaryDirectory()
        let site = parent.url.appendingPathComponent("site")

        _ = try SiteInitializer.initSite(at: site, options: InitSiteOptions(ci: nil, deploy: nil, syndication: [.flickr]))

        XCTAssertTrue(FileManager.default.fileExists(atPath: site.appendingPathComponent("inkstead-writer.json").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: site.appendingPathComponent("inkstead-writer").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: site.appendingPathComponent("package.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: site.appendingPathComponent(".github/workflows/publish.yml").path))

        let config = try ConfigLoader.load(root: site)
        XCTAssertEqual(config.version, InksteadWriterMetadata.currentVersion)
        XCTAssertNil(config.deploy)
        XCTAssertEqual(config.syndication?.providers, [.flickr])

        let hello = try String(contentsOf: site.appendingPathComponent("content/posts/hello.md"), encoding: .utf8)
        XCTAssertFalse(hello.contains("syndicate:"))
        let gitignore = try String(contentsOf: site.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertFalse(gitignore.contains(".cache/inkstead-writer/"))
        let wrapper = try String(contentsOf: site.appendingPathComponent("inkstead-writer"), encoding: .utf8)
        XCTAssertTrue(wrapper.contains("releases/download/v$VERSION"))
        XCTAssertTrue(wrapper.contains(#"CACHE="$VERSION_CACHE/$OS-$ARCH""#))
        XCTAssertTrue(wrapper.contains(#"download_binary "$VERSION" "$(cache_root)""#))
    }

    func testParsesInitCommandOptionsWithoutTreatingFlagsAsDirectory() throws {
        let parsed = try InitCommandParser.parse([
            "--ci", "none",
            "--deploy", "netlify",
            "--syndication", "mastodon,bluesky",
            "--connection-provider", "github",
            "--connection-repository", "ivonunes/site"
        ])

        XCTAssertEqual(parsed.directory, "my-site")
        XCTAssertNil(parsed.options.ci)
        XCTAssertEqual(parsed.options.deploy, .netlify)
        XCTAssertEqual(parsed.options.syndication, [.bluesky, .mastodon])
        XCTAssertEqual(parsed.options.connection?.provider, .github)
        XCTAssertEqual(parsed.options.connection?.repository, "ivonunes/site")
        XCTAssertEqual(parsed.options.connection?.branch, "main")
    }

    func testParsesInitDirectoryAndInfersWriterProviderFromCi() throws {
        let parsed = try InitCommandParser.parse([
            "blog",
            "--ci", "forgejo-actions",
            "--deploy", "cloudflare-workers",
            "--deploy-project-name", "blog-worker",
            "--connection-repository", "ivonunes/blog",
            "--connection-instance-url", "https://codeberg.org"
        ])

        XCTAssertEqual(parsed.directory, "blog")
        XCTAssertEqual(parsed.options.ci, .forgejoActions)
        XCTAssertEqual(parsed.options.deploy, .cloudflareWorkers)
        XCTAssertEqual(parsed.options.deployProjectName, "blog-worker")
        XCTAssertEqual(parsed.options.connection?.provider, .forgejo)
        XCTAssertEqual(parsed.options.connection?.instanceUrl, "https://codeberg.org")
    }

    func testRejectsUnknownInitOptions() throws {
        XCTAssertThrowsError(try InitCommandParser.parse(["--unknown-option"])) { error in
            XCTAssertTrue(String(describing: error).contains("Unknown init option --unknown-option"))
        }
    }

    func testInitializesExistingEmptyDirectoryButRejectsNonEmptyTargets() throws {
        let parent = try TemporaryDirectory()
        let emptySite = parent.url.appendingPathComponent("empty")
        let nonEmptySite = parent.url.appendingPathComponent("non-empty")
        try FileManager.default.createDirectory(at: emptySite, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nonEmptySite, withIntermediateDirectories: true)
        try "keep".write(to: nonEmptySite.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        _ = try SiteInitializer.initSite(at: emptySite, options: InitSiteOptions(ci: nil, deploy: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: emptySite.appendingPathComponent("inkstead-writer.json").path))

        XCTAssertThrowsError(try SiteInitializer.initSite(at: nonEmptySite, options: InitSiteOptions(ci: nil, deploy: nil)))
    }

    func testInitNextStepsUseSingleBinaryCommandsAndEnvGuidance() throws {
        let parent = try TemporaryDirectory()
        let site = parent.url.appendingPathComponent("site")

        let message = try SiteInitializer.initSite(at: site, options: InitSiteOptions(ci: nil, deploy: .netlify))

        XCTAssertTrue(message.contains("./inkstead-writer dev"))
        XCTAssertTrue(message.contains("cp .env.example .env"))
        XCTAssertTrue(message.contains("./inkstead-writer doctor"))
        XCTAssertFalse(message.contains("   5."))
        XCTAssertFalse(message.contains("npm"))
    }

    func testGeneratedWorkflowsUseSiteWrapper() throws {
        let github = try XCTUnwrap(AdapterSupport.workflowFile(config: InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            ci: CiConfig(provider: .githubActions),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker")
        )))
        let gitlab = try XCTUnwrap(AdapterSupport.workflowFile(config: InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            ci: CiConfig(provider: .gitlabCi),
            deploy: DeployConfig(provider: .gitlabPages)
        )))
        let forgejo = try XCTUnwrap(AdapterSupport.workflowFile(config: InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            ci: CiConfig(provider: .forgejoActions)
        )))
        for workflow in [github.content, gitlab.content, forgejo.content] {
            XCTAssertTrue(workflow.contains("./inkstead-writer publish"))
            XCTAssertTrue(workflow.contains(".cache/inkstead-writer"))
            XCTAssertFalse(workflow.contains("releases/download"))
            XCTAssertFalse(workflow.contains("npm"))
        }
        XCTAssertTrue(github.content.contains("permissions:\n  contents: write"))
        XCTAssertTrue(github.content.contains("actions/cache@v5"))
        XCTAssertTrue(github.content.contains("id: writer_version"))
        XCTAssertTrue(github.content.contains("inkstead-writer-bin-${{ runner.os }}-${{ steps.writer_version.outputs.version }}"))
        XCTAssertTrue(github.content.contains("inkstead-writer-data-${{ runner.os }}-${{ hashFiles('inkstead-writer.json', 'content/media/**') }}"))
        XCTAssertFalse(github.content.contains("./inkstead-writer cache clean"))
        XCTAssertTrue(gitlab.content.contains("XDG_CACHE_HOME"))
        XCTAssertTrue(gitlab.content.contains("./inkstead-writer cache clean"))
        XCTAssertTrue(forgejo.content.contains("actions/cache@v5"))
        XCTAssertTrue(forgejo.content.contains("./inkstead-writer cache clean"))
    }

    func testGeneratedGitHubWorkflowInstallsNodeWhenHooksUseNPM() throws {
        var config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            ci: CiConfig(provider: .githubActions),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker")
        )
        config.hooks = HooksConfig(beforeBuild: ["npm run build:js"], afterBuild: ["node ./scripts/after-build.mjs"])

        let workflow = try XCTUnwrap(AdapterSupport.workflowFile(config: config)?.content)

        XCTAssertTrue(workflow.contains("\n      - uses: actions/setup-node@v6"))
        XCTAssertFalse(workflow.contains("\n          - uses: actions/setup-node@v6"))
        XCTAssertTrue(workflow.contains("node-version: lts/*"))
        XCTAssertTrue(workflow.contains("cache: npm"))
        XCTAssertTrue(workflow.contains("- run: npm ci"))
        XCTAssertLessThan(
            try XCTUnwrap(workflow.range(of: "npm ci")?.lowerBound),
            try XCTUnwrap(workflow.range(of: "./inkstead-writer publish")?.lowerBound)
        )
    }

    func testCreatesNewArticleAndNoteWithWriterSlugRules() throws {
        let parent = try TemporaryDirectory()
        let site = parent.url.appendingPathComponent("site")
        _ = try SiteInitializer.initSite(at: site, options: InitSiteOptions(ci: nil, deploy: nil, syndication: [.mastodon, .bluesky, .flickr]))
        let config = try ConfigLoader.load(root: site)
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12, minute: 30)))

        let article = try PostCreator.create(root: site, config: config, options: CreatePostOptions(kind: .article, title: "A New Local Article", date: date))
        let note = try PostCreator.create(root: site, config: config, options: CreatePostOptions(kind: .note, text: "📍 Tokyo, Japan\n\nLess **duct tape**, more <em>website</em>.", date: date))
        let emoji = try PostCreator.create(root: site, config: config, options: CreatePostOptions(kind: .note, text: "✨📷", date: date))

        XCTAssertEqual(article.relativePath, "content/posts/2026-05-10-a-new-local-article.md")
        XCTAssertEqual(note.relativePath, "content/posts/2026-05-10-tokyo-japan-less-duct-tape-more-website.md")
        XCTAssertEqual(emoji.relativePath, "content/posts/2026-05-10-untitled-1230.md")

        let articleBody = try String(contentsOf: article.path, encoding: .utf8)
        XCTAssertTrue(articleBody.contains("syndicate:\n  - mastodon\n  - bluesky"))
        XCTAssertFalse(articleBody.contains("flickr"))
    }
}
