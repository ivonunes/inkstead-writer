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
            for target in post.syndicate {
                if SyndicationFrontmatter.result(in: post.syndication, for: target)?["status"]?.string != nil { continue }
                if !SyndicationProviders.canSyndicate(target, post: post) { continue }
                let postPath = FileTreeSupport.relativePath(of: post.path, under: root) ?? post.path.path
                let result = await SyndicationProviders.publish(target, post: post, context: context)
                guard result.status == .published else {
                    failed += 1
                    log("Syndicating \(postPath) to \(target.rawValue) failed: \(result.fields["error"] ?? "unknown error")")
                    do {
                        let raw = try String(contentsOf: post.path, encoding: .utf8)
                        let updated = SyndicationFrontmatter.update(markdown: raw, target: target, result: result)
                        try updated.write(to: post.path, atomically: true, encoding: .utf8)
                        changed = true
                    } catch {
                        log("Could not record the \(target.rawValue) failure in \(postPath): \(error)")
                    }
                    continue
                }
                published += 1
                do {
                    let raw = try String(contentsOf: post.path, encoding: .utf8)
                    let updated = SyndicationFrontmatter.update(markdown: raw, target: target, result: result)
                    try updated.write(to: post.path, atomically: true, encoding: .utf8)
                    changed = true
                } catch {
                    failed += 1
                    log("""
                    ERROR: \(postPath) was published to \(target.rawValue), but its syndication status could not be written back: \(error)
                    Record the \(target.rawValue) status as published in the frontmatter of \(post.path.path) manually before syndicating again, or the next run will publish a duplicate.
                    """)
                    return SyndicationSummary(changed: changed, published: published, failed: failed)
                }
            }
        }
        return SyndicationSummary(changed: changed, published: published, failed: failed)
    }
}
