import Foundation

public enum Publish {
    @discardableResult
    public static func publishSite(
        root: URL,
        config: InksteadWriterConfig,
        build: (URL, InksteadWriterConfig) throws -> Void = { root, config in
            try SiteBuilder.build(root: root, config: config, log: { print($0) })
        },
        deploy: (URL, InksteadWriterConfig) async throws -> Void = { root, config in try await Deploy.deploySite(root: root, config: config) },
        syndicate: (URL, InksteadWriterConfig) async throws -> SyndicationSummary = { root, config in try await Syndicator.syndicateSite(root: root, config: config) },
        commit: (URL, InksteadWriterConfig) throws -> Void = { root, config in _ = try commitSyndicationChanges(root: root, config: config) },
        log: (String) -> Void = { print($0) }
    ) async throws -> SyndicationSummary {
        let publishStarted = Date()
        let buildStarted = Date()
        try build(root, config)
        log("Build completed in \(BuildFormatting.formatDuration(since: buildStarted)).")

        let deployStarted = Date()
        try await deploy(root, config)
        log("Deploy completed in \(BuildFormatting.formatDuration(since: deployStarted)).")

        let syndicationStarted = Date()
        let result = try await syndicate(root, config)
        log("Syndication completed in \(BuildFormatting.formatDuration(since: syndicationStarted)). Published: \(result.published). Failed: \(result.failed).")
        if result.changed {
            let rebuildStarted = Date()
            try build(root, config)
            log("Post-syndication rebuild completed in \(BuildFormatting.formatDuration(since: rebuildStarted)).")
            let redeployStarted = Date()
            try await deploy(root, config)
            log("Post-syndication redeploy completed in \(BuildFormatting.formatDuration(since: redeployStarted)).")
            let commitStarted = Date()
            try commit(root, config)
            log("Syndication commit completed in \(BuildFormatting.formatDuration(since: commitStarted)).")
        }
        log("Publish completed in \(BuildFormatting.formatDuration(since: publishStarted)).")
        if result.failed > 0 {
            log("Syndication failed for \(result.failed) target\(result.failed == 1 ? "" : "s"); the failures are recorded in the post frontmatter. Remove a failed entry from a post's syndication block to try that target again.")
        }
        return result
    }

    @discardableResult
    public static func commitSyndicationChanges(
        root: URL,
        config: InksteadWriterConfig,
        env: [String: String] = ProcessInfo.processInfo.environment,
        run: (DeployCommand, URL) throws -> Int32 = runCommand
    ) throws -> [DeployCommand] {
        guard env["GITHUB_ACTIONS"] != nil || env["GITLAB_CI"] != nil || env["FORGEJO_ACTIONS"] != nil else {
            return []
        }

        let isGitLab = env["GITLAB_CI"] != nil
        let isForgejo = env["FORGEJO_ACTIONS"] != nil
        let name = isGitLab ? "GitLab CI" : (isForgejo ? "Forgejo Actions" : "github-actions[bot]")
        let email = isGitLab ? "gitlab-ci@example.invalid" : (isForgejo ? "forgejo-actions@example.invalid" : "41898282+github-actions[bot]@users.noreply.github.com")
        var executed: [DeployCommand] = []

        func execute(_ arguments: [String]) throws -> Int32 {
            let command = DeployCommand(executable: "git", arguments: arguments, environment: env)
            executed.append(command)
            return try run(command, root)
        }

        func require(_ arguments: [String]) throws {
            let status = try execute(arguments)
            guard status == 0 else {
                throw InksteadWriterError.io("git \(arguments.joined(separator: " ")) exited with status \(status).")
            }
        }

        try require(["config", "user.name", name])
        try require(["config", "user.email", email])
        try require(["add", config.content.posts])
        let commitStatus = try execute(["commit", "-m", "Update syndication data [skip ci]"])
        guard commitStatus == 0 else { return executed }

        if isGitLab, let token = env["CI_JOB_TOKEN"], let host = env["CI_SERVER_HOST"], let project = env["CI_PROJECT_PATH"], !token.isEmpty, !host.isEmpty, !project.isEmpty {
            try require(["remote", "set-url", "origin", "https://gitlab-ci-token:\(token)@\(host)/\(project).git"])
        }

        if isGitLab, let branch = env["CI_COMMIT_BRANCH"], !branch.isEmpty {
            try require(["push", "origin", "HEAD:\(branch)"])
        } else if isForgejo, let branch = env["FORGEJO_REF_NAME"], !branch.isEmpty {
            try require(["push", "origin", "HEAD:\(branch)"])
        } else {
            try require(["push"])
        }

        return executed
    }

    public static func runCommand(_ command: DeployCommand, cwd: URL) throws -> Int32 {
        let process = Process()
        ProcessSupport.configure(process, launch: ProcessSupport.command(command), cwd: cwd, environment: command.environment)
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
