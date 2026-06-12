import XCTest
@testable import InksteadWriter

final class PublishTests: XCTestCase {
    private let config = InksteadWriterConfig(site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"))

    func testSkipsSyndicationCommitOutsideCi() throws {
        let root = try TemporaryDirectory()
        let commands = try Publish.commitSyndicationChanges(root: root.url, config: config, env: [:]) { _, _ in
            XCTFail("No git commands should run outside CI.")
            return 0
        }

        XCTAssertTrue(commands.isEmpty)
    }

    func testCommitsAndPushesSyndicationChangesInGitHubActions() throws {
        let root = try TemporaryDirectory()
        var captured: [DeployCommand] = []

        let commands = try Publish.commitSyndicationChanges(root: root.url, config: config, env: ["GITHUB_ACTIONS": "true"]) { command, cwd in
            XCTAssertEqual(cwd, root.url)
            captured.append(command)
            return 0
        }

        XCTAssertEqual(commands, captured)
        XCTAssertEqual(captured.map(commandLine), [
            "git config user.name github-actions[bot]",
            "git config user.email 41898282+github-actions[bot]@users.noreply.github.com",
            "git add content/posts",
            "git commit -m Update syndication data [skip ci]",
            "git push"
        ])
    }

    func testStagesConfiguredPostsPath() throws {
        let root = try TemporaryDirectory()
        let config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name"),
            content: ContentConfig(posts: "writing/posts")
        )
        var captured: [DeployCommand] = []

        _ = try Publish.commitSyndicationChanges(root: root.url, config: config, env: ["GITHUB_ACTIONS": "true"]) { command, _ in
            captured.append(command)
            return 0
        }

        XCTAssertTrue(captured.map(commandLine).contains("git add writing/posts"))
        XCTAssertFalse(captured.map(commandLine).contains("git add content/posts"))
    }

    func testStopsBeforePushWhenCommitHasNoChanges() throws {
        let root = try TemporaryDirectory()
        var captured: [DeployCommand] = []

        _ = try Publish.commitSyndicationChanges(root: root.url, config: config, env: ["GITHUB_ACTIONS": "true"]) { command, _ in
            captured.append(command)
            return command.arguments.first == "commit" ? 1 : 0
        }

        XCTAssertEqual(captured.map(commandLine), [
            "git config user.name github-actions[bot]",
            "git config user.email 41898282+github-actions[bot]@users.noreply.github.com",
            "git add content/posts",
            "git commit -m Update syndication data [skip ci]"
        ])
    }

    func testFailsWhenStagingOrConfigCommandsExitNonZero() throws {
        let root = try TemporaryDirectory()

        XCTAssertThrowsError(try Publish.commitSyndicationChanges(root: root.url, config: config, env: ["GITHUB_ACTIONS": "true"]) { command, _ in
            command.arguments.first == "add" ? 128 : 0
        }) { error in
            XCTAssertEqual(error as? InksteadWriterError, .io("git add content/posts exited with status 128."))
        }

        XCTAssertThrowsError(try Publish.commitSyndicationChanges(root: root.url, config: config, env: ["GITHUB_ACTIONS": "true"]) { command, _ in
            command.arguments.first == "config" ? 1 : 0
        })

        XCTAssertThrowsError(try Publish.commitSyndicationChanges(root: root.url, config: config, env: ["GITHUB_ACTIONS": "true"]) { command, _ in
            command.arguments.first == "push" ? 1 : 0
        })
    }

    func testUsesGitLabRemoteAndBranchWhenAvailable() throws {
        let root = try TemporaryDirectory()
        var captured: [DeployCommand] = []
        let env = [
            "GITLAB_CI": "true",
            "CI_JOB_TOKEN": "token",
            "CI_SERVER_HOST": "gitlab.example.com",
            "CI_PROJECT_PATH": "owner/site",
            "CI_COMMIT_BRANCH": "main"
        ]

        _ = try Publish.commitSyndicationChanges(root: root.url, config: config, env: env) { command, _ in
            captured.append(command)
            return 0
        }

        XCTAssertEqual(captured.map(commandLine), [
            "git config user.name GitLab CI",
            "git config user.email gitlab-ci@example.invalid",
            "git add content/posts",
            "git commit -m Update syndication data [skip ci]",
            "git remote set-url origin https://gitlab-ci-token:token@gitlab.example.com/owner/site.git",
            "git push origin HEAD:main"
        ])
    }

    func testPublishBuildsDeploysSyndicatesRedeploysAndCommitsWhenSyndicationChanges() async throws {
        let root = try TemporaryDirectory()
        var events: [String] = []

        let result = try await Publish.publishSite(
            root: root.url,
            config: config,
            build: { buildRoot, buildConfig in
                XCTAssertEqual(buildRoot, root.url)
                XCTAssertEqual(buildConfig.site.title, "My Website")
                events.append("build")
            },
            deploy: { deployRoot, deployConfig in
                XCTAssertEqual(deployRoot, root.url)
                XCTAssertEqual(deployConfig.site.url, "https://example.com")
                events.append("deploy")
            },
            syndicate: { syndicateRoot, syndicateConfig in
                XCTAssertEqual(syndicateRoot, root.url)
                XCTAssertEqual(syndicateConfig.site.author, "Your Name")
                events.append("syndicate")
                return SyndicationSummary(changed: true, published: 1, failed: 0)
            },
            commit: { commitRoot, commitConfig in
                XCTAssertEqual(commitRoot, root.url)
                XCTAssertEqual(commitConfig.site.title, "My Website")
                events.append("commit")
            }
        )

        XCTAssertEqual(result, SyndicationSummary(changed: true, published: 1, failed: 0))
        XCTAssertEqual(events, ["build", "deploy", "syndicate", "build", "deploy", "commit"])
    }

    func testPublishDoesNotRedeployOrCommitWhenSyndicationDoesNotChangeFiles() async throws {
        let root = try TemporaryDirectory()
        var events: [String] = []

        let result = try await Publish.publishSite(
            root: root.url,
            config: config,
            build: { _, _ in events.append("build") },
            deploy: { _, _ in events.append("deploy") },
            syndicate: { _, _ in
                events.append("syndicate")
                return SyndicationSummary(changed: false, published: 0, failed: 0)
            },
            commit: { _, _ in
                XCTFail("Publish should not commit when syndication did not change frontmatter.")
            }
        )

        XCTAssertEqual(result, SyndicationSummary(changed: false, published: 0, failed: 0))
        XCTAssertEqual(events, ["build", "deploy", "syndicate"])
    }

    func testPublishCompletesAndLogsWhenSyndicationFails() async throws {
        let root = try TemporaryDirectory()
        var events: [String] = []
        var logs: [String] = []

        let result = try await Publish.publishSite(
            root: root.url,
            config: config,
            build: { _, _ in events.append("build") },
            deploy: { _, _ in events.append("deploy") },
            syndicate: { _, _ in
                events.append("syndicate")
                return SyndicationSummary(changed: true, published: 1, failed: 2)
            },
            commit: { _, _ in events.append("commit") },
            log: { logs.append($0) }
        )

        XCTAssertEqual(result, SyndicationSummary(changed: true, published: 1, failed: 2))
        XCTAssertEqual(events, ["build", "deploy", "syndicate", "build", "deploy", "commit"])
        XCTAssertTrue(logs.contains { $0.contains("Syndication failed for 2 targets") })
    }

    func testPublishPropagatesSyndicationErrors() async throws {
        let root = try TemporaryDirectory()

        do {
            _ = try await Publish.publishSite(
                root: root.url,
                config: config,
                build: { _, _ in },
                deploy: { _, _ in },
                syndicate: { _, _ in throw InksteadWriterError.config("broken post") },
                commit: { _, _ in XCTFail("Publish should not commit when syndication throws.") }
            )
            XCTFail("Publish should propagate syndication errors.")
        } catch {
            XCTAssertEqual(error as? InksteadWriterError, .config("broken post"))
        }
    }

    private func commandLine(_ command: DeployCommand) -> String {
        ([command.executable] + command.arguments).joined(separator: " ")
    }
}
