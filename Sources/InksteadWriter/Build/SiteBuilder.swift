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
        try build(root: root, config: config, options: .full, log: nil)
    }

    public static func build(root: URL, config: InksteadWriterConfig, log: ((String) -> Void)?) throws {
        try build(root: root, config: config, options: .full, log: log)
    }

    public static func build(root: URL, config: InksteadWriterConfig, options: SiteBuildOptions) throws {
        try build(root: root, config: config, options: options, log: nil)
    }

    public static func build(root: URL, config: InksteadWriterConfig, options: SiteBuildOptions, log: ((String) -> Void)?) throws {
        let timer = BuildPhaseTimer(log: log)
        if config.hooks?.beforeBuild?.isEmpty == false {
            try timer.measure("before-build hooks") {
                try runHooks(config.hooks?.beforeBuild, root: root)
            }
        }
        let dist = root.appendingPathComponent(config.build?.output ?? "dist")
        try timer.measure("prepared output") {
            if !options.incremental, FileManager.default.fileExists(atPath: dist.path) {
                try FileManager.default.removeItem(at: dist)
            }
            try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        }

        let posts = try timer.measure("loaded posts") {
            try ContentLoader.loadPosts(root: root, config: config)
        }
        let pages = try timer.measure("loaded pages") {
            try ContentLoader.loadPages(root: root, config: config)
        }
        let customCollections = try timer.measure("loaded collections") {
            try ContentLoader.loadCollections(root: root, config: config)
        }
        let data = try timer.measure("loaded data sources") {
            try DataSourceLoader.load(root: root, config: config)
        }
        let categories = timer.measure("grouped content") {
            ContentLoader.groupPostsByCategory(posts)
        }
        let photoPosts = posts.filter(ContentLoader.isGalleryPhotoPost)
        let renderer = try timer.measure("prepared renderer") {
            try ThemeRenderer(root: root, dist: dist, config: config, posts: posts, pages: pages, categories: categories, photoPosts: photoPosts, customCollections: customCollections, data: data)
        }
        let postsPerPage = config.pagination?.postsPerPage ?? 20

        try timer.measure("rendered home index") {
            try writePaginatedIndex(
                dist: dist,
                posts: posts,
                postsPerPage: postsPerPage,
                firstOutput: dist.appendingPathComponent("index.html"),
                pageOutput: { dist.appendingPathComponent("page/\($0)/index.html") },
                pageUrl: { $0 == 1 ? "/" : "/page/\($0)/" },
                render: { pagePosts, pagination in try renderer.home(posts: pagePosts, pagination: pagination, title: config.site.title) }
            )
        }

        try timer.measure("rendered categories") {
            try BuildConcurrency.run(categories) { category in
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
        }

        try timer.measure("rendered posts") {
            try BuildConcurrency.run(posts) { post in
                try write(try renderer.post(post), to: dist.appendingPathComponent("\(post.urlPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/index.html"))
            }
        }
        try timer.measure("rendered pages") {
            try BuildConcurrency.run(pages) { page in
                try write(try renderer.page(page), to: dist.appendingPathComponent("\(page.urlPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/index.html"))
            }
        }

        try timer.measure("rendered feeds and sitemap") {
            try write(try renderer.notFound(), to: dist.appendingPathComponent("404.html"))
            try write(try renderer.xmlFeed(posts: posts), to: dist.appendingPathComponent("feed.xml"))
            try write(try renderer.jsonFeed(posts: posts), to: dist.appendingPathComponent("feed.json"))
            let sitemapUrls = [config.site.url] + posts.map(\.canonicalUrl) + pages.map(\.canonicalUrl) + categories.map { "\(config.site.url.replacingOccurrences(of: #"/$"#, with: "", options: .regularExpression))\($0.urlPath)" }
            try write(FeedRenderer.sitemap(config: config, urls: sitemapUrls), to: dist.appendingPathComponent("sitemap.xml"))
        }

        let mediaSummary = try timer.measure("processed media") {
            try ImageOptimizer.copyOptimizedMedia(
                from: root.appendingPathComponent(config.content.media),
                to: dist.appendingPathComponent("media"),
                config: config,
                log: log
            )
        }
        if !mediaSummary.isEmpty {
            log?(mediaSummaryLine(mediaSummary))
        }
        if config.assets?.passthrough?.isEmpty == false {
            try timer.measure("copied passthrough assets") {
                for asset in config.assets?.passthrough ?? [] {
                    try copyIfExists(root.appendingPathComponent(asset.from), to: dist.appendingPathComponent(asset.to ?? "."))
                }
            }
        }
        try timer.measure("wrote app connection config") {
            try AppConnectionBuild.writePublicConfig(to: dist, config: config)
        }
        if config.hooks?.afterBuild?.isEmpty == false {
            try timer.measure("after-build hooks") {
                try runHooks(config.hooks?.afterBuild, root: root)
            }
        }
        log?("Build: completed in \(BuildFormatting.formatDuration(since: timer.started)).")
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

    private static func mediaSummaryLine(_ summary: ImageOptimizationSummary) -> String {
        "Media cache: \(summary.reusedFromCache) reused, \(summary.cacheMisses) optimized, \(summary.copiedWithoutOptimization) copied, \(summary.unchangedCopies) unchanged."
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
        for file in try FileTreeCopyPlan.regularFilePairs(from: source, to: destination) {
            try FileManager.default.createDirectory(at: file.target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try copyFileIfChanged(file.source, to: file.target)
        }
    }

    private static func copyFileIfChanged(_ source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            if try FileTreeSupport.filesHaveSameContents(source, destination) {
                return
            }
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
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

enum FileTreeCopyPlan {
    static func regularFilePairs(from source: URL, to destination: URL) throws -> [(source: URL, target: URL)] {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]) else {
            return []
        }
        var files: [(source: URL, target: URL)] = []
        for case let item as URL in enumerator {
            guard let relative = FileTreeSupport.relativePath(of: item, under: source), !relative.isEmpty else { continue }
            let target = destination.appendingPathComponent(relative)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                files.append((item, target))
            }
        }
        return files
    }
}

private final class BuildPhaseTimer {
    let started = Date()
    private let log: ((String) -> Void)?

    init(log: ((String) -> Void)?) {
        self.log = log
    }

    func measure<Value>(_ label: String, _ work: () throws -> Value) rethrows -> Value {
        let phaseStarted = Date()
        defer {
            log?("Build: \(label) in \(BuildFormatting.formatDuration(since: phaseStarted)).")
        }
        return try work()
    }
}
