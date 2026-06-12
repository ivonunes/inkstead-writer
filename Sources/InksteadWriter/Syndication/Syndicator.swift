import Foundation

public struct SyndicationSummary: Equatable, Sendable {
    public var changed: Bool
    public var published: Int
    public var failed: Int
}

public enum Syndicator {
    public static func syndicateSite(
        root: URL,
        config: InksteadWriterConfig,
        env: [String: String] = ProcessInfo.processInfo.environment,
        http: @escaping HTTPClient = DefaultHTTPClient.send,
        log: @escaping (String) -> Void = { print($0) }
    ) async throws -> SyndicationSummary {
        let posts = try ContentLoader.loadPosts(root: root, config: config)
        let mergedEnv = EnvFile.read(root: root).merging(env) { _, new in new }
        let context = SyndicationContext(root: root, env: mergedEnv, http: http)
        var changed = false
        var published = 0
        var failed = 0

        for post in posts {
            for provider in post.syndicate {
                if post.syndication[provider.rawValue]?.object?["status"]?.string != nil { continue }
                if !SyndicationProviders.canSyndicate(provider, post: post) { continue }
                let postPath = FileTreeSupport.relativePath(of: post.path, under: root) ?? post.path.path
                let result = await SyndicationProviders.publish(provider, post: post, context: context)
                guard result.status == .published else {
                    failed += 1
                    log("Syndicating \(postPath) to \(provider.rawValue) failed: \(result.fields["error"] ?? "unknown error")")
                    do {
                        let raw = try String(contentsOf: post.path, encoding: .utf8)
                        let updated = SyndicationFrontmatter.update(markdown: raw, provider: provider, result: result)
                        try updated.write(to: post.path, atomically: true, encoding: .utf8)
                        changed = true
                    } catch {
                        log("Could not record the \(provider.rawValue) failure in \(postPath): \(error)")
                    }
                    continue
                }
                published += 1
                do {
                    let raw = try String(contentsOf: post.path, encoding: .utf8)
                    let updated = SyndicationFrontmatter.update(markdown: raw, provider: provider, result: result)
                    try updated.write(to: post.path, atomically: true, encoding: .utf8)
                    changed = true
                } catch {
                    failed += 1
                    log("""
                    ERROR: \(postPath) was published to \(provider.rawValue), but its syndication status could not be written back: \(error)
                    Record the \(provider.rawValue) status as published in the frontmatter of \(post.path.path) manually before syndicating again, or the next run will publish a duplicate.
                    """)
                    return SyndicationSummary(changed: changed, published: published, failed: failed)
                }
            }
        }
        return SyndicationSummary(changed: changed, published: published, failed: failed)
    }
}
