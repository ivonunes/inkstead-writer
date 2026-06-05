import Foundation

public enum InksteadWriterMetadata {
    public static let currentVersion = "2.0.2"
    public static let configFileName = "inkstead-writer.json"
    public static let legacyConfigFileName = "inkstead.json"
    public static let executableName = "inkstead-writer"
    public static let cacheDirectoryName = "inkstead-writer"
}

public struct LegacyInksteadMetadata: Codable, Equatable {
    public var version: String

    public init(version: String = InksteadWriterMetadata.currentVersion) {
        self.version = version
    }
}

public struct SiteConfig: Codable, Equatable {
    public var title: String
    public var url: String
    public var author: String
    public var description: String?
    public var lang: String?
    public var timezone: String?
    public var email: String?
    public var avatar: String?
    public var bio: String?
    public var navigation: [NavigationItem]?
    public var social: [SocialItem]?
}

public struct NavigationItem: Codable, Equatable {
    public var name: String
    public var url: String
    public var icon: String?
    public var className: String?
}

public struct SocialItem: Codable, Equatable {
    public var name: String
    public var url: String
    public var relMe: Bool?
    public var icon: String?
    public var className: String?
}

public struct ContentConfig: Codable, Equatable {
    public var posts: String
    public var pages: String
    public var media: String
    public var collections: String

    enum CodingKeys: String, CodingKey {
        case posts
        case pages
        case media
        case collections
    }

    public init(posts: String = "content/posts", pages: String = "content/pages", media: String = "content/media", collections: String = "content/collections") {
        self.posts = posts
        self.pages = pages
        self.media = media
        self.collections = collections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        posts = try container.decodeIfPresent(String.self, forKey: .posts) ?? "content/posts"
        pages = try container.decodeIfPresent(String.self, forKey: .pages) ?? "content/pages"
        media = try container.decodeIfPresent(String.self, forKey: .media) ?? "content/media"
        collections = try container.decodeIfPresent(String.self, forKey: .collections) ?? "content/collections"
    }
}

public struct BuildConfig: Codable, Equatable {
    public var output: String?
}

public struct HooksConfig: Codable, Equatable {
    public var beforeBuild: [String]?
    public var afterBuild: [String]?
}

public struct UrlsConfig: Codable, Equatable {
    public var posts: PostUrlStyle?
}

public enum PostUrlStyle: String, Codable, Equatable {
    case dated
    case slug
}

public struct MarkdownConfig: Codable, Equatable {
    public var html: Bool?
    public var breaks: Bool?
}

public struct AssetsConfig: Codable, Equatable {
    public var passthrough: [PassthroughAsset]?
}

public struct PassthroughAsset: Codable, Equatable {
    public var from: String
    public var to: String?
}

public struct MediaConfig: Codable, Equatable {
    public var optimize: Bool?
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var quality: Int?
}

public struct ThemeConfig: Codable, Equatable {
    public var path: String?
    public var showPoweredBy: Bool?
}

public struct PaginationConfig: Codable, Equatable {
    public var postsPerPage: Int?
}

public struct FeedsConfig: Codable, Equatable {
    public var limit: Int?
}

public struct DataSourceConfig: Codable, Equatable {
    public var url: String?
    public var file: String?
    public var cache: String?
    public var required: Bool?
    public var headers: [String: String]?

    enum CodingKeys: String, CodingKey {
        case url
        case file
        case path
        case cache
        case required
        case headers
    }

    public init(url: String? = nil, file: String? = nil, cache: String? = nil, required: Bool? = nil, headers: [String: String]? = nil) {
        self.url = url
        self.file = file
        self.cache = cache
        self.required = required
        self.headers = headers
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self) {
            if value.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil {
                url = value
                file = nil
            } else {
                url = nil
                file = value
            }
            cache = nil
            required = nil
            headers = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        file = try container.decodeIfPresent(String.self, forKey: .file)
            ?? container.decodeIfPresent(String.self, forKey: .path)
        cache = try container.decodeIfPresent(String.self, forKey: .cache)
        required = try container.decodeIfPresent(Bool.self, forKey: .required)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(file, forKey: .file)
        try container.encodeIfPresent(cache, forKey: .cache)
        try container.encodeIfPresent(required, forKey: .required)
        try container.encodeIfPresent(headers, forKey: .headers)
    }
}

public enum AppConnectionProviderName: String, Codable, Equatable {
    case github
    case gitlab
    case forgejo
}

public struct AppConnectionConfig: Codable, Equatable {
    public var provider: AppConnectionProviderName?
    public var repository: String?
    public var branch: String?
    public var instanceUrl: String?
    public var categories: [String]?

    public init(
        provider: AppConnectionProviderName? = nil,
        repository: String? = nil,
        branch: String? = nil,
        instanceUrl: String? = nil,
        categories: [String]? = nil
    ) {
        self.provider = provider
        self.repository = repository
        self.branch = branch
        self.instanceUrl = instanceUrl
        self.categories = categories
    }
}

private struct LegacyWriterConfig: Decodable {
    var version: String
    var connection: AppConnectionConfig?

    enum CodingKeys: String, CodingKey {
        case version
        case connection
        case enabled
        case path
        case provider
        case owner
        case repo
        case repository
        case branch
        case instanceUrl
        case categories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.version) || container.contains(.connection) {
            version = try container.decodeIfPresent(String.self, forKey: .version) ?? InksteadWriterMetadata.currentVersion
            connection = try container.decodeIfPresent(AppConnectionConfig.self, forKey: .connection)
            return
        }

        version = "1.2.0"
        let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        guard enabled != false else {
            connection = nil
            return
        }

        let path = try container.decodeIfPresent(String.self, forKey: .path)
        let provider = try container.decodeIfPresent(AppConnectionProviderName.self, forKey: .provider)
        let repository = try container.decodeIfPresent(String.self, forKey: .repository)
            ?? Self.legacyRepository(
                owner: try container.decodeIfPresent(String.self, forKey: .owner),
                repo: try container.decodeIfPresent(String.self, forKey: .repo)
            )
        let branch = try container.decodeIfPresent(String.self, forKey: .branch)
        let instanceUrl = try container.decodeIfPresent(String.self, forKey: .instanceUrl)
        let categories = try container.decodeIfPresent([String].self, forKey: .categories)

        if enabled == true || path != nil || provider != nil || repository != nil || branch != nil || instanceUrl != nil || categories != nil {
            connection = AppConnectionConfig(
                provider: provider,
                repository: repository,
                branch: branch,
                instanceUrl: instanceUrl,
                categories: categories
            )
        } else {
            connection = nil
        }
    }

    private static func legacyRepository(owner: String?, repo: String?) -> String? {
        guard let owner = owner?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty,
              let repo = repo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty else {
            return nil
        }
        return "\(owner)/\(repo)"
    }
}

public enum CiProviderName: String, Codable, Equatable {
    case githubActions = "github-actions"
    case gitlabCi = "gitlab-ci"
    case forgejoActions = "forgejo-actions"
}

public struct CiConfig: Codable, Equatable {
    public var provider: CiProviderName
}

public enum DeployProviderName: String, Codable, Equatable {
    case cloudflareWorkers = "cloudflare-workers"
    case githubPages = "github-pages"
    case gitlabPages = "gitlab-pages"
    case netlify
}

public struct DeployConfig: Codable, Equatable {
    public var provider: DeployProviderName
    public var projectName: String?
}

public enum SyndicationProviderName: String, Codable, Equatable, CaseIterable {
    case mastodon
    case bluesky
    case flickr
}

public struct SyndicationConfig: Codable, Equatable {
    public var providers: [SyndicationProviderName]
}

public struct InksteadWriterConfig: Codable, Equatable {
    public var legacyInkstead: LegacyInksteadMetadata?
    public var version: String
    public var site: SiteConfig
    public var content: ContentConfig
    public var build: BuildConfig?
    public var hooks: HooksConfig?
    public var urls: UrlsConfig?
    public var markdown: MarkdownConfig?
    public var assets: AssetsConfig?
    public var media: MediaConfig?
    public var theme: ThemeConfig?
    public var pagination: PaginationConfig?
    public var feeds: FeedsConfig?
    public var data: [String: DataSourceConfig]?
    public var connection: AppConnectionConfig?
    public var ci: CiConfig?
    public var deploy: DeployConfig?
    public var syndication: SyndicationConfig?

    enum CodingKeys: String, CodingKey {
        case legacyInkstead = "inkstead"
        case version
        case site
        case content
        case build
        case hooks
        case urls
        case markdown
        case assets
        case media
        case legacyPhotos = "photos"
        case theme
        case pagination
        case feeds
        case data
        case writer
        case connection
        case ci
        case deploy
        case syndication
    }

    public init(
        legacyInkstead: LegacyInksteadMetadata? = nil,
        version: String = InksteadWriterMetadata.currentVersion,
        site: SiteConfig,
        content: ContentConfig = ContentConfig(),
        build: BuildConfig? = nil,
        hooks: HooksConfig? = nil,
        urls: UrlsConfig? = nil,
        markdown: MarkdownConfig? = nil,
        assets: AssetsConfig? = nil,
        media: MediaConfig? = nil,
        theme: ThemeConfig? = nil,
        pagination: PaginationConfig? = nil,
        feeds: FeedsConfig? = nil,
        data: [String: DataSourceConfig]? = nil,
        connection: AppConnectionConfig? = nil,
        ci: CiConfig? = nil,
        deploy: DeployConfig? = nil,
        syndication: SyndicationConfig? = nil
    ) {
        self.legacyInkstead = legacyInkstead
        self.version = version
        self.site = site
        self.content = content
        self.build = build
        self.hooks = hooks
        self.urls = urls
        self.markdown = markdown
        self.assets = assets
        self.media = media
        self.theme = theme
        self.pagination = pagination
        self.feeds = feeds
        self.data = data
        self.connection = connection
        self.ci = ci
        self.deploy = deploy
        self.syndication = syndication
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        legacyInkstead = try container.decodeIfPresent(LegacyInksteadMetadata.self, forKey: .legacyInkstead)
        let legacyWriter = try container.decodeIfPresent(LegacyWriterConfig.self, forKey: .writer)
        version = try container.decodeIfPresent(String.self, forKey: .version)
            ?? legacyInkstead?.version
            ?? legacyWriter?.version
            ?? "1.2.0"
        site = try container.decode(SiteConfig.self, forKey: .site)
        content = try container.decodeIfPresent(ContentConfig.self, forKey: .content) ?? ContentConfig()
        build = try container.decodeIfPresent(BuildConfig.self, forKey: .build)
        hooks = try container.decodeIfPresent(HooksConfig.self, forKey: .hooks)
        urls = try container.decodeIfPresent(UrlsConfig.self, forKey: .urls)
        markdown = try container.decodeIfPresent(MarkdownConfig.self, forKey: .markdown)
        assets = try container.decodeIfPresent(AssetsConfig.self, forKey: .assets)
        media = try container.decodeIfPresent(MediaConfig.self, forKey: .media)
            ?? container.decodeIfPresent(MediaConfig.self, forKey: .legacyPhotos)
        theme = try container.decodeIfPresent(ThemeConfig.self, forKey: .theme)
        pagination = try container.decodeIfPresent(PaginationConfig.self, forKey: .pagination)
        feeds = try container.decodeIfPresent(FeedsConfig.self, forKey: .feeds)
        data = try container.decodeIfPresent([String: DataSourceConfig].self, forKey: .data)
        connection = try container.decodeIfPresent(AppConnectionConfig.self, forKey: .connection)
            ?? legacyWriter?.connection
        ci = try container.decodeIfPresent(CiConfig.self, forKey: .ci)
        deploy = try container.decodeIfPresent(DeployConfig.self, forKey: .deploy)
        syndication = try container.decodeIfPresent(SyndicationConfig.self, forKey: .syndication)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(site, forKey: .site)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(build, forKey: .build)
        try container.encodeIfPresent(hooks, forKey: .hooks)
        try container.encodeIfPresent(urls, forKey: .urls)
        try container.encodeIfPresent(markdown, forKey: .markdown)
        try container.encodeIfPresent(assets, forKey: .assets)
        try container.encodeIfPresent(media, forKey: .media)
        try container.encodeIfPresent(theme, forKey: .theme)
        try container.encodeIfPresent(pagination, forKey: .pagination)
        try container.encodeIfPresent(feeds, forKey: .feeds)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(connection, forKey: .connection)
        try container.encodeIfPresent(ci, forKey: .ci)
        try container.encodeIfPresent(deploy, forKey: .deploy)
        try container.encodeIfPresent(syndication, forKey: .syndication)
    }

    public var recordedVersion: String {
        version
    }

    public func validate() throws {
        if site.title.isEmpty { throw InksteadWriterError.config("site.title is required.") }
        if site.url.isEmpty { throw InksteadWriterError.config("site.url is required.") }
        if site.author.isEmpty { throw InksteadWriterError.config("site.author is required.") }

        if deploy?.provider == .githubPages && ci?.provider != .githubActions {
            throw InksteadWriterError.config("GitHub Pages deployment requires GitHub Actions CI.")
        }
        if deploy?.provider == .gitlabPages && ci?.provider != .gitlabCi {
            throw InksteadWriterError.config("GitLab Pages deployment requires GitLab CI.")
        }
        if let repository = connection?.repository, repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw InksteadWriterError.config("Connection repository must not be empty.")
        }
        if let branch = connection?.branch, branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw InksteadWriterError.config("Connection branch must not be empty.")
        }
        if content.collections.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw InksteadWriterError.config("content.collections must not be empty.")
        }
        for (name, source) in data ?? [:] {
            guard Self.isPlumeIdentifier(name) else {
                throw InksteadWriterError.config("Data source name \(name) must be a valid Plume identifier.")
            }
            let hasURL = source.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasFile = source.file?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard hasURL != hasFile else {
                throw InksteadWriterError.config("Data source \(name) must define exactly one of url or file.")
            }
        }
        if let categories = connection?.categories {
            if categories.contains(where: { $0.isEmpty }) {
                throw InksteadWriterError.config("Connection categories must not be empty.")
            }
            if Set(categories).count != categories.count {
                throw InksteadWriterError.config("Connection categories must be unique.")
            }
        }
    }

    private static func isPlumeIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }
}

public enum InksteadWriterError: Error, CustomStringConvertible, Equatable {
    case config(String)
    case io(String)
    case parse(String)
    case template(String)

    public var description: String {
        switch self {
        case .config(let message), .io(let message), .parse(let message), .template(let message):
            message
        }
    }
}
