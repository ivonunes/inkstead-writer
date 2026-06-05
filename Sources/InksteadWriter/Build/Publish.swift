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
        syndicate: (URL, InksteadWriterConfig) async -> SyndicationSummary = { root, config in await Syndicator.syndicateSite(root: root, config: config) },
        commit: (URL) throws -> Void = { root in _ = try commitSyndicationChanges(root: root) },
        log: (String) -> Void = { print($0) }
    ) async throws -> SyndicationSummary {
        let publishStarted = Date()
        let buildStarted = Date()
        try build(root, config)
        log("Build completed in \(formatDuration(since: buildStarted)).")

        let deployStarted = Date()
        try await deploy(root, config)
        log("Deploy completed in \(formatDuration(since: deployStarted)).")

        let syndicationStarted = Date()
        let result = await syndicate(root, config)
        log("Syndication completed in \(formatDuration(since: syndicationStarted)). Published: \(result.published). Failed: \(result.failed).")
        if result.changed {
            let rebuildStarted = Date()
            try build(root, config)
            log("Post-syndication rebuild completed in \(formatDuration(since: rebuildStarted)).")
            let redeployStarted = Date()
            try await deploy(root, config)
            log("Post-syndication redeploy completed in \(formatDuration(since: redeployStarted)).")
            let commitStarted = Date()
            try commit(root)
            log("Syndication commit completed in \(formatDuration(since: commitStarted)).")
        }
        log("Publish completed in \(formatDuration(since: publishStarted)).")
        return result
    }

    @discardableResult
    public static func commitSyndicationChanges(
        root: URL,
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

        _ = try execute(["config", "user.name", name])
        _ = try execute(["config", "user.email", email])
        _ = try execute(["add", "content/posts"])
        let commitStatus = try execute(["commit", "-m", "Update syndication data [skip ci]"])
        guard commitStatus == 0 else { return executed }

        if isGitLab, let token = env["CI_JOB_TOKEN"], let host = env["CI_SERVER_HOST"], let project = env["CI_PROJECT_PATH"], !token.isEmpty, !host.isEmpty, !project.isEmpty {
            _ = try execute(["remote", "set-url", "origin", "https://gitlab-ci-token:\(token)@\(host)/\(project).git"])
        }

        if isGitLab, let branch = env["CI_COMMIT_BRANCH"], !branch.isEmpty {
            _ = try execute(["push", "origin", "HEAD:\(branch)"])
        } else if isForgejo, let branch = env["FORGEJO_REF_NAME"], !branch.isEmpty {
            _ = try execute(["push", "origin", "HEAD:\(branch)"])
        } else {
            _ = try execute(["push"])
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

    private static func formatDuration(since start: Date) -> String {
        let seconds = Date().timeIntervalSince(start)
        if seconds < 10 {
            return String(format: "%.2fs", seconds)
        }
        return String(format: "%.1fs", seconds)
    }
}
