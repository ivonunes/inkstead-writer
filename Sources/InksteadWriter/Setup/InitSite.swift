import Foundation

public struct InitSiteOptions: Equatable {
    public var ci: CiProviderName?
    public var deploy: DeployProviderName?
    public var deployProjectName: String?
    public var syndication: [SyndicationProviderName]
    public var connection: AppConnectionConfig?

    public init(
        ci: CiProviderName? = .githubActions,
        deploy: DeployProviderName? = .cloudflareWorkers,
        deployProjectName: String? = nil,
        syndication: [SyndicationProviderName] = [],
        connection: AppConnectionConfig? = nil
    ) {
        self.ci = ci
        self.deploy = deploy
        self.deployProjectName = deployProjectName
        self.syndication = syndication
        self.connection = connection
    }
}

public struct ParsedInitCommand: Equatable {
    public var directory: String
    public var options: InitSiteOptions

    public init(directory: String, options: InitSiteOptions) {
        self.directory = directory
        self.options = options
    }
}

public enum InitCommandParser {
    public static func parse(_ arguments: [String]) throws -> ParsedInitCommand {
        var directory: String?
        var ci: CiProviderName? = .githubActions
        var deploy: DeployProviderName? = .cloudflareWorkers
        var deployProjectName: String?
        var syndication: [SyndicationProviderName] = []
        var connectionProvider: AppConnectionProviderName?
        var connectionRepository: String?
        var connectionBranch: String?
        var connectionInstanceURL: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--ci":
                ci = try parseOptionalCI(value(after: argument, in: arguments, index: &index))
            case "--deploy":
                deploy = try parseOptionalDeploy(value(after: argument, in: arguments, index: &index))
            case "--deploy-project-name", "--deployProjectName":
                deployProjectName = try value(after: argument, in: arguments, index: &index)
            case "--syndication":
                let raw = try value(after: argument, in: arguments, index: &index)
                syndication.append(contentsOf: try parseSyndication(raw))
            case "--connection-provider":
                connectionProvider = try parseConnectionProvider(value(after: argument, in: arguments, index: &index))
            case "--connection-repository":
                connectionRepository = try value(after: argument, in: arguments, index: &index)
            case "--connection-branch":
                connectionBranch = try value(after: argument, in: arguments, index: &index)
            case "--connection-instance-url", "--connection-instanceUrl":
                connectionInstanceURL = try value(after: argument, in: arguments, index: &index)
            default:
                if argument.hasPrefix("-") {
                    throw InksteadWriterError.config("Unknown init option \(argument).")
                }
                if directory != nil {
                    throw InksteadWriterError.config("Only one init directory can be provided.")
                }
                directory = argument
            }
            index += 1
        }

        let connection = try connectionConfig(
            provider: connectionProvider,
            repository: connectionRepository,
            branch: connectionBranch,
            instanceURL: connectionInstanceURL,
            ci: ci
        )
        return ParsedInitCommand(
            directory: directory ?? "my-site",
            options: InitSiteOptions(
                ci: ci,
                deploy: deploy,
                deployProjectName: deployProjectName,
                syndication: Array(Set(syndication)).sorted { $0.rawValue < $1.rawValue },
                connection: connection
            )
        )
    }

    private static func value(after flag: String, in arguments: [String], index: inout Int) throws -> String {
        let next = index + 1
        guard next < arguments.count, !arguments[next].hasPrefix("-") else {
            throw InksteadWriterError.config("\(flag) requires a value.")
        }
        index = next
        return arguments[next]
    }

    private static func parseOptionalCI(_ raw: String) throws -> CiProviderName? {
        if raw == "none" { return nil }
        guard let provider = CiProviderName(rawValue: raw) else {
            throw InksteadWriterError.config("Unknown CI provider \(raw).")
        }
        return provider
    }

    private static func parseOptionalDeploy(_ raw: String) throws -> DeployProviderName? {
        if raw == "none" { return nil }
        guard let provider = DeployProviderName(rawValue: raw) else {
            throw InksteadWriterError.config("Unknown deployment provider \(raw).")
        }
        return provider
    }

    private static func parseSyndication(_ raw: String) throws -> [SyndicationProviderName] {
        if raw == "none" { return [] }
        return try raw.split(separator: ",").map { item in
            let name = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let provider = SyndicationProviderName(rawValue: name) else {
                throw InksteadWriterError.config("Unknown syndication provider \(name).")
            }
            return provider
        }
    }

    private static func parseConnectionProvider(_ raw: String) throws -> AppConnectionProviderName {
        guard let provider = AppConnectionProviderName(rawValue: raw) else {
            throw InksteadWriterError.config("Connection provider must be github, gitlab, or forgejo.")
        }
        return provider
    }

    private static func inferredConnectionProvider(ci: CiProviderName?) -> AppConnectionProviderName? {
        switch ci {
        case .githubActions: .github
        case .gitlabCi: .gitlab
        case .forgejoActions: .forgejo
        case nil: nil
        }
    }

    private static func connectionConfig(
        provider: AppConnectionProviderName?,
        repository: String?,
        branch: String?,
        instanceURL: String?,
        ci: CiProviderName?
    ) throws -> AppConnectionConfig? {
        guard provider != nil || repository != nil || branch != nil || instanceURL != nil else {
            return nil
        }
        return AppConnectionConfig(
            provider: provider ?? inferredConnectionProvider(ci: ci),
            repository: repository,
            branch: branch ?? "main",
            instanceUrl: instanceURL
        )
    }

}

public enum SiteInitializer {
    public static func initSite(at root: URL, options: InitSiteOptions = InitSiteOptions()) throws -> String {
        if FileManager.default.fileExists(atPath: root.path) {
            let values = try root.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                throw InksteadWriterError.io("\(root.lastPathComponent) already exists.")
            }
            let existing = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != ".DS_Store" }
            guard existing.isEmpty else {
                throw InksteadWriterError.io("\(root.lastPathComponent) already exists and is not empty.")
            }
        }
        let projectName = root.lastPathComponent
        let config = siteConfig(projectName: projectName, options: options)
        let files = generatedFiles(config: config, options: options)
        for (path, content) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            if path == SiteWrapper.path {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
        return nextSteps(projectName: projectName, config: config)
    }

    private static func siteConfig(projectName: String, options: InitSiteOptions) -> InksteadWriterConfig {
        var config = InksteadWriterConfig(
            site: SiteConfig(title: "My Website", url: "https://example.com", author: "Your Name", description: "Notes, photos, and longer writing."),
            content: ContentConfig(),
            connection: options.connection
        )
        config.ci = options.ci.map(CiConfig.init(provider:))
        if options.deploy == .githubPages { config.ci = CiConfig(provider: .githubActions) }
        if options.deploy == .gitlabPages { config.ci = CiConfig(provider: .gitlabCi) }
        if let deploy = options.deploy {
            config.deploy = DeployConfig(provider: deploy, projectName: deploy == .cloudflareWorkers ? (options.deployProjectName ?? projectName) : nil)
        }
        if !options.syndication.isEmpty {
            config.syndication = SyndicationConfig(providers: options.syndication)
        }
        return config
    }

    private static func generatedFiles(config: InksteadWriterConfig, options: InitSiteOptions) -> [String: String] {
        var files: [String: String] = [
            InksteadWriterMetadata.configFileName: encodeConfig(config),
            SiteWrapper.path: SiteWrapper.script,
            ".env.example": environmentVariables(config).map { "\($0)=" }.joined(separator: "\n") + "\n",
            ".gitignore": "dist/\n.env\n.env.*\n!.env.example\n.DS_Store\n.site/\n",
            "README.md": "# My Inkstead Writer Site\n\nDocumentation: https://inkstead.dev/\n",
            "content/posts/hello.md": "\(postFrontmatter(base: ["date": "2026-05-10T18:30:00+01:00"], syndication: options.syndication))\n\nThinking about notes...\n",
            "content/posts/first-article.md": "\(postFrontmatter(base: ["title": "\"Why I Still Want a Personal Website\"", "date": "2026-05-10T18:30:00+01:00"], syndication: options.syndication))\n\nLonger article content here.\n",
            "content/pages/about.md": "---\ntitle: About\n---\n\nThis is my website.\n",
            "content/pages/now.md": "---\ntitle: Now\n---\n\nWhat I am focused on now.\n",
            "content/media/.gitkeep": ""
        ]
        if let workflow = AdapterSupport.workflowFile(config: config) {
            files[workflow.path] = workflow.content
        }
        return files
    }

    private static func encodeConfig(_ config: InksteadWriterConfig) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try? encoder.encode(config)
        return String(data: data ?? Data(), encoding: .utf8) ?? "{}"
    }

    private static func postFrontmatter(base: [String: String], syndication: [SyndicationProviderName]) -> String {
        var lines = base.map { "\($0.key): \($0.value)" }.sorted()
        let social = syndication.filter { $0 != .flickr }
        if !social.isEmpty {
            lines.append("syndicate:")
            lines.append(contentsOf: social.map { "  - \($0.rawValue)" })
        }
        return "---\n\(lines.joined(separator: "\n"))\n---"
    }

    private static func environmentVariables(_ config: InksteadWriterConfig) -> [String] {
        var names: [String] = []
        if config.deploy?.provider == .cloudflareWorkers {
            names.append(contentsOf: ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"])
        }
        if config.deploy?.provider == .netlify {
            names.append(contentsOf: ["NETLIFY_SITE_ID", "NETLIFY_AUTH_TOKEN"])
        }
        for provider in config.syndication?.providers ?? [] {
            switch provider {
            case .mastodon:
                names.append(contentsOf: ["MASTODON_INSTANCE_URL", "MASTODON_ACCESS_TOKEN"])
            case .bluesky:
                names.append(contentsOf: ["BLUESKY_IDENTIFIER", "BLUESKY_APP_PASSWORD"])
            case .flickr:
                names.append(contentsOf: ["FLICKR_API_KEY", "FLICKR_API_SECRET", "FLICKR_ACCESS_TOKEN", "FLICKR_ACCESS_SECRET"])
            case .pixelfed:
                names.append(contentsOf: ["PIXELFED_INSTANCE_URL", "PIXELFED_ACCESS_TOKEN"])
            }
        }
        return Array(Set(names)).sorted()
    }

    private static func nextSteps(projectName: String, config: InksteadWriterConfig) -> String {
        let envNames = environmentVariables(config)
        if envNames.isEmpty {
            return """
            Created Inkstead Writer site.

            Next:
              1. cd \(projectName)
              2. ./inkstead-writer dev
              3. ./inkstead-writer doctor
            """
        }

        return """
        Created Inkstead Writer site.

        Next:
          1. cd \(projectName)
          2. cp .env.example .env
          3. Fill in .env
          4. Add the same values to CI secrets or variables
          5. ./inkstead-writer doctor
          6. ./inkstead-writer dev
        """
    }
}
