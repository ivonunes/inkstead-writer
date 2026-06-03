import Foundation

public enum Publish {
    @discardableResult
    public static func publishSite(
        root: URL,
        config: InksteadWriterConfig,
        build: (URL, InksteadWriterConfig) throws -> Void = SiteBuilder.build,
        deploy: (URL, InksteadWriterConfig) async throws -> Void = { root, config in try await Deploy.deploySite(root: root, config: config) },
        syndicate: (URL, InksteadWriterConfig) async -> SyndicationSummary = { root, config in await Syndicator.syndicateSite(root: root, config: config) },
        commit: (URL) throws -> Void = { root in _ = try commitSyndicationChanges(root: root) }
    ) async throws -> SyndicationSummary {
        try build(root, config)
        try await deploy(root, config)

        let result = await syndicate(root, config)
        if result.changed {
            try build(root, config)
            try await deploy(root, config)
            try commit(root)
        }
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
}
