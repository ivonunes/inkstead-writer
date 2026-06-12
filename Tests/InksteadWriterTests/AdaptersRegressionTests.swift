import XCTest
@testable import InksteadWriter

final class AdaptersRegressionTests: XCTestCase {
    func testForgejoWorkflowForwardsSecretsAndInstallsHookDependencies() throws {
        var config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            ci: CiConfig(provider: .forgejoActions),
            deploy: DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker"),
            syndication: SyndicationConfig(providers: [.mastodon])
        )
        config.hooks = HooksConfig(beforeBuild: ["npm run build:js"], afterBuild: nil)

        let workflow = try XCTUnwrap(AdapterSupport.workflowFile(config: config))

        XCTAssertEqual(workflow.path, ".forgejo/workflows/publish.yml")
        XCTAssertTrue(workflow.content.contains("\n    env:\n"))
        XCTAssertTrue(workflow.content.contains("CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}"))
        XCTAssertTrue(workflow.content.contains("CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}"))
        XCTAssertTrue(workflow.content.contains("MASTODON_INSTANCE_URL: ${{ secrets.MASTODON_INSTANCE_URL }}"))
        XCTAssertTrue(workflow.content.contains("MASTODON_ACCESS_TOKEN: ${{ secrets.MASTODON_ACCESS_TOKEN }}"))
        // All supported syndication variables are forwarded, not just the
        // enabled providers', so enabling one later only needs a CI secret.
        XCTAssertTrue(workflow.content.contains("BLUESKY_APP_PASSWORD: ${{ secrets.BLUESKY_APP_PASSWORD }}"))
        XCTAssertTrue(workflow.content.contains("FLICKR_ACCESS_SECRET: ${{ secrets.FLICKR_ACCESS_SECRET }}"))
        XCTAssertTrue(workflow.content.contains("PIXELFED_ACCESS_TOKEN: ${{ secrets.PIXELFED_ACCESS_TOKEN }}"))
        XCTAssertTrue(workflow.content.contains("\n      - uses: actions/setup-node@v6"))
        XCTAssertTrue(workflow.content.contains("node-version: lts/*"))
        XCTAssertTrue(workflow.content.contains("- run: npm ci"))
        XCTAssertLessThan(
            try XCTUnwrap(workflow.content.range(of: "npm ci")?.lowerBound),
            try XCTUnwrap(workflow.content.range(of: "./inkstead-writer publish")?.lowerBound)
        )
        XCTAssertTrue(workflow.content.contains("apt-get install -y --no-install-recommends ca-certificates curl tar"))
        XCTAssertTrue(workflow.content.contains("- uses: actions/checkout@v6"))
        XCTAssertTrue(workflow.content.contains("./inkstead-writer cache clean"))
    }

    func testForgejoWorkflowMatchesGitHubSecretForwarding() throws {
        let site = SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name")
        let deploy = DeployConfig(provider: .cloudflareWorkers, projectName: "my-worker")
        let github = try XCTUnwrap(AdapterSupport.workflowFile(config: InksteadWriterConfig(
            site: site,
            ci: CiConfig(provider: .githubActions),
            deploy: deploy
        )))
        let forgejo = try XCTUnwrap(AdapterSupport.workflowFile(config: InksteadWriterConfig(
            site: site,
            ci: CiConfig(provider: .forgejoActions),
            deploy: deploy
        )))

        for requirement in AdapterSupport.requirements(for: InksteadWriterConfig(site: site, deploy: deploy)) {
            let line = "      \(requirement.environmentVariable): ${{ secrets.\(requirement.environmentVariable) }}"
            XCTAssertTrue(github.content.contains(line), "GitHub workflow is missing \(requirement.environmentVariable)")
            XCTAssertTrue(forgejo.content.contains(line), "Forgejo workflow is missing \(requirement.environmentVariable)")
        }
    }

    func testForgejoWorkflowWithoutDeployOrHooksForwardsSyndicationSecretsOnly() throws {
        let workflow = try XCTUnwrap(AdapterSupport.workflowFile(config: InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            ci: CiConfig(provider: .forgejoActions)
        )))

        XCTAssertTrue(workflow.content.contains("env:"))
        XCTAssertTrue(workflow.content.contains("MASTODON_ACCESS_TOKEN: ${{ secrets.MASTODON_ACCESS_TOKEN }}"))
        XCTAssertFalse(workflow.content.contains("CLOUDFLARE_API_TOKEN"))
        XCTAssertFalse(workflow.content.contains("NETLIFY_SITE_ID"))
        XCTAssertFalse(workflow.content.contains("setup-node"))
        XCTAssertFalse(workflow.content.contains("npm"))
    }
}
