import Foundation

public struct PublicAppConnectionConfig: Codable, Equatable {
    public var version: String
    public var siteName: String
    public var provider: AppConnectionProviderName?
    public var owner: String?
    public var repo: String?
    public var branch: String?
    public var instanceUrl: String?
    public var postsPath: String
    public var mediaPath: String
    public var syndicationProviders: [SyndicationTarget]
    public var categories: [String]
}

public enum AppConnectionSupport {
    public static let publicConfigPath = InksteadWriterMetadata.configFileName

    public static func publicConfig(
        _ config: InksteadWriterConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PublicAppConnectionConfig {
        let connection = config.connection
        let inferred = inferredConnectionConfig(environment: environment)
        let repository = connection?.repository ?? inferred.repository
        let ownerRepo = splitRepository(repository)
        return PublicAppConnectionConfig(
            version: InksteadWriterMetadata.currentVersion,
            siteName: config.site.title,
            provider: connection?.provider ?? inferred.provider ?? inferredConnectionProvider(ci: config.ci?.provider),
            owner: ownerRepo.owner,
            repo: ownerRepo.repo,
            branch: connection?.branch ?? inferred.branch,
            instanceUrl: connection?.instanceUrl ?? inferred.instanceUrl,
            postsPath: config.content.posts,
            mediaPath: config.content.media,
            syndicationProviders: config.syndication?.providers ?? [],
            categories: connection?.categories ?? []
        )
    }

    private static func splitRepository(_ repository: String?) -> (owner: String?, repo: String?) {
        guard let repository = repository?.trimmingCharacters(in: .whitespacesAndNewlines), !repository.isEmpty else {
            return (nil, nil)
        }
        let parts = repository.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (nil, repository) }
        return (parts[0], parts[1])
    }

    private static func inferredConnectionConfig(environment: [String: String]) -> AppConnectionConfig {
        if let repository = nonEmpty(environment["GITHUB_REPOSITORY"]) {
            let server = nonEmpty(environment["GITHUB_SERVER_URL"]) ?? "https://github.com"
            let isGitHub = server == "https://github.com" || server == "http://github.com"
            return AppConnectionConfig(
                provider: isGitHub ? .github : .forgejo,
                repository: repository,
                branch: nonEmpty(environment["GITHUB_HEAD_REF"]) ?? nonEmpty(environment["GITHUB_REF_NAME"]),
                instanceUrl: isGitHub ? nil : server
            )
        }

        if let repository = nonEmpty(environment["CI_PROJECT_PATH"]) {
            return AppConnectionConfig(
                provider: .gitlab,
                repository: repository,
                branch: nonEmpty(environment["CI_COMMIT_BRANCH"]) ?? nonEmpty(environment["CI_DEFAULT_BRANCH"]),
                instanceUrl: nonEmpty(environment["CI_SERVER_URL"])
            )
        }

        if let repository = nonEmpty(environment["FORGEJO_REPOSITORY"]) ?? nonEmpty(environment["GITEA_REPOSITORY"]) {
            return AppConnectionConfig(
                provider: .forgejo,
                repository: repository,
                branch: nonEmpty(environment["FORGEJO_REF_NAME"]) ?? nonEmpty(environment["GITEA_REF_NAME"]),
                instanceUrl: nonEmpty(environment["FORGEJO_SERVER_URL"]) ?? nonEmpty(environment["GITEA_SERVER_URL"])
            )
        }

        return AppConnectionConfig()
    }

    public static func inferredConnectionProvider(ci: CiProviderName?) -> AppConnectionProviderName? {
        switch ci {
        case .githubActions: .github
        case .gitlabCi: .gitlab
        case .forgejoActions: .forgejo
        case nil: nil
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
