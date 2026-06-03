import Foundation
import Plume

struct ThemeRenderer: @unchecked Sendable {
    let root: URL
    let dist: URL
    let config: InksteadWriterConfig
    let posts: [NormalizedPost]
    let pages: [NormalizedPage]
    let categories: [CategoryCollection]
    let photoPosts: [NormalizedPost]
    let customCollections: [String: [CustomCollectionItem]]
    let data: [String: Any]
    let components: [String: String]
    let plumeEnvironment: PlumeTemplateEnvironment
    let plumeTemplateCache: PlumeTemplateCache
    let themeTemplates: [String: String]
    let legacyTemplatePaths: Set<String>
    let serializedSite: [String: Any]
    let serializedConfig: [String: Any]
    let serializedPosts: [[String: Any]]
    let serializedPages: [[String: Any]]
    let serializedCategories: [[String: Any]]
    let serializedPhotoPosts: [[String: Any]]
    let serializedCollections: [String: Any]
    let serializedPostsByURL: [String: [String: Any]]
    let serializedPagesBySlug: [String: [String: Any]]
    let serializedCategoriesBySlug: [String: [String: Any]]
    let currentYear: Int
    let emittedStyleCache: RenderEmissionCache
    let emittedScriptCache: RenderEmissionCache
    let emittedAssetCache: RenderEmissionCache
    let imageDimensionCache: ImageDimensionCache

    init(
        root: URL,
        dist: URL,
        config: InksteadWriterConfig,
        posts: [NormalizedPost],
        pages: [NormalizedPage],
        categories: [CategoryCollection],
        photoPosts: [NormalizedPost],
        customCollections: [String: [CustomCollectionItem]],
        data: [String: Any]
    ) throws {
        self.root = root
        self.dist = dist
        self.config = config
        self.posts = posts
        self.pages = pages
        self.categories = categories
        self.photoPosts = photoPosts
        self.customCollections = customCollections
        self.data = data
        self.themeTemplates = try ThemeRenderer.loadThemeTemplates(root: root, config: config)
        self.legacyTemplatePaths = try ThemeRenderer.loadLegacyTemplatePaths(
            root: root, config: config)
        let components = try ThemeRenderer.loadComponents(root: root, config: config)
        let plumeEnvironment = try PlumeTemplateEnvironment(componentSources: components)
        self.components = components
        self.plumeEnvironment = plumeEnvironment
        self.plumeTemplateCache = PlumeTemplateCache(environment: plumeEnvironment)
        self.serializedSite = serializeSite(config.site)
        self.serializedConfig = serializeConfig(config)
        let serializedPosts = posts.map(serializePost)
        let serializedPages = pages.map(serializePage)
        let serializedCategories = categories.map(serializeCategory)
        let serializedPhotoPosts = photoPosts.map(serializePost)
        self.serializedPosts = serializedPosts
        self.serializedPages = serializedPages
        self.serializedCategories = serializedCategories
        self.serializedPhotoPosts = serializedPhotoPosts
        self.serializedPostsByURL = ThemeRenderer.index(
            serializedPosts, by: posts.map(\.canonicalUrl))
        self.serializedPagesBySlug = ThemeRenderer.index(serializedPages, by: pages.map(\.slug))
        self.serializedCategoriesBySlug = ThemeRenderer.index(
            serializedCategories, by: categories.map(\.slug))
        var serializedCollections: [String: Any] = [
            "posts": self.serializedPosts,
            "pages": self.serializedPages,
            "categories": self.serializedCategories,
            "photoPosts": self.serializedPhotoPosts,
        ]
        for (name, items) in customCollections {
            serializedCollections[name] = items.map(serializeCustomCollectionItem)
        }
        self.serializedCollections = serializedCollections
        self.currentYear = Calendar.current.component(.year, from: Date())
        self.emittedStyleCache = RenderEmissionCache()
        self.emittedScriptCache = RenderEmissionCache()
        self.emittedAssetCache = RenderEmissionCache()
        self.imageDimensionCache = ImageDimensionCache()
    }

    func home(posts: [NormalizedPost], pagination: [String: Any], title: String) throws -> String {
        try renderBody(
            "home",
            context: [
                "title": title,
                "posts": posts.map(serializedPost),
                "pagination": pagination,
                "meta": meta(
                    title: title, canonicalUrl: config.site.url,
                    description: config.site.description),
            ])
    }

    func category(
        _ category: CategoryCollection, posts: [NormalizedPost], pagination: [String: Any]
    )
        throws -> String
    {
        let jsonFeedPath = category.feedPath.replacingOccurrences(of: "feed.xml", with: "feed.json")
        return try renderBody(
            "category",
            context: [
                "title": "#\(category.name)",
                "category": serializedCategory(category),
                "posts": posts.map(serializedPost),
                "pagination": pagination,
                "meta": meta(
                    title: "#\(category.name)",
                    canonicalUrl:
                        "\(config.site.url.replacingOccurrences(of: #"/$"#, with: "", options: .regularExpression))\(category.urlPath)",
                    description: config.site.description,
                    feeds: [
                        [
                            "type": "application/rss+xml",
                            "title": "\(config.site.title) - \(category.name) RSS",
                            "href": category.feedPath,
                        ],
                        [
                            "type": "application/feed+json",
                            "title": "\(config.site.title) - \(category.name) JSON Feed",
                            "href": jsonFeedPath,
                        ],
                    ]
                ),
            ])
    }

    func post(_ post: NormalizedPost) throws -> String {
        try renderBody(
            "post",
            context: [
                "post": serializedPost(post),
                "meta": meta(
                    title: post.title ?? (post.kind == .photoNote ? "Photo note" : "Note"),
                    canonicalUrl: post.canonicalUrl, description: plainText(post.excerpt)),
            ])
    }

    func page(_ page: NormalizedPage) throws -> String {
        let template = try customTemplateExists(page.slug) ? page.slug : "page"
        return try renderBody(
            template,
            context: [
                "page": serializedPage(page),
                "meta": meta(
                    title: page.title, canonicalUrl: page.canonicalUrl,
                    description: plainText(page.excerpt)),
            ])
    }

    func renderBody(_ template: String, context: [String: Any]) throws -> String {
        var fullContext = baseContext()
        for (key, value) in context {
            fullContext[key] = value
        }
        let bodyResult = try plumeTemplate(template).renderResult(fullContext)
        if bodyResult.html.range(
            of: #"<!doctype html"#, options: [.regularExpression, .caseInsensitive]) != nil
        {
            return try injectPlumeAssetsIfNeeded(bodyResult.html, result: bodyResult)
        }
        fullContext["content"] = PlumeSafeHTML(bodyResult.html)
        let layoutResult = try plumeTemplate("layout").renderResult(fullContext)
        return try injectPlumeAssetsIfNeeded(
            layoutResult.html, result: mergedRenderResult(bodyResult, layoutResult))
    }

    func plumeTemplate(_ name: String) throws -> PlumeTemplate {
        try plumeTemplateCache.template(
            key: templatePath(name),
            source: loadTemplate(name),
            sourceName: templatePath(name)
        )
    }

    func baseContext() -> [String: Any] {
        return [
            "site": serializedSite,
            "config": serializedConfig,
            "collections": serializedCollections,
            "data": data,
            "posts": serializedPosts,
            "pages": serializedPages,
            "categories": serializedCategories,
            "photoPosts": serializedPhotoPosts,
            "now": ["year": currentYear],
            "asset": PlumeFunction { call in
                guard let first = plumeArgument(named: "path", in: call) ?? firstPlumeArgument(call)
                else {
                    throw InksteadWriterError.template("asset() requires a path.")
                }
                return try plumeAssetURL(
                    stringifyPlumeValue(first), sourceName: call.context?.sourceName)
            },
            "image": PlumeFunction { call in
                try plumeImageHTML(call)
            },
        ]
    }

    func serializedPost(_ post: NormalizedPost) -> [String: Any] {
        serializedPostsByURL[post.canonicalUrl] ?? serializePost(post)
    }

    func serializedPage(_ page: NormalizedPage) -> [String: Any] {
        serializedPagesBySlug[page.slug] ?? serializePage(page)
    }

    func serializedCategory(_ category: CategoryCollection) -> [String: Any] {
        serializedCategoriesBySlug[category.slug] ?? serializeCategory(category)
    }

    static func index(_ values: [[String: Any]], by keys: [String]) -> [String: [String: Any]] {
        var output: [String: [String: Any]] = [:]
        for (key, value) in zip(keys, values) {
            output[key] = value
        }
        return output
    }
}

final class RenderEmissionCache {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func value(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: String, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }
}

final class PlumeTemplateCache {
    private let environment: PlumeTemplateEnvironment
    private let lock = NSLock()
    private var templates: [String: PlumeTemplate] = [:]

    init(environment: PlumeTemplateEnvironment) {
        self.environment = environment
    }

    func template(key: String, source: String, sourceName: String?) throws -> PlumeTemplate {
        lock.lock()
        defer { lock.unlock() }
        if let cached = templates[key] {
            return cached
        }
        let template = try PlumeTemplate(source, sourceName: sourceName, environment: environment)
        templates[key] = template
        return template
    }
}

final class ImageDimensionCache {
    private let lock = NSLock()
    private var values: [String: ImageDimensions] = [:]

    func dimensions(for url: URL, load: () throws -> ImageDimensions?) throws -> ImageDimensions? {
        let key = url.standardizedFileURL.path
        lock.lock()
        if let cached = values[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let dimensions = try load()
        if let dimensions {
            lock.lock()
            values[key] = dimensions
            lock.unlock()
        }
        return dimensions
    }
}
