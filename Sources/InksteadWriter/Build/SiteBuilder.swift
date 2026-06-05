import Foundation
import Plume

public struct SiteBuildOptions: Equatable, Sendable {
    public var incremental: Bool

    public init(incremental: Bool = false) {
        self.incremental = incremental
    }

    public static let full = SiteBuildOptions()
    public static let incremental = SiteBuildOptions(incremental: true)
}

public enum SiteBuilder {
    public static func build(root: URL, config: InksteadWriterConfig) throws {
        try build(root: root, config: config, options: .full)
    }

    public static func build(root: URL, config: InksteadWriterConfig, options: SiteBuildOptions) throws {
        try runHooks(config.hooks?.beforeBuild, root: root)
        let dist = root.appendingPathComponent(config.build?.output ?? "dist")
        if !options.incremental, FileManager.default.fileExists(atPath: dist.path) {
            try FileManager.default.removeItem(at: dist)
        }
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)

        let posts = try ContentLoader.loadPosts(root: root, config: config)
        let pages = try ContentLoader.loadPages(root: root, config: config)
        let customCollections = try ContentLoader.loadCollections(root: root, config: config)
        let data = try DataSourceLoader.load(root: root, config: config)
        let categories = ContentLoader.groupPostsByCategory(posts)
        let photoPosts = posts.filter(ContentLoader.isGalleryPhotoPost)
        let renderer = try ThemeRenderer(root: root, dist: dist, config: config, posts: posts, pages: pages, categories: categories, photoPosts: photoPosts, customCollections: customCollections, data: data)
        let postsPerPage = config.pagination?.postsPerPage ?? 20

        try writePaginatedIndex(
            dist: dist,
            posts: posts,
            postsPerPage: postsPerPage,
            firstOutput: dist.appendingPathComponent("index.html"),
            pageOutput: { dist.appendingPathComponent("page/\($0)/index.html") },
            pageUrl: { $0 == 1 ? "/" : "/page/\($0)/" },
            render: { pagePosts, pagination in try renderer.home(posts: pagePosts, pagination: pagination, title: config.site.title) }
        )

        for category in categories {
            try writePaginatedIndex(
                dist: dist,
                posts: category.posts,
                postsPerPage: postsPerPage,
                firstOutput: dist.appendingPathComponent("\(category.urlPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/index.html"),
                pageOutput: { dist.appendingPathComponent("categories/\(category.slug)/page/\($0)/index.html") },
                pageUrl: { $0 == 1 ? category.urlPath : "/categories/\(category.slug)/page/\($0)/" },
                render: { pagePosts, pagination in try renderer.category(category, posts: pagePosts, pagination: pagination) }
            )
            try write(
                try renderer.xmlFeed(posts: category.posts, title: "\(config.site.title) - \(category.name)", path: category.feedPath, category: category),
                to: dist.appendingPathComponent(category.feedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            )
            let categoryJSONFeedPath = category.feedPath.replacingOccurrences(of: "feed.xml", with: "feed.json")
            try write(
                try renderer.jsonFeed(posts: category.posts, title: "\(config.site.title) - \(category.name)", path: categoryJSONFeedPath, category: category),
                to: dist.appendingPathComponent(categoryJSONFeedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            )
        }

        try runParallel(posts) { post in
            try write(try renderer.post(post), to: dist.appendingPathComponent("\(post.urlPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/index.html"))
        }
        try runParallel(pages) { page in
            try write(try renderer.page(page), to: dist.appendingPathComponent("\(page.urlPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/index.html"))
        }

        try write(try renderer.notFound(), to: dist.appendingPathComponent("404.html"))
        try write(try renderer.xmlFeed(posts: posts), to: dist.appendingPathComponent("feed.xml"))
        try write(try renderer.jsonFeed(posts: posts), to: dist.appendingPathComponent("feed.json"))
        let sitemapUrls = [config.site.url] + posts.map(\.canonicalUrl) + pages.map(\.canonicalUrl) + categories.map { "\(config.site.url.replacingOccurrences(of: #"/$"#, with: "", options: .regularExpression))\($0.urlPath)" }
        try write(FeedRenderer.sitemap(config: config, urls: sitemapUrls), to: dist.appendingPathComponent("sitemap.xml"))

        try ImageOptimizer.copyOptimizedMedia(
            from: root.appendingPathComponent(config.content.media),
            to: dist.appendingPathComponent("media"),
            config: config
        )
        for asset in config.assets?.passthrough ?? [] {
            try copyIfExists(root.appendingPathComponent(asset.from), to: dist.appendingPathComponent(asset.to ?? "."))
        }
        try AppConnectionBuild.writePublicConfig(to: dist, config: config)
        try runHooks(config.hooks?.afterBuild, root: root)
    }

    private static func writePaginatedIndex(
        dist: URL,
        posts: [NormalizedPost],
        postsPerPage: Int,
        firstOutput: URL,
        pageOutput: (Int) -> URL,
        pageUrl: (Int) -> String,
        render: ([NormalizedPost], [String: Any]) throws -> String
    ) throws {
        let pageCount = max(1, Int(ceil(Double(posts.count) / Double(postsPerPage))))
        for page in 1...pageCount {
            let start = (page - 1) * postsPerPage
            let end = min(posts.count, start + postsPerPage)
            let pagePosts = start < end ? Array(posts[start..<end]) : []
            let pagination: [String: Any] = [
                "current": page,
                "total": pageCount,
                "previousUrl": page > 1 ? pageUrl(page - 1) : "",
                "nextUrl": page < pageCount ? pageUrl(page + 1) : ""
            ]
            try write(try render(pagePosts, pagination), to: page == 1 ? firstOutput : pageOutput(page))
        }
    }

    private static func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path),
           (try? String(contentsOf: url, encoding: .utf8)) == content {
            return
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func copyIfExists(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey])
        let destinationValues = try? destination.resourceValues(forKeys: [.isDirectoryKey])
        if sourceValues.isDirectory == true, destinationValues?.isDirectory == true {
            try copyDirectoryContents(source, to: destination)
            return
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copyFileIfChanged(source, to: destination)
    }

    private static func copyDirectoryContents(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]) else { return }
        for case let item as URL in enumerator {
            let relative = item.standardizedFileURL.path.replacingOccurrences(of: source.standardizedFileURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }
            let target = destination.appendingPathComponent(relative)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try copyFileIfChanged(item, to: target)
            }
        }
    }

    private static func copyFileIfChanged(_ source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            if try filesHaveSameContents(source, destination) {
                return
            }
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func filesHaveSameContents(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let leftValues = try lhs.resourceValues(forKeys: [.fileSizeKey])
        let rightValues = try rhs.resourceValues(forKeys: [.fileSizeKey])
        guard leftValues.fileSize == rightValues.fileSize else { return false }
        return try Data(contentsOf: lhs) == Data(contentsOf: rhs)
    }

    private static func runParallel<Element: Sendable>(_ items: [Element], body: @escaping @Sendable (Element) throws -> Void) throws {
        guard items.count > 1 else {
            if let item = items.first {
                try body(item)
            }
            return
        }
        let workerCount = min(max(1, ProcessInfo.processInfo.activeProcessorCount), items.count, 4)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = workerCount
        let errors = SiteBuildErrorBox()
        for item in items {
            queue.addOperation {
                do {
                    try body(item)
                } catch {
                    errors.setIfEmpty(error)
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        if let firstError = errors.firstError {
            throw firstError
        }
    }

    private static func runHooks(_ hooks: [String]?, root: URL) throws {
        for hook in hooks ?? [] {
            let process = Process()
            ProcessSupport.configure(process, launch: ProcessSupport.shell(hook), cwd: root)
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw InksteadWriterError.io("Hook failed: \(hook)")
            }
        }
    }
}

private final class SiteBuildErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var firstError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }

    func setIfEmpty(_ error: Error) {
        lock.lock()
        if storedError == nil {
            storedError = error
        }
        lock.unlock()
    }
}
